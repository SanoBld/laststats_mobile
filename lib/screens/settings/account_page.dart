// lib/screens/settings/account_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n.dart';
import '../../app_state.dart';
import '../setup_screen.dart';
import 'settings_helpers.dart';

class AccountPage extends StatelessWidget {
  final String username;
  const AccountPage({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsAccount),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Avatar + pseudo ───────────────────────────────────────────────
        Center(child: Column(children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: scheme.primaryContainer,
            child: Text(initial, style: TextStyle(
                fontSize: 32, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Text('@$username', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(L.settingsConnectedProfile,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
        ])),

        // ── Infos Last.fm ─────────────────────────────────────────────────
        SettingsSection(label: isEn ? 'Last.fm Profile' : 'Profil Last.fm', children: [
          ListTile(
            leading: Icon(Icons.person_rounded, color: scheme.primary),
            title: Text(isEn ? 'Username' : 'Nom d\'utilisateur'),
            trailing: Text(username,
                style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.open_in_new_rounded, color: scheme.primary, size: 20),
            title: Text(isEn ? 'View on Last.fm' : 'Voir sur Last.fm'),
            subtitle: Text('last.fm/user/$username',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            onTap: () async {
              final uri = Uri.parse('https://www.last.fm/user/$username');
              // canLaunchUrl / launchUrl nécessite url_launcher — import si non présent
              // import 'package:url_launcher/url_launcher.dart';
              // if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ]),

        const SizedBox(height: 16),

        // ── Déconnexion ───────────────────────────────────────────────────
        SettingsSection(label: isEn ? 'Danger Zone' : 'Zone de danger', children: [
          ListTile(
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text(L.settingsLogout,
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
            subtitle: Text(L.settingsLogoutContent,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(L.settingsLogoutTitle),
                  content: Text(L.settingsLogoutContent),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(L.commonCancel)),
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: scheme.error,
                            foregroundColor: scheme.onError),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(L.settingsLogoutConfirm)),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                final nav = Navigator.of(context);
                final p   = await SharedPreferences.getInstance();
                await p.remove('ls_username');
                await p.remove('ls_apikey');
                nav.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false);
              }
            },
          ),
        ]),

        const SizedBox(height: 20),
      ]),
    );
  }
}
