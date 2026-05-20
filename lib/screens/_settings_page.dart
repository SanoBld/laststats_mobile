// ignore_for_file: unused_import
part of 'home_screen.dart';

class _SettingsPage extends StatefulWidget {
  final String username; const _SettingsPage({required this.username});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  String _theme = 'system', _accent = 'purple';
  bool   _useDynamicColor = false, _useNowPlayingColor = false;
  int    _startupTab = 0;
  String _headerSource = 'nowplaying';
  double _headerBlur = 0.0;
  String _headerAnimation = 'fade';
  String _headerCustomUrl = '';
  String _headerFallbackUrl = '';
  bool   _headerFallbackEnabled = false;
  String _headerPeriod = 'overall';
  bool   _showNowPlay = true, _showStats = true, _showArtists = true, _showTracks = true;
  bool   _autoUpdate = true;
  UpdateInfo? _updateInfo; bool _checkingUpdate = false; String? _updateError;

  final _customUrlCtrl  = TextEditingController();
  final _fallbackUrlCtrl = TextEditingController();

  bool get _isCustomAccent =>
      _accent.startsWith('#') ||
      !_kAccentOptions.any((o) => o.$2 == _accent);

  @override
  void dispose() {
    _customUrlCtrl.dispose();
    _fallbackUrlCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() { super.initState(); _loadPrefs().then((_) => _maybeCheckUpdate()); }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _theme               = p.getString('ls_theme')                    ?? 'system';
      _accent              = p.getString('ls_accent')                   ?? 'purple';
      _useDynamicColor     = p.getBool('ls_use_dynamic_color')          ?? false;
      _useNowPlayingColor  = p.getBool('ls_use_nowplaying_color')       ?? false;
      _startupTab          = p.getInt('ls_startup_tab')                 ?? 0;
      _headerSource        = p.getString('ls_header_source')            ?? 'nowplaying';
      _headerBlur          = p.getDouble('ls_header_blur')              ?? 0.0;
      _headerAnimation     = p.getString('ls_header_animation')         ?? 'fade';
      _headerCustomUrl     = p.getString('ls_header_custom_url')        ?? '';
      _headerFallbackUrl   = p.getString('ls_header_fallback_url')      ?? '';
      _headerFallbackEnabled = p.getBool('ls_header_fallback_enabled')  ?? false;
      _headerPeriod        = p.getString('ls_header_period')            ?? 'overall';
      _showNowPlay         = p.getBool('ls_show_nowplay')               ?? true;
      _showStats           = p.getBool('ls_show_stats')                 ?? true;
      _showArtists         = p.getBool('ls_show_artists')               ?? true;
      _showTracks          = p.getBool('ls_show_tracks')                ?? true;
      _autoUpdate          = p.getBool('ls_auto_update_check')          ?? true;
    });
    _customUrlCtrl.text  = _headerCustomUrl;
    _fallbackUrlCtrl.text = _headerFallbackUrl;
  }

  Future<void> _maybeCheckUpdate() async {
    if (!_autoUpdate) return;
    final p = await SharedPreferences.getInstance();
    if (DateTime.now().millisecondsSinceEpoch - (p.getInt('ls_last_update_check') ?? 0) <
        const Duration(days: 1).inMilliseconds) return;
    await _checkUpdate(auto: true);
  }

  Future<void> _checkUpdate({bool auto = false}) async {
    if (!mounted) return;
    setState(() { _checkingUpdate = true; _updateError = null; });
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      final p = await SharedPreferences.getInstance();
      await p.setInt('ls_last_update_check', DateTime.now().millisecondsSinceEpoch);
      setState(() { _updateInfo = info; _checkingUpdate = false; });
    } catch (_) {
      if (mounted) setState(() { _updateError = 'Vérification impossible.'; _checkingUpdate = false; });
    }
  }

  Future<void> _set<T>(String key, T v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool)   await p.setBool(key, v);
    if (v is String) await p.setString(key, v);
    if (v is int)    await p.setInt(key, v);
  }

  Future<void> _setTheme(String v) async {
    await _set('ls_theme', v); setState(() => _theme = v);
    themeModeNotifier.value = themeFromString(v);
  }

  Future<void> _setAccentPreset(String key, Color color) async {
    await _set('ls_accent', key); setState(() => _accent = key);
    if (!_useDynamicColor && !_useNowPlayingColor) accentNotifier.value = color;
  }

  Future<void> _pickCustomColor() async {
    if (_useDynamicColor || _useNowPlayingColor) return;
    final current = accentNotifier.value;
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(initialColor: current),
    );
    if (result != null && mounted) {
      final hex = colorToHex(result);
      await _set('ls_accent', hex);
      setState(() => _accent = hex);
      accentNotifier.value = result;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final currentAccent = accentNotifier.value;

    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Paramètres', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),

        // Update banner
        if (_updateInfo != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4))),
            child: Row(children: [
              Icon(Icons.system_update_rounded, color: scheme.onTertiaryContainer, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mise à jour — v${_updateInfo!.version}',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700,
                        color: scheme.onTertiaryContainer)),
                if (_updateInfo!.notes.isNotEmpty)
                  Text(_updateInfo!.notes.length > 100
                      ? '${_updateInfo!.notes.substring(0, 100)}…' : _updateInfo!.notes,
                      style: text.bodySmall?.copyWith(color: scheme.onTertiaryContainer.withValues(alpha: 0.8))),
              ])),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final url = Uri.parse(_updateInfo!.hasApk ? _updateInfo!.apkUrl! : _updateInfo!.releaseUrl);
                  if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary, foregroundColor: scheme.onTertiary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: text.labelMedium),
                child: Text(_updateInfo!.hasApk ? 'Télécharger' : 'Voir'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // Appearance
        _SettingsSection(label: 'Apparence', children: [

          // Theme
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.contrast_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Thème', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
                  ButtonSegment(value: 'light',  icon: Icon(Icons.light_mode_rounded),       label: Text('Clair')),
                  ButtonSegment(value: 'dark',   icon: Icon(Icons.dark_mode_rounded),        label: Text('Sombre')),
                ],
                selected: {_theme},
                onSelectionChanged: (s) => _setTheme(s.first),
                style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ],
          )),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Accent color
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.palette_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text("Couleur d'accent", style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (_useDynamicColor || _useNowPlayingColor) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant)),
                    child: Text('Auto', style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ]),
              const SizedBox(height: 12),
              Opacity(
                opacity: (_useDynamicColor || _useNowPlayingColor) ? 0.35 : 1.0,
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  // Named presets
                  ..._kAccentOptions.map((opt) {
                    final (color, key, label) = opt;
                    final sel = _accent == key;
                    return GestureDetector(
                      onTap: (_useDynamicColor || _useNowPlayingColor) ? null : () => _setAccentPreset(key, color),
                      child: Tooltip(message: label, child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle,
                          border: sel ? Border.all(color: scheme.onSurface, width: 3)
                              : Border.all(color: scheme.outlineVariant, width: 1.5),
                          boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)] : [],
                        ),
                        child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                      )),
                    );
                  }),
                  // Custom color button (color wheel)
                  GestureDetector(
                    onTap: (_useDynamicColor || _useNowPlayingColor) ? null : _pickCustomColor,
                    child: Tooltip(
                      message: 'Personnalisé',
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isCustomAccent
                              ? null
                              : const SweepGradient(colors: [
                                  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                                  Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
                                ]),
                          color: _isCustomAccent ? currentAccent : null,
                          border: _isCustomAccent
                              ? Border.all(color: scheme.onSurface, width: 3)
                              : Border.all(color: scheme.outlineVariant, width: 1.5),
                          boxShadow: _isCustomAccent
                              ? [BoxShadow(color: currentAccent.withValues(alpha: 0.5), blurRadius: 8)] : [],
                        ),
                        child: _isCustomAccent
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                            : const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ]),
              ),
              // Show selected custom color
              if (_isCustomAccent && !_useDynamicColor && !_useNowPlayingColor) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Container(width: 18, height: 18,
                    decoration: BoxDecoration(color: currentAccent, shape: BoxShape.circle,
                        border: Border.all(color: scheme.outlineVariant))),
                  const SizedBox(width: 8),
                  Text(colorToHex(currentAccent),
                      style: text.bodySmall?.copyWith(
                          fontFamily: 'monospace', color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _pickCustomColor,
                      child: const Text('Modifier')),
                ]),
              ],
            ],
          )),
        ]),

        const SizedBox(height: 16),

        // Dynamic color
        _SettingsSection(label: 'Couleur dynamique', children: [
          SwitchListTile(
            secondary: Icon(Icons.colorize_rounded, color: scheme.primary),
            title: const Text('Material You'),
            subtitle: const Text('Utilise la couleur du thème Android'),
            value: _useDynamicColor,
            onChanged: (v) async {
              await _set('ls_use_dynamic_color', v);
              setState(() { _useDynamicColor = v; if (v) _useNowPlayingColor = false; });
              useDynamicColorNotifier.value    = v;
              useNowPlayingColorNotifier.value = false;
              if (!v) accentNotifier.value = accentFromString(_accent);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: Icon(Icons.album_rounded,
                color: _useDynamicColor ? scheme.onSurfaceVariant : scheme.primary),
            title: const Text('Couleur depuis la musique'),
            subtitle: Text(_useDynamicColor
                ? 'Désactiver Material You d\'abord'
                : 'Extrait la couleur de la pochette en cours'),
            value: _useNowPlayingColor,
            onChanged: _useDynamicColor ? null : (v) async {
              await _set('ls_use_nowplaying_color', v);
              setState(() => _useNowPlayingColor = v);
              useNowPlayingColorNotifier.value = v;
              if (!v) accentNotifier.value = accentFromString(_accent);
            },
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('La couleur dominante de la pochette en cours remplace l\'accent.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        ]),

        const SizedBox(height: 16),

        // Startup page
        _SettingsSection(label: 'Page de démarrage', children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.rocket_launch_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text("Onglet à l'ouverture", style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8,
                children: _kStartupLabels.asMap().entries.map((e) => FilterChip(
                  avatar: Icon(e.value.$1, size: 16), label: Text(e.value.$2),
                  selected: _startupTab == e.key, showCheckmark: false,
                  onSelected: (_) async { await _set('ls_startup_tab', e.key); setState(() => _startupTab = e.key); },
                )).toList()),
            ],
          )),
        ]),

        const SizedBox(height: 16),

        // Dashboard
        _SettingsSection(label: 'Dashboard', children: [

          // Header image
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.wallpaper_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text("Image d'en-tête", style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text('La pochette choisie s\'affiche en fond de l\'accueil.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),

              // Source selector
              Text('Source', style: text.labelSmall?.copyWith(
                  color: scheme.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8,
                children: _kHeaderSources.map((opt) {
                  final (key, label, icon) = opt;
                  final sel = _headerSource == key;
                  return FilterChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: sel,
                    showCheckmark: false,
                    onSelected: (_) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setString('ls_header_source', key);
                      setState(() => _headerSource = key);
                    },
                  );
                }).toList()),

              // Custom URL (when source is custom)
              if (_headerSource == 'custom') ...[
                const SizedBox(height: 14),
                Text('URL de l\'image', style: text.labelSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                TextField(
                  controller: _customUrlCtrl,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'https://exemple.com/image.jpg',
                    prefixIcon: const Icon(Icons.link_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      tooltip: 'Appliquer',
                      onPressed: () async {
                        final url = _customUrlCtrl.text.trim();
                        final p = await SharedPreferences.getInstance();
                        await p.setString('ls_header_custom_url', url);
                        setState(() => _headerCustomUrl = url);
                      },
                    ),
                  ),
                  onSubmitted: (url) async {
                    final u = url.trim();
                    final p = await SharedPreferences.getInstance();
                    await p.setString('ls_header_custom_url', u);
                    setState(() => _headerCustomUrl = u);
                  },
                ),
                const SizedBox(height: 6),
                Text('Colle l\'URL directe d\'une image (jpg, png, webp…).',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],

              // Period (for top_* sources)
              if (['top_track', 'top_album', 'top_artist'].contains(_headerSource)) ...[
                const SizedBox(height: 14),
                Text('Période', style: text.labelSmall?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8,
                  children: _kHeaderPeriods.map((opt) {
                    final (key, label) = opt;
                    return FilterChip(
                      label: Text(label),
                      selected: _headerPeriod == key,
                      showCheckmark: false,
                      onSelected: (_) async {
                        final p = await SharedPreferences.getInstance();
                        await p.setString('ls_header_period', key);
                        setState(() => _headerPeriod = key);
                      },
                    );
                  }).toList()),
              ],

              // Fallback (when source is nowplaying)
              if (_headerSource == 'nowplaying') ...[
                const SizedBox(height: 14),
                Row(children: [
                  Switch(
                    value: _headerFallbackEnabled,
                    onChanged: (v) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setBool('ls_header_fallback_enabled', v);
                      setState(() => _headerFallbackEnabled = v);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Image par défaut', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Affichée si aucune musique n\'est en cours.',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ])),
                ]),
                if (_headerFallbackEnabled) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _fallbackUrlCtrl,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'URL de l\'image par défaut',
                      hintText: 'https://exemple.com/image.jpg',
                      prefixIcon: const Icon(Icons.image_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        tooltip: 'Appliquer',
                        onPressed: () async {
                          final url = _fallbackUrlCtrl.text.trim();
                          final p = await SharedPreferences.getInstance();
                          await p.setString('ls_header_fallback_url', url);
                          setState(() => _headerFallbackUrl = url);
                        },
                      ),
                    ),
                    onSubmitted: (url) async {
                      final u = url.trim();
                      final p = await SharedPreferences.getInstance();
                      await p.setString('ls_header_fallback_url', u);
                      setState(() => _headerFallbackUrl = u);
                    },
                  ),
                ],
              ],

              const SizedBox(height: 16),
              Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 12),

              // Transition animation
              Row(children: [
                Icon(Icons.animation_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Transition', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              Text('Animation lors du changement de pochette.',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                children: _kHeaderAnimations.map((opt) {
                  final (key, label, icon) = opt;
                  return FilterChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _headerAnimation == key,
                    showCheckmark: false,
                    onSelected: (_) async {
                      final p = await SharedPreferences.getInstance();
                      await p.setString('ls_header_animation', key);
                      setState(() => _headerAnimation = key);
                    },
                  );
                }).toList()),

              const SizedBox(height: 16),

              // Blur
              Row(children: [
                Icon(Icons.blur_on_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Flou', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    _headerBlur < 1 ? 'Aucun' : '${_headerBlur.round()}',
                    style: text.labelMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Slider(
                value: _headerBlur,
                min: 0,
                max: 20,
                divisions: 20,
                label: _headerBlur < 1 ? 'Aucun' : '${_headerBlur.round()}',
                onChanged: (v) => setState(() => _headerBlur = v),
                onChangeEnd: (v) async {
                  final p = await SharedPreferences.getInstance();
                  await p.setDouble('ls_header_blur', v);
                },
              ),
              const SizedBox(height: 10),
            ],
          )),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Visible sections
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Sections visibles', style: text.bodySmall
                ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700))),
          SwitchListTile(secondary: const Icon(Icons.play_circle_outline_rounded),
            title: const Text('En cours de lecture'), value: _showNowPlay,
            onChanged: (v) async { await _set('ls_show_nowplay', v); setState(() => _showNowPlay = v); }),
          SwitchListTile(secondary: const Icon(Icons.bar_chart_rounded),
            title: const Text('Statistiques'), value: _showStats,
            onChanged: (v) async { await _set('ls_show_stats', v); setState(() => _showStats = v); }),
          SwitchListTile(secondary: const Icon(Icons.mic_rounded),
            title: const Text('Top Artistes'), value: _showArtists,
            onChanged: (v) async { await _set('ls_show_artists', v); setState(() => _showArtists = v); }),
          SwitchListTile(secondary: const Icon(Icons.music_note_rounded),
            title: const Text('Top Titres'), value: _showTracks,
            onChanged: (v) async { await _set('ls_show_tracks', v); setState(() => _showTracks = v); }),
        ]),


        const SizedBox(height: 16),

        // Account
        _SettingsSection(label: 'Compte', children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Text(widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
                  style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700))),
            title: Text(widget.username, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Profil Last.fm connecté')),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text('Se déconnecter', style: TextStyle(color: scheme.error)),
            onTap: () async {
              final ok = await showDialog<bool>(context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Se déconnecter ?'),
                  content: const Text('Tes identifiants seront supprimés.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Déconnecter')),
                  ],
                ));
              if (ok == true && mounted) {
                final p = await SharedPreferences.getInstance();
                await p.remove('ls_username'); await p.remove('ls_apikey');
                if (mounted) Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false);
              }
            }),
        ]),

        const SizedBox(height: 16),

        // Updates
        _SettingsSection(label: 'Mises à jour', children: [
          SwitchListTile(secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Vérification automatique'),
            subtitle: const Text('1 fois par jour'), value: _autoUpdate,
            onChanged: (v) async { await _set('ls_auto_update_check', v); setState(() => _autoUpdate = v); }),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: _checkingUpdate ? const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_outlined),
            title: const Text('Vérifier maintenant'),
            subtitle: _updateError != null ? Text(_updateError!, style: TextStyle(color: scheme.error))
                : (_updateInfo == null ? const Text('À jour') : Text('v${_updateInfo!.version} disponible')),
            onTap: _checkingUpdate ? null : () => _checkUpdate()),
        ]),

        const SizedBox(height: 16),

        // About
        _SettingsSection(label: 'À propos', children: [
          ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('Version'),
            trailing: Text(UpdateService.currentVersion,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(leading: const Icon(Icons.web_rounded), title: const Text('Version web'),
            subtitle: const Text('sanobld.github.io/LastStats'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 16),
            onTap: () async {
              final u = Uri.parse('https://sanobld.github.io/LastStats');
              if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
            }),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(leading: const Icon(Icons.code_rounded), title: const Text('Code source'),
            subtitle: const Text('github.com/sanobld/LastStats'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 16),
            onTap: () async {
              final u = Uri.parse('https://github.com/sanobld/LastStats');
              if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
            }),
        ]),

        const SizedBox(height: 24),
        Center(child: Text('LastStats Mobile v${UpdateService.currentVersion}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        const SizedBox(height: 8),
      ]),
    );
  }
}


// Color picker dialog (full HSL)

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSLColor _hsl;
  late TextEditingController _hexCtrl;
  bool _hexError = false;

  @override
  void initState() {
    super.initState();
    _hsl = HSLColor.fromColor(widget.initialColor)
        .withSaturation(_clamp01(HSLColor.fromColor(widget.initialColor).saturation, 0.4, 1.0))
        .withLightness(_clamp01(HSLColor.fromColor(widget.initialColor).lightness, 0.3, 0.7));
    _hexCtrl = TextEditingController(text: colorToHex(_hsl.toColor()));
  }

  @override
  void dispose() { _hexCtrl.dispose(); super.dispose(); }

  double _clamp01(double v, double min, double max) => v.clamp(min, max);
  Color  get _color => _hsl.toColor();

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
      final hsl = HSLColor.fromColor(c);
      setState(() {
        _hsl = hsl
            .withSaturation(_clamp01(hsl.saturation, 0.0, 1.0))
            .withLightness(_clamp01(hsl.lightness, 0.0, 1.0));
        _hexError = false;
      });
    } catch (_) { setState(() => _hexError = true); }
  }

  // Custom hue slider
  Widget _buildHueSlider(BuildContext ctx) {
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      return GestureDetector(
        onTapDown:  (d) => setState(() { _hsl = _hsl.withHue((d.localPosition.dx / w).clamp(0, 1) * 360); _syncHex(); }),
        onPanUpdate:(d) => setState(() { _hsl = _hsl.withHue((d.localPosition.dx / w).clamp(0, 1) * 360); _syncHex(); }),
        child: SizedBox(height: 36, child: Stack(alignment: Alignment.centerLeft, children: [
          // Rainbow gradient
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Container(height: 24, decoration: const BoxDecoration(gradient: LinearGradient(colors: [
              Color(0xFFFF0000), Color(0xFFFF8000), Color(0xFFFFFF00),
              Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF),
              Color(0xFFFF00FF), Color(0xFFFF0000),
            ])))),
          // Slider
          Positioned(
            left: ((_hsl.hue / 360) * w - 12).clamp(0, w - 24),
            child: Container(width: 24, height: 36,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.black26, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [_hsl.withLightness(0.5).withSaturation(1.0).toColor(),
                              _hsl.withLightness(0.5).withSaturation(1.0).toColor()]))),
          ),
        ])),
      );
    });
  }

  Widget _buildSliderRow(String label, double value, double min, double max,
      List<Color> gradientColors, void Function(double) onChanged) {
    return LayoutBuilder(builder: (_, c) => GestureDetector(
      onTapDown:  (d) => setState(() { onChanged(((d.localPosition.dx / c.maxWidth) * (max - min) + min).clamp(min, max)); _syncHex(); }),
      onPanUpdate:(d) => setState(() { onChanged(((d.localPosition.dx / c.maxWidth) * (max - min) + min).clamp(min, max)); _syncHex(); }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        SizedBox(height: 28, child: Stack(alignment: Alignment.centerLeft, children: [
          ClipRRect(borderRadius: BorderRadius.circular(6),
            child: Container(height: 20, decoration: BoxDecoration(gradient: LinearGradient(colors: gradientColors)))),
          Positioned(
            left: (((value - min) / (max - min)) * c.maxWidth - 10).clamp(0, c.maxWidth - 20),
            child: Container(width: 20, height: 28,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.black26, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]))),
        ])),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final pure   = _hsl.withSaturation(1.0).withLightness(0.5).toColor();

    // Quick presets
    const quickPresets = [
      Color(0xFF7C3AED), Color(0xFF1D4ED8), Color(0xFF059669),
      Color(0xFFDC2626), Color(0xFFD97706), Color(0xFFDB2777),
      Color(0xFF0F766E), Color(0xFFEA580C), Color(0xFF7C3AED),
      Color(0xFF0284C7), Color(0xFF16A34A), Color(0xFF9333EA),
    ];

    return AlertDialog(
      title: const Text('Couleur personnalisée'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview
            Row(children: [
              Expanded(child: Container(height: 52,
                decoration: BoxDecoration(color: _color,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant)))),
              const SizedBox(width: 10),
              // Hex input
              Expanded(child: TextField(
                controller: _hexCtrl,
                onChanged: _onHexInput,
                decoration: InputDecoration(
                  labelText: 'HEX',
                  prefixText: '',
                  errorText: _hexError ? 'Format invalide' : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                style: text.bodyMedium?.copyWith(fontFamily: 'monospace'),
              )),
            ]),
            const SizedBox(height: 16),

            // Hue
            Text('Teinte', style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _buildHueSlider(context),
            const SizedBox(height: 14),

            // Saturation
            _buildSliderRow('Saturation',
              _hsl.saturation, 0.0, 1.0,
              [Colors.grey.shade400, pure],
              (v) => _hsl = _hsl.withSaturation(v)),
            const SizedBox(height: 14),

            // Brightness
            _buildSliderRow('Luminosité',
              _hsl.lightness, 0.15, 0.85,
              [Colors.black, _hsl.withSaturation(1.0).withLightness(0.5).toColor(), Colors.white],
              (v) => _hsl = _hsl.withLightness(v)),
            const SizedBox(height: 16),

            // Quick presets
            Text('Couleurs rapides', style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8,
              children: quickPresets.toSet().toList().take(10).map((c) => GestureDetector(
                onTap: () => setState(() {
                  _hsl = HSLColor.fromColor(c);
                  _syncHex();
                }),
                child: Container(width: 28, height: 28,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant, width: 1))),
              )).toList()),
            const SizedBox(height: 16),
          ],
        )),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}


// Shared widgets


class _SettingsSection extends StatelessWidget {
  final String label; final List<Widget> children;
  const _SettingsSection({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label.toUpperCase(), style: text.labelSmall?.copyWith(
            color: scheme.primary, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
      Card(
        elevation: 0, color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _cardBorder(scheme),           
        ),
        child: Column(children: children)),
    ]);
  }
}

