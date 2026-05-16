import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs      = await SharedPreferences.getInstance();
  final username   = prefs.getString('ls_username') ?? '';
  final apiKey     = prefs.getString('ls_apikey')   ?? '';
  final startupTab = prefs.getInt('ls_startup_tab') ?? 0;

  // Restaurer les préférences d'apparence
  themeModeNotifier.value = themeFromString(prefs.getString('ls_theme'));
  accentNotifier.value    = accentFromString(prefs.getString('ls_accent'));

  runApp(LastStatsApp(
    username:   username,
    apiKey:     apiKey,
    startupTab: startupTab,
  ));
}

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
    return ValueListenableBuilder<Color>(
      valueListenable: accentNotifier,
      builder: (_, accent, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (_, mode, __) => MaterialApp(
          title: 'LastStats',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: mode,
          home: (username.isNotEmpty && apiKey.isNotEmpty)
              ? HomeScreen(username: username, apiKey: apiKey, startupTab: startupTab)
              : const SetupScreen(),
        ),
      ),
    );
  }
}
