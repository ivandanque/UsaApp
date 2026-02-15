import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/core/services/time_format_service.dart';
import 'package:usaapp/src/core/utils/timestamp_formatter.dart';

void main() {
  group('TimestampFormatter', () {
    // Use local DateTime values so tests are timezone-independent.
    // The formatter calls toLocal(), so we construct "local" times here
    // and convert to UTC when passing to the formatter.
    //
    // "now" is Sunday, 15 Feb 2026 at 14:00 local time.
    final nowLocal = DateTime(2026, 2, 15, 14, 0, 0);
    final nowUtc = nowLocal.toUtc();

    group('24-hour format', () {
      const fmt = TimeFormatPreference.twentyFourHour;

      test('same day shows only time', () {
        // Today at 08:30 local
        final ts = DateTime(2026, 2, 15, 8, 30, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('08:30'));
      });

      test('yesterday shows "Yesterday" prefix', () {
        final ts = DateTime(2026, 2, 14, 20, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('Yesterday, 20:00'));
      });

      test('2 days ago shows weekday name', () {
        // Friday, 13 Feb 2026
        final ts = DateTime(2026, 2, 13, 10, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('Fri, 10:00'));
      });

      test('6 days ago shows weekday name', () {
        // Monday, 9 Feb 2026
        final ts = DateTime(2026, 2, 9, 10, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('Mon, 10:00'));
      });

      test('7+ days ago same year shows day+month', () {
        final ts = DateTime(2026, 1, 1, 12, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('1 Jan, 12:00'));
      });

      test('different year shows full date', () {
        final ts = DateTime(2024, 12, 25, 18, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('25 Dec 2024, 18:00'));
      });

      test('midnight formats as 00:00', () {
        final ts = DateTime(2026, 2, 15, 0, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('00:00'));
      });

      test('minutes are zero-padded', () {
        final ts = DateTime(2026, 2, 15, 9, 5, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('09:05'));
      });
    });

    group('12-hour format', () {
      const fmt = TimeFormatPreference.twelveHour;

      test('same day shows time with AM/PM', () {
        final ts = DateTime(2026, 2, 15, 8, 30, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('8:30 AM'));
      });

      test('yesterday shows "Yesterday" with AM/PM time', () {
        final ts = DateTime(2026, 2, 14, 15, 45, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('Yesterday, 3:45 PM'));
      });

      test('PM time formats correctly', () {
        final ts = DateTime(2026, 2, 15, 14, 30, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('2:30 PM'));
      });

      test('AM time formats correctly', () {
        final ts = DateTime(2026, 2, 15, 9, 15, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('9:15 AM'));
      });

      test('midnight formats as 12:00 AM', () {
        final ts = DateTime(2026, 2, 15, 0, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('12:00 AM'));
      });

      test('noon formats as 12:00 PM', () {
        final ts = DateTime(2026, 2, 15, 12, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('12:00 PM'));
      });

      test('different year includes year in date', () {
        final ts = DateTime(2024, 6, 15, 21, 5, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('15 Jun 2024, 9:05 PM'));
      });

      test('minutes are zero-padded', () {
        final ts = DateTime(2026, 2, 15, 3, 5, 0).toUtc();
        final result = TimestampFormatter.format(ts, format: fmt, now: nowUtc);
        expect(result, equals('3:05 AM'));
      });
    });

    group('edge cases', () {
      test('defaults to 24-hour when format not specified', () {
        final ts = DateTime(2026, 2, 15, 14, 30, 0).toUtc();
        final result = TimestampFormatter.format(ts, now: nowUtc);
        expect(result, equals('14:30'));
      });

      test('future date same day shows just time', () {
        final ts = DateTime(2026, 2, 15, 16, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, now: nowUtc);
        expect(result, equals('16:00'));
      });

      test('3 days ago shows correct weekday', () {
        // Thursday, 12 Feb 2026
        final ts = DateTime(2026, 2, 12, 18, 0, 0).toUtc();
        final result = TimestampFormatter.format(ts, now: nowUtc);
        expect(result, equals('Thu, 18:00'));
      });
    });
  });
}
