import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user prefers 12-hour (AM/PM) or 24-hour clock display.
enum TimeFormatPreference {
  /// 24-hour clock, e.g. 14:30
  twentyFourHour,

  /// 12-hour clock with AM/PM, e.g. 2:30 PM
  twelveHour;

  String get displayName {
    switch (this) {
      case TimeFormatPreference.twentyFourHour:
        return '24-hour (14:30)';
      case TimeFormatPreference.twelveHour:
        return '12-hour (2:30 PM)';
    }
  }
}

/// Persists and retrieves the user's preferred time display format.
class TimeFormatService {
  static const String _key = 'pref_time_format';

  /// Read the persisted preference, defaulting to 24-hour.
  static Future<TimeFormatPreference> getPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return _fromString(prefs.getString(_key));
  }

  /// Read synchronously from an already-obtained [SharedPreferences] instance.
  static TimeFormatPreference getPreferenceSync(SharedPreferences prefs) {
    return _fromString(prefs.getString(_key));
  }

  /// Persist the user's choice.
  static Future<void> setPreference(TimeFormatPreference value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }

  static TimeFormatPreference _fromString(String? value) {
    if (value == TimeFormatPreference.twelveHour.name) {
      return TimeFormatPreference.twelveHour;
    }
    return TimeFormatPreference.twentyFourHour;
  }
}
