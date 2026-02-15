import '../services/time_format_service.dart';

/// Formats [DateTime] values for display in the chat UI with contextual date
/// labels and the user's preferred clock format (12h / 24h).
///
/// Rules:
///  • **Today**       → `08:00` or `8:00 AM`
///  • **Yesterday**   → `Yesterday, 08:00` / `Yesterday, 8:00 AM`
///  • **This week** (2–6 days ago) → `Mon, 08:00` / `Mon, 8:00 AM`
///  • **This year**   → `12 Feb, 08:00` / `12 Feb, 8:00 AM`
///  • **Older**       → `12 Feb 2024, 08:00` / `12 Feb 2024, 8:00 AM`
class TimestampFormatter {
  const TimestampFormatter._();

  static const List<String> _weekdays = [
    '', // DateTime weekday is 1-indexed
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _months = [
    '', // 1-indexed
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Format a chat message timestamp with contextual date and clock preference.
  static String format(
    DateTime utcTimestamp, {
    TimeFormatPreference format = TimeFormatPreference.twentyFourHour,
    DateTime? now,
  }) {
    final local = utcTimestamp.toLocal();
    final today = now?.toLocal() ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final messageDate = DateTime(local.year, local.month, local.day);
    final difference = todayDate.difference(messageDate).inDays;

    final time = _formatTime(local, format);

    if (difference == 0) {
      // Today — just the time
      return time;
    }
    if (difference == 1) {
      return 'Yesterday, $time';
    }
    if (difference >= 2 && difference <= 6) {
      // Same week — weekday name
      return '${_weekdays[local.weekday]}, $time';
    }
    if (local.year == today.year) {
      // Same year — day + month
      return '${local.day} ${_months[local.month]}, $time';
    }
    // Different year — day + month + year
    return '${local.day} ${_months[local.month]} ${local.year}, $time';
  }

  /// Format just the time portion in the user's preferred clock style.
  static String _formatTime(
    DateTime local,
    TimeFormatPreference pref,
  ) {
    if (pref == TimeFormatPreference.twelveHour) {
      final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minutes = local.minute.toString().padLeft(2, '0');
      final period = local.hour < 12 ? 'AM' : 'PM';
      return '$hour:$minutes $period';
    }
    // 24-hour
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}
