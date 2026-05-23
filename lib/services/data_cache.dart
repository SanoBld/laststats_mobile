// lib/services/data_cache.dart
// ══════════════════════════════════════════════════════════════════════════
//  DataCache — cache persistant sur disque via SharedPreferences
//
//  • Chaque entrée est stockée sous la forme { "ts": <epoch_ms>, "data": … }
//  • TTL configurable par catégorie de données
//  • API synchrone-first : getSync() lit le cache en mémoire (instantané),
//    get() lit depuis SharedPreferences si nécessaire
//  • clearExpired() à appeler au démarrage pour ne pas saturer le disque
// ══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DataCache {
  DataCache._();

  static const _prefix = 'lscache_';

  // ── TTL par catégorie (en minutes) ────────────────────────────────────────
  static const _ttl = <String, int>{
    'userinfo':   60,   // info profil : 1 h
    'topartists': 30,   // top artistes par période : 30 min
    'topalbums':  30,
    'toptracks':  30,
    'recent':      2,   // pistes récentes : 2 min (quasi-live)
    'nowplaying':  1,   // en cours : 1 min
    'monthly':   360,   // scrobbles mensuels : 6 h
    'loved':      60,   // pistes aimées : 1 h
    'friends':     5,   // amis : 5 min
    'search':     10,   // résultats de recherche : 10 min
  };

  // Cache en mémoire (évite les lectures disque répétées)
  static final Map<String, _CacheEntry> _mem = {};

  static SharedPreferences? _prefs;

  // ──────────────────────────────────────────────────────────────────────────
  //  Init / Cleanup
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Charger le cache mémoire depuis le disque au démarrage
    await _warmUp();
  }

  /// Lit toutes les entrées non expirées depuis SharedPreferences
  /// et les charge en mémoire. À appeler une seule fois au démarrage.
  static Future<void> _warmUp() async {
    final p = _prefs!;
    for (final key in p.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = p.getString(key);
      if (raw == null) continue;
      try {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        final ts = (entry['ts'] as num?)?.toInt() ?? 0;
        final cacheKey = key.substring(_prefix.length);
        final e = _CacheEntry(ts: ts, data: entry['data']);
        if (!e.isExpired(_ttlOf(cacheKey))) {
          _mem[cacheKey] = e;
        }
      } catch (_) {}
    }
  }

  /// Supprime les entrées expirées du disque. À appeler au démarrage.
  static Future<void> clearExpired() async {
    await init();
    final p = _prefs!;
    final toRemove = <String>[];
    for (final key in p.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = p.getString(key);
      if (raw == null) { toRemove.add(key); continue; }
      try {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        final ts = (entry['ts'] as num?)?.toInt() ?? 0;
        final cacheKey = key.substring(_prefix.length);
        if (_CacheEntry(ts: ts, data: null).isExpired(_ttlOf(cacheKey))) {
          toRemove.add(key);
        }
      } catch (_) {
        toRemove.add(key);
      }
    }
    for (final key in toRemove) {
      await p.remove(key);
      _mem.remove(key.substring(_prefix.length));
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Lecture
  // ──────────────────────────────────────────────────────────────────────────

  /// Lecture instantanée depuis le cache mémoire (résultat synchrone).
  /// Retourne null si absent ou expiré.
  static dynamic getSync(String key) {
    final e = _mem[key];
    if (e == null) return null;
    if (e.isExpired(_ttlOf(key))) { _mem.remove(key); return null; }
    return e.data;
  }

  /// Lecture depuis le disque (fallback si le cache mémoire est vide).
  static Future<dynamic> get(String key) async {
    // 1. Essayer la mémoire d'abord
    final mem = getSync(key);
    if (mem != null) return mem;

    // 2. Lire depuis le disque
    await init();
    final raw = _prefs!.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (entry['ts'] as num?)?.toInt() ?? 0;
      final e = _CacheEntry(ts: ts, data: entry['data']);
      if (e.isExpired(_ttlOf(key))) return null;
      _mem[key] = e; // remonter en mémoire
      return e.data;
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Écriture
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> set(String key, dynamic data) async {
    await init();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final e = _CacheEntry(ts: ts, data: data);
    _mem[key] = e;
    try {
      final encoded = jsonEncode({'ts': ts, 'data': data});
      await _prefs!.setString('$_prefix$key', encoded);
    } catch (_) {
      // Si la donnée est trop volumineuse ou non-sérialisable, ignorer
      _mem.remove(key);
    }
  }

  /// Invalide une entrée (mémoire + disque).
  static Future<void> invalidate(String key) async {
    _mem.remove(key);
    await init();
    await _prefs!.remove('$_prefix$key');
  }

  /// Vide tout le cache.
  static Future<void> clear() async {
    _mem.clear();
    await init();
    final keys = _prefs!.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) await _prefs!.remove(k);
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Stats
  // ──────────────────────────────────────────────────────────────────────────

  static int get memEntries  => _mem.length;
  static int get diskEntries =>
      _prefs?.getKeys().where((k) => k.startsWith(_prefix)).length ?? 0;

  // ──────────────────────────────────────────────────────────────────────────
  //  Clés standards (évite les fautes de frappe)
  // ──────────────────────────────────────────────────────────────────────────

  static String keyUserInfo()                    => 'userinfo';
  static String keyTopArtists(String period)     => 'topartists_$period';
  static String keyTopAlbums(String period)      => 'topalbums_$period';
  static String keyTopTracks(String period)      => 'toptracks_$period';
  static String keyRecentTracks({String user = '', int limit = 10}) =>
      'recent_${user}_$limit';
  static String keyNowPlaying()                  => 'nowplaying';
  static String keyMonthlyScrobbles()            => 'monthly';
  static String keyLovedTracks()                 => 'loved';
  static String keyFriends()                     => 'friends';

  // ──────────────────────────────────────────────────────────────────────────
  //  Helpers privés
  // ──────────────────────────────────────────────────────────────────────────

  static int _ttlOf(String key) {
    for (final cat in _ttl.keys) {
      if (key.startsWith(cat)) return _ttl[cat]!;
    }
    return 30; // défaut : 30 min
  }
}

// ── Entrée de cache interne ───────────────────────────────────────────────────

class _CacheEntry {
  final int     ts;
  final dynamic data;
  const _CacheEntry({required this.ts, required this.data});

  bool isExpired(int ttlMinutes) {
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    return age > ttlMinutes * 60 * 1000;
  }
}