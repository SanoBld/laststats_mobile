// lib/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  // Notification channel IDs
  static const _chMilestoneId   = 'ls_milestone';
  static const _chMilestoneName = 'Scrobble milestones';
  static const _chRecapId       = 'ls_recap';
  static const _chRecapName     = 'Listening recaps';

  // Notification IDs (stable so we don't stack duplicates)
  static const _idMilestone = 1;
  static const _idDailyRecap  = 2;
  static const _idWeeklyRecap = 3;

  /// Call once at app startup.
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(const InitializationSettings(
      android: android,
      iOS:     ios,
    ));

    // Create Android channels
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chMilestoneId, _chMilestoneName,
        description: 'Notifies when you hit a scrobble milestone',
        importance:  Importance.defaultImportance,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chRecapId, _chRecapName,
        description: 'Daily and weekly listening summaries',
        importance:  Importance.low,
      ),
    );
  }

  /// Ask for notification permission (Android 13+, iOS).
  /// Returns true if granted.
  static Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    final a = await android?.requestNotificationsPermission() ?? true;
    final i = await ios?.requestPermissions(
      alert: true, badge: true, sound: true) ?? true;
    return a && i;
  }

  /// Check whether the app already has notification permission.
  static Future<bool> hasPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // areNotificationsEnabled is available on Android API 24+
    return await android?.areNotificationsEnabled() ?? true;
  }

  // ── Show helpers ─────────────────────────────────────────────────────────

  static Future<void> showMilestone(int count) => _plugin.show(
    _idMilestone,
    '🎵 Scrobble milestone!',
    'You just hit $count scrobbles on Last.fm',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _chMilestoneId, _chMilestoneName,
        icon:      '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );

  static Future<void> showDailyRecap({
    required int    count,
    required String topArtist,
    required String date,
  }) => _plugin.show(
    _idDailyRecap,
    '📊 Daily recap · $date',
    '$count scrobbles · Top: $topArtist',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _chRecapId, _chRecapName,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );

  static Future<void> showWeeklyRecap({
    required int    count,
    required String topArtist,
    required String weekLabel,
  }) => _plugin.show(
    _idWeeklyRecap,
    '📅 Weekly recap · $weekLabel',
    '$count scrobbles · Top: $topArtist',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _chRecapId, _chRecapName,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}