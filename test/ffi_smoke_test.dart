import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/src/ffi/hegel_bindings.g.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    ensureHegelLibraryVerified();
  });

  test('can create and free context', () {
    final ctx = hegel_context_new();
    expect(ctx, isNot(equals(nullptr)));
    hegel_context_free(ctx);
  });

  test('can get version', () {
    final ctx = hegel_context_new();
    try {
      final outVersion = calloc<hegel_string_t>();
      try {
        final res = hegel_version(ctx, outVersion);
        expect(res, equals(hegel_result_t.HEGEL_OK));
        expect(outVersion.ref.data, isNot(equals(nullptr)));
        final bytes = outVersion.ref.data.cast<Uint8>().asTypedList(
          outVersion.ref.len,
        );
        final version = utf8.decode(bytes);
        expect(version, isNotEmpty);
        expect(hegelNativeVersion(), equals(version));
        expect(version, startsWith('0.53.'));
        // ignore: avoid_print
        print('libhegel version: $version');
      } finally {
        calloc.free(outVersion);
      }
    } finally {
      hegel_context_free(ctx);
    }
  });

  test('can create and free settings', () {
    final ctx = hegel_context_new();
    try {
      final outSettings = calloc<Pointer<hegel_settings_t>>();
      try {
        final res = hegel_settings_new(ctx, outSettings);
        expect(res, equals(hegel_result_t.HEGEL_OK));
        final settings = outSettings.value;
        expect(settings, isNot(equals(nullptr)));
        hegel_settings_free(ctx, settings);
      } finally {
        calloc.free(outSettings);
      }
    } finally {
      hegel_context_free(ctx);
    }
  });

  test('full run lifecycle: draw integer and complete', () {
    final ctx = hegel_context_new();
    try {
      // Create settings
      final outSettings = calloc<Pointer<hegel_settings_t>>();
      hegel_settings_new(ctx, outSettings);
      final settings = outSettings.value;
      calloc.free(outSettings);

      // Set test cases to 5
      hegel_settings_set_test_cases(ctx, settings, 5);

      // Start run
      final outRun = calloc<Pointer<hegel_run_t>>();
      final res = hegel_run_start(ctx, settings, nullptr, nullptr, outRun);
      expect(res, equals(hegel_result_t.HEGEL_OK));
      final runHandle = outRun.value;
      calloc.free(outRun);

      // Test case loop
      var caseCount = 0;
      while (true) {
        final outTc = calloc<Pointer<hegel_test_case_t>>();
        hegel_next_test_case(ctx, runHandle, outTc);
        final tc = outTc.value;
        calloc.free(outTc);

        if (tc == nullptr) break;
        caseCount++;

        // Draw an integer
        final outInt = calloc<Int64>();
        final drawRes = hegel_generate_integer(ctx, tc, -100, 100, outInt);
        expect(drawRes, equals(hegel_result_t.HEGEL_OK));
        final value = outInt.value;
        expect(value, greaterThanOrEqualTo(-100));
        expect(value, lessThanOrEqualTo(100));
        calloc.free(outInt);

        // Mark complete (valid)
        hegel_mark_complete(
          ctx,
          tc,
          hegel_status_t.HEGEL_STATUS_VALID.value,
          nullptr,
          nullptr,
          nullptr,
        );
        hegel_test_case_free(ctx, tc);
      }

      expect(caseCount, equals(5));

      // Get result
      final outResult = calloc<Pointer<hegel_run_result_t>>();
      hegel_run_result(ctx, runHandle, outResult);
      final result = outResult.value;
      calloc.free(outResult);

      final outStatus = calloc<UnsignedInt>();
      hegel_run_result_status(ctx, result, outStatus);
      expect(
        outStatus.value,
        equals(hegel_run_status_t.HEGEL_RUN_STATUS_PASSED.value),
      );
      calloc.free(outStatus);

      hegel_run_result_free(ctx, result);
      hegel_run_free(ctx, runHandle);
      hegel_settings_free(ctx, settings);
    } finally {
      hegel_context_free(ctx);
    }
  });
}
