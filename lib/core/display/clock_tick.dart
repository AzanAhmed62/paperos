import 'display_profile.dart';

/// How long until the clock should rebuild for [now].
///
/// The standard profile refreshes every second. The E-Ink profile schedules one
/// one-shot timer that fires just after the next minute boundary, which avoids
/// sixty needless screen updates per minute. A small positive floor prevents a
/// zero-duration timer from spinning when called exactly on a boundary.
Duration nextClockDelay(DateTime now, DisplayProfile profile) {
  if (!profile.isEink) return const Duration(seconds: 1);

  final int secondsIntoMinute = now.second;
  final int millisecondsIntoSecond = now.millisecond;
  final int microsecondsIntoSecond = now.microsecond;

  int micros =
      const Duration(minutes: 1).inMicroseconds -
      Duration(
        seconds: secondsIntoMinute,
        milliseconds: millisecondsIntoSecond,
        microseconds: microsecondsIntoSecond,
      ).inMicroseconds;

  // Land just after the boundary so the displayed minute has definitely
  // changed, even if the timer is scheduled a fraction early by the platform.
  micros += const Duration(milliseconds: 40).inMicroseconds;
  if (micros <= 0) micros = const Duration(seconds: 60).inMicroseconds;
  return Duration(microseconds: micros);
}
