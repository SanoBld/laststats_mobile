// lib/screens/settings/updates_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n.dart';
import '../../app_state.dart';
import '../../services/update_service.dart';
import 'settings_helpers.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool        _autoUpdate    = true;
  bool        _checkingUpdate = false;
  UpdateInfo? _updateInfo;
  String?     _updateError;

  @override
  void initState() {
    super.initState();
    _load().then((_) => _maybeCheckUpdate());
    localeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() { localeNotifier.removeListener(_rebuild); super.dispose(); }

  void _rebuild() => setState(() {});

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _autoUpdate = p.getBool('ls_auto_update_check') ?? true);
  }

  Future<void> _maybeCheckUpdate() async {
    if (!_autoUpdate) return;
    final p = await SharedPreferences.getInstance();
    final last = p.getInt('ls_last_update_check') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 1).inMilliseconds) return;
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
      if (mounted) setState(() { _updateError = L.settingsCheckFailed; _checkingUpdate = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsUpdates),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Bannière de mise à jour disponible ────────────────────────────
        if (_updateInfo != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.system_update_rounded, color: scheme.onTertiaryContainer, size: 28),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(L.settingsUpdateBanner(_updateInfo!.version),
                      style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer)),
                  if (_updateInfo!.publishedAt != null)
                    Text(
                      isEn ? 'Published on ${_fmtDate(_updateInfo!.publishedAt!)}' : 'Publié le ${_fmtDate(_updateInfo!.publishedAt!)}',
                      style: text.bodySmall?.copyWith(color: scheme.onTertiaryContainer.withValues(alpha: 0.7)),
                    ),
                ])),
              ]),
              if (_updateInfo!.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _updateInfo!.notes.length > 200
                      ? '${_updateInfo!.notes.substring(0, 200)}…'
                      : _updateInfo!.notes,
                  style: text.bodySmall?.copyWith(color: scheme.onTertiaryContainer.withValues(alpha: 0.85)),
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(_updateInfo!.hasApk
                        ? _updateInfo!.apkUrl! : _updateInfo!.releaseUrl);
                    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                  icon: Icon(_updateInfo!.hasApk ? Icons.download_rounded : Icons.open_in_new_rounded),
                  label: Text(_updateInfo!.hasApk ? L.settingsDownload : L.settingsViewRelease),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.tertiary,
                    foregroundColor: scheme.onTertiary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )),
                if (_updateInfo!.hasApk) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () async {
                      final url = Uri.parse(_updateInfo!.releaseUrl);
                      if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                    },
                    child: Text(L.settingsViewRelease),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // ── Version actuelle ──────────────────────────────────────────────
        SettingsSection(label: isEn ? 'Current version' : 'Version actuelle', children: [
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.info_outline_rounded, color: scheme.onPrimaryContainer),
            ),
            title: Text(L.settingsVersion,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Text('v${UpdateService.currentVersion}',
                  style: text.labelMedium?.copyWith(
                      fontFamily: 'monospace', color: scheme.onSurfaceVariant)),
            ),
          ),
        ]),

        const SizedBox(height: 16),

        // ── Vérification des mises à jour ─────────────────────────────────
        SettingsSection(label: L.settingsUpdates, children: [
          SwitchListTile(
            secondary: Icon(Icons.notifications_outlined, color: scheme.primary),
            title: Text(L.settingsAutoUpdate,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(L.settingsAutoUpdateSub,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            value: _autoUpdate,
            onChanged: (v) async {
              final p = await SharedPreferences.getInstance();
              await p.setBool('ls_auto_update_check', v);
              setState(() => _autoUpdate = v);
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: _checkingUpdate
                ? const SizedBox(width: 40, height: 40, child: Center(
                    child: SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5))))
                : Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.refresh_rounded, color: scheme.onSecondaryContainer)),
            title: Text(L.settingsCheckNow,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: _updateError != null
                ? Text(_updateError!, style: TextStyle(color: scheme.error))
                : _updateInfo == null
                    ? Text(L.settingsUpToDate,
                        style: text.bodySmall?.copyWith(color: Colors.green.shade600))
                    : Text(L.settingsUpdateAvailable(_updateInfo!.version),
                        style: TextStyle(
                            color: scheme.tertiary, fontWeight: FontWeight.w600)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: _checkingUpdate ? null : () => _checkUpdate(),
          ),
        ]),

        const SizedBox(height: 20),
      ]),
    );
  }

  String _fmtDate(DateTime d) {
    final months = L.months;
    return '${d.day} ${months[d.month]} ${d.year}';
  }
}
