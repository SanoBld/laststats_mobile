// lib/services/notification_worker.dart
//
// WorkManager integration.
// All tasks run in a separate Dart isolate — no Flutter widgets available.
// Only SharedPreferences, http, and notification_service are used here.

import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart'             as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'notification_service.dart';

// ── Task names ───────────────────────────────────────────────────────────────
const _kTaskMilestone = 'ls_milestone_check';
const _kTaskRecap     = 'ls_recap_check';      // handles both daily + weekly

// ── SharedPreferences keys ───────────────────────────────────────────────────
const _kMilestoneEnabled  = 'ls_notif_milestone_enabled';
const _kMilestoneInterval = 'ls_notif_milestone_interval'; // int, default 500
const _kMilestoneLastCount = 'ls_notif_milestone_last_count';

const _kDailyEnabled = 'ls_notif_daily_enabled';
const _kDailyHour    = 'ls_notif_daily_hour';    // int 0–23, default 21
const _kDailyMin     = 'ls_notif_daily_min';     // int 0–59, default 0
const _kDailyLastDay = 'ls_notif_daily_last_day'; // int yyyyMMdd, last fired

const _kWeeklyEnabled  = 'ls_notif_weekly_enabled';
const _kWeeklyDay      = 'ls_notif_weekly_day';    // int 1–7 (Mon–Sun)
const _kWeeklyHour     = 'ls_notif_weekly_hour';
const _kWeeklyMin      = 'ls_notif_weekly_min';
const _kWeeklyLastWeek = 'ls_notif_weekly_last_week'; // int yyyyWW, last fired

// ── Last.fm API key / username (read from prefs in background) ───────────────
const _kUsername = 'ls_username';
const _kApiKey   = 'ls_apikey';

// ══════════════════════════════════════════════════════════════════════════════
//  Top-level callback — MUST be top-level (not inside a class).
//  Annotated so the AOT compiler keeps it.
// ══════════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, _) async {
    // Background isolate needs its own binding + notification init.
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.init();

    try {
      switch (taskName) {
        case _kTaskMilestone:
          await _runMilestoneCheck();
          break;
        case _kTaskRecap:
          await _runRecapCheck();
          break;
      }
    } catch (_) {
      // Never crash the worker — WorkManager would retry and spam.
    }
    return true;
  });
}

// ── Milestone check ──────────────────────────────────────────────────────────

Future<void> _runMilestoneCheck() async {
  final prefs = await SharedPreferences.getInstance();

  if (!(prefs.getBool(_kMilestoneEnabled) ?? false)) return;

  final username = prefs.getString(_kUsername) ?? '';
  final apiKey   = prefs.getString(_kApiKey)   ?? '';
  if (username.isEmpty || apiKey.isEmpty) return;

  // Fetch current total scrobble count from Last.fm
  final count = await _fetchPlaycount(username, apiKey);
  if (count == null) return; // offline or API error — skip silently

  final interval  = prefs.getInt(_kMilestoneInterval) ?? 500;
  final lastCount = prefs.getInt(_kMilestoneLastCount) ?? 0;

  // Find the highest milestone that was crossed since last check
  final lastMilestone = (lastCount ~/ interval) * interval;
  final nowMilestone  = (count     ~/ interval) * interval;

  if (nowMilestone > lastMilestone) {
    await NotificationService.showMilestone(nowMilestone);
  }

  // Always update last known count
  await prefs.setInt(_kMilestoneLastCount, count);
}

// ── Recap check (daily + weekly, same periodic task) ─────────────────────────

Future<void> _runRecapCheck() async {
  final prefs = await SharedPreferences.getInstance();
  final now   = DateTime.now();

  // ── Daily ────────────────────────────────────────────────────────────────
  if (prefs.getBool(_kDailyEnabled) ?? false) {
    final targetH = prefs.getInt(_kDailyHour) ?? 21;
    final targetM = prefs.getInt(_kDailyMin)  ?? 0;
    final lastDay = prefs.getInt(_kDailyLastDay) ?? 0;
    final todayId = int.parse(
        '${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}');

    // Fire only once per day, within a ±30 min window of the target time
    final targetMinutes  = targetH * 60 + targetM;
    final currentMinutes = now.hour * 60 + now.minute;
    final diff           = (currentMinutes - targetMinutes).abs();

    if (lastDay < todayId && diff <= 30) {
      final username = prefs.getString(_kUsername) ?? '';
      final apiKey   = prefs.getString(_kApiKey)   ?? '';
      if (username.isNotEmpty && apiKey.isNotEmpty) {
        final result = await _fetchTodayStats(username, apiKey, now);
        if (result != null) {
          final monthAbbr = _monthAbbr(now.month);
          await NotificationService.showDailyRecap(
            count:     result.$1,
            topArtist: result.$2,
            date:      '${now.day} $monthAbbr',
          );
          await prefs.setInt(_kDailyLastDay, todayId);
        }
      }
    }
  }

  // ── Weekly ───────────────────────────────────────────────────────────────
  if (prefs.getBool(_kWeeklyEnabled) ?? false) {
    final targetDay  = prefs.getInt(_kWeeklyDay)  ?? 1; // 1=Mon
    final targetH    = prefs.getInt(_kWeeklyHour) ?? 20;
    final targetM    = prefs.getInt(_kWeeklyMin)  ?? 0;
    final lastWeek   = prefs.getInt(_kWeeklyLastWeek) ?? 0;

    // ISO week number
    final weekId = _isoWeekId(now);

    final targetMinutes  = targetH * 60 + targetM;
    final currentMinutes = now.hour * 60 + now.minute;
    final diff           = (currentMinutes - targetMinutes).abs();

    if (now.weekday == targetDay && lastWeek < weekId && diff <= 30) {
      final username = prefs.getString(_kUsername) ?? '';
      final apiKey   = prefs.getString(_kApiKey)   ?? '';
      if (username.isNotEmpty && apiKey.isNotEmpty) {
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final result    = await _fetchRangeStats(username, apiKey, weekStart, now);
        if (result != null) {
          await NotificationService.showWeeklyRecap(
            count:     result.$1,
            topArtist: result.$2,
            weekLabel: 'Week ${_isoWeek(now)}',
          );
          await prefs.setInt(_kWeeklyLastWeek, weekId);
        }
      }
    }
  }
}

// ── Last.fm helpers ──────────────────────────────────────────────────────────

const _lfmBase = 'https://ws.audioscrobbler.com/2.0/';

/// Returns total playcount for the user, or null on failure.
Future<int?> _fetchPlaycount(String user, String key) async {
  try {
    final uri = Uri.parse(
        '$_lfmBase?method=user.getinfo&user=$user&api_key=$key&format=json');
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map;
    final count = json['user']?['playcount']?.toString() ?? '';
    return int.tryParse(count);
  } catch (_) { return null; }
}

/// Returns (scrobble count today, top artist name) or null.
Future<(int, String)?> _fetchTodayStats(
    String user, String key, DateTime now) async {
  try {
    final from = DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch ~/ 1000;
    final to   = now.millisecondsSinceEpoch ~/ 1000;
    return _fetchRangeStats(user, key,
        DateTime.fromMillisecondsSinceEpoch(from * 1000), now);
  } catch (_) { return null; }
}

/// Returns (total scrobbles in range, top artist name) or null.
Future<(int, String)?> _fetchRangeStats(
    String user, String key, DateTime from, DateTime to) async {
  try {
    final fromTs = from.millisecondsSinceEpoch ~/ 1000;
    final toTs   = to.millisecondsSinceEpoch   ~/ 1000;

    // Fetch first page to get total count + artist list
    final uri = Uri.parse(
        '$_lfmBase?method=user.getrecenttracks'
        '&user=$user&api_key=$key&format=json'
        '&from=$fromTs&to=$toTs&limit=50');
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;

    final json   = jsonDecode(res.body) as Map;
    final attr   = json['recenttracks']?['@attr'] as Map? ?? {};
    final total  = int.tryParse(attr['total']?.toString() ?? '0') ?? 0;
    final tracks = json['recenttracks']?['track'] as List? ?? [];

    // Count artist frequencies
    final freq = <String, int>{};
    for (final t in tracks) {
      final name = (t['artist']?['#text'] ?? t['artist']?['name'] ?? '')
          .toString().trim();
      if (name.isNotEmpty) freq[name] = (freq[name] ?? 0) + 1;
    }
    final top = freq.isEmpty
        ? '—'
        : (freq.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    return (total, top);
  } catch (_) { return null; }
}

// ── Date utils ───────────────────────────────────────────────────────────────

int _isoWeek(DateTime d) {
  final doy      = int.parse(
      d.difference(DateTime(d.year, 1, 1)).inDays.toString()) + 1;
  final dow      = d.weekday; // 1=Mon
  return ((doy - dow + 10) ~/ 7);
}

/// Unique int for year+week (e.g. 202423).
int _isoWeekId(DateTime d) => d.year * 100 + _isoWeek(d);

const _months = [
  '', 'Jan','Feb','Mar','Apr','May','Jun',
  'Jul','Aug','Sep','Oct','Nov','Dec'
];
String _monthAbbr(int m) => _months[m.clamp(1, 12)];

// ══════════════════════════════════════════════════════════════════════════════
//  NotificationWorker — public API (called from UI / main.dart)
// ══════════════════════════════════════════════════════════════════════════════

class NotificationWorker {
  NotificationWorker._();

  /// Re-register (or cancel) all tasks based on current prefs.
  /// Call after changing any notification setting.
  static Future<void> scheduleAll() async {
    final prefs = await SharedPreferences.getInstance();

    // ── Milestone task ───────────────────────────────────────────────────
    await Workmanager().cancelByUniqueName(_kTaskMilestone);
    if (prefs.getBool(_kMilestoneEnabled) ?? false) {
      await Workmanager().registerPeriodicTask(
        _kTaskMilestone,
        _kTaskMilestone,
        // 15 min is the Android minimum; battery-friendly choice.
        frequency:       const Duration(minutes: 15),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(
          networkType: NetworkType.connected, // needs internet to check count
        ),
      );
    }

    // ── Recap task ───────────────────────────────────────────────────────
    await Workmanager().cancelByUniqueName(_kTaskRecap);
    final dailyOn  = prefs.getBool(_kDailyEnabled)  ?? false;
    final weeklyOn = prefs.getBool(_kWeeklyEnabled) ?? false;
    if (dailyOn || weeklyOn) {
      await Workmanager().registerPeriodicTask(
        _kTaskRecap,
        _kTaskRecap,
        // Fires every hour; the worker checks if it's within the time window.
        frequency:          const Duration(hours: 1),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
  }

  /// Cancel all background tasks (call when all notifications are disabled).
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }

  /// Reset stored scrobble count (e.g. after changing interval).
  static Future<void> resetMilestoneCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMilestoneLastCount);
  }
}