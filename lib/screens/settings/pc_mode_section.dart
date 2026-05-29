// lib/screens/settings/pc_mode_section.dart
//
// Reusable widget dropped into AppearancePage.
// Controls pcModeNotifier ('auto' | 'on' | 'off') and persists to prefs.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_state.dart';
import '../../l10n.dart';
import 'settings_helpers.dart';

class PcModeSection extends StatefulWidget {
  const PcModeSection({super.key});

  @override
  State<PcModeSection> createState() => _PcModeSectionState();
}

class _PcModeSectionState extends State<PcModeSection> {
  // Current value — mirrors pcModeNotifier
  String _mode = 'auto';

  @override
  void initState() {
    super.initState();
    _mode = pcModeNotifier.value;
    // Keep local state in sync if notifier changes from elsewhere
    pcModeNotifier.addListener(_onNotifierChange);
    localeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    pcModeNotifier.removeListener(_onNotifierChange);
    localeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _onNotifierChange() => setState(() => _mode = pcModeNotifier.value);
  void _rebuild()          => setState(() {});

  // Save choice and update the global notifier so HomeScreen reacts instantly
  Future<void> _setMode(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ls_pc_mode', v);
    setState(() => _mode = v);
    pcModeNotifier.value = v; // triggers HomeScreen rebuild
  }

  // Human-readable hint shown below the segmented button
  String get _hint {
    switch (_mode) {
      case 'on':
        return 'Always use the side navigation rail, regardless of screen size.';
      case 'off':
        return 'Always use the bottom navigation bar, regardless of screen size.';
      default:
        return 'Side rail on wide screens (≥ 720 dp), bottom bar on narrow screens.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return SettingsSection(
      label: 'Layout',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section title ─────────────────────────────────────────
              Row(children: [
                Icon(Icons.desktop_windows_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Navigation layout',
                  style: text.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ]),

              const SizedBox(height: 12),

              // ── Three-segment toggle ──────────────────────────────────
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'auto',
                    icon: Icon(Icons.devices_rounded),
                    label: Text('Auto'),
                  ),
                  ButtonSegment(
                    value: 'on',
                    icon: Icon(Icons.view_sidebar_outlined),
                    label: Text('Side rail'),
                  ),
                  ButtonSegment(
                    value: 'off',
                    icon: Icon(Icons.view_headline_rounded),
                    label: Text('Bottom bar'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.first),
                style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),

              const SizedBox(height: 8),

              // ── Contextual hint ───────────────────────────────────────
              Text(
                _hint,
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}