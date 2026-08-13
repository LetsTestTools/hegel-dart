import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../ffi/hegel_bindings.g.dart';
import '../core/test_case.dart';
import '../core/exceptions.dart';
import 'generator.dart';

class DateGenerator extends Generator<DateTime> {
  final DateTime min;
  final DateTime max;

  const DateGenerator(this.min, this.max);

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

      final result = tc.lib.hegel_generate_date(
        tc.ctx,
        tc.handle,
        minDateStruct.ref,
        maxDateStruct.ref,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate date: ${result.value}');
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

  const TimeGenerator(this.min, this.max);

  @override
  TimeRecord generate(TestCase tc) {
    return using((Arena arena) {
      final outValue = arena<hegel_time_t>();

      final minTimeStruct = arena<hegel_time_t>()
        ..ref.hour = min.hour
        ..ref.minute = min.minute
        ..ref.second = min.second
        ..ref.microsecond = min.microsecond;

      final maxTimeStruct = arena<hegel_time_t>()
        ..ref.hour = max.hour
        ..ref.minute = max.minute
        ..ref.second = max.second
        ..ref.microsecond = max.microsecond;

      final result = tc.lib.hegel_generate_time(
        tc.ctx,
        tc.handle,
        minTimeStruct.ref,
        maxTimeStruct.ref,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate time: ${result.value}');
      }

      return (
        hour: outValue.ref.hour,
        minute: outValue.ref.minute,
        second: outValue.ref.second,
        microsecond: outValue.ref.microsecond,
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

  const DateTimeGenerator(this.min, this.max);

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
        ..ref.time.microsecond = min.microsecond;

      final maxStruct = arena<hegel_datetime_t>()
        ..ref.date.year = max.year
        ..ref.date.month = max.month
        ..ref.date.day = max.day
        ..ref.time.hour = max.hour
        ..ref.time.minute = max.minute
        ..ref.time.second = max.second
        ..ref.time.microsecond = max.microsecond;

      final result = tc.lib.hegel_generate_datetime(
        tc.ctx,
        tc.handle,
        minStruct.ref,
        maxStruct.ref,
        outValue,
      );

      if (result == hegel_result_t.HEGEL_E_STOP_TEST) {
        throw const HegelStopTest();
      }
      if (result != hegel_result_t.HEGEL_OK) {
        throw HegelException('Failed to generate datetime: ${result.value}');
      }

      final totalMicroseconds = outValue.ref.time.microsecond;
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
    max ?? DateTime.utc(9999, 12, 31, 23, 59, 59, 0, 999),
  );
}
