// lib/services/scrobbles_cache_backend_stub.dart
// ══════════════════════════════════════════════════════════════════════════
//  Stub — jamais atteint en production (web ou natif couvre tout).
//  Nécessaire pour que l'import conditionnel compile sans erreur.
// ══════════════════════════════════════════════════════════════════════════

class CacheBackend {
  static Future<String?> read(String key)            async => null;
  static Future<void>    write(String key, String v) async {}
  static Future<void>    delete(String key)          async {}
  static Future<List<String>> listKeys()             async => [];
  static Future<int>     totalBytes()                async => 0;
  static Future<void>    clearAll()                  async {}
}
