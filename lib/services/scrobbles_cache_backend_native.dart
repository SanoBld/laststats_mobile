// lib/services/scrobbles_cache_backend_native.dart
// ══════════════════════════════════════════════════════════════════════════
//  Backend Natif — stockage via fichiers (Android / iOS / Desktop)
//  Même interface que le backend web.
// ══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CacheBackend {
  static Directory? _dir;

  // ── Répertoire ─────────────────────────────────────────────────────────────

  static Future<Directory> _ensureDir() async {
    if (_dir != null && _dir!.existsSync()) return _dir!;
    final base = await getApplicationSupportDirectory();
    _dir = Directory('${base.path}/scrobbles');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  static File _file(Directory dir, String key) =>
      File('${dir.path}/$key.json');

  // ── API publique ───────────────────────────────────────────────────────────

  /// Lit le contenu JSON du fichier [key].json.
  static Future<String?> read(String key) async {
    try {
      final dir = await _ensureDir();
      final f   = _file(dir, key);
      if (!f.existsSync()) return null;
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  /// Écrit [value] dans le fichier [key].json.
  static Future<void> write(String key, String value) async {
    try {
      final dir = await _ensureDir();
      await _file(dir, key).writeAsString(value);
    } catch (_) {}
  }

  /// Supprime le fichier [key].json.
  static Future<void> delete(String key) async {
    try {
      final dir = await _ensureDir();
      final f   = _file(dir, key);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Liste les clés présentes sur disque (noms de fichiers sans extension).
  static Future<List<String>> listKeys() async {
    try {
      final dir  = await _ensureDir();
      final keys = <String>[];
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.endsWith('.json')) {
            keys.add(name.replaceAll('.json', ''));
          }
        }
      }
      return keys;
    } catch (_) {
      return [];
    }
  }

  /// Taille totale du répertoire en octets.
  static Future<int> totalBytes() async {
    try {
      final dir   = await _ensureDir();
      int   total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          try { total += await entity.length(); } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Supprime et recrée le répertoire.
  static Future<void> clearAll() async {
    try {
      final dir = await _ensureDir();
      _dir = null;
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      _dir = dir;
    } catch (_) {}
  }
}
