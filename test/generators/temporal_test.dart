import 'package:test/test.dart';
import 'package:hegeltest/hegeltest.dart';

void main() {
  group('temporal', () {
    group('dates', () {
      hegelTest('generates valid DateTimes with no time component', (tc) {
        final d = tc.draw(dates());
        expect(d.isUtc, isTrue);
        expect(d.hour, equals(0));
        expect(d.minute, equals(0));
        expect(d.second, equals(0));
        expect(d.millisecond, equals(0));
        expect(d.microsecond, equals(0));
      });

      hegelTest('respects min and max bounds', (tc) {
        final min = DateTime.utc(2020, 1, 1);
        final max = DateTime.utc(2025, 12, 31);
        final d = tc.draw(dates(min: min, max: max));

        expect(d.compareTo(min) >= 0, isTrue);
        expect(d.compareTo(max) <= 0, isTrue);
      });
    });

    group('times', () {
      hegelTest('generates valid TimeRecords', (tc) {
        final t = tc.draw(times());
        expect(t.hour, inInclusiveRange(0, 23));
        expect(t.minute, inInclusiveRange(0, 59));
        expect(t.second, inInclusiveRange(0, 59));
        expect(t.microsecond, inInclusiveRange(0, 999999));
      });

      hegelTest('respects min and max bounds', (tc) {
        final min = (hour: 10, minute: 30, second: 15, microsecond: 0);
        final max = (hour: 14, minute: 45, second: 30, microsecond: 500000);
        final t = tc.draw(times(min: min, max: max));

        // Simple comparison by total microseconds
        final totalMin =
            min.hour * 3600000000 +
            min.minute * 60000000 +
            min.second * 1000000 +
            min.microsecond;
        final totalMax =
            max.hour * 3600000000 +
            max.minute * 60000000 +
            max.second * 1000000 +
            max.microsecond;
        final totalT =
            t.hour * 3600000000 +
            t.minute * 60000000 +
            t.second * 1000000 +
            t.microsecond;

        expect(totalT >= totalMin, isTrue);
        expect(totalT <= totalMax, isTrue);
      });
    });

    group('dateTimes', () {
      hegelTest('generates valid DateTimes', (tc) {
        final dt = tc.draw(dateTimes());
        expect(dt.isUtc, isTrue);
        // Can be any valid date/time
        expect(dt.year, inInclusiveRange(1, 9999));
        expect(dt.month, inInclusiveRange(1, 12));
        expect(dt.day, inInclusiveRange(1, 31));
        expect(dt.hour, inInclusiveRange(0, 23));
        expect(dt.minute, inInclusiveRange(0, 59));
        expect(dt.second, inInclusiveRange(0, 59));
      });

      hegelTest('respects min and max bounds', (tc) {
        final min = DateTime.utc(2023, 5, 10, 12, 0, 0);
        final max = DateTime.utc(2023, 5, 10, 18, 30, 0);
        final dt = tc.draw(dateTimes(min: min, max: max));

        expect(dt.compareTo(min) >= 0, isTrue);
        expect(dt.compareTo(max) <= 0, isTrue);
      });
    });
  });
}
