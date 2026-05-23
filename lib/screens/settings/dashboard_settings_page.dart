// lib/screens/settings/dashboard_settings_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n.dart';
import '../../app_state.dart';
import 'settings_helpers.dart';

class DashboardSettingsPage extends StatefulWidget {
  const DashboardSettingsPage({super.key});

  @override
  State<DashboardSettingsPage> createState() => _DashboardSettingsPageState();
}

class _DashboardSettingsPageState extends State<DashboardSettingsPage> {
  String _headerSource          = 'nowplaying';
  String _headerAnimation       = 'fade';
  String _headerPeriod          = 'overall';
  double _headerBlur            = 0.0;
  String _headerCustomUrl       = '';
  String _headerFallbackUrl     = '';
  bool   _headerFallbackEnabled = false;
  bool   _showNowPlay           = true;
  bool   _showStats             = true;
  bool   _showArtists           = true;
  bool   _showTracks            = true;
  bool   _showFriends           = true;
  List<String> _statCards       = List.from(kDefaultStatCards);

  final _customUrlCtrl   = TextEditingController();
  final _fallbackUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    localeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_rebuild);
    _customUrlCtrl.dispose();
    _fallbackUrlCtrl.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _headerSource          = p.getString('ls_header_source')          ?? 'nowplaying';
      _headerAnimation       = p.getString('ls_header_animation')       ?? 'fade';
      _headerPeriod          = p.getString('ls_header_period')          ?? 'overall';
      _headerBlur            = p.getDouble('ls_header_blur')            ?? 0.0;
      _headerCustomUrl       = p.getString('ls_header_custom_url')      ?? '';
      _headerFallbackUrl     = p.getString('ls_header_fallback_url')    ?? '';
      _headerFallbackEnabled = p.getBool('ls_header_fallback_enabled')  ?? false;
      _showNowPlay           = p.getBool('ls_show_nowplay')             ?? true;
      _showStats             = p.getBool('ls_show_stats')               ?? true;
      _showArtists           = p.getBool('ls_show_artists')             ?? true;
      _showTracks            = p.getBool('ls_show_tracks')              ?? true;
      _showFriends           = p.getBool('ls_show_friends')             ?? true;
      final raw = p.getStringList('ls_stat_cards');
      _statCards = raw != null && raw.isNotEmpty ? raw : List.from(kDefaultStatCards);
    });
    _customUrlCtrl.text   = _headerCustomUrl;
    _fallbackUrlCtrl.text = _headerFallbackUrl;
  }

  Future<void> _set<T>(String key, T v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool)   await p.setBool(key, v);
    if (v is String) await p.setString(key, v);
    if (v is double) await p.setDouble(key, v);
  }

  Future<void> _saveList(String key, List<String> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(key, list);
  }

  @override
  Widget build(BuildContext context) {
    final scheme    = Theme.of(context).colorScheme;
    final text      = Theme.of(context).textTheme;
    final isEn      = localeNotifier.value == 'en';
    final sources   = buildHeaderSources();
    final anims     = buildHeaderAnimations();
    final periods   = buildHeaderPeriods();

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsDashboardSection),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── En-tête (image de fond) ────────────────────────────────────────
        SettingsSection(label: L.settingsHeaderImage, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Source
              Row(children: [
                Icon(Icons.wallpaper_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(L.settingsHeaderSource, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(L.settingsHeaderImageSub,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: sources.map((opt) {
                final (key, label, icon) = opt;
                final sel = _headerSource == key;
                return FilterChip(
                  avatar: Icon(icon, size: 16), label: Text(label),
                  selected: sel, showCheckmark: false,
                  onSelected: (_) async {
                    await _set('ls_header_source', key);
                    setState(() => _headerSource = key);
                  },
                );
              }).toList()),

              // URL personnalisée (si source = custom)
              if (_headerSource == 'custom') ...[
                const SizedBox(height: 16),
                Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.link_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(L.settingsHeaderCustomUrl,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: _customUrlCtrl, autocorrect: false,
                  keyboardType: TextInputType.url, textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: L.settingsHeaderCustomUrlHint,
                    prefixIcon: const Icon(Icons.image_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      tooltip: L.settingsHeaderApply,
                      onPressed: () async {
                        final url = _customUrlCtrl.text.trim();
                        await _set('ls_header_custom_url', url);
                        setState(() => _headerCustomUrl = url);
                      },
                    ),
                  ),
                  onSubmitted: (url) async {
                    await _set('ls_header_custom_url', url.trim());
                    setState(() => _headerCustomUrl = url.trim());
                  },
                ),
                const SizedBox(height: 6),
                Text(L.settingsHeaderCustomUrlSub,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],

              // Période (si source = top_*)
              if (['top_track', 'top_album', 'top_artist'].contains(_headerSource)) ...[
                const SizedBox(height: 16),
                Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.date_range_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(L.settingsHeaderPeriod,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: periods.map((opt) {
                  final (key, label) = opt;
                  return FilterChip(
                    label: Text(label), selected: _headerPeriod == key, showCheckmark: false,
                    onSelected: (_) async {
                      await _set('ls_header_period', key);
                      setState(() => _headerPeriod = key);
                    },
                  );
                }).toList()),
              ],

              // Image de secours (si source = nowplaying)
              if (_headerSource == 'nowplaying') ...[
                const SizedBox(height: 16),
                Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Row(children: [
                  Switch(
                    value: _headerFallbackEnabled,
                    onChanged: (v) async {
                      await _set('ls_header_fallback_enabled', v);
                      setState(() => _headerFallbackEnabled = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(L.settingsHeaderFallback,
                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(L.settingsHeaderFallbackSub,
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ])),
                ]),
                if (_headerFallbackEnabled) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _fallbackUrlCtrl, autocorrect: false,
                    keyboardType: TextInputType.url, textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: L.settingsHeaderFallbackUrlLabel,
                      hintText: L.settingsHeaderCustomUrlHint,
                      prefixIcon: const Icon(Icons.image_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        tooltip: L.settingsHeaderApply,
                        onPressed: () async {
                          final url = _fallbackUrlCtrl.text.trim();
                          await _set('ls_header_fallback_url', url);
                          setState(() => _headerFallbackUrl = url);
                        },
                      ),
                    ),
                    onSubmitted: (url) async {
                      await _set('ls_header_fallback_url', url.trim());
                      setState(() => _headerFallbackUrl = url.trim());
                    },
                  ),
                ],
              ],
            ],
          )),
        ]),

        const SizedBox(height: 16),

        // ── Animation & Flou ──────────────────────────────────────────────
        SettingsSection(label: isEn ? 'Animation & Blur' : 'Animation & Flou', children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [

              Row(children: [
                Icon(Icons.animation_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(L.settingsHeaderAnimation,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(L.settingsHeaderAnimationSub,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: anims.map((opt) {
                final (key, label, icon) = opt;
                return FilterChip(
                  avatar: Icon(icon, size: 16), label: Text(label),
                  selected: _headerAnimation == key, showCheckmark: false,
                  onSelected: (_) async {
                    await _set('ls_header_animation', key);
                    setState(() => _headerAnimation = key);
                  },
                );
              }).toList()),

              const SizedBox(height: 16),
              Divider(color: scheme.outlineVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),

              Row(children: [
                Icon(Icons.blur_on_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(L.settingsHeaderBlur,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant)),
                  child: Text(
                    _headerBlur < 1 ? L.settingsHeaderBlurNone : '${_headerBlur.round()}',
                    style: text.labelMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Slider(
                value: _headerBlur, min: 0, max: 20, divisions: 20,
                label: _headerBlur < 1 ? L.settingsHeaderBlurNone : '${_headerBlur.round()}',
                onChanged: (v) => setState(() => _headerBlur = v),
                onChangeEnd: (v) async => await _set('ls_header_blur', v),
              ),
              const SizedBox(height: 8),
            ],
          )),
        ]),

        const SizedBox(height: 16),

        // ── Sections visibles ─────────────────────────────────────────────
        SettingsSection(label: L.settingsVisibleSections, children: [
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline_rounded),
            title: Text(L.settingsNowPlayingSection), value: _showNowPlay,
            onChanged: (v) async { await _set('ls_show_nowplay', v); setState(() => _showNowPlay = v); }),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.bar_chart_rounded),
            title: Text(L.settingsStatsSection), value: _showStats,
            onChanged: (v) async { await _set('ls_show_stats', v); setState(() => _showStats = v); }),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.mic_rounded),
            title: Text(L.settingsTopArtistsSection), value: _showArtists,
            onChanged: (v) async { await _set('ls_show_artists', v); setState(() => _showArtists = v); }),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.music_note_rounded),
            title: Text(L.settingsTopTracksSection), value: _showTracks,
            onChanged: (v) async { await _set('ls_show_tracks', v); setState(() => _showTracks = v); }),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: const Icon(Icons.people_rounded),
            title: Text(L.settingsFriendsSection),
            subtitle: Text(L.settingsFriendsSectionSub),
            value: _showFriends,
            onChanged: (v) async { await _set('ls_show_friends', v); setState(() => _showFriends = v); }),
        ]),

        const SizedBox(height: 16),

        // ── Cartes de statistiques ────────────────────────────────────────
        SettingsSection(
          label: isEn ? 'Stat Cards' : 'Cartes de statistiques',
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.grid_view_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(isEn ? 'Stat Cards' : 'Cartes de stats',
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                Text(isEn
                    ? 'Choose and reorder the cards shown in the stats block.'
                    : 'Choisissez les cartes affichées dans le bloc statistiques.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            )),
            ...kAllStatCards.map((card) {
              final (id, emoji, labelFr, labelEn) = card;
              final label   = isEn ? labelEn : labelFr;
              final enabled = _statCards.contains(id);
              return CheckboxListTile(
                secondary: Text(emoji, style: const TextStyle(fontSize: 20)),
                title: Text(label),
                value: enabled,
                controlAffinity: ListTileControlAffinity.trailing,
                dense: true,
                onChanged: (v) async {
                  final updated = List<String>.from(_statCards);
                  if (v == true) {
                    if (!updated.contains(id)) updated.add(id);
                  } else {
                    updated.remove(id);
                  }
                  await _saveList('ls_stat_cards', updated);
                  setState(() => _statCards = updated);
                },
              );
            }),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14), child: FilledButton.tonalIcon(
              icon: const Icon(Icons.swap_vert_rounded, size: 18),
              label: Text(isEn ? 'Reorder cards' : 'Réordonner les cartes'),
              onPressed: () async {
                final result = await showModalBottomSheet<List<String>>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  useSafeArea: true,
                  builder: (_) => CardReorderSheet(cards: List.from(_statCards)),
                );
                if (result != null && mounted) {
                  await _saveList('ls_stat_cards', result);
                  setState(() => _statCards = result);
                }
              },
            )),
          ],
        ),

        const SizedBox(height: 20),
        const RestartBanner(),
        const SizedBox(height: 20),
      ]),
    );
  }
}
