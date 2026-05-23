// lib/screens/settings/about_page.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n.dart';
import '../../app_state.dart';
import '../../services/update_service.dart';
import 'settings_helpers.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _open(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsAbout),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Logo / En-tête ────────────────────────────────────────────────
        Center(child: Column(children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Icon(Icons.graphic_eq_rounded, size: 44, color: scheme.primary),
          ),
          const SizedBox(height: 14),
          Text('LastStats', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('v${UpdateService.currentVersion}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(isEn ? 'Your Last.fm stats companion' : 'Votre compagnon de stats Last.fm',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
        ])),

        // ── Infos ─────────────────────────────────────────────────────────
        SettingsSection(label: isEn ? 'App info' : 'Infos', children: [
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(L.settingsVersion,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            trailing: Text('v${UpdateService.currentVersion}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.web_rounded),
            title: Text(L.settingsWebVersion,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(L.settingsWebVersionSub,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            trailing: const Icon(Icons.open_in_new_rounded, size: 16),
            onTap: () => _open('https://sanobld.github.io/LastStats'),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: Text(L.settingsSourceCode,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            subtitle: Text(L.settingsSourceCodeSub,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            trailing: const Icon(Icons.open_in_new_rounded, size: 16),
            onTap: () => _open('https://github.com/sanobld/LastStats'),
          ),
        ]),

        const SizedBox(height: 16),

        // ── Remerciements ─────────────────────────────────────────────────
        SettingsSection(label: isEn ? 'Powered by' : 'Propulsé par', children: [
          _PoweredByTile(
            icon: Icons.music_note_rounded,
            label: 'Last.fm API',
            url: 'https://www.last.fm/api',
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _PoweredByTile(
            icon: Icons.apple_rounded,
            label: 'iTunes Search API',
            url: 'https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI',
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _PoweredByTile(
            icon: Icons.album_rounded,
            label: 'MusicBrainz',
            url: 'https://musicbrainz.org',
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _PoweredByTile(
            icon: Icons.flutter_dash_rounded,
            label: 'Flutter',
            url: 'https://flutter.dev',
          ),
        ]),

        const SizedBox(height: 20),

        Center(child: Text(
          isEn
              ? 'Made with ❤️ · Not affiliated with Last.fm / CBS'
              : 'Fait avec ❤️ · Non affilié à Last.fm / CBS',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        )),
        const SizedBox(height: 20),
      ]),
    );
  }
}

class _PoweredByTile extends StatelessWidget {
  final IconData icon;
  final String label, url;
  const _PoweredByTile({required this.icon, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: scheme.primary, size: 22),
      title: Text(label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.open_in_new_rounded, size: 16),
      onTap: () async {
        final u = Uri.parse(url);
        if (await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
      },
    );
  }
}
