// lib/services/scrobbles_cache_backend_web.dart
// ══════════════════════════════════════════════════════════════════════════
//  Backend Web — stockage via SharedPreferences (localStorage)
//  Même interface que le backend natif.
// ══════════════════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';

class CacheBackend {
  static const _prefix = 'scrobbles_cache_';

  /// Lit une entrée depuis localStorage.
  static Future<String?> read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_prefix$key');
    } catch (_) {
      return null;
    }
  }

  /// Écrit une entrée dans localStorage.
  static Future<void> write(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', value);
    } catch (_) {}
  }

  /// Supprime une entrée.
  static Future<void> delete(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Liste toutes les clés du cache (sans le préfixe interne).
  static Future<List<String>> listKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs
          .getKeys()
          .where((k) => k.startsWith(_prefix))
          .map((k) => k.substring(_prefix.length))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Estimation de la taille totale en octets (UTF-16 × 2).
  static Future<int> totalBytes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int total = 0;
      for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
        total += (prefs.getString(k)?.length ?? 0) * 2;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Vide tout le cache.
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}
