// lib/screens/settings/appearance_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_state.dart';
import '../../l10n.dart';
import 'settings_helpers.dart';
import 'pc_mode_section.dart';   // PC / responsive layout toggle

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  String _theme              = 'system';
  String _accent             = 'purple';
  bool   _useDynamicColor    = false;
  bool   _useNowPlayingColor = false;
  // The accent color shown when music-color mode is on but nothing is playing
  Color  _fallbackAccent     = const Color(0xFF7C3AED);

  @override
  void initState() {
    super.initState();
    _load();
    localeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _theme              = p.getString('ls_theme')              ?? 'system';
      _accent             = p.getString('ls_accent')             ?? 'purple';
      _useDynamicColor    = p.getBool('ls_use_dynamic_color')    ?? false;
      _useNowPlayingColor = p.getBool('ls_use_nowplaying_color') ?? false;
      // Load the fallback color; default to the regular accent if never set
      final fbHex = p.getString('ls_nowplaying_fallback_color');
      _fallbackAccent = fbHex != null
          ? accentFromString(fbHex)
          : accentFromString(p.getString('ls_accent'));
    });
  }

  Future<void> _set<T>(String key, T v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool)   await p.setBool(key, v);
    if (v is String) await p.setString(key, v);
  }

  Future<void> _setTheme(String v) async {
    await _set('ls_theme', v);
    setState(() => _theme = v);
    themeModeNotifier.value = themeFromString(v);
  }

  Future<void> _setAccentPreset(String key, Color color) async {
    await _set('ls_accent', key);
    setState(() => _accent = key);
    if (!_useDynamicColor && !_useNowPlayingColor) accentNotifier.value = color;
  }

  Future<void> _pickCustomColor() async {    if (_useDynamicColor || _useNowPlayingColor) return;
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initialColor: accentNotifier.value),
    );
    if (result != null && mounted) {
      final hex = colorToHex(result);
      await _set('ls_accent', hex);
      setState(() => _accent = hex);
      accentNotifier.value = result;
    }
  }

  // Opens the picker to choose the fallback accent.
  // This color is shown when music-color mode is ON but nothing is playing.
  Future<void> _pickFallbackColor() async {
    final result = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(initialColor: _fallbackAccent),
    );
    if (result != null && mounted) {
      final hex = colorToHex(result);
      await _set('ls_nowplaying_fallback_color', hex);
      setState(() => _fallbackAccent = result);
      nowPlayingFallbackColorNotifier.value = result;
      // Apply right away so the user sees the change if no track is playing
      accentNotifier.value = result;
    }
  }

  bool get _isCustomAccent =>
      _accent.startsWith('#') ||
      !kSettingsAccentOptions.any((o) => o.$2 == _accent);

  @override
  Widget build(BuildContext context) {
    final scheme        = Theme.of(context).colorScheme;
    final text          = Theme.of(context).textTheme;
    final currentAccent = accentNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsAppearance),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Theme ─────────────────────────────────────────────────────────
        SettingsSection(label: L.settingsTheme, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.contrast_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(L.settingsTheme,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'system',
                      icon: const Icon(Icons.brightness_auto_rounded),
                      label: Text(L.settingsThemeAuto)),
                  ButtonSegment(
                      value: 'light',
                      icon: const Icon(Icons.light_mode_rounded),
                      label: Text(L.settingsThemeLight)),
                  ButtonSegment(
                      value: 'dark',
                      icon: const Icon(Icons.dark_mode_rounded),
                      label: Text(L.settingsThemeDark)),
                ],
                selected: {_theme},
                onSelectionChanged: (s) => _setTheme(s.first),
                style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ],
          )),
        ]),

        const SizedBox(height: 16),

        // ── Accent colour ─────────────────────────────────────────────────
        SettingsSection(label: L.settingsAccentColor, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.palette_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(L.settingsAccentColor,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (_useDynamicColor || _useNowPlayingColor) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant)),
                    child: Text(L.settingsAccentAuto,
                        style: text.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ]),
              const SizedBox(height: 12),
              Opacity(
                opacity: (_useDynamicColor || _useNowPlayingColor) ? 0.35 : 1.0,
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  // Preset swatches
                  ...kSettingsAccentOptions.map((opt) {
                    final (color, key, label) = opt;
                    final sel = _accent == key;
                    return GestureDetector(
                      onTap: (_useDynamicColor || _useNowPlayingColor)
                          ? null
                          : () => _setAccentPreset(key, color),
                      child: Tooltip(
                          message: label,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle,
                              border: sel
                                  ? Border.all(color: scheme.onSurface, width: 3)
                                  : Border.all(
                                      color: scheme.outlineVariant, width: 1.5),
                              boxShadow: sel
                                  ? [BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8)]
                                  : [],
                            ),
                            child: sel
                                ? const Icon(Icons.check_rounded,
                                    color: Colors.white, size: 18)
                                : null,
                          )),
                    );
                  }),
                  // Custom colour picker swatch
                  GestureDetector(
                    onTap: (_useDynamicColor || _useNowPlayingColor)
                        ? null
                        : _pickCustomColor,
                    child: Tooltip(
                      message: L.colorCustomTooltip,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isCustomAccent
                              ? null
                              : const SweepGradient(colors: [
                                  Color(0xFFFF0000), Color(0xFFFFFF00),
                                  Color(0xFF00FF00), Color(0xFF00FFFF),
                                  Color(0xFF0000FF), Color(0xFFFF00FF),
                                  Color(0xFFFF0000),
                                ]),
                          color: _isCustomAccent ? currentAccent : null,
                          border: _isCustomAccent
                              ? Border.all(color: scheme.onSurface, width: 3)
                              : Border.all(
                                  color: scheme.outlineVariant, width: 1.5),
                          boxShadow: _isCustomAccent
                              ? [BoxShadow(
                                  color: currentAccent.withValues(alpha: 0.5),
                                  blurRadius: 8)]
                              : [],
                        ),
                        child: _isCustomAccent
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 18)
                            : const Icon(Icons.add_rounded,
                                color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ]),
              ),
              // Hex display when a custom colour is active
              if (_isCustomAccent &&
                  !_useDynamicColor &&
                  !_useNowPlayingColor) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                          color: currentAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant))),
                  const SizedBox(width: 8),
                  Text(colorToHex(currentAccent),
                      style: text.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: _pickCustomColor,
                      child: Text(L.settingsCustomColorEdit)),
                ]),
              ],
            ],
          )),
        ]),

        const SizedBox(height: 16),

        // ── Dynamic colour (Material You) ─────────────────────────────────
        SettingsSection(label: L.settingsDynamicColor, children: [
          SwitchListTile(
            secondary: Icon(Icons.colorize_rounded, color: scheme.primary),
            title: Text(L.settingsMaterialYou),
            subtitle: Text(L.settingsMaterialYouSub),
            value: _useDynamicColor,
            onChanged: (v) async {
              await _set('ls_use_dynamic_color', v);
              setState(() {
                _useDynamicColor = v;
                if (v) _useNowPlayingColor = false;
              });
              useDynamicColorNotifier.value    = v;
              useNowPlayingColorNotifier.value = false;
              if (!v) accentNotifier.value = accentFromString(_accent);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            secondary: Icon(Icons.album_rounded,
                color: _useDynamicColor
                    ? scheme.onSurfaceVariant
                    : scheme.primary),
            title: Text(L.settingsMusicColor),
            subtitle: Text(_useDynamicColor
                ? L.settingsMusicColorLocked
                : L.settingsMusicColorSub),
            value: _useNowPlayingColor,
            onChanged: _useDynamicColor
                ? null
                : (v) async {
                    await _set('ls_use_nowplaying_color', v);
                    setState(() => _useNowPlayingColor = v);
                    useNowPlayingColorNotifier.value = v;
                    if (!v) accentNotifier.value = accentFromString(_accent);
                  },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(L.settingsMusicColorNote,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),

          // Fallback color: shown when music-color mode is ON but nothing plays.
          // Only visible when the toggle above is active.
          if (_useNowPlayingColor && !_useDynamicColor) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: Icon(Icons.music_off_rounded, color: scheme.primary),
              title: Text(
                localeNotifier.value == 'en'
                    ? 'Color when nothing plays'
                    : 'Couleur quand rien ne joue',
              ),
              subtitle: Text(
                localeNotifier.value == 'en'
                    ? 'Accent used while no track is scrobbling'
                    : "Accent utilisé quand aucune piste n'est en cours",
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              trailing: GestureDetector(
                onTap: _pickFallbackColor,
                child: Tooltip(
                  message: localeNotifier.value == 'en'
                      ? 'Pick fallback color'
                      : 'Choisir la couleur de secours',
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _fallbackAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant, width: 2),
                    ),
                  ),
                ),
              ),
              onTap: _pickFallbackColor,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 10),
              child: Row(children: [
                // Small swatch showing the current fallback color
                Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: _fallbackAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  colorToHex(_fallbackAccent),
                  style: text.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _pickFallbackColor,
                  child: Text(L.settingsCustomColorEdit),
                ),
              ]),
            ),
          ],
        ]),

        const SizedBox(height: 16),

        // ── PC / responsive layout mode ───────────────────────────────────
        // Lets the user force the side-rail or bottom-bar layout regardless
        // of screen size. PcModeSection handles its own state + persistence.
        const PcModeSection(),

        const SizedBox(height: 20),
        const RestartBanner(),
        const SizedBox(height: 20),
      ]),
    );
  }
}