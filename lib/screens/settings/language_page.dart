// lib/screens/settings/language_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n.dart';
import '../../app_state.dart';
import 'settings_helpers.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String _locale = 'fr';

  @override
  void initState() {
    super.initState();
    _locale = localeNotifier.value;
    localeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() { localeNotifier.removeListener(_rebuild); super.dispose(); }

  void _rebuild() => setState(() => _locale = localeNotifier.value);

  Future<void> _setLocale(String code) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ls_locale', code);
    setState(() => _locale = code);
    localeNotifier.value = code;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = _locale == 'en';

    const langs = [
      ('fr', '🇫🇷', 'Français', 'French'),
      ('en', '🇬🇧', 'English', 'English'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(L.settingsLanguage),
        centerTitle: false,
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        SettingsSection(label: L.settingsLanguage, children: [
          ...langs.map((lang) {
            final (code, flag, nativeName, enName) = lang;
            final sel = _locale == code;
            return Column(children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _setLocale(code),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Text(flag, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nativeName, style: text.bodyLarge?.copyWith(
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                      Text(enName, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ])),
                    if (sel)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                      )
                    else
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant, width: 1.5),
                        ),
                      ),
                  ]),
                ),
              ),
              if (code != langs.last.$1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ]);
          }),
        ]),

        const SizedBox(height: 16),

        // Note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Icon(Icons.translate_rounded, size: 16, color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(
              isEn
                  ? 'The language changes immediately throughout the app.'
                  : 'La langue change immédiatement dans toute l\'application.',
              style: text.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
            )),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
