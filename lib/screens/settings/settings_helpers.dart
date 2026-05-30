// lib/screens/settings/settings_helpers.dart
// Partagé par toutes les sous-pages de paramètres / Shared by all settings sub-pages

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_state.dart';
import '../../l10n.dart';

// ── Clés SharedPreferences (référence) ───────────────────────────────────────
// ls_header_fallback_type   : 'none' | 'top_track' | 'top_album' | 'top_artist' | 'custom_url'
// ls_header_fallback_period : '7day' | '1month' | 'overall'
// ls_header_fallback_url    : URL string (fallback custom image)
// ls_header_fallback_enabled: bool (rétrocompatibilité)
// ─────────────────────────────────────────────────────────────────────────────

// ── Constantes ────────────────────────────────────────────────────────────────

const kSettingsAccentOptions = [
  (Color(0xFF7C3AED), 'purple', 'Violet / Purple'),
  (Color(0xFF1D4ED8), 'blue',   'Bleu / Blue'),
  (Color(0xFF059669), 'green',  'Vert / Green'),
  (Color(0xFFDC2626), 'red',    'Rouge / Red'),
  (Color(0xFFD97706), 'orange', 'Orange'),
  (Color(0xFFDB2777), 'pink',   'Rose / Pink'),
  (Color(0xFF0F766E), 'teal',   'Sarcelle / Teal'),
];

/// Cartes de statistiques — dupliqué ici pour être accessible hors du part-of.
const kAllStatCards = [
  ('top_artist',      '🎤', 'Artiste #1',           'Artist #1'),
  ('top_album',       '💿', 'Album #1',              'Album #1'),
  ('top_track',       '🎵', 'Titre #1',              'Track #1'),
  ('last_track',      '⏱️', 'Dernière écoute',       'Last played'),
  ('total',           '🎯', 'Total scrobbles',        'Total scrobbles'),
  ('avg_day',         '⚡', 'Moy. / jour',            'Avg / day'),
  ('avg_week',        '📅', 'Moy. / semaine',         'Avg / week'),
  ('days_active',     '🗓️', 'Jours actifs',           'Days active'),
  ('since',           '📆', 'Membre depuis',           'Member since'),
  ('country',         '🌍', 'Pays',                   'Country'),
  ('top_artist_week', '🎤', 'Artiste #1 (semaine)',   'Artist #1 (week)'),
  ('top_album_week',  '💿', 'Album #1 (semaine)',     'Album #1 (week)'),
  ('top_track_week',  '🎵', 'Titre #1 (semaine)',     'Track #1 (week)'),
];
const kDefaultStatCards = ['top_artist', 'top_album', 'top_track', 'last_track'];

String statCardLabel(String id) {
  final isEn = localeNotifier.value == 'en';
  for (final c in kAllStatCards) {
    if (c.$1 == id) return isEn ? c.$4 : c.$3;
  }
  return id;
}

// ── Listes localisées ─────────────────────────────────────────────────────────

List<(IconData, String)> buildStartupLabels() => [
  (Icons.dashboard_rounded,    L.navDashboard),
  (Icons.search_rounded,       L.navSearch),
  (Icons.emoji_events_rounded, L.navRankings),
  (Icons.auto_graph_rounded,   L.navCharts),
  (Icons.history_rounded,      L.navHistory),
];

List<(String, String, IconData)> buildHeaderSources() => [
  ('nowplaying',  L.headerNowPlaying,  Icons.play_circle_rounded),
  ('top_track',   L.headerTopTrack,    Icons.music_note_rounded),
  ('top_album',   L.headerTopAlbum,    Icons.album_rounded),
  ('top_artist',  L.headerTopArtist,   Icons.mic_rounded),
  ('custom',      L.headerCustomImage, Icons.image_rounded),
  ('none',        L.headerThemeColor,  Icons.palette_rounded),
];

List<(String, String, IconData)> buildHeaderAnimations() => [
  ('none',  L.headerAnimNone,  Icons.block_rounded),
  ('fade',  L.headerAnimFade,  Icons.opacity_rounded),
  ('slide', L.headerAnimSlide, Icons.swap_horiz_rounded),
  ('zoom',  L.headerAnimZoom,  Icons.zoom_in_rounded),
];

List<(String, String)> buildHeaderPeriods() => [
  ('7day',    L.headerPeriodWeek),
  ('1month',  L.headerPeriodMonth),
  ('overall', L.headerPeriodAllTime),
];

// ── SettingsSection ───────────────────────────────────────────────────────────

class SettingsSection extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const SettingsSection({super.key, required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label.toUpperCase(), style: text.labelSmall?.copyWith(
            color: scheme.primary, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 1),
        ),
        child: Column(children: children),
      ),
    ]);
  }
}

// ── Bannière "redémarrage requis" ─────────────────────────────────────────────

class RestartBanner extends StatelessWidget {
  const RestartBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEn   = localeNotifier.value == 'en';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 16, color: scheme.onTertiaryContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(
          isEn
              ? 'Some features may require restarting the app to take effect.'
              : 'Certaines fonctionnalités nécessitent un redémarrage de l\'app pour s\'appliquer.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer),
        )),
      ]),
    );
  }
}

// ── ColorPickerDialog (public) ────────────────────────────────────────────────

class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  const ColorPickerDialog({super.key, required this.initialColor});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSLColor _hsl;
  late TextEditingController _hexCtrl;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    // Load the initial color as-is — no clamping.
    // Black, white, and any gray are all valid choices.
    _hsl = HSLColor.fromColor(widget.initialColor);
    _hexCtrl = TextEditingController(text: colorToHex(_hsl.toColor()));
  }

  @override
  void dispose() { _hexCtrl.dispose(); super.dispose(); }

  Color get _color => _hsl.toColor();

  void _syncHex() {
    _hexCtrl.text = colorToHex(_color);
    _hexCtrl.selection = TextSelection.collapsed(offset: _hexCtrl.text.length);
    _hexError = false;
  }

  void _onHexInput(String raw) {
    final hex = raw.trim().replaceAll('#', '');
    if (hex.length != 6) { setState(() => _hexError = true); return; }
    try {
      final c = Color(0xFF000000 | int.parse(hex, radix: 16));
      setState(() { _hsl = HSLColor.fromColor(c); _hexError = false; });
    } catch (_) { setState(() => _hexError = true); }
  }

  Widget _hueSlider() => LayoutBuilder(builder: (_, c) => GestureDetector(
    onTapDown:   (d) => setState(() { _hsl = _hsl.withHue((d.localPosition.dx / c.maxWidth).clamp(0, 1) * 360); _syncHex(); }),
    onPanUpdate: (d) => setState(() { _hsl = _hsl.withHue((d.localPosition.dx / c.maxWidth).clamp(0, 1) * 360); _syncHex(); }),
    child: SizedBox(height: 36, child: Stack(alignment: Alignment.centerLeft, children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: Container(height: 24,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [
            Color(0xFFFF0000), Color(0xFFFF8000), Color(0xFFFFFF00),
            Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF),
            Color(0xFFFF00FF), Color(0xFFFF0000),
          ])))),
      Positioned(
        left: ((_hsl.hue / 360) * c.maxWidth - 12).clamp(0, c.maxWidth - 24),
        child: Container(width: 24, height: 36, decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black26, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        )),
      ),
    ])),
  ));

  Widget _sliderRow(String label, double value, double min, double max,
      List<Color> gradient, void Function(double) onChange) =>
    LayoutBuilder(builder: (_, c) => GestureDetector(
      onTapDown:   (d) => setState(() { onChange(((d.localPosition.dx / c.maxWidth) * (max - min) + min).clamp(min, max)); _syncHex(); }),
      onPanUpdate: (d) => setState(() { onChange(((d.localPosition.dx / c.maxWidth) * (max - min) + min).clamp(min, max)); _syncHex(); }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(height: 28, child: Stack(alignment: Alignment.centerLeft, children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: Container(height: 20,
              decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)))),
          Positioned(
            left: (((value - min) / (max - min)) * c.maxWidth - 10).clamp(0, c.maxWidth - 20),
            child: Container(width: 20, height: 28, decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.black26, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
            )),
          ),
        ])),
      ]),
    ));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final pure   = _hsl.withSaturation(1.0).withLightness(0.5).toColor();

    // Quick presets — includes black and white for monochromatic themes
    const quickPresets = [
      Color(0xFF7C3AED), Color(0xFF1D4ED8), Color(0xFF059669), Color(0xFFDC2626),
      Color(0xFFD97706), Color(0xFFDB2777), Color(0xFF0F766E), Color(0xFFEA580C),
      Color(0xFF0284C7), Color(0xFF16A34A),
      Color(0xFF000000), // Black — produces a neutral dark theme
      Color(0xFFFFFFFF), // White — produces a neutral light theme
    ];

    return AlertDialog(
      title: Text(L.colorPickerTitle),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(width: 340, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Container(height: 52, decoration: BoxDecoration(
                color: _color, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _hexCtrl, onChanged: _onHexInput,
              decoration: InputDecoration(
                labelText: 'HEX',
                errorText: _hexError ? L.colorPickerInvalid : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              style: text.bodyMedium?.copyWith(fontFamily: 'monospace'),
            )),
          ]),
          const SizedBox(height: 16),
          Text(L.colorPickerHue, style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _hueSlider(),
          const SizedBox(height: 14),
          _sliderRow(L.colorPickerSaturation, _hsl.saturation, 0.0, 1.0,
            [Colors.grey.shade400, pure], (v) => _hsl = _hsl.withSaturation(v)),
          const SizedBox(height: 14),
          _sliderRow(L.colorPickerBrightness, _hsl.lightness, 0.0, 1.0,
            [Colors.black, _hsl.withSaturation(1.0).withLightness(0.5).toColor(), Colors.white],
            (v) => _hsl = _hsl.withLightness(v)),
          const SizedBox(height: 16),
          Text(L.colorPickerQuickColors, style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: quickPresets.map((c) => GestureDetector(
            onTap: () => setState(() { _hsl = HSLColor.fromColor(c); _syncHex(); }),
            child: Container(width: 28, height: 28, decoration: BoxDecoration(
                color: c, shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant, width: 1))),
          )).toList()),
          const SizedBox(height: 16),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(L.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: Text(L.commonApply)),
      ],
    );
  }
}

// ── ExportSheet (public) ──────────────────────────────────────────────────────

class ExportSheet extends StatefulWidget {
  final String payload, defaultName;
  const ExportSheet({super.key, required this.payload, required this.defaultName});

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  late final TextEditingController _nameCtrl;
  bool _copied = false;

  @override
  void initState() { super.initState(); _nameCtrl = TextEditingController(text: widget.defaultName); }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.payload));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _copied = false); });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
      builder: (ctx, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Scaffold(body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 12, 8, 4), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                Icon(Icons.upload_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(L.exportTitle, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ])),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
          ])),
          const Divider(height: 1),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
            Text(L.exportFilename, style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _nameCtrl, decoration: InputDecoration(
              prefixIcon: const Icon(Icons.insert_drive_file_outlined), suffixText: '.json',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            )),
            const SizedBox(height: 20),
            Text(L.exportJsonContent, style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5))),
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(padding: const EdgeInsets.all(12),
                child: SelectableText(widget.payload,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: scheme.onSurfaceVariant))),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(L.exportInfo,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _copy,
              icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
              label: Text(_copied ? L.exportCopied : L.exportCopy),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: _copied ? Colors.green.shade600 : null,
              ),
            ),
          ])),
        ])),
      ),
    );
  }
}

// ── CardReorderSheet (public) ─────────────────────────────────────────────────

class CardReorderSheet extends StatefulWidget {
  final List<String> cards;
  const CardReorderSheet({super.key, required this.cards});

  @override
  State<CardReorderSheet> createState() => _CardReorderSheetState();
}

class _CardReorderSheetState extends State<CardReorderSheet> {
  late List<String> _items;

  @override
  void initState() { super.initState(); _items = List.from(widget.cards); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final ctrl   = ScrollController();
    final isEn   = localeNotifier.value == 'en';

    return DraggableScrollableSheet(
      initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
      builder: (ctx, sc) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(color: scheme.surface, child: Column(children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36, height: 4, decoration: BoxDecoration(
                  color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 16, 12), child: Row(children: [
            Text(isEn ? 'Reorder cards' : 'Réordonner les cartes',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(ctx, _items),
                child: Text(isEn ? 'Save' : 'Enregistrer')),
          ])),
          Expanded(child: ReorderableListView(
            scrollController: ctrl,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onReorder: (oldIdx, newIdx) => setState(() {
              if (newIdx > oldIdx) newIdx--;
              final item = _items.removeAt(oldIdx);
              _items.insert(newIdx, item);
            }),
            children: _items.map((id) {
              final card = kAllStatCards.firstWhere((c) => c.$1 == id,
                  orElse: () => (id, '📋', id, id));
              return Card(key: ValueKey(id), elevation: 0,
                color: scheme.surfaceContainerHighest,
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
                child: ListTile(
                  leading: Text(card.$2, style: const TextStyle(fontSize: 20)),
                  title: Text(isEn ? card.$4 : card.$3,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  trailing: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant),
                ));
            }).toList(),
          )),
        ])),
      ),
    );
  }
}