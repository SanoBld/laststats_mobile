// lib/screens/settings/cache_page.dart
// ══════════════════════════════════════════════════════════════════════════
//  CachePage — gestion et monitoring du cache
//
//  Sections :
//    • Scrobbles  — total, années, dernière sync, taille disque
//    • Images     — entrées URL en cache, vider
//    • Données API — entrées DataCache, vider
//    • Actions globales — vider tout, forcer rechargement
// ══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/scrobbles_file_cache.dart';
import '../../services/all_scrobbles_service.dart';
import '../../services/data_cache.dart';
import '../../services/image_service.dart';
import '../../app_state.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

bool get _isEn => localeNotifier.value == 'en';

String _t(String fr, String en) => _isEn ? en : fr;

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} Mo';
}

String _formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)} k';
  return '${(n / 1000000).toStringAsFixed(2)} M';
}

String _relativeDate(int? ms) {
  if (ms == null || ms == 0) return _t('Jamais', 'Never');
  final dt   = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60)  return _t('À l\'instant', 'Just now');
  if (diff.inMinutes < 60)  return _t('Il y a ${diff.inMinutes} min', '${diff.inMinutes} min ago');
  if (diff.inHours   < 24)  return _t('Il y a ${diff.inHours} h', '${diff.inHours} h ago');
  if (diff.inDays    < 7)   return _t('Il y a ${diff.inDays} j', '${diff.inDays} d ago');
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

// ══════════════════════════════════════════════════════════════════════════
//  Page
// ══════════════════════════════════════════════════════════════════════════

class CachePage extends StatefulWidget {
  const CachePage({super.key});

  @override
  State<CachePage> createState() => _CachePageState();
}

class _CachePageState extends State<CachePage> {
  // ── Stats ────────────────────────────────────────────────────────────────
  bool   _loading    = true;
  int    _scrobbleCount = 0;
  List<int> _cachedYears = [];
  int?   _lastSyncTs;
  int    _scroDiskBytes = 0;
  int    _imgMemEntries  = 0;
  int    _apiMemEntries  = 0;
  int    _apiDiskEntries = 0;
  int    _maxImgEntries  = 500; // préférence sauvegardée

  // ── États actions ────────────────────────────────────────────────────────
  bool _clearingImg    = false;
  bool _clearingApi    = false;
  bool _clearingScro   = false;
  bool _clearingAll    = false;

  @override
  void initState() {
    super.initState();
    localeNotifier.addListener(_rebuild);
    _load();
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs      = await SharedPreferences.getInstance();
      final diskBytes  = await ScrobblesFileCache.getDiskUsageBytes();
      final meta       = ScrobblesFileCache.getMeta();
      final lastSync   = (meta?['last_sync_ts'] as num?)?.toInt();

      if (!mounted) return;
      setState(() {
        _scrobbleCount  = ScrobblesFileCache.getTotalScrobbleCount();
        _cachedYears    = ScrobblesFileCache.getCachedYears();
        _lastSyncTs     = lastSync;
        _scroDiskBytes  = diskBytes;
        _imgMemEntries  = ImageService.memCacheSize;
        _apiMemEntries  = DataCache.memEntries;
        _apiDiskEntries = DataCache.diskEntries;
        _maxImgEntries  = prefs.getInt('ls_max_img_cache_entries') ?? 500;
        _loading        = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveMaxImgEntries(int v) async {
    setState(() => _maxImgEntries = v);
    final p = await SharedPreferences.getInstance();
    await p.setInt('ls_max_img_cache_entries', v);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _clearImages() async {
    setState(() => _clearingImg = true);
    await ImageService.clearAllCache();
    await _load();
    setState(() => _clearingImg = false);
  }

  Future<void> _clearApi() async {
    setState(() => _clearingApi = true);
    await DataCache.clear();
    await _load();
    setState(() => _clearingApi = false);
  }

  Future<void> _clearScrobbles() async {
    final confirm = await _confirm(
      _t('Vider l\'historique ?', 'Clear scrobble history?'),
      _t(
        'Les données seront retéléchargées depuis Last.fm au prochain lancement.',
        'Data will be re-downloaded from Last.fm on the next launch.',
      ),
    );
    if (!confirm) return;
    setState(() => _clearingScro = true);
    await ScrobblesFileCache.clear();
    await _load();
    setState(() => _clearingScro = false);
  }

  Future<void> _clearAll() async {
    final confirm = await _confirm(
      _t('Vider tout le cache ?', 'Clear all cache?'),
      _t(
        'Images, données API et historique des scrobbles seront supprimés.',
        'Images, API data and scrobble history will all be deleted.',
      ),
    );
    if (!confirm) return;
    setState(() => _clearingAll = true);
    await Future.wait([
      ImageService.clearAllCache(),
      DataCache.clear(),
      ScrobblesFileCache.clear(),
    ]);
    await _load();
    setState(() => _clearingAll = false);
  }

  Future<bool> _confirm(String title, String msg) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Annuler', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(_t('Vider', 'Clear')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Gestion du cache', 'Cache management')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Scrobbles ────────────────────────────────────────────
                  _Section(
                    icon:  Icons.history_rounded,
                    color: scheme.primaryContainer,
                    fgColor: scheme.onPrimaryContainer,
                    title: _t('Historique des scrobbles', 'Scrobble history'),
                    children: [
                      _StatRow(
                        label: _t('Total en cache', 'Cached scrobbles'),
                        value: _scrobbleCount > 0
                            ? _formatCount(_scrobbleCount)
                            : _t('Aucun', 'None'),
                        icon: Icons.music_note_rounded,
                      ),
                      _StatRow(
                        label: _t('Années chargées', 'Loaded years'),
                        value: _cachedYears.isEmpty
                            ? '—'
                            : '${_cachedYears.first} – ${_cachedYears.last}'
                              ' (${_cachedYears.length})',
                        icon: Icons.calendar_today_rounded,
                      ),
                      _StatRow(
                        label: _t('Dernière sync', 'Last sync'),
                        value: _relativeDate(_lastSyncTs),
                        icon: Icons.sync_rounded,
                      ),
                      _StatRow(
                        label: _t('Taille sur disque', 'Disk usage'),
                        value: _formatBytes(_scroDiskBytes),
                        icon: Icons.storage_rounded,
                      ),

                      // Barre de progression de couverture
                      if (_cachedYears.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _YearCoverage(
                          years: _cachedYears,
                          completeYears: _cachedYears
                              .where(AllScrobblesService.isYearComplete)
                              .toList(),
                          scheme: scheme,
                          text: text,
                        ),
                      ],

                      const SizedBox(height: 12),
                      _ActionButton(
                        label: _t('Vider l\'historique', 'Clear history'),
                        icon:  Icons.delete_outline_rounded,
                        color: scheme.error,
                        onFg:  scheme.onError,
                        loading: _clearingScro,
                        onTap: _clearScrobbles,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Images ───────────────────────────────────────────────
                  _Section(
                    icon:  Icons.image_rounded,
                    color: scheme.secondaryContainer,
                    fgColor: scheme.onSecondaryContainer,
                    title: _t('Cache d\'images', 'Image cache'),
                    children: [
                      _StatRow(
                        label: _t('URLs en mémoire', 'In-memory URLs'),
                        value: '$_imgMemEntries',
                        icon: Icons.memory_rounded,
                      ),
                      const SizedBox(height: 12),
                      // Limite du cache d'images
                      Text(
                        _t(
                          'Nombre max d\'images en cache : $_maxImgEntries',
                          'Max cached images: $_maxImgEntries',
                        ),
                        style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant),
                      ),
                      Slider(
                        value:   _maxImgEntries.toDouble(),
                        min:     100,
                        max:     2000,
                        divisions: 19,
                        label:   '$_maxImgEntries',
                        onChanged: (v) => _saveMaxImgEntries(v.round()),
                      ),
                      const SizedBox(height: 4),
                      _ActionButton(
                        label: _t('Vider le cache images', 'Clear image cache'),
                        icon:  Icons.clear_rounded,
                        color: scheme.secondary,
                        onFg:  scheme.onSecondary,
                        loading: _clearingImg,
                        onTap: _clearImages,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ── Données API ──────────────────────────────────────────
                  _Section(
                    icon:  Icons.cloud_rounded,
                    color: scheme.tertiaryContainer,
                    fgColor: scheme.onTertiaryContainer,
                    title: _t('Données API', 'API data'),
                    children: [
                      _StatRow(
                        label: _t('Entrées mémoire', 'In-memory entries'),
                        value: '$_apiMemEntries',
                        icon: Icons.memory_rounded,
                      ),
                      _StatRow(
                        label: _t('Entrées disque', 'Disk entries'),
                        value: '$_apiDiskEntries',
                        icon: Icons.storage_rounded,
                      ),
                      const SizedBox(height: 12),
                      _ActionButton(
                        label: _t('Vider le cache API', 'Clear API cache'),
                        icon:  Icons.refresh_rounded,
                        color: scheme.tertiary,
                        onFg:  scheme.onTertiary,
                        loading: _clearingApi,
                        onTap: _clearApi,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Tout vider ───────────────────────────────────────────
                  FilledButton.icon(
                    onPressed: _clearingAll ? null : _clearAll,
                    icon: _clearingAll
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_forever_rounded),
                    label: Text(_t('Vider tout le cache', 'Clear all cache')),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    _t(
                      'Les scrobbles seront retéléchargés depuis Last.fm.',
                      'Scrobbles will be re-downloaded from Last.fm.',
                    ),
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Widgets internes
// ══════════════════════════════════════════════════════════════════════════

class _Section extends StatelessWidget {
  final IconData  icon;
  final Color     color;
  final Color     fgColor;
  final String    title;
  final List<Widget> children;

  const _Section({
    required this.icon,
    required this.color,
    required this.fgColor,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: fgColor),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;

  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ),
        Text(value,
            style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final Color    onFg;
  final bool     loading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onFg,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color),
            )
          : Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        minimumSize: const Size.fromHeight(40),
      ),
    );
  }
}

class _YearCoverage extends StatelessWidget {
  final List<int>   years;
  final List<int>   completeYears;
  final ColorScheme scheme;
  final TextTheme   text;

  const _YearCoverage({
    required this.years,
    required this.completeYears,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isEn = localeNotifier.value == 'en';
    final total    = years.length;
    final complete = completeYears.length;
    final pct      = total > 0 ? (complete / total * 100).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEn
              ? '$complete / $total years with full metadata ($pct%)'
              : '$complete / $total années avec métadonnées ($pct%)',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:           total > 0 ? complete / total : 0,
            minHeight:       6,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor:      AlwaysStoppedAnimation(scheme.primary),
          ),
        ),
        const SizedBox(height: 6),
        // Mini chips par année
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: years.map((y) {
            final ok = completeYears.contains(y);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: ok
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$y',
                style: text.labelSmall?.copyWith(
                  color: ok ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                  fontWeight: ok ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}