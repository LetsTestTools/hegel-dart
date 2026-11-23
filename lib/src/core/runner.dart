import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import '../ffi/hegel_bindings.g.dart';
import '../ffi/library_loader.dart';
import '../ffi/string_helpers.dart';
import 'exceptions.dart';
import 'hegel_settings.dart';
import 'origin.dart';
import 'result.dart';
import 'settings.dart';
import 'test_case.dart';

/// Callback for engine output.
///
/// SAFETY: This runs inside a NativeCallable — any unhandled exception
/// will crash the VM. We use allowMalformed to tolerate bad UTF-8.
void _outputCallback(Pointer<Void> userData, Pointer<Char> line, int len) {
  if (line == nullptr || len <= 0) return;
  try {
    final bytes = line.cast<Uint8>().asTypedList(len);
    final str = utf8.decode(bytes, allowMalformed: true);
    // ignore: avoid_print
    print(str);
  } catch (_) {
    // Swallow ALL exceptions — we must never throw across the FFI boundary.
  }
}

typedef _CapturedFailure = ({
  String errorText,
  StackTrace stackTrace,
  List<(String, String)> drawLog,
  List<String> notes,
});

class HegelRunner {
  HegelRunner();

  Future<RunResult> runWithResult(
    FutureOr<void> Function(TestCase) body, {
    String? reproduceBlob,
    int? testCases,
    int? seed,
    bool? derandomize,
    Set<Phase>? phases,
    Verbosity? verbosity,
    Set<HealthCheck>? suppressHealthChecks,
    bool? reportMultipleFailures,
    String? databaseKey,
    bool? database,
    String? databasePath,
    FutureOr<void> Function()? setUpEach,
    FutureOr<void> Function()? tearDownEach,
  }) async {
    ensureHegelLibraryVerified();
    final caughtExceptions = <String, _CapturedFailure>{};
    final ctx = hegel_context_new();
    if (ctx == nullptr) {
      throw StateError('Failed to allocate libhegel context.');
    }
    final lifecycle = RunLifecycle();
    final statistics = <String, Map<String, int>>{};
    final coverageTargets = <String, double>{};
    final stampedOrigins = <String>{};
    int validCasesRun = 0;
    Pointer<hegel_settings_t> settings = nullptr;
    Pointer<hegel_run_t> runHandle = nullptr;
    Pointer<hegel_test_case_t> tcHandle = nullptr;
    NativeCallable<hegel_output_callback_tFunction>? callback;

    try {
      // 1. Create Settings
      final outSettings = calloc<Pointer<hegel_settings_t>>();
      try {
        final res = hegel_settings_new(ctx, outSettings);
        if (res != hegel_result_t.HEGEL_OK) {
          throw hegelExceptionWithDetail(
            ctx,
            'Failed to create settings',
            res.value,
          );
        }
        settings = outSettings.value;
      } finally {
        calloc.free(outSettings);
      }

      final effectiveDb = _envDatabase(database);
      if (effectiveDb) {
        _ensureHegelGitignore(databasePath);
      }

      // Apply user settings
      applySettings(
        ctx,
        settings,
        testCases: testCases,
        seed: seed,
        derandomize: derandomize,
        phases: phases,
        verbosity: verbosity,
        suppressHealthChecks: suppressHealthChecks,
        reportMultipleFailures: reportMultipleFailures,
        databaseKey: databaseKey,
        database: effectiveDb,
        databasePath: databasePath,
      );

      // Per the C API docs, the callback is invoked synchronously on
      // whichever thread calls hegel_next_test_case / hegel_mark_complete —
      // which is our isolate's thread.
      callback = NativeCallable<hegel_output_callback_tFunction>.isolateLocal(
        _outputCallback,
      );

      // 2. Start Run
      final outRun = calloc<Pointer<hegel_run_t>>();
      try {
        final hegel_result_t res;
        if (reproduceBlob != null) {
          if (reproduceBlob.contains('\x00')) {
            throw ArgumentError('reproduce blob must not contain NUL bytes');
          }
          res = using((Arena arena) {
            return hegel_run_start_blob(
              ctx,
              settings,
              makeHegelString(arena, reproduceBlob),
              callback!.nativeFunction,
              nullptr,
              outRun,
            );
          });
          if (res != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to start blob replay run',
              res.value,
            );
          }
        } else {
          res = hegel_run_start(
            ctx,
            settings,
            callback.nativeFunction,
            nullptr,
            outRun,
          );
          if (res != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to start run',
              res.value,
            );
          }
        }
        runHandle = outRun.value;
      } finally {
        calloc.free(outRun);
      }

      // 3. Test case loop
      final outTestCase = calloc<Pointer<hegel_test_case_t>>();
      final outWantsOutput = calloc<Bool>();
      final outWantsDetail = calloc<Bool>();
      final sharedBufferCache = <String, Pointer<Void>>{};
      int testCasesRun = 0;
      try {
        while (true) {
          final res = hegel_next_test_case(ctx, runHandle, outTestCase);
          if (res != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to get next test case',
              res.value,
            );
          }
          tcHandle = outTestCase.value;

          if (tcHandle == nullptr) {
            break; // Run finished
          }
          testCasesRun++;

          var wantsOutput = false;
          var wantsDetail = false;
          if (hegel_test_case_wants_output(ctx, tcHandle, outWantsOutput) ==
              hegel_result_t.HEGEL_OK) {
            wantsOutput = outWantsOutput.value;
          }
          if (hegel_test_case_wants_detail(ctx, tcHandle, outWantsDetail) ==
              hegel_result_t.HEGEL_OK) {
            wantsDetail = outWantsDetail.value;
          }

          final tc = TestCase(
            ctx,
            tcHandle,
            lifecycle,
            bufferCache: sharedBufferCache,
          );
          var status = hegel_status_t.HEGEL_STATUS_VALID.value;
          String? originStr;
          String? caughtErrorText;
          StackTrace? caughtStack;

          try {
            if (setUpEach != null) await setUpEach();

            // Run body in an isolated zone to catch unawaited async errors.
            final completer = Completer<void>();

            unawaited(
              runZonedGuarded(
                () async {
                  try {
                    await body(tc);
                    if (!completer.isCompleted) completer.complete();
                  } catch (e, st) {
                    if (!completer.isCompleted) completer.completeError(e, st);
                  }
                },
                (e, st) {
                  if (!completer.isCompleted) {
                    completer.completeError(e, st);
                  } else {
                    stderr.writeln(
                      '[hegeltest] Late async error (after iteration completed): '
                      '${_safeFormatError(e)}',
                    );
                    stderr.writeln(_safeFormatStackTrace(st));
                  }
                },
              ),
            );

            await completer.future;
          } on HegelStopTest {
            status = hegel_status_t.HEGEL_STATUS_OVERRUN.value;
          } on HegelAssumptionViolated {
            status = hegel_status_t.HEGEL_STATUS_INVALID.value;
          } on HegelException {
            tc.clearStagedObservations();
            rethrow;
          } catch (e, st) {
            status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
            originStr = _nonEmptyOrigin(extractOrigin(st));
            caughtErrorText = _safeFormatError(e);
            caughtStack = st;
            if (wantsOutput || !caughtExceptions.containsKey(originStr)) {
              caughtExceptions[originStr] = (
                errorText: caughtErrorText,
                stackTrace: st,
                drawLog: tc.drawLog,
                notes: tc.notes,
              );
            }
            if (wantsOutput) {
              stampedOrigins.add(originStr);
            }
          } finally {
            if (tearDownEach != null) {
              try {
                await tearDownEach();
              } catch (e, st) {
                if (status == hegel_status_t.HEGEL_STATUS_VALID.value) {
                  status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
                  originStr = _nonEmptyOrigin(extractOrigin(st));
                  caughtErrorText = _safeFormatError(e);
                  caughtStack = st;
                  if (wantsOutput || !caughtExceptions.containsKey(originStr)) {
                    caughtExceptions[originStr] = (
                      errorText: caughtErrorText,
                      stackTrace: st,
                      drawLog: tc.drawLog,
                      notes: tc.notes,
                    );
                  }
                  if (wantsOutput) {
                    stampedOrigins.add(originStr);
                  }
                } else {
                  stderr.writeln(
                    '[hegeltest] tearDownEach threw: ${_safeFormatError(e)}\n'
                    '${_safeFormatStackTrace(st)}',
                  );
                }
              }
            }

            if (status == hegel_status_t.HEGEL_STATUS_VALID.value) {
              validCasesRun++;
              coverageTargets.addAll(tc.coverageTargets);
              final staged = tc.takeStagedObservations();
              for (final entry in staged.entries) {
                final labelMap = statistics.putIfAbsent(entry.key, () => {});
                for (final obs in entry.value) {
                  labelMap[obs] = (labelMap[obs] ?? 0) + 1;
                }
              }
            } else {
              coverageTargets.addAll(tc.coverageTargets);
              tc.clearStagedObservations();
            }
          }

          tc.invalidate();

          _markComplete(
            ctx,
            tcHandle,
            status,
            origin: originStr,
            errorText: caughtErrorText,
            stackTrace: caughtStack,
            wantsOutput: wantsOutput,
            wantsDetail: wantsDetail,
          );

          hegel_test_case_free(ctx, tcHandle);
          tcHandle = nullptr;
        }
      } finally {
        calloc.free(outTestCase);
        calloc.free(outWantsOutput);
        calloc.free(outWantsDetail);
        for (final ptr in sharedBufferCache.values) {
          calloc.free(ptr);
        }
        sharedBufferCache.clear();
      }

      // 4. Report Results
      final outResult = calloc<Pointer<hegel_run_result_t>>();
      try {
        final res = hegel_run_result(ctx, runHandle, outResult);
        if (res != hegel_result_t.HEGEL_OK) {
          throw hegelExceptionWithDetail(
            ctx,
            'Failed to get run result',
            res.value,
          );
        }
        final resultHandle = outResult.value;
        if (resultHandle != nullptr) {
          try {
            if (reproduceBlob == null && testCasesRun > 1) {
              await _replayWinningFailures(
                ctx,
                settings,
                resultHandle,
                callback.nativeFunction,
                lifecycle,
                body,
                stampedOrigins: stampedOrigins,
                caughtExceptions: caughtExceptions,
                setUpEach: setUpEach,
                tearDownEach: tearDownEach,
              );
            }
            return _extractRunResult(
              ctx,
              resultHandle,
              testCasesRun,
              statistics,
              caughtExceptions,
              reproduceBlob: reproduceBlob,
              coverageTargets: coverageTargets,
              validCasesRun: validCasesRun,
            );
          } finally {
            hegel_run_result_free(ctx, resultHandle);
          }
        }
        final coverageFailures = _checkCoverage(
          validCasesRun,
          statistics,
          coverageTargets,
        );
        if (coverageFailures.isNotEmpty) {
          return RunResult(
            status: RunStatus.failed,
            testCasesRun: testCasesRun,
            failures: coverageFailures,
            statistics: _freezeStatistics(statistics),
          );
        }
        return RunResult(
          status: RunStatus.passed,
          testCasesRun: testCasesRun,
          statistics: _freezeStatistics(statistics),
        );
      } finally {
        calloc.free(outResult);
      }
    } finally {
      lifecycle.isAlive = false;
      for (final genPtr in lifecycle.stringGeneratorCache.values) {
        if (genPtr != nullptr) {
          hegel_string_generator_free(ctx, genPtr);
        }
      }
      lifecycle.stringGeneratorCache.clear();
      if (tcHandle != nullptr) hegel_test_case_free(ctx, tcHandle);
      if (runHandle != nullptr) hegel_run_free(ctx, runHandle);
      if (settings != nullptr) hegel_settings_free(ctx, settings);
      hegel_context_free(ctx);
      callback?.close();
    }
  }

  Future<void> run(
    FutureOr<void> Function(TestCase) body, {
    String? reproduceBlob,
    int? testCases,
    int? seed,
    bool? derandomize,
    Set<Phase>? phases,
    Verbosity? verbosity,
    Set<HealthCheck>? suppressHealthChecks,
    bool? reportMultipleFailures,
    String? databaseKey,
    bool? database,
    String? databasePath,
    FutureOr<void> Function()? setUpEach,
    FutureOr<void> Function()? tearDownEach,
  }) async {
    final result = await runWithResult(
      body,
      reproduceBlob: reproduceBlob,
      testCases: testCases,
      seed: seed,
      derandomize: derandomize,
      phases: phases,
      verbosity: verbosity,
      suppressHealthChecks: suppressHealthChecks,
      reportMultipleFailures: reportMultipleFailures,
      databaseKey: databaseKey,
      database: database,
      databasePath: databasePath,
      setUpEach: setUpEach,
      tearDownEach: tearDownEach,
    );

    if (result.status == RunStatus.failed) {
      for (final f in result.failures) {
        if (f.exception is InsufficientCoverageException) {
          throw f.exception!;
        }
      }
      throw HegelTestFailure(
        result.failures.map((f) => f.message).join('\n---\n'),
      );
    } else if (result.status == RunStatus.error) {
      throw HegelTestFailure(result.errorMessage ?? 'Run ended in an error.');
    } else if (verbosity == Verbosity.verbose && result.statistics.isNotEmpty) {
      // ignore: avoid_print
      print('Collected statistics:\n${result.formatStatistics()}');
    }
  }

  static (bool wantsOutput, bool wantsDetail) _queryOutputFlags(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_test_case_t> tcHandle,
  ) {
    final outFlag = calloc<Bool>();
    try {
      var wantsOutput = false;
      var wantsDetail = false;
      if (hegel_test_case_wants_output(ctx, tcHandle, outFlag) ==
          hegel_result_t.HEGEL_OK) {
        wantsOutput = outFlag.value;
      }
      if (hegel_test_case_wants_detail(ctx, tcHandle, outFlag) ==
          hegel_result_t.HEGEL_OK) {
        wantsDetail = outFlag.value;
      }
      return (wantsOutput, wantsDetail);
    } finally {
      calloc.free(outFlag);
    }
  }

  static String _safeFormatError(Object? error) {
    if (error == null) return 'Property failed';
    try {
      return error.toString();
    } catch (formatError) {
      return '<${error.runtimeType}: toString() threw ${formatError.runtimeType}>';
    }
  }

  static String _safeFormatStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return '';
    try {
      return stackTrace.toString();
    } catch (formatError) {
      return '<${stackTrace.runtimeType}: toString() threw ${formatError.runtimeType}>';
    }
  }

  static String _nonEmptyOrigin(String origin) =>
      origin.isEmpty ? 'unknown' : origin;

  static String _buildFailureSummary(String origin, String? errorText) {
    final raw = (errorText ?? 'Property failed')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    final lines = raw.split('\n');
    final firstLine = lines.first.trim().isEmpty
        ? 'Property failed'
        : lines.first.trim();
    final clipped = lines.length > 1 ? '$firstLine …' : firstLine;
    final combined = origin.isNotEmpty ? '$origin: $clipped' : clipped;
    final sanitized = combined
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .trim();
    return sanitized.isEmpty ? 'Property failed' : sanitized;
  }

  static String _buildFailureDetail(
    String origin,
    String? errorText,
    StackTrace? stackTrace,
  ) {
    final stackText = _safeFormatStackTrace(stackTrace).trim();
    if (errorText != null && stackText.isNotEmpty) {
      final detail = '$errorText\n$stackText'.trim();
      if (detail.isNotEmpty) return detail;
    }
    final fallback = (errorText ?? origin).trim();
    return fallback.isEmpty ? 'Property failed' : fallback;
  }

  static void _markComplete(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_test_case_t> tcHandle,
    int status, {
    String? origin,
    String? errorText,
    StackTrace? stackTrace,
    required bool wantsOutput,
    required bool wantsDetail,
  }) {
    if (status != hegel_status_t.HEGEL_STATUS_INTERESTING.value) {
      final compRes = hegel_mark_complete(
        ctx,
        tcHandle,
        status,
        nullptr,
        nullptr,
        nullptr,
      );
      if (compRes != hegel_result_t.HEGEL_OK &&
          compRes != hegel_result_t.HEGEL_E_ALREADY_COMPLETE) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to mark complete',
          compRes.value,
        );
      }
      return;
    }

    final effectiveOrigin = _nonEmptyOrigin(origin ?? '');
    using((Arena arena) {
      final originPtr = allocHegelString(arena, effectiveOrigin);
      final summaryPtr = wantsOutput
          ? allocHegelString(
              arena,
              _buildFailureSummary(effectiveOrigin, errorText),
            )
          : nullptr;
      final detailPtr = wantsDetail
          ? allocHegelString(
              arena,
              _buildFailureDetail(effectiveOrigin, errorText, stackTrace),
            )
          : nullptr;

      final compRes = hegel_mark_complete(
        ctx,
        tcHandle,
        status,
        originPtr,
        summaryPtr,
        detailPtr,
      );
      if (compRes != hegel_result_t.HEGEL_OK &&
          compRes != hegel_result_t.HEGEL_E_ALREADY_COMPLETE) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to mark complete',
          compRes.value,
        );
      }
    });
  }

  static Map<String, Map<String, int>> _freezeStatistics(
    Map<String, Map<String, int>> stats,
  ) {
    if (stats.isEmpty) return const {};
    final filtered = Map<String, Map<String, int>>.from(stats)
      ..remove('__hegel_coverage__');
    if (filtered.isEmpty) return const {};
    return Map<String, Map<String, int>>.unmodifiable(
      filtered.map((k, v) => MapEntry(k, Map<String, int>.unmodifiable(v))),
    );
  }

  Future<void> _replayWinningFailures(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_settings_t> settings,
    Pointer<hegel_run_result_t> resultHandle,
    Pointer<NativeFunction<hegel_output_callback_tFunction>> callbackFn,
    RunLifecycle lifecycle,
    FutureOr<void> Function(TestCase) body, {
    required Set<String> stampedOrigins,
    required Map<String, _CapturedFailure> caughtExceptions,
    FutureOr<void> Function()? setUpEach,
    FutureOr<void> Function()? tearDownEach,
  }) async {
    final outStatus = calloc<UnsignedInt>();
    try {
      final statusRes = hegel_run_result_status(ctx, resultHandle, outStatus);
      if (statusRes != hegel_result_t.HEGEL_OK ||
          outStatus.value != hegel_run_status_t.HEGEL_RUN_STATUS_FAILED.value) {
        return;
      }
    } finally {
      calloc.free(outStatus);
    }

    final countPtr = calloc<Size>();
    int failCount = 0;
    try {
      if (hegel_run_result_failure_count(ctx, resultHandle, countPtr) ==
          hegel_result_t.HEGEL_OK) {
        failCount = countPtr.value;
      }
    } finally {
      calloc.free(countPtr);
    }
    if (failCount == 0) return;

    final winningBlobs = <(String, String)>[];
    for (var i = 0; i < failCount; i++) {
      final failOut = calloc<Pointer<hegel_failure_t>>();
      try {
        if (hegel_run_result_failure(ctx, resultHandle, i, failOut) ==
                hegel_result_t.HEGEL_OK &&
            failOut.value != nullptr) {
          final failure = failOut.value;
          try {
            String? originStr;
            final originOut = calloc<hegel_string_t>();
            try {
              if (hegel_failure_origin(ctx, failure, originOut) ==
                  hegel_result_t.HEGEL_OK) {
                originStr = readHegelString(originOut.ref);
              }
            } finally {
              calloc.free(originOut);
            }

            if (originStr != null && stampedOrigins.contains(originStr)) {
              continue;
            }

            String? blobStr;
            final blobOut = calloc<Pointer<hegel_string_t>>();
            try {
              if (hegel_failure_reproduction_blob(ctx, failure, blobOut) ==
                  hegel_result_t.HEGEL_OK) {
                blobStr = readHegelStringPtr(blobOut.value);
              }
            } finally {
              calloc.free(blobOut);
            }

            if (originStr != null && blobStr != null && blobStr.isNotEmpty) {
              winningBlobs.add((originStr, blobStr));
            }
          } finally {
            hegel_failure_free(ctx, failure);
          }
        }
      } finally {
        calloc.free(failOut);
      }
    }

    if (winningBlobs.isEmpty) return;

    final replayBufferCache = <String, Pointer<Void>>{};
    try {
      for (final (originStr, blobStr) in winningBlobs) {
        Pointer<hegel_test_case_t> replayTcHandle = nullptr;
        using((Arena arena) {
          final outTc = arena<Pointer<hegel_test_case_t>>();
          final res = hegel_test_case_from_blob(
            ctx,
            settings,
            makeHegelString(arena, blobStr),
            callbackFn,
            nullptr,
            outTc,
          );
          if (res == hegel_result_t.HEGEL_OK) {
            replayTcHandle = outTc.value;
          }
        });
        if (replayTcHandle == nullptr) continue;

        final (wantsOutput, wantsDetail) = _queryOutputFlags(
          ctx,
          replayTcHandle,
        );
        final tc = TestCase(
          ctx,
          replayTcHandle,
          lifecycle,
          bufferCache: replayBufferCache,
        );
        var status = hegel_status_t.HEGEL_STATUS_VALID.value;
        String? caughtErrorText;
        StackTrace? caughtStack;
        List<(String, String)>? drawLog;
        List<String>? notes;

        try {
          if (setUpEach != null) await setUpEach();
          final completer = Completer<void>();
          unawaited(
            runZonedGuarded(
              () async {
                try {
                  await body(tc);
                  if (!completer.isCompleted) completer.complete();
                } catch (e, st) {
                  if (!completer.isCompleted) completer.completeError(e, st);
                }
              },
              (e, st) {
                if (!completer.isCompleted) {
                  completer.completeError(e, st);
                }
              },
            ),
          );
          await completer.future;
        } on HegelStopTest {
          status = hegel_status_t.HEGEL_STATUS_OVERRUN.value;
        } on HegelAssumptionViolated {
          status = hegel_status_t.HEGEL_STATUS_INVALID.value;
        } on HegelException {
          tc.clearStagedObservations();
        } catch (e, st) {
          status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
          caughtErrorText = _safeFormatError(e);
          caughtStack = st;
        } finally {
          if (tearDownEach != null) {
            try {
              await tearDownEach();
            } catch (e, st) {
              if (status == hegel_status_t.HEGEL_STATUS_VALID.value) {
                status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
                caughtErrorText = _safeFormatError(e);
                caughtStack = st;
              }
            }
          }
          drawLog = tc.drawLog;
          notes = tc.notes;
          tc.clearStagedObservations();
          tc.invalidate();
          _markComplete(
            ctx,
            replayTcHandle,
            status,
            origin: status == hegel_status_t.HEGEL_STATUS_INTERESTING.value
                ? originStr
                : null,
            errorText: caughtErrorText,
            stackTrace: caughtStack,
            wantsOutput: wantsOutput,
            wantsDetail: wantsDetail,
          );
          hegel_test_case_free(ctx, replayTcHandle);
        }

        if (caughtErrorText != null &&
            caughtStack != null &&
            (!caughtExceptions.containsKey(originStr) ||
                _nonEmptyOrigin(extractOrigin(caughtStack)) == originStr)) {
          caughtExceptions[originStr] = (
            errorText: caughtErrorText,
            stackTrace: caughtStack,
            drawLog: drawLog,
            notes: notes,
          );
        }
      }
    } finally {
      for (final ptr in replayBufferCache.values) {
        calloc.free(ptr);
      }
      replayBufferCache.clear();
    }
  }

  RunResult _extractRunResult(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_run_result_t> resultHandle,
    int testCasesRun,
    Map<String, Map<String, int>> statistics,
    Map<String, _CapturedFailure> caughtExceptions, {
    String? reproduceBlob,
    Map<String, double> coverageTargets = const {},
    int validCasesRun = 0,
  }) {
    final outStatus = calloc<UnsignedInt>();
    int statusValue;
    try {
      final statusRes = hegel_run_result_status(ctx, resultHandle, outStatus);
      if (statusRes != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to get run status',
          statusRes.value,
        );
      }
      statusValue = outStatus.value;
    } finally {
      calloc.free(outStatus);
    }

    final frozenStats = _freezeStatistics(statistics);
    if (statusValue == hegel_run_status_t.HEGEL_RUN_STATUS_FAILED.value) {
      final failures = _extractFailures(
        ctx,
        resultHandle,
        caughtExceptions,
        reproduceBlob: reproduceBlob,
      );
      return RunResult(
        status: RunStatus.failed,
        testCasesRun: testCasesRun,
        failures: failures,
        statistics: frozenStats,
      );
    } else if (statusValue == hegel_run_status_t.HEGEL_RUN_STATUS_ERROR.value) {
      final errorKind = _extractErrorKind(ctx, resultHandle);
      final errMsg = _extractError(ctx, resultHandle);
      return RunResult(
        status: RunStatus.error,
        errorKind: errorKind,
        testCasesRun: testCasesRun,
        errorMessage: errMsg,
        statistics: frozenStats,
      );
    }

    final coverageFailures = _checkCoverage(
      validCasesRun,
      statistics,
      coverageTargets,
    );
    if (coverageFailures.isNotEmpty) {
      return RunResult(
        status: RunStatus.failed,
        testCasesRun: testCasesRun,
        failures: coverageFailures,
        statistics: frozenStats,
      );
    }

    return RunResult(
      status: RunStatus.passed,
      testCasesRun: testCasesRun,
      statistics: frozenStats,
    );
  }

  static RunErrorKind _extractErrorKind(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_run_result_t> resultHandle,
  ) {
    final kindOut = calloc<UnsignedInt>();
    try {
      if (hegel_run_result_error_kind(ctx, resultHandle, kindOut, nullptr) !=
          hegel_result_t.HEGEL_OK) {
        return RunErrorKind.internal;
      }
      return switch (kindOut.value) {
        0 => RunErrorKind.none,
        1 => RunErrorKind.healthCheck,
        2 => RunErrorKind.flaky,
        3 => RunErrorKind.nondeterministic,
        4 => RunErrorKind.unsatisfiable,
        5 => RunErrorKind.usage,
        6 => RunErrorKind.internal,
        _ => RunErrorKind.internal,
      };
    } finally {
      calloc.free(kindOut);
    }
  }

  static List<Failure> _checkCoverage(
    int validCasesRun,
    Map<String, Map<String, int>> statistics,
    Map<String, double> coverageTargets,
  ) {
    if (coverageTargets.isEmpty) return const [];
    final coverageStats = statistics['__hegel_coverage__'] ?? const {};
    final failures = <Failure>[];

    for (final entry in coverageTargets.entries) {
      final label = entry.key;
      final minPercentage = entry.value;
      final hitCount = coverageStats[label] ?? 0;
      final actualPercent = validCasesRun > 0
          ? (hitCount / validCasesRun * 100.0)
          : 0.0;

      if (actualPercent < minPercentage) {
        final ex = InsufficientCoverageException(
          label: label,
          requiredPercent: minPercentage,
          actualPercent: actualPercent,
          hitCount: hitCount,
          totalCount: validCasesRun,
        );
        failures.add(
          Failure(
            message: ex.message,
            origin: '',
            reproductionBlob: '',
            exception: ex,
          ),
        );
      }
    }
    return failures;
  }

  List<Failure> _extractFailures(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_run_result_t> resultHandle,
    Map<String, _CapturedFailure> caughtExceptions, {
    String? reproduceBlob,
  }) {
    final countPtr = calloc<Size>();
    try {
      final countRes = hegel_run_result_failure_count(
        ctx,
        resultHandle,
        countPtr,
      );
      if (countRes != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          ctx,
          'Failed to get failure count',
          countRes.value,
        );
      }
      final failCount = countPtr.value;
      if (failCount == 0) return [];

      final failures = <Failure>[];
      for (var i = 0; i < failCount; i++) {
        final failOut = calloc<Pointer<hegel_failure_t>>();
        try {
          final failRes = hegel_run_result_failure(
            ctx,
            resultHandle,
            i,
            failOut,
          );
          if (failRes != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              ctx,
              'Failed to get failure $i',
              failRes.value,
            );
          }
          final failure = failOut.value;
          if (failure != nullptr) {
            try {
              final message = _extractFailureMessage(
                ctx,
                failure,
                caughtExceptions,
              );

              var originStr = '';
              final originOut = calloc<hegel_string_t>();
              try {
                if (hegel_failure_origin(ctx, failure, originOut) ==
                    hegel_result_t.HEGEL_OK) {
                  originStr = readHegelString(originOut.ref);
                }
              } finally {
                calloc.free(originOut);
              }

              var blobStr = '';
              final blobOut = calloc<Pointer<hegel_string_t>>();
              try {
                if (hegel_failure_reproduction_blob(ctx, failure, blobOut) ==
                    hegel_result_t.HEGEL_OK) {
                  blobStr = readHegelStringPtr(blobOut.value) ?? '';
                }
              } finally {
                calloc.free(blobOut);
              }

              failures.add(
                Failure(
                  message: message,
                  origin: originStr,
                  reproductionBlob: blobStr.isNotEmpty
                      ? blobStr
                      : (reproduceBlob ?? ''),
                ),
              );
            } finally {
              hegel_failure_free(ctx, failure);
            }
          }
        } finally {
          calloc.free(failOut);
        }
      }
      return failures;
    } finally {
      calloc.free(countPtr);
    }
  }

  String _extractError(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_run_result_t> resultHandle,
  ) {
    final errOut = calloc<Pointer<hegel_string_t>>();
    try {
      hegel_run_result_error(ctx, resultHandle, errOut);
      return readHegelStringPtr(errOut.value) ?? 'Run ended in an error.';
    } finally {
      calloc.free(errOut);
    }
  }

  String _extractFailureMessage(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_failure_t> failure,
    Map<String, _CapturedFailure> caughtExceptions,
  ) {
    final buf = StringBuffer('Property failed.');

    String? originStr;
    final originOut = calloc<hegel_string_t>();
    try {
      if (hegel_failure_origin(ctx, failure, originOut) ==
          hegel_result_t.HEGEL_OK) {
        final decoded = readHegelString(originOut.ref);
        if (decoded.isNotEmpty) {
          originStr = decoded;
          buf.write(' Origin: $originStr');
        }
      }
    } finally {
      calloc.free(originOut);
    }

    final captured = originStr != null ? caughtExceptions[originStr] : null;
    if (captured != null) {
      buf.write('\n\nCaused by: ${captured.errorText}');
      final stackText = _safeFormatStackTrace(captured.stackTrace);
      if (stackText.isNotEmpty) {
        buf.write('\n$stackText');
      }

      if (captured.drawLog.isNotEmpty) {
        buf.write('\nCounterexample:');
        for (var i = 0; i < captured.drawLog.length; i++) {
          final (label, value) = captured.drawLog[i];
          buf.write('\n  draw #${i + 1} ($label): $value');
        }
      }
    } else {
      final diagOut = calloc<Pointer<hegel_string_t>>();
      try {
        if (hegel_failure_diagnostic(ctx, failure, diagOut) ==
            hegel_result_t.HEGEL_OK) {
          final diag = readHegelStringPtr(diagOut.value);
          if (diag != null && diag.isNotEmpty) {
            buf.write('\n\n$diag');
          }
        }
      } finally {
        calloc.free(diagOut);
      }
    }

    String? nativeOutput;
    final outputOut = calloc<Pointer<hegel_string_t>>();
    try {
      if (hegel_failure_output(ctx, failure, outputOut) ==
          hegel_result_t.HEGEL_OK) {
        nativeOutput = readHegelStringPtr(outputOut.value);
      }
    } finally {
      calloc.free(outputOut);
    }
    if (nativeOutput != null && nativeOutput.isNotEmpty) {
      buf.write('\n\nNotes:\n$nativeOutput');
    } else if (captured != null && captured.notes.isNotEmpty) {
      buf.write('\n\nNotes:\n${captured.notes.join('\n')}');
    }

    final caveatOut = calloc<Pointer<hegel_string_t>>();
    try {
      if (hegel_failure_caveat(ctx, failure, caveatOut) ==
          hegel_result_t.HEGEL_OK) {
        final caveat = readHegelStringPtr(caveatOut.value);
        if (caveat != null && caveat.isNotEmpty) {
          buf.write('\n\nCaveat:\n$caveat');
        }
      }
    } finally {
      calloc.free(caveatOut);
    }

    final blobOut = calloc<Pointer<hegel_string_t>>();
    try {
      if (hegel_failure_reproduction_blob(ctx, failure, blobOut) ==
          hegel_result_t.HEGEL_OK) {
        final blob = readHegelStringPtr(blobOut.value);
        if (blob != null && blob.isNotEmpty) {
          buf.write(
            '\n\nTo reproduce, add to your hegelTest() call:\n'
            '  reproduce: \'$blob\'',
          );
        }
      }
    } finally {
      calloc.free(blobOut);
    }

    return buf.toString();
  }
}

/// Run a property-based test using hegeltest.
///
/// Integrates with `package:test`. The [body] receives a [TestCase]
/// to draw values from. Both sync and async bodies are supported.
///
/// **Note:** `setUp` / `tearDown` run once per property (i.e. once
/// before all test cases), not once per individual generated test case.
void hegelTest(
  String description,
  FutureOr<void> Function(TestCase tc) body, {
  Timeout? timeout,
  dynamic tags,
  dynamic skip,
  Map<String, dynamic>? onPlatform,
  int? retry,
  HegelConfig? config,
  int? testCases,
  int? seed,
  bool? derandomize,
  Set<Phase>? phases,
  Verbosity? verbosity,
  Set<HealthCheck>? suppressHealthChecks,
  bool? reportMultipleFailures,
  String? reproduce,
  String? databaseKey,
  bool? database,
  String? databasePath,
  FutureOr<void> Function()? setUpEach,
  FutureOr<void> Function()? tearDownEach,
}) {
  test(
    description,
    () async {
      final runner = HegelRunner();
      await runner.run(
        body,
        reproduceBlob: reproduce ?? config?.reproduce,
        testCases: testCases ?? config?.testCases,
        seed: seed ?? config?.seed ?? envSeed(),
        derandomize: derandomize ?? config?.derandomize,
        phases: phases ?? config?.phases,
        verbosity: verbosity ?? config?.verbosity,
        suppressHealthChecks:
            suppressHealthChecks ?? config?.suppressHealthChecks,
        reportMultipleFailures:
            reportMultipleFailures ?? config?.reportMultipleFailures,
        databaseKey: databaseKey ?? config?.databaseKey ?? description,
        database: database ?? config?.database,
        databasePath: databasePath ?? config?.databasePath,
        setUpEach: setUpEach,
        tearDownEach: tearDownEach,
      );
    },
    timeout: timeout ?? const Timeout(Duration(minutes: 10)),
    tags: tags,
    skip: skip,
    onPlatform: onPlatform,
    retry: retry,
  );
}

/// Run a property-based test standalone, returning a [RunResult] instead of
/// throwing an exception.
Future<RunResult> runHegelTest(
  FutureOr<void> Function(TestCase tc) body, {
  HegelConfig? config,
  int? testCases,
  int? seed,
  bool? derandomize,
  Set<Phase>? phases,
  Verbosity? verbosity,
  Set<HealthCheck>? suppressHealthChecks,
  bool? reportMultipleFailures,
  String? reproduce,
  String? databaseKey,
  bool? database,
  String? databasePath,
  FutureOr<void> Function()? setUpEach,
  FutureOr<void> Function()? tearDownEach,
}) async {
  final runner = HegelRunner();
  return runner.runWithResult(
    body,
    reproduceBlob: reproduce ?? config?.reproduce,
    testCases: testCases ?? config?.testCases,
    seed: seed ?? config?.seed ?? envSeed(),
    derandomize: derandomize ?? config?.derandomize,
    phases: phases ?? config?.phases,
    verbosity: verbosity ?? config?.verbosity,
    suppressHealthChecks: suppressHealthChecks ?? config?.suppressHealthChecks,
    reportMultipleFailures:
        reportMultipleFailures ?? config?.reportMultipleFailures,
    databaseKey: databaseKey ?? config?.databaseKey ?? 'runHegelTest',
    database: database ?? config?.database,
    databasePath: databasePath ?? config?.databasePath,
    setUpEach: setUpEach,
    tearDownEach: tearDownEach,
  );
}

/// Check the `HEGEL_DATABASE` environment variable for global persistence control.
///
/// Defaults to `true` (enabled) unless explicitly set to `0`, `false`, `no`, or `off`.
bool _envDatabase(bool? userSetting) {
  if (userSetting != null) return userSetting;
  final env = Platform.environment['HEGEL_DATABASE']?.trim().toLowerCase();
  if (env == '0' || env == 'false' || env == 'no' || env == 'off') {
    return false;
  }
  return true;
}

/// Ensure `.gitignore` exists inside the database directory so git worktrees stay clean.
void _ensureHegelGitignore(String? dbDir) {
  try {
    final Directory targetDir;
    if (dbDir == null) {
      targetDir = Directory('.hegel');
    } else {
      targetDir = Directory(dbDir);
    }
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    final gitignore = File('${targetDir.path}/.gitignore');
    if (!gitignore.existsSync()) {
      gitignore.writeAsStringSync('*\n!.gitignore\n');
    }
  } catch (_) {
    // Non-fatal if filesystem is read-only or in sandboxed environment.
  }
}

/// Parse the `HEGEL_SEED` environment variable for CI reproducibility.
@internal
int? envSeed() {
  final raw = Platform.environment['HEGEL_SEED'];
  if (raw == null || raw.isEmpty) return null;
  final parsed = int.tryParse(raw);
  if (parsed == null) {
    throw ArgumentError(
      'HEGEL_SEED environment variable must be a valid integer, '
      'got: "$raw"',
    );
  }
  return parsed;
}
