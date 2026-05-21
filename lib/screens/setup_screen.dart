import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/lastfm_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _usernameCtrl = TextEditingController();
  final _apikeyCtrl   = TextEditingController();

  bool    _obscureApiKey = true;
  bool    _rememberMe    = true;
  bool    _isLoading     = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _apikeyCtrl.dispose();
    super.dispose();
  }

  // ── Import JSON ────────────────────────────────────────────────────────
  // Format attendu : {"username": "...", "api_key": "..."} ou {"apiKey": "..."}
  Future<void> _importJson() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Importer JSON'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Colle le contenu de ton fichier JSON ci-dessous.',
                style: Theme.of(ctx).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '{ "username": "…", "api_key": "…" }',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace', color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller:  ctrl,
                maxLines:    5,
                autocorrect: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  hintText: '{ "username": "...", "api_key": "..." }',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importer'),
            ),
          ],
        );
      },
    );

    if (ok != true || !mounted) return;
    final raw = ctrl.text.trim();
    if (raw.isEmpty) return;

    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final username = (data['username'] ?? '').toString().trim();
      final apiKey   = (data['api_key'] ?? data['apiKey'] ?? data['api-key'] ?? '').toString().trim();

      if (username.isEmpty || apiKey.isEmpty) {
        setState(() => _errorMessage = 'JSON invalide : champs "username" ou "api_key" manquants.');
        return;
      }
      setState(() {
        _usernameCtrl.text = username;
        _apikeyCtrl.text   = apiKey;
        _errorMessage      = null;
      });
    } catch (_) {
      setState(() => _errorMessage = 'JSON invalide. Vérifie le format.');
    }
  }

  Future<void> _launch() async {
    final username = _usernameCtrl.text.trim();
    final apiKey   = _apikeyCtrl.text.trim();

    if (username.isEmpty || apiKey.isEmpty) {
      setState(() => _errorMessage = 'Remplis les deux champs.');
      return;
    }
    if (apiKey.length != 32) {
      setState(() => _errorMessage = 'La clé API doit faire 32 caractères.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final service  = LastFmService(apiKey: apiKey, username: username);
      final userInfo = await service.getUserInfo();

      if (userInfo == null) throw Exception('Profil introuvable.');

      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ls_username', username);
        await prefs.setString('ls_apikey',   apiKey);
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(username: username, apiKey: apiKey),
        ),
      );

    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Logo ──────────────────────────────────────
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/images/icon.png',
                          width:  80,
                          height: 80,
                          fit:    BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width:  80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.headphones_rounded,
                              size:  40,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'LastStats',
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color:      scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tes stats Last.fm, réinventées.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // ── Card formulaire ───────────────────────────
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [

                          Text(
                            'Analyser un profil',
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Champ username
                          TextField(
                            controller:      _usernameCtrl,
                            textInputAction: TextInputAction.next,
                            autocorrect:     false,
                            decoration: InputDecoration(
                              labelText:  'Pseudo Last.fm',
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Champ API key
                          TextField(
                            controller:       _apikeyCtrl,
                            textInputAction:  TextInputAction.done,
                            obscureText:      _obscureApiKey,
                            autocorrect:      false,
                            enableSuggestions: false,
                            onSubmitted: (_) => _launch(),
                            decoration: InputDecoration(
                              labelText: 'Clé API Last.fm',
                              hintText:  'Clé hexadécimale de 32 caractères',
                              prefixIcon: const Icon(Icons.key_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureApiKey
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () =>
                                    setState(() => _obscureApiKey = !_obscureApiKey),
                              ),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Hint sécurité
                          Row(
                            children: [
                              Icon(Icons.shield_outlined,
                                  size: 14, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Stockée localement. Jamais envoyée à un tiers.',
                                  style: text.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Remember me
                          Row(
                            children: [
                              Checkbox(
                                value:     _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? true),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _rememberMe = !_rememberMe),
                                child: const Text('Se souvenir de moi'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Bouton lancer
                          FilledButton.icon(
                            onPressed: _isLoading ? null : _launch,
                            icon: _isLoading
                                ? SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: scheme.onPrimary),
                                  )
                                : const Icon(Icons.bar_chart_rounded),
                            label: Text(_isLoading
                                ? 'Connexion…'
                                : "Lancer l'analyse"),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),

                          // Bloc erreur
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:        scheme.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: scheme.onErrorContainer, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: text.bodySmall?.copyWith(
                                          color: scheme.onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Import JSON ──────────────────────────────
                  OutlinedButton.icon(
                    onPressed: _importJson,
                    icon:  const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Importer JSON'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),

                  const SizedBox(height: 8),

                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(
                            'https://www.last.fm/api/account/create');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      icon:  const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Obtenir une clé API gratuitement'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}