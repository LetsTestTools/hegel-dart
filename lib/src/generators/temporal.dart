import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../ffi/span_labels.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class DateGenerator extends Generator<DateTime> {
  final DateTime min;
  final DateTime max;

  DateGenerator(this.min, this.max) {
    final minDay = DateTime.utc(min.year, min.month, min.day);
    final maxDay = DateTime.utc(max.year, max.month, max.day);
    if (minDay.isAfter(maxDay)) {
      throw ArgumentError('dates: min ($min) must be <= max ($max)');
    }
  }

  @override
  int get spanLabel => SpanLabels.date;

  @override
  DateTime generate(TestCase tc) {
    return using((Arena arena) {
      final outValue = arena<hegel_date_t>();

      final minDateStruct = arena<hegel_date_t>()
        ..ref.year = min.year
        ..ref.month = min.month
        ..ref.day = min.day;

      final maxDateStruct = arena<hegel_date_t>()
        ..ref.year = max.year
        ..ref.month = max.month
        ..ref.day = max.day;

      final result = hegel_generate_date(
        tc.ctx,
        tc.handle,
        minDateStruct.ref,
        maxDateStruct.ref,
        ffi.nullptr,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          tc.ctx,
          'Failed to generate date',
          result.value,
        );
      }

      return DateTime.utc(
        outValue.ref.year,
        outValue.ref.month,
        outValue.ref.day,
      );
    });
  }
}

/// Generates DateTime values containing only a date component.
///
/// ```dart
/// tc.draw(dates())
/// ```
Generator<DateTime> dates({DateTime? min, DateTime? max}) {
  return DateGenerator(
    min ?? DateTime.utc(1, 1, 1),
    max ?? DateTime.utc(9999, 12, 31),
  );
}

typedef TimeRecord = ({int hour, int minute, int second, int microsecond});

class TimeGenerator extends Generator<TimeRecord> {
  final TimeRecord min;
  final TimeRecord max;

  TimeGenerator(this.min, this.max) {
    _validateTimeRecord(min, 'min');
    _validateTimeRecord(max, 'max');
    if (_toTotalMicros(min) > _toTotalMicros(max)) {
      throw ArgumentError('times: min ($min) must be <= max ($max)');
    }
  }

  @override
  int get spanLabel => SpanLabels.time;

  static void _validateTimeRecord(TimeRecord t, String name) {
    if (t.hour < 0 || t.hour > 23) {
      throw ArgumentError.value(t.hour, '$name.hour', 'must be in 0..23');
    }
    if (t.minute < 0 || t.minute > 59) {
      throw ArgumentError.value(t.minute, '$name.minute', 'must be in 0..59');
    }
    if (t.second < 0 || t.second > 59) {
      throw ArgumentError.value(t.second, '$name.second', 'must be in 0..59');
    }
    if (t.microsecond < 0 || t.microsecond > 999999) {
      throw ArgumentError.value(
        t.microsecond,
        '$name.microsecond',
        'must be in 0..999999',
      );
    }
  }

  static int _toTotalMicros(TimeRecord t) =>
      (((t.hour * 60 + t.minute) * 60 + t.second) * 1000000) + t.microsecond;

  @override
  TimeRecord generate(TestCase tc) {
    return using((Arena arena) {
      final outValue = arena<hegel_time_t>();

      final minTimeStruct = arena<hegel_time_t>()
        ..ref.hour = min.hour
        ..ref.minute = min.minute
        ..ref.second = min.second
        ..ref.nanosecond = min.microsecond * 1000;

      final maxTimeStruct = arena<hegel_time_t>()
        ..ref.hour = max.hour
        ..ref.minute = max.minute
        ..ref.second = max.second
        ..ref.nanosecond = max.microsecond * 1000;

      final result = hegel_generate_time(
        tc.ctx,
        tc.handle,
        minTimeStruct.ref,
        maxTimeStruct.ref,
        hegel_precision_t.HEGEL_PRECISION_MICROSECONDS.value,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          tc.ctx,
          'Failed to generate time',
          result.value,
        );
      }

      return (
        hour: outValue.ref.hour,
        minute: outValue.ref.minute,
        second: outValue.ref.second,
        microsecond: outValue.ref.nanosecond ~/ 1000,
      );
    });
  }
}

/// Generates TimeRecord values containing only a time component.
///
/// ```dart
/// tc.draw(times())
/// ```
Generator<TimeRecord> times({TimeRecord? min, TimeRecord? max}) {
  return TimeGenerator(
    min ?? (hour: 0, minute: 0, second: 0, microsecond: 0),
    max ?? (hour: 23, minute: 59, second: 59, microsecond: 999999),
  );
}

class DateTimeGenerator extends Generator<DateTime> {
  final DateTime min;
  final DateTime max;

  DateTimeGenerator(DateTime min, DateTime max)
    : min = min.toUtc(),
      max = max.toUtc() {
    if (this.min.isAfter(this.max)) {
      throw ArgumentError('dateTimes: min ($min) must be <= max ($max)');
    }
    if (this.min.year < 1 || this.max.year > 9999) {
      throw ArgumentError(
        'dateTimes: UTC year must be in [1, 9999] (got min=${this.min}, max=${this.max})',
      );
    }
  }

  @override
  int get spanLabel => SpanLabels.dateTime;

  @override
  DateTime generate(TestCase tc) {
    return using((Arena arena) {
      final outValue = arena<hegel_datetime_t>();

      final minStruct = arena<hegel_datetime_t>()
        ..ref.date.year = min.year
        ..ref.date.month = min.month
        ..ref.date.day = min.day
        ..ref.time.hour = min.hour
        ..ref.time.minute = min.minute
        ..ref.time.second = min.second
        ..ref.time.nanosecond =
            (min.millisecond * 1000 + min.microsecond) * 1000;

      final maxStruct = arena<hegel_datetime_t>()
        ..ref.date.year = max.year
        ..ref.date.month = max.month
        ..ref.date.day = max.day
        ..ref.time.hour = max.hour
        ..ref.time.minute = max.minute
        ..ref.time.second = max.second
        ..ref.time.nanosecond =
            (max.millisecond * 1000 + max.microsecond) * 1000;

      final result = hegel_generate_datetime(
        tc.ctx,
        tc.handle,
        minStruct.ref,
        maxStruct.ref,
        hegel_precision_t.HEGEL_PRECISION_MICROSECONDS.value,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          tc.ctx,
          'Failed to generate datetime',
          result.value,
        );
      }

      final totalMicroseconds = outValue.ref.time.nanosecond ~/ 1000;
      return DateTime.utc(
        outValue.ref.date.year,
        outValue.ref.date.month,
        outValue.ref.date.day,
        outValue.ref.time.hour,
        outValue.ref.time.minute,
        outValue.ref.time.second,
        totalMicroseconds ~/ 1000, // millisecond
        totalMicroseconds % 1000, // microsecond remainder
      );
    });
  }
}

/// Generates full DateTime values with both date and time.
///
/// ```dart
/// tc.draw(dateTimes())
/// ```
Generator<DateTime> dateTimes({DateTime? min, DateTime? max}) {
  return DateTimeGenerator(
    min ?? DateTime.utc(1, 1, 1),
    max ?? DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999),
  );
}

class DurationGenerator extends Generator<Duration> {
  final Duration min;
  final Duration max;

  DurationGenerator(this.min, this.max) {
    if (min > max) {
      throw ArgumentError('durations: min ($min) must be <= max ($max)');
    }
  }

  @override
  int get spanLabel => SpanLabels.duration;

  @override
  Duration generate(TestCase tc) {
    return using((Arena arena) {
      final outValue = arena<hegel_duration_t>();

      final minMicros = min.inMicroseconds;
      final minStruct = arena<hegel_duration_t>()
        ..ref.seconds = minMicros ~/ 1000000
        ..ref.nanoseconds = minMicros.remainder(1000000) * 1000;

      final maxMicros = max.inMicroseconds;
      final maxStruct = arena<hegel_duration_t>()
        ..ref.seconds = maxMicros ~/ 1000000
        ..ref.nanoseconds = maxMicros.remainder(1000000) * 1000;

      final result = hegel_generate_duration(
        tc.ctx,
        tc.handle,
        minStruct.ref,
        maxStruct.ref,
        hegel_precision_t.HEGEL_PRECISION_MICROSECONDS.value,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw hegelExceptionWithDetail(
          tc.ctx,
          'Failed to generate duration',
          result.value,
        );
      }

      final totalMicroseconds =
          outValue.ref.seconds * 1000000 + (outValue.ref.nanoseconds ~/ 1000);
      return Duration(microseconds: totalMicroseconds);
    });
  }
}

/// Generates [Duration] values between [min] and [max] (inclusive).
///
/// Defaults to ±36500 days (~±100 years) at microsecond precision.
///
/// ```dart
/// tc.draw(durations(min: Duration.zero, max: const Duration(hours: 24)))
/// ```
Generator<Duration> durations({Duration? min, Duration? max}) {
  return DurationGenerator(
    min ?? const Duration(days: -36500),
    max ?? const Duration(days: 36500),
  );
}
