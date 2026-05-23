// lib/services/prefetch_service.dart
// ══════════════════════════════════════════════════════════════════════════
//  PrefetchService — préchargement en arrière-plan de toutes les données
//
//  Méthodes publiques :
//    • prefetchAllWithProgress  — import complet avec progression (12 étapes),
//                                 utilisé par _FirstLoadScreen (1ère connexion)
//    • prefetchAll              — préchargement complet silencieux (HomeScreen)
//    • prefetchDashboardWithProgress — rétro-compatibilité (LoadingScreen supprimé)
//    • prefetchDashboard        — version sans suivi (rétro-compatibilité)
//
//  Stratégie (par priorité) :
//    1. Profil utilisateur
//    2. Tops global (artistes, albums, titres)
//    3. Écoutes récentes
//    4. Tops par période (7j · 1m · 3m · 6m · 12m)
//    5. Historique mensuel (graphiques)
//    6. Titres aimés
//
//  Règles :
//    • N'appelle l'API que si l'entrée est absente OU expirée
//    • Délai 250 ms entre chaque appel (rate-limit Last.fm ≈ 5 req/s)
//    • Si une requête échoue → on continue sans planter
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import '../app_state.dart';
import 'data_cache.dart';
import 'lastfm_service.dart';

// ══════════════════════════════════════════════════════════════════════════
//  PrefetchState — snapshot immuable de la progression
// ══════════════════════════════════════════════════════════════════════════

class PrefetchState {
  /// Label de l'étape en cours (vide avant la première étape).
  final String currentStep;

  /// Fraction de complétion [0.0 – 1.0].
  final double fraction;

  /// Labels des étapes déjà complètes (ordre chronologique).
  final List<String> completedSteps;

  /// true une fois que toutes les étapes sont terminées.
  final bool isComplete;

  const PrefetchState({
    required this.currentStep,
    required this.fraction,
    required this.completedSteps,
    required this.isComplete,
  });

  PrefetchState copyWith({
    String?       currentStep,
    double?       fraction,
    List<String>? completedSteps,
    bool?         isComplete,
  }) => PrefetchState(
    currentStep:    currentStep    ?? this.currentStep,
    fraction:       fraction       ?? this.fraction,
    completedSteps: completedSteps ?? this.completedSteps,
    isComplete:     isComplete     ?? this.isComplete,
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  PrefetchService
// ══════════════════════════════════════════════════════════════════════════

class PrefetchService {
  PrefetchService._();

  static const _allPeriods  = ['overall', '7day', '1month', '3month', '6month', '12month'];
  static const _dashPeriods = ['overall', '7day'];
  static const _delay       = Duration(milliseconds: 250);

  // ── État global ───────────────────────────────────────────────────────────

  static bool      _running     = false;
  static bool      _dashRunning = false;
  static DateTime? _lastPrefetchAt;

  static bool      get isRunning      => _running;
  static DateTime? get lastPrefetchAt => _lastPrefetchAt;

  /// Notifie les listeners (ex: _FirstLoadScreen) de l'avancement.
  static final progressNotifier = ValueNotifier<PrefetchState>(
    const PrefetchState(
      currentStep: '', fraction: 0, completedSteps: [], isComplete: false,
    ),
  );

  // ── i18n helper ───────────────────────────────────────────────────────────
  static String _t(String fr, String en) =>
      localeNotifier.value == 'en' ? en : fr;

  // ── Helpers de progression ────────────────────────────────────────────────

  static void _report({
    required String       step,
    required double       fraction,
    required List<String> done,
    bool                  complete = false,
  }) {
    progressNotifier.value = PrefetchState(
      currentStep:    step,
      fraction:       fraction,
      completedSteps: List.unmodifiable(done),
      isComplete:     complete,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  prefetchAllWithProgress — import complet avec suivi (1ère connexion)
  // ──────────────────────────────────────────────────────────────────────────

  /// Précharge TOUTES les données en 12 étapes avec rapport de progression.
  /// [_FirstLoadScreen] écoute [progressNotifier] pour mettre à jour son UI.
  /// Utilisé uniquement lors de la première connexion (force: true).
  static Future<void> prefetchAllWithProgress(
    LastFmService service, {
    bool force = false,
  }) async {
    if (_running) return;
    _running = true;

    // Reset notifier
    progressNotifier.value = const PrefetchState(
      currentStep: '', fraction: 0, completedSteps: [], isComplete: false,
    );

    debugPrint('[Prefetch] Import complet avec progression…');

    final steps = <(String, Future<void> Function())>[
      // ── Étape 1 : profil ───────────────────────────────────────────────
      (
        _t('👤 Profil utilisateur', '👤 User profile'),
        () => _prefetchUserInfo(service, force: force),
      ),

      // ── Étape 2–4 : tops global ────────────────────────────────────────
      (
        _t('🎤 Top artistes — Global', '🎤 Top artists — All time'),
        () => _prefetchTopList(service, 'artists', 'overall', force: force),
      ),
      (
        _t('💿 Top albums — Global', '💿 Top albums — All time'),
        () => _prefetchTopList(service, 'albums', 'overall', force: force),
      ),
      (
        _t('🎵 Top titres — Global', '🎵 Top tracks — All time'),
        () => _prefetchTopList(service, 'tracks', 'overall', force: force),
      ),

      // ── Étape 5 : écoutes récentes ─────────────────────────────────────
      (
        _t('⏱️ Écoutes récentes', '⏱️ Recent plays'),
        () => _prefetchRecent(service, force: force),
      ),

      // ── Étape 6 : tops 7 jours ─────────────────────────────────────────
      (
        _t('🗓️ Cette semaine', '🗓️ This week'),
        () async {
          await _prefetchTopList(service, 'artists', '7day', force: force);
          await _prefetchTopList(service, 'albums',  '7day', force: force);
          await _prefetchTopList(service, 'tracks',  '7day', force: force);
        },
      ),

      // ── Étape 7 : tops 1 mois ──────────────────────────────────────────
      (
        _t('📅 Ce mois-ci', '📅 This month'),
        () async {
          await _prefetchTopList(service, 'artists', '1month', force: force);
          await _prefetchTopList(service, 'albums',  '1month', force: force);
          await _prefetchTopList(service, 'tracks',  '1month', force: force);
        },
      ),

      // ── Étape 8 : tops 3 mois ──────────────────────────────────────────
      (
        _t('📅 3 derniers mois', '📅 Last 3 months'),
        () async {
          await _prefetchTopList(service, 'artists', '3month', force: force);
          await _prefetchTopList(service, 'albums',  '3month', force: force);
          await _prefetchTopList(service, 'tracks',  '3month', force: force);
        },
      ),

      // ── Étape 9 : tops 6 mois ──────────────────────────────────────────
      (
        _t('📅 6 derniers mois', '📅 Last 6 months'),
        () async {
          await _prefetchTopList(service, 'artists', '6month', force: force);
          await _prefetchTopList(service, 'albums',  '6month', force: force);
          await _prefetchTopList(service, 'tracks',  '6month', force: force);
        },
      ),

      // ── Étape 10 : tops 12 mois ────────────────────────────────────────
      (
        _t('📅 12 derniers mois', '📅 Last 12 months'),
        () async {
          await _prefetchTopList(service, 'artists', '12month', force: force);
          await _prefetchTopList(service, 'albums',  '12month', force: force);
          await _prefetchTopList(service, 'tracks',  '12month', force: force);
        },
      ),

      // ── Étape 11 : historique mensuel ──────────────────────────────────
      (
        _t('📊 Historique mensuel', '📊 Monthly history'),
        () => _prefetchMonthly(service, force: force),
      ),

      // ── Étape 12 : titres aimés ────────────────────────────────────────
      (
        _t('❤️ Titres aimés', '❤️ Loved tracks'),
        () => _prefetchLoved(service, force: force),
      ),
    ];

    final total = steps.length;
    final done  = <String>[];

    try {
      for (var i = 0; i < total; i++) {
        final (label, worker) = steps[i];
        _report(step: label, fraction: i / total, done: done);
        await _call(worker);
        done.add(label);
      }

      _report(step: '', fraction: 1.0, done: done, complete: true);
      _lastPrefetchAt = DateTime.now();
      debugPrint('[Prefetch] Import complet — ${done.length} étapes.');
    } catch (e) {
      debugPrint('[Prefetch] Erreur inattendue : $e');
      // Marquer quand même comme terminé pour ne pas bloquer l'UI
      _report(step: '', fraction: 1.0, done: done, complete: true);
    } finally {
      _running = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  prefetchAll — préchargement complet silencieux (depuis HomeScreen)
  // ──────────────────────────────────────────────────────────────────────────

  /// Lance le préchargement complet en arrière-plan, sans mise à jour du notifier.
  /// [force] = true → recharge même si le cache est encore frais.
  static Future<void> prefetchAll(LastFmService service, {bool force = false}) async {
    if (_running) return;
    _running = true;
    debugPrint('[Prefetch] Préchargement complet (silencieux)…');

    try {
      // ── Priorité 1 : données du Dashboard ─────────────────────────────
      await _prefetchUserInfo(service,                      force: force);
      await _prefetchTopList(service, 'artists', 'overall', force: force);
      await _prefetchTopList(service, 'albums',  'overall', force: force);
      await _prefetchTopList(service, 'tracks',  'overall', force: force);
      await _prefetchRecent(service,                        force: force);
      await _prefetchTopList(service, 'artists', '7day',    force: force);
      await _prefetchTopList(service, 'albums',  '7day',    force: force);
      await _prefetchTopList(service, 'tracks',  '7day',    force: force);

      // ── Priorité 2 : autres périodes ──────────────────────────────────
      for (final period in _allPeriods) {
        if (_dashPeriods.contains(period)) continue;
        await _prefetchTopList(service, 'artists', period, force: force);
        await _prefetchTopList(service, 'albums',  period, force: force);
        await _prefetchTopList(service, 'tracks',  period, force: force);
      }

      // ── Priorité 3 : scrobbles mensuels ───────────────────────────────
      await _prefetchMonthly(service, force: force);

      // ── Priorité 4 : pistes aimées ────────────────────────────────────
      await _prefetchLoved(service, force: force);

      _lastPrefetchAt = DateTime.now();
      debugPrint('[Prefetch] Complet — ${DataCache.memEntries} entrées en cache.');
    } catch (e) {
      debugPrint('[Prefetch] Erreur inattendue : $e');
    } finally {
      _running = false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  prefetchDashboardWithProgress — rétro-compatibilité
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> prefetchDashboardWithProgress(
    LastFmService service, {bool force = false}
  ) async {
    if (_dashRunning) return;
    _dashRunning = true;

    progressNotifier.value = const PrefetchState(
      currentStep: '', fraction: 0, completedSteps: [], isComplete: false,
    );

    final steps = <(String, Future<void> Function())>[
      (_t('👤 Profil utilisateur',         '👤 User profile'),          () => _prefetchUserInfo(service,   force: force)),
      (_t('🎤 Top artistes — Global',      '🎤 Top artists — All time'), () => _prefetchTopList(service, 'artists', 'overall', force: force)),
      (_t('💿 Top albums — Global',        '💿 Top albums — All time'),  () => _prefetchTopList(service, 'albums',  'overall', force: force)),
      (_t('🎵 Top titres — Global',        '🎵 Top tracks — All time'),  () => _prefetchTopList(service, 'tracks',  'overall', force: force)),
      (_t('⏱️ Écoutes récentes',           '⏱️ Recent plays'),           () => _prefetchRecent(service,             force: force)),
      (_t('🗓️ Top artistes — Semaine',     '🗓️ Top artists — This week'), () => _prefetchTopList(service, 'artists', '7day', force: force)),
      (_t('🗓️ Albums & titres — Semaine',  '🗓️ Albums & tracks — This week'), () async {
        await _prefetchTopList(service, 'albums', '7day', force: force);
        await _prefetchTopList(service, 'tracks', '7day', force: force);
      }),
    ];

    final total = steps.length;
    final done  = <String>[];

    for (var i = 0; i < total; i++) {
      final (label, worker) = steps[i];
      _report(step: label, fraction: i / total, done: done);
      await _call(worker);
      done.add(label);
    }

    _report(step: '', fraction: 1.0, done: done, complete: true);
    debugPrint('[Prefetch] Dashboard prêt (${done.length} étapes).');
    _dashRunning = false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  prefetchDashboard — version sans suivi (rétro-compatibilité)
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> prefetchDashboard(LastFmService service, {bool force = false}) async {
    debugPrint('[Prefetch] Dashboard (sans suivi)…');
    await _prefetchUserInfo(service,                      force: force);
    await _prefetchTopList(service, 'artists', 'overall', force: force);
    await _prefetchTopList(service, 'albums',  'overall', force: force);
    await _prefetchTopList(service, 'tracks',  'overall', force: force);
    await _prefetchRecent(service,                        force: force);
    await _prefetchTopList(service, 'artists', '7day',    force: force);
    await _prefetchTopList(service, 'albums',  '7day',    force: force);
    await _prefetchTopList(service, 'tracks',  '7day',    force: force);
    debugPrint('[Prefetch] Dashboard prêt.');
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Workers privés
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> _prefetchUserInfo(
    LastFmService service, {bool force = false}
  ) async {
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
    int  limit = 50,
    bool force = false,
  }) async {
    final key = switch (type) {
      'artists' => DataCache.keyTopArtists(period),
      'albums'  => DataCache.keyTopAlbums(period),
      _         => DataCache.keyTopTracks(period),
    };
    if (!force && DataCache.getSync(key) != null) return;

    await _call(() async {
      final List<dynamic> data = switch (type) {
        'artists' => await service.getTopArtists(period: period, limit: limit),
        'albums'  => await service.getTopAlbums(period: period,  limit: limit),
        _         => await service.getTopTracks(period: period,  limit: limit),
      };
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchRecent(
    LastFmService service, {int limit = 10, bool force = false}
  ) async {
    final key = DataCache.keyRecentTracks(limit: limit);
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getRecentTracks(limit: limit);
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchMonthly(
    LastFmService service, {bool force = false}
  ) async {
    final key = DataCache.keyMonthlyScrobbles();
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getMonthlyScrobbles(months: 12);
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  static Future<void> _prefetchLoved(
    LastFmService service, {bool force = false}
  ) async {
    final key = DataCache.keyLovedTracks();
    if (!force && DataCache.getSync(key) != null) return;
    await _call(() async {
      final data = await service.getLovedTracks(limit: 50);
      if (data.isNotEmpty) await DataCache.set(key, data);
    });
  }

  // ── Helper : exécute fn avec délai et gestion d'erreur ───────────────────

  static Future<void> _call(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('[Prefetch] Erreur ignorée : $e');
    }
    await Future.delayed(_delay);
  }
}