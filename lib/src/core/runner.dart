import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import '../ffi/hegel_bindings.g.dart';
import '../ffi/library_loader.dart';
import 'exceptions.dart';
import 'origin.dart';
import 'result.dart';
import 'settings.dart';
import 'hegel_settings.dart';
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

class HegelRunner {
  final LibHegel lib;

  HegelRunner(this.lib);

  /// Map of origin strings to (exception, stack trace, draw log) for reporting.
  final Map<String, (Object, StackTrace, List<(String, String)>)>
  _caughtExceptions = {};

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
    String? database,
    FutureOr<void> Function()? setUpEach,
    FutureOr<void> Function()? tearDownEach,
  }) async {
    final ctx = lib.hegel_context_new();
    final lifecycle = RunLifecycle();
    Pointer<hegel_settings_t> settings = nullptr;
    Pointer<hegel_run_t> runHandle = nullptr;
    Pointer<hegel_test_case_t> tcHandle = nullptr;
    NativeCallable<hegel_output_callback_tFunction>? callback;

    try {
      // 1. Create Settings
      final outSettings = calloc<Pointer<hegel_settings_t>>();
      try {
        final res = lib.hegel_settings_new(ctx, outSettings);
        if (res != hegel_result_t.HEGEL_OK) {
          throw hegelExceptionWithDetail(
            lib,
            ctx,
            'Failed to create settings',
            res.value,
          );
        }
        settings = outSettings.value;
      } finally {
        calloc.free(outSettings);
      }

      // Apply user settings
      applySettings(
        lib,
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
        database: database,
      );

      // Per the C API docs, the callback is invoked synchronously on
      // whichever thread calls hegel_next_test_case — which is our
      // isolate's thread. So isolateLocal is safe and correct here.
      callback = NativeCallable<hegel_output_callback_tFunction>.isolateLocal(
        _outputCallback,
      );

      if (reproduceBlob != null) {
        if (reproduceBlob.contains('\x00')) {
          throw ArgumentError('reproduce blob must not contain NUL bytes');
        }
        // Replay a single blob
        using((Arena arena) {
          final blobPtr = reproduceBlob
              .toNativeUtf8(allocator: arena)
              .cast<Char>();
          final outTestCase = arena<Pointer<hegel_test_case_t>>();
          final res = lib.hegel_test_case_from_blob(
            ctx,
            settings,
            blobPtr,
            callback!.nativeFunction,
            nullptr,
            outTestCase,
          );
          if (res != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              lib,
              ctx,
              'Failed to load test case from blob',
              res.value,
            );
          }
          tcHandle = outTestCase.value;
        });

        final tc = TestCase(ctx, tcHandle, lib, lifecycle);
        var status = hegel_status_t.HEGEL_STATUS_VALID.value;
        String? originStr;
        Object? caughtError;
        StackTrace? caughtStack;

        try {
          if (setUpEach != null) await setUpEach();

          final completer = Completer<void>();
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
                  '[hegeltest] Late async error (after iteration completed): $e',
                );
                stderr.writeln(st);
              }
            },
          );

          await completer.future;
        } on HegelStopTest {
          status = hegel_status_t.HEGEL_STATUS_OVERRUN.value;
        } on HegelAssumptionViolated {
          status = hegel_status_t.HEGEL_STATUS_INVALID.value;
        } on HegelException {
          rethrow;
        } catch (e, st) {
          status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
          originStr = extractOrigin(st);
          caughtError = e;
          caughtStack = st;
        } finally {
          if (tearDownEach != null) {
            try {
              await tearDownEach();
            } catch (e, st) {
              if (status == hegel_status_t.HEGEL_STATUS_VALID.value) {
                status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
                originStr = extractOrigin(st);
                caughtError = e;
                caughtStack = st;
              } else {
                stderr.writeln('[hegeltest] tearDownEach threw: $e\n$st');
              }
            }
          }
        }

        using((Arena arena) {
          Pointer<Char> originPtr = nullptr;
          if (originStr != null) {
            originPtr = originStr.toNativeUtf8(allocator: arena).cast<Char>();
          }
          final compRes = lib.hegel_mark_complete(
            ctx,
            tcHandle,
            status,
            originPtr,
          );
          if (compRes != hegel_result_t.HEGEL_OK &&
              compRes != hegel_result_t.HEGEL_E_ALREADY_COMPLETE) {
            throw hegelExceptionWithDetail(
              lib,
              ctx,
              'Failed to mark complete',
              compRes.value,
            );
          }
        });

        if (status == hegel_status_t.HEGEL_STATUS_INTERESTING.value) {
          String message =
              'Property failed during blob replay. Origin: $originStr';
          if (caughtError != null && caughtStack != null) {
            final drawLogStr = tc.drawLog.isNotEmpty
                ? '\nCounterexample:\n${tc.drawLog.indexed.map((e) => '  draw #${e.$1 + 1} (${e.$2.$1}): ${e.$2.$2}').join('\n')}'
                : '';
            message =
                'Property failed during blob replay. Origin: $originStr\n'
                '\nCaused by: $caughtError'
                '\n$caughtStack'
                '$drawLogStr';
          }
          return RunResult(
            status: RunStatus.failed,
            testCasesRun: 1,
            failures: [
              Failure(
                message: message,
                origin: originStr ?? '',
                reproductionBlob: reproduceBlob,
              ),
            ],
          );
        }

        return const RunResult(
          status: RunStatus.passed,
          testCasesRun: 1,
        ); // Done with blob replay
      }

      // 2. Start Run
      final outRun = calloc<Pointer<hegel_run_t>>();
      try {
        final res = lib.hegel_run_start(
          ctx,
          settings,
          callback.nativeFunction,
          nullptr,
          outRun,
        );
        if (res != hegel_result_t.HEGEL_OK) {
          throw hegelExceptionWithDetail(
            lib,
            ctx,
            'Failed to start run',
            res.value,
          );
        }
        runHandle = outRun.value;
      } finally {
        calloc.free(outRun);
      }

      // 3. Test case loop
      // Hoist the out-parameter allocation outside the loop to avoid
      // per-iteration alloc/free overhead (significant at 100K+ iterations).
      final outTestCase = calloc<Pointer<hegel_test_case_t>>();
      // Shared buffer cache survives across iterations — freed at end-of-run.
      final sharedBufferCache = <String, Pointer<Void>>{};
      int testCasesRun = 0;
      try {
        while (true) {
          final res = lib.hegel_next_test_case(ctx, runHandle, outTestCase);
          if (res != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              lib,
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

          final tc = TestCase(
            ctx,
            tcHandle,
            lib,
            lifecycle,
            bufferCache: sharedBufferCache,
          );
          var status = hegel_status_t.HEGEL_STATUS_VALID.value;
          String? originStr;

          try {
            if (setUpEach != null) await setUpEach();

            // Run body in an isolated zone to catch unawaited async errors.
            // Without this, a delayed Future.error from iteration N could
            // crash iteration N+10, attributing the failure to wrong inputs.
            final completer = Completer<void>();

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
                // Unawaited async error caught by zone
                if (!completer.isCompleted) {
                  completer.completeError(e, st);
                } else {
                  // Late async error — body already completed. Log instead of swallowing.
                  stderr.writeln(
                    '[hegeltest] Late async error (after iteration completed): $e',
                  );
                  stderr.writeln(st);
                }
              },
            );

            await completer.future;
          } on HegelStopTest {
            status = hegel_status_t.HEGEL_STATUS_OVERRUN.value;
          } on HegelAssumptionViolated {
            status = hegel_status_t.HEGEL_STATUS_INVALID.value;
          } on HegelException {
            // Framework/engine errors must not be treated as property failures.
            // Rethrow so the runner's outer try/finally handles cleanup.
            rethrow;
          } catch (e, st) {
            status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
            originStr = extractOrigin(st);
            // Store the exception with draw log for counterexample reporting
            _caughtExceptions[originStr] = (e, st, tc.drawLog);
          } finally {
            if (tearDownEach != null) {
              try {
                await tearDownEach();
              } catch (e, st) {
                // If the test passed but tearDown failed, treat as a failure.
                if (status == hegel_status_t.HEGEL_STATUS_VALID.value) {
                  status = hegel_status_t.HEGEL_STATUS_INTERESTING.value;
                  originStr = extractOrigin(st);
                  _caughtExceptions[originStr] = (e, st, tc.drawLog);
                } else {
                  // Don't mask the original exception
                  stderr.writeln('[hegeltest] tearDownEach threw: $e\n$st');
                }
              }
            }
          }

          // Invalidate the test case so captured references can't
          // use freed native pointers.
          tc.invalidate();

          // Complete the test case.
          // Fast-path: skip Arena allocation when no origin string needed
          // (the ~99% passing case).
          if (originStr == null) {
            final compRes = lib.hegel_mark_complete(
              ctx,
              tcHandle,
              status,
              nullptr,
            );
            if (compRes != hegel_result_t.HEGEL_OK &&
                compRes != hegel_result_t.HEGEL_E_ALREADY_COMPLETE) {
              throw hegelExceptionWithDetail(
                lib,
                ctx,
                'Failed to mark complete',
                compRes.value,
              );
            }
          } else {
            final origin = originStr;
            using((Arena arena) {
              final originPtr = origin
                  .toNativeUtf8(allocator: arena)
                  .cast<Char>();
              final compRes = lib.hegel_mark_complete(
                ctx,
                tcHandle,
                status,
                originPtr,
              );
              if (compRes != hegel_result_t.HEGEL_OK &&
                  compRes != hegel_result_t.HEGEL_E_ALREADY_COMPLETE) {
                throw hegelExceptionWithDetail(
                  lib,
                  ctx,
                  'Failed to mark complete',
                  compRes.value,
                );
              }
            });
          }

          lib.hegel_test_case_free(ctx, tcHandle);
          tcHandle = nullptr;
        }
      } finally {
        calloc.free(outTestCase);
        // Free the shared buffer cache at end-of-run.
        for (final ptr in sharedBufferCache.values) {
          calloc.free(ptr);
        }
        sharedBufferCache.clear();
      }

      // 4. Report Results
      final outResult = calloc<Pointer<hegel_run_result_t>>();
      try {
        final res = lib.hegel_run_result(ctx, runHandle, outResult);
        if (res != hegel_result_t.HEGEL_OK) {
          throw hegelExceptionWithDetail(
            lib,
            ctx,
            'Failed to get run result',
            res.value,
          );
        }
        final resultHandle = outResult.value;
        if (resultHandle != nullptr) {
          try {
            return _extractRunResult(ctx, resultHandle, testCasesRun);
          } finally {
            lib.hegel_run_result_free(ctx, resultHandle);
          }
        }
        return RunResult(status: RunStatus.passed, testCasesRun: testCasesRun);
      } finally {
        calloc.free(outResult);
      }
    } finally {
      // Mark the run as dead BEFORE freeing ctx — this prevents
      // the GC finalizer and zombie clone usage from touching freed
      // memory. This is the single point of lifecycle coordination.
      lifecycle.isAlive = false;
      if (tcHandle != nullptr) lib.hegel_test_case_free(ctx, tcHandle);
      if (runHandle != nullptr) lib.hegel_run_free(ctx, runHandle);
      if (settings != nullptr) lib.hegel_settings_free(ctx, settings);
      lib.hegel_context_free(ctx);
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
    String? database,
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
      setUpEach: setUpEach,
      tearDownEach: tearDownEach,
    );

    if (result.status == RunStatus.failed) {
      throw HegelTestFailure(
        result.failures.map((f) => f.message).join('\n---\n'),
      );
    } else if (result.status == RunStatus.error) {
      throw HegelTestFailure(result.errorMessage ?? 'Run ended in an error.');
    }
  }

  RunResult _extractRunResult(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_run_result_t> resultHandle,
    int testCasesRun,
  ) {
    final outStatus = calloc<UnsignedInt>();
    int statusValue;
    try {
      final statusRes = lib.hegel_run_result_status(
        ctx,
        resultHandle,
        outStatus,
      );
      if (statusRes != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          lib,
          ctx,
          'Failed to get run status',
          statusRes.value,
        );
      }
      statusValue = outStatus.value;
    } finally {
      calloc.free(outStatus);
    }

    if (statusValue == hegel_run_status_t.HEGEL_RUN_STATUS_FAILED.value) {
      final failures = _extractFailures(ctx, resultHandle);
      return RunResult(
        status: RunStatus.failed,
        testCasesRun: testCasesRun,
        failures: failures,
      );
    } else if (statusValue == hegel_run_status_t.HEGEL_RUN_STATUS_ERROR.value) {
      final errMsg = _extractError(ctx, resultHandle);
      return RunResult(
        status: RunStatus.error,
        testCasesRun: testCasesRun,
        errorMessage: errMsg,
      );
    }
    return RunResult(status: RunStatus.passed, testCasesRun: testCasesRun);
  }

  List<Failure> _extractFailures(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_run_result_t> resultHandle,
  ) {
    final countPtr = calloc<Size>();
    try {
      final countRes = lib.hegel_run_result_failure_count(
        ctx,
        resultHandle,
        countPtr,
      );
      if (countRes != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          lib,
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
          final failRes = lib.hegel_run_result_failure(
            ctx,
            resultHandle,
            i,
            failOut,
          );
          if (failRes != hegel_result_t.HEGEL_OK) {
            throw hegelExceptionWithDetail(
              lib,
              ctx,
              'Failed to get failure $i',
              failRes.value,
            );
          }
          final failure = failOut.value;
          if (failure != nullptr) {
            try {
              final message = _extractFailureMessage(ctx, failure);

              String originStr = '';
              final originOut = calloc<Pointer<Char>>();
              try {
                lib.hegel_failure_origin(ctx, failure, originOut);
                if (originOut.value != nullptr) {
                  originStr = originOut.value.cast<Utf8>().toDartString();
                }
              } finally {
                calloc.free(originOut);
              }

              String blobStr = '';
              final blobOut = calloc<Pointer<Char>>();
              try {
                lib.hegel_failure_reproduction_blob(ctx, failure, blobOut);
                if (blobOut.value != nullptr) {
                  blobStr = blobOut.value.cast<Utf8>().toDartString();
                }
              } finally {
                calloc.free(blobOut);
              }

              failures.add(
                Failure(
                  message: message,
                  origin: originStr,
                  reproductionBlob: blobStr,
                ),
              );
            } finally {
              lib.hegel_failure_free(ctx, failure);
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
    final errOut = calloc<Pointer<Char>>();
    try {
      lib.hegel_run_result_error(ctx, resultHandle, errOut);
      var errMsg = 'Run ended in an error.';
      if (errOut.value != nullptr) {
        errMsg = errOut.value.cast<Utf8>().toDartString();
      }
      return errMsg;
    } finally {
      calloc.free(errOut);
    }
  }

  String _extractFailureMessage(
    Pointer<hegel_context_t> ctx,
    Pointer<hegel_failure_t> failure,
  ) {
    final buf = StringBuffer('Property failed.');

    // Extract origin
    String? originStr;
    final originOut = calloc<Pointer<Char>>();
    try {
      lib.hegel_failure_origin(ctx, failure, originOut);
      if (originOut.value != nullptr) {
        originStr = originOut.value.cast<Utf8>().toDartString();
        buf.write(' Origin: $originStr');
      }
    } finally {
      calloc.free(originOut);
    }

    // Include the actual Dart exception if we captured one
    if (originStr != null && _caughtExceptions.containsKey(originStr)) {
      final (error, stackTrace, drawLog) = _caughtExceptions[originStr]!;
      buf.write('\n\nCaused by: $error');
      buf.write('\n$stackTrace');

      // Include counterexample values
      if (drawLog.isNotEmpty) {
        buf.write('\nCounterexample:');
        for (var i = 0; i < drawLog.length; i++) {
          final (label, value) = drawLog[i];
          buf.write('\n  draw #${i + 1} ($label): $value');
        }
      }
    }

    final blobOut = calloc<Pointer<Char>>();
    try {
      lib.hegel_failure_reproduction_blob(ctx, failure, blobOut);
      if (blobOut.value != nullptr) {
        final blob = blobOut.value.cast<Utf8>().toDartString();
        buf.write(
          '\n\nTo reproduce, add to your hegelTest() call:\n'
          '  reproduce: \'$blob\'',
        );
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
///
/// ```dart
/// hegelTest('addition is commutative', (tc) {
///   final a = tc.draw(integers());
///   final b = tc.draw(integers());
///   expect(a + b, equals(b + a));
/// });
/// ```
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
  String? database,
  FutureOr<void> Function()? setUpEach,
  FutureOr<void> Function()? tearDownEach,
}) {
  test(
    description,
    () async {
      final lib = loadHegelLibrary();
      final runner = HegelRunner(lib);
      await runner.run(
        body,
        reproduceBlob: reproduce ?? config?.reproduce,
        testCases: testCases ?? config?.testCases,
        seed: seed ?? config?.seed ?? _envSeed(),
        derandomize: derandomize ?? config?.derandomize,
        phases: phases ?? config?.phases,
        verbosity: verbosity ?? config?.verbosity,
        suppressHealthChecks:
            suppressHealthChecks ?? config?.suppressHealthChecks,
        reportMultipleFailures:
            reportMultipleFailures ?? config?.reportMultipleFailures,
        databaseKey: databaseKey ?? config?.databaseKey,
        database: database ?? config?.database,
        setUpEach: setUpEach,
        tearDownEach: tearDownEach,
      );
    },
    // Fuzzing loops can run many iterations; default to 10 minutes
    // to avoid flaky CI timeouts.
    timeout: timeout ?? const Timeout(Duration(minutes: 10)),
    tags: tags,
    skip: skip,
    onPlatform: onPlatform,
    retry: retry,
  );
}

/// Run a property-based test standalone, returning a [RunResult] instead of
/// throwing an exception.
///
/// This does not depend on `package:test` and is useful for custom test
/// runners, programmatic execution, or analysis.
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
  String? database,
  FutureOr<void> Function()? setUpEach,
  FutureOr<void> Function()? tearDownEach,
}) async {
  final lib = loadHegelLibrary();
  final runner = HegelRunner(lib);
  return runner.runWithResult(
    body,
    reproduceBlob: reproduce ?? config?.reproduce,
    testCases: testCases ?? config?.testCases,
    seed: seed ?? config?.seed ?? _envSeed(),
    derandomize: derandomize ?? config?.derandomize,
    phases: phases ?? config?.phases,
    verbosity: verbosity ?? config?.verbosity,
    suppressHealthChecks: suppressHealthChecks ?? config?.suppressHealthChecks,
    reportMultipleFailures:
        reportMultipleFailures ?? config?.reportMultipleFailures,
    databaseKey: databaseKey ?? config?.databaseKey,
    database: database ?? config?.database,
    setUpEach: setUpEach,
    tearDownEach: tearDownEach,
  );
}

/// Parse the `HEGEL_SEED` environment variable for CI reproducibility.
///
/// When set, all `hegelTest` calls use this seed unless explicitly
/// overridden via the `seed:` parameter.
int? _envSeed() {
  final envSeed = Platform.environment['HEGEL_SEED'];
  if (envSeed == null || envSeed.isEmpty) return null;
  final parsed = int.tryParse(envSeed);
  if (parsed == null) {
    throw ArgumentError(
      'HEGEL_SEED environment variable must be a valid integer, '
      'got: "$envSeed"',
    );
  }
  return parsed;
}
