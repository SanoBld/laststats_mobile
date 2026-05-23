// lib/screens/settings/backup_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n.dart';
import '../../app_state.dart';
import 'settings_helpers.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {

  static const _kBackupKeys = [
    'ls_username', 'ls_apikey',
    'ls_theme', 'ls_accent', 'ls_use_dynamic_color', 'ls_use_nowplaying_color',
    'ls_header_source', 'ls_header_period', 'ls_header_animation',
    'ls_header_blur', 'ls_header_custom_url',
    'ls_header_fallback_enabled', 'ls_header_fallback_url',
    'ls_show_nowplay', 'ls_show_stats', 'ls_show_artists', 'ls_show_tracks', 'ls_show_friends',
    'ls_stat_cards',
    'ls_startup_tab', 'ls_auto_update_check',
    'ls_fav_friends', 'ls_fav_profiles', 'ls_locale',
  ];

  Future<void> _export() async {
    final p   = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final key in _kBackupKeys) {
      final v = p.get(key);
      if (v != null) map[key] = v;
    }
    final now      = DateTime.now();
    final payload  = jsonEncode({'app': 'LastStats', 'version': '1',
        'exported_at': now.toIso8601String(), 'prefs': map});
    final dateStr  = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
    final defName  = 'laststats_backup_$dateStr.json';
    if (!mounted) return;
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (_) => ExportSheet(payload: payload, defaultName: defName),
    );
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
          title: Text(L.importTitle),
          content: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.importHintLabel, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl, maxLines: 5, autofocus: true,
              decoration: InputDecoration(
                hintText: '{"app":"LastStats",...}',
                border: const OutlineInputBorder(),
                errorText: err,
              ),
              onChanged: (_) { if (err != null) setDlg(() => err = null); },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(L.commonCancel)),
            FilledButton(
              onPressed: () async {
                final raw = ctrl.text.trim();
                if (raw.isEmpty) { setDlg(() => err = L.importEmpty); return; }
                Map<String, dynamic> parsed;
                try { parsed = jsonDecode(raw) as Map<String, dynamic>; }
                catch (_) { setDlg(() => err = L.importInvalidJson); return; }
                if (parsed['app'] != 'LastStats') { setDlg(() => err = L.importUnknownFile); return; }
                final prefs = parsed['prefs'];
                if (prefs is! Map) { setDlg(() => err = L.importInvalidFormat); return; }
                if (ctx.mounted) Navigator.pop(ctx);
                await _applyBackup(Map<String, dynamic>.from(prefs));
              },
              child: Text(L.importRestore),
            ),
          ],
        ));
      },
    );
    ctrl.dispose();
  }

  Future<void> _applyBackup(Map<String, dynamic> prefs) async {
    final p = await SharedPreferences.getInstance();
    for (final e in prefs.entries) {
      if (!e.key.startsWith('ls_')) continue;
      final v = e.value;
      if (v is bool)   await p.setBool(e.key, v);
      else if (v is int)    await p.setInt(e.key, v);
      else if (v is double) await p.setDouble(e.key, v);
      else if (v is String) await p.setString(e.key, v);
      else if (v is List)   await p.setStringList(e.key, List<String>.from(v));
    }
    themeModeNotifier.value          = themeFromString(p.getString('ls_theme'));
    accentNotifier.value             = accentFromString(p.getString('ls_accent'));
    useDynamicColorNotifier.value    = p.getBool('ls_use_dynamic_color')    ?? false;
    useNowPlayingColorNotifier.value = p.getBool('ls_use_nowplaying_color') ?? false;
    localeNotifier.value             = p.getString('ls_locale')             ?? 'fr';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.importSuccess), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsBackup),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // Info générale
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.backup_rounded, color: scheme.onPrimaryContainer, size: 22),
              const SizedBox(width: 10),
              Text(isEn ? 'What\'s included' : 'Ce qui est inclus',
                  style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
            ]),
            const SizedBox(height: 8),
            Text(L.settingsBackupInfo,
                style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Export ────────────────────────────────────────────────────────
        SettingsSection(label: L.settingsExport, children: [
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.upload_rounded, color: scheme.onPrimaryContainer, size: 22),
            ),
            title: Text(L.settingsExport,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(L.settingsExportSub,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: _export,
          ),
        ]),

        const SizedBox(height: 16),

        // ── Import ────────────────────────────────────────────────────────
        SettingsSection(label: L.settingsImport, children: [
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.download_rounded, color: scheme.onSecondaryContainer, size: 22),
            ),
            title: Text(L.settingsImport,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(L.settingsImportSub,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: _import,
          ),
        ]),

        const SizedBox(height: 20),

        // Avertissement données
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 10),
            Expanded(child: Text(
              isEn
                  ? 'Restoring a backup will overwrite your current settings.'
                  : 'Restaurer une sauvegarde écrasera vos paramètres actuels.',
              style: text.bodySmall?.copyWith(color: scheme.error),
            )),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
