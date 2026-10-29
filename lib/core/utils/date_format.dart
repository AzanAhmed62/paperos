/// Date formatting for PaperOS.
///
/// Hand-rolled instead of pulling in `intl`: PaperOS needs exactly five
/// shapes, and locale data is a poor fit for a deliberately narrow visual
/// language ("SATURDAY 26 SEPTEMBER" should not be a Tuesday in some locales).
library;

const List<String> _weekdaysLong = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _weekdaysShort = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> _monthsLong = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _monthsShort = <String>[
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

const List<String> _weekdayInitials = <String>[
  'M',
  'T',
  'W',
  'T',
  'F',
  'S',
  'S',
];

/// 24-hour clock, zero padded. PaperOS deliberately avoids 12-hour time: it is
/// used far less across the world and the ambiguity is never worth the space.
String formatClock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// "Saturday 26 September"
String formatLongDate(DateTime date) =>
    '${_weekdaysLong[date.weekday - 1]} ${date.day} ${_monthsLong[date.month - 1]}';

/// "26 Sep 2026"
String formatShortDate(DateTime date) =>
    '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';

/// "26 Sep"
String formatDayMonth(DateTime date) =>
    '${date.day} ${_monthsShort[date.month - 1]}';

/// "S 26 Sep" — the one-letter day form used in dense list rows.
String formatCompactDate(DateTime date) =>
    '${_weekdayInitials[date.weekday - 1]} ${formatDayMonth(date)}';

/// Relative time for recency metadata: "Just now", "14 minutes ago",
/// "Yesterday", "Tue", "12 Mar".
///
/// [now] is injected so this is deterministic under test.
String formatRelative(DateTime timestamp, DateTime now) {
  final Duration delta = now.difference(timestamp);

  if (delta.isNegative) return 'Just now';
  if (delta.inSeconds < 45) return 'Just now';
  if (delta.inMinutes < 60) {
    final int m = delta.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }

  final DateTime day = DateTime(timestamp.year, timestamp.month, timestamp.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int dayDelta = today.difference(day).inDays;

  if (dayDelta == 0) {
    final int h = delta.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  if (dayDelta == 1) return 'Yesterday';
  if (dayDelta < 7) return _weekdaysShort[timestamp.weekday - 1];
  if (timestamp.year == now.year) return formatDayMonth(timestamp);
  return formatShortDate(timestamp);
}

/// Duration of a reading session, e.g. "12 min", "1h 05m".
String formatDuration(Duration duration) {
  if (duration.inMinutes < 1) return '<1 min';
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes % 60;
  if (hours == 0) return '$minutes min';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

/// Whole-percent progress, always "NN%", never "NN %".
String formatPercent(double fraction) {
  final int value = (fraction.clamp(0.0, 1.0) * 100).round();
  return '$value%';
}

/// Human readable byte size, e.g. "1.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String rendered = value >= 100 || value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$rendered ${units[unit]}';
}

/// "Page 12 of 340"
String formatPageOf(int page, int total) => 'Page $page of $total';

/// Strips the extension for display: "notes.final.txt" -> "notes.final"
String stripExtension(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot <= 0) return fileName;
  return fileName.substring(0, dot);
}
