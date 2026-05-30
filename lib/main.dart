// lib/main.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'app_state.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'services/data_cache.dart';
import 'services/image_service.dart';
import 'services/scrobbles_file_cache.dart';
import 'services/notification_service.dart';
import 'services/notification_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch unhandled Flutter errors before the window opens
  FlutterError.onError = (details) => debugPrint('Flutter error: ${details.exception}');

  final prefs      = await SharedPreferences.getInstance();
  final username   = prefs.getString('ls_username') ?? '';
  final apiKey     = prefs.getString('ls_apikey')   ?? '';
  final startupTab = prefs.getInt('ls_startup_tab') ?? 0;

  // ── Appearance ──────────────────────────────────────────────────────────
  themeModeNotifier.value          = themeFromString(prefs.getString('ls_theme'));
  accentNotifier.value             = accentFromString(prefs.getString('ls_accent'));
  useDynamicColorNotifier.value    = prefs.getBool('ls_use_dynamic_color')    ?? false;
  useNowPlayingColorNotifier.value = prefs.getBool('ls_use_nowplaying_color') ?? false;
  localeNotifier.value             = prefs.getString('ls_locale') ?? 'fr';

  // Fallback accent used when music-color mode is on but nothing is playing.
  // Defaults to the normal accent color if never set.
  final fallbackHex = prefs.getString('ls_nowplaying_fallback_color');
  nowPlayingFallbackColorNotifier.value =
      fallbackHex != null ? accentFromString(fallbackHex) : accentNotifier.value;

  // ── Navigation layout ('auto' | 'on' | 'off') ───────────────────────────
  pcModeNotifier.value = prefs.getString('ls_pc_mode') ?? 'auto';

  // ── Data caches ─────────────────────────────────────────────────────────
  await DataCache.init();
  await DataCache.clearExpired();
  await ScrobblesFileCache.init();
  ImageService.pruneExpired();

  // ── Notifications & WorkManager ──────────────────────────────────────────
  // workmanager only supports Android & iOS — calling it on desktop/web
  // throws MissingPluginException before runApp(), killing the window.
  if (!kIsWeb) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    await NotificationService.init();
    if (isMobile) {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      await NotificationWorker.scheduleAll();
    }
  }

  runApp(LastStatsApp(
    username:   username,
    apiKey:     apiKey,
    startupTab: startupTab,
  ));
}

// ══════════════════════════════════════════════════════════════════════════════
//  LastStatsApp
// ══════════════════════════════════════════════════════════════════════════════

class LastStatsApp extends StatelessWidget {
  final String username;
  final String apiKey;
  final int    startupTab;

  const LastStatsApp({
    super.key,
    required this.username,
    required this.apiKey,
    this.startupTab = 0,
  });

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return ValueListenableBuilder<bool>(
          valueListenable: useDynamicColorNotifier,
          builder: (_, useDynamic, _) {
            return ValueListenableBuilder<Color>(
              valueListenable: accentNotifier,
              builder: (_, accent, _) {
                return ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (_, mode, _) {
                    return ValueListenableBuilder<String>(
                      valueListenable: localeNotifier,
                      builder: (_, _, _) {
                        final ColorScheme lightScheme =
                            (useDynamic && lightDynamic != null)
                                ? lightDynamic.harmonized()
                                : ColorScheme.fromSeed(
                                    // seedColorForScheme handles pure black/white edge cases
                                    seedColor:  seedColorForScheme(accent),
                                    brightness: Brightness.light,
                                  );
                        final ColorScheme darkScheme =
                            (useDynamic && darkDynamic != null)
                                ? darkDynamic.harmonized()
                                : ColorScheme.fromSeed(
                                    seedColor:  seedColorForScheme(accent),
                                    brightness: Brightness.dark,
                                  );

                        return MaterialApp(
                          title:                     'LastStats',
                          debugShowCheckedModeBanner: false,
                          theme:     ThemeData(colorScheme: lightScheme, useMaterial3: true),
                          darkTheme: ThemeData(colorScheme: darkScheme,  useMaterial3: true),
                          themeMode: mode,
                          home: (username.isNotEmpty && apiKey.isNotEmpty)
                              ? HomeScreen(
                                  username:   username,
                                  apiKey:     apiKey,
                                  startupTab: startupTab,
                                )
                              : const SetupScreen(),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}