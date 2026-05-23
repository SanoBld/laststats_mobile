// lib/services/prefetch_service.dart
// ══════════════════════════════════════════════════════════════════════════
//  PrefetchService — préchargement en arrière-plan de toutes les données
//
//  Stratégie de chargement (par priorité) :
//    1. Données du Dashboard  (userinfo, top overall×3, recent, nowplaying)
//    2. Top lists 7day        (pour les cartes "semaine")
//    3. Top lists autres      (1month, 3month, 6month, 12month)
//    4. Scrobbles mensuels    (graphiques)
//    5. Pistes aimées         (page Historique)
//
//  Règles :
//    • N'appelle l'API que si l'entrée est absente OU expirée en cache
//    • Respecte un délai de 200 ms entre chaque appel pour éviter le
//      rate-limiting de Last.fm (max ~5 req/s avec clé gratuite)
//    • Si une requête échoue, on continue sans planter
//    • Expose [isRunning] et [lastPrefetchAt] pour les settings
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'data_cache.dart';
import 'lastfm_service.dart';

class PrefetchService {
  PrefetchService._();

  static const _allPeriods   = ['overall', '7day', '1month', '3month', '6month', '12month'];
  static const _dashPeriods  = ['overall', '7day'];
  static const _delay        = Duration(milliseconds: 250); // entre chaque appel API

  static bool      _running        = false;
  static DateTime? _lastPrefetchAt;

  static bool      get isRunning       => _running;
  static DateTime? get lastPrefetchAt  => _lastPrefetchAt;

  // ──────────────────────────────────────────────────────────────────────────
  //  Point d'entrée principal
  // ──────────────────────────────────────────────────────────────────────────

  /// Lance le préchargement complet en arrière-plan.
  /// [force] = true → recharge même si le cache est encore frais.
  static Future<void> prefetchAll(LastFmService service, {bool force = false}) async {
    if (_running) return; // déjà en cours, ne pas relancer
    _running = true;
    debugPrint('[Prefetch] Démarrage du préchargement…');

    try {
      // ── Priorité 1 : données du Dashboard ─────────────────────────────
      await _prefetchUserInfo(service,   force: force);
      await _prefetchTopList(service, 'artists', 'overall', limit: 50, force: force);
      await _prefetchTopList(service, 'albums',  'overall', limit: 50, force: force);
      await _prefetchTopList(service, 'tracks',  'overall', limit: 50, force: force);
      await _prefetchRecent(service,             limit: 10, force: force);

      // ── Priorité 2 : semaine (cards semaine + Rankings) ───────────────
      await _prefetchTopList(service, 'artists', '7day', limit: 50, force: force);
      await _prefetchTopList(service, 'albums',  '7day', limit: 50, force: force);
      await _prefetchTopList(service, 'tracks',  '7day', limit: 50, force: force);

      // ── Priorité 3 : autres périodes (Rankings) ────────────────────────
      for (final period in _allPeriods) {
        if (_dashPeriods.contains(period)) continue; // déjà fait
        await _prefetchTopList(service, 'artists', period, limit: 50, force: force);
        await _prefetchTopList(service, 'albums',  period, limit: 50, force: force);
        await _prefetchTopList(service, 'tracks',  period, limit: 50, force: force);
      }

      // ── Priorité 4 : scrobbles mensuels (Graphiques) ──────────────────
      await _prefetchMonthly(service, force: force);

      // ── Priorité 5 : pistes aimées ────────────────────────────────────
      await _prefetchLoved(service, force: force);

      _lastPrefetchAt = DateTime.now();
      debugPrint('[Prefetch] Terminé — ${DataCache.memEntries} entrées en cache.');
    } catch (e) {
      debugPrint('[Prefetch] Erreur inattendue : $e');
    } finally {
      _running = false;
    }
  }

  /// Préchargement rapide (Dashboard uniquement).
  /// À appeler immédiatement après la connexion pour un 1er affichage rapide.
  static Future<void> prefetchDashboard(LastFmService service, {bool force = false}) async {
    debugPrint('[Prefetch] Préchargement Dashboard prioritaire…');
    await _prefetchUserInfo(service,   force: force);
    await _prefetchTopList(service, 'artists', 'overall', limit: 50, force: force);
    await _prefetchTopList(service, 'albums',  'overall', limit: 50, force: force);
    await _prefetchTopList(service, 'tracks',  'overall', limit: 50, force: force);
    await _prefetchRecent(service,             limit: 10, force: force);
    await _prefetchTopList(service, 'artists', '7day', limit: 1, force: force);
    await _prefetchTopList(service, 'albums',  '7day', limit: 1, force: force);
    await _prefetchTopList(service, 'tracks',  '7day', limit: 1, force: force);
    debugPrint('[Prefetch] Dashboard prêt.');
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Workers privés
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> _prefetchUserInfo(LastFmService service, {bool force = false}) async {
    final key = DataCache.keyUserInfo();
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getUserInfo();
      if (data != null) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchTopList(
    LastFmService service,
    String type,
    String period, {
    int limit = 50,
    bool force = false,
  }) async {
    final key = switch (type) {
      'artists' => DataCache.keyTopArtists(period),
      'albums'  => DataCache.keyTopAlbums(period),
      _         => DataCache.keyTopTracks(period),
    };

    // Si cache frais ET pas force → skip
    if (!force && DataCache.getSync(key) != null) return;

    await _call(() async {
      final List<dynamic> data;
      data = switch (type) {
        'artists' => await service.getTopArtists(period: period, limit: limit),
        'albums'  => await service.getTopAlbums(period: period,  limit: limit),
        _         => await service.getTopTracks(period: period,  limit: limit),
      };
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchRecent(LastFmService service, {
    int limit = 10,
    bool force = false,
  }) async {
    final key = DataCache.keyRecentTracks(limit: limit);
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getRecentTracks(limit: limit);
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchMonthly(LastFmService service, {bool force = false}) async {
    final key = DataCache.keyMonthlyScrobbles();
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getMonthlyScrobbles(months: 12);
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchLoved(LastFmService service, {bool force = false}) async {
    final key = DataCache.keyLovedTracks();
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getLovedTracks(limit: 50);
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Helper : exécute un appel API avec délai et gestion d'erreur
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> _call(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('[Prefetch] Erreur ignorée : $e');
    }
    await Future.delayed(_delay);
  }
}