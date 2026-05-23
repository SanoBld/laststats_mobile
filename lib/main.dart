// lib/main.dart
// ══════════════════════════════════════════════════════════════════════════
//  Point d'entrée de l'application LastStats
//
//  Comportement au démarrage :
//    • Credentials présents → HomeScreen directement (pas d'écran de chargement)
//      Le préchargement en arrière-plan est lancé depuis HomeScreen.initState.
//    • Premiers accès → SetupScreen → _FirstLoadScreen (import complet avec
//      progression détaillée) → HomeScreen.
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'services/data_cache.dart';
import 'services/image_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs      = await SharedPreferences.getInstance();
  final username   = prefs.getString('ls_username') ?? '';
  final apiKey     = prefs.getString('ls_apikey')   ?? '';
  final startupTab = prefs.getInt('ls_startup_tab') ?? 0;

  // ── Paramètres d'apparence ──────────────────────────────────────────────
  themeModeNotifier.value          = themeFromString(prefs.getString('ls_theme'));
  accentNotifier.value             = accentFromString(prefs.getString('ls_accent'));
  useDynamicColorNotifier.value    = prefs.getBool('ls_use_dynamic_color')    ?? false;
  useNowPlayingColorNotifier.value = prefs.getBool('ls_use_nowplaying_color') ?? false;
  localeNotifier.value             = prefs.getString('ls_locale') ?? 'fr';

  // ── Cache de données scrobble ────────────────────────────────────────────
  await DataCache.init();
  await DataCache.clearExpired();

  // ── Cache d'images (nettoyage non-bloquant) ──────────────────────────────
  ImageService.pruneExpired();

  runApp(LastStatsApp(
    username:   username,
    apiKey:     apiKey,
    startupTab: startupTab,
  ));
}

// ══════════════════════════════════════════════════════════════════════════
//  LastStatsApp
// ══════════════════════════════════════════════════════════════════════════

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
                                    seedColor:  accent,
                                    brightness: Brightness.light,
                                  );

                        final ColorScheme darkScheme =
                            (useDynamic && darkDynamic != null)
                                ? darkDynamic.harmonized()
                                : ColorScheme.fromSeed(
                                    seedColor:  accent,
                                    brightness: Brightness.dark,
                                  );

                        return MaterialApp(
                          title:                     'LastStats',
                          debugShowCheckedModeBanner: false,
                          theme: ThemeData(
                            colorScheme: lightScheme,
                            useMaterial3: true,
                          ),
                          darkTheme: ThemeData(
                            colorScheme: darkScheme,
                            useMaterial3: true,
                          ),
                          themeMode: mode,
                          // ── Routing ─────────────────────────────────────
                          // Credentials présents → HomeScreen directement.
                          // Le prefetch en arrière-plan est géré par HomeScreen.
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