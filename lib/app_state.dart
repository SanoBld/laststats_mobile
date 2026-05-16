import 'package:flutter/material.dart';

// ── Notifiers globaux partagés entre main.dart et home_screen.dart ───────────
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final accentNotifier    = ValueNotifier<Color>(const Color(0xFF7C3AED));

ThemeMode themeFromString(String? s) {
  switch (s) {
    case 'light':  return ThemeMode.light;
    case 'dark':   return ThemeMode.dark;
    default:       return ThemeMode.system;
  }
}

Color accentFromString(String? s) {
  switch (s) {
    case 'blue':   return const Color(0xFF1D4ED8);
    case 'green':  return const Color(0xFF059669);
    case 'red':    return const Color(0xFFDC2626);
    case 'orange': return const Color(0xFFD97706);
    case 'pink':   return const Color(0xFFDB2777);
    default:       return const Color(0xFF7C3AED); // purple
  }
}
