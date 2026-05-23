import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../l10n.dart';
import '../services/lastfm_service.dart';
import '../services/data_cache.dart';
import '../services/prefetch_service.dart';
import 'home_screen.dart';

// ══════════════════════════════════════════════════════════════════════════
//  SetupScreen — credentials entry
// ══════════════════════════════════════════════════════════════════════════

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _usernameCtrl  = TextEditingController();
  final _apikeyCtrl    = TextEditingController();
  final _jsonCtrl      = TextEditingController();

  bool    _obscureApiKey = true;
  bool    _rememberMe    = true;
  bool    _isLoading     = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _apikeyCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  // ── Parse JSON inline → remplit les champs ────────────────────────────
  void _applyJson() {
    final raw = _jsonCtrl.text.trim();
    if (raw.isEmpty) return;
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final username = (data['username'] ?? '').toString().trim();
      final apiKey   = (data['api_key'] ?? data['apiKey'] ?? data['api-key'] ?? '').toString().trim();
      if (username.isEmpty || apiKey.isEmpty) {
        setState(() => _errorMessage = L.setupInvalidFields);
        return;
      }
      setState(() {
        _usernameCtrl.text = username;
        _apikeyCtrl.text   = apiKey;
        _jsonCtrl.text     = '';
        _errorMessage      = null;
      });
    } catch (_) {
      setState(() => _errorMessage = L.importInvalidJson);
    }
  }

  // ── Validation + connexion ────────────────────────────────────────────
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

      final totalScrobbles =
          int.tryParse(userInfo['playcount']?.toString() ?? '0') ?? 0;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => _FirstLoadScreen(
            username:        username,
            apiKey:          apiKey,
            service:         service,
            totalScrobbles:  totalScrobbles,
          ),
        ),
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
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
                  Column(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/icon.png',
                        width: 80, height: 80, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(Icons.headphones_rounded,
                              size: 40, color: scheme.onPrimaryContainer),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('LastStats',
                        style: text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: scheme.primary)),
                    const SizedBox(height: 4),
                    Text('Tes stats Last.fm, réinventées.',
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),

                  const SizedBox(height: 40),

                  // ── Card formulaire ───────────────────────────
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Analyser un profil',
                            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 24),

                        // Username
                        TextField(
                          controller:      _usernameCtrl,
                          textInputAction: TextInputAction.next,
                          autocorrect:     false,
                          decoration: InputDecoration(
                            labelText:  'Pseudo Last.fm',
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // API key
                        TextField(
                          controller:        _apikeyCtrl,
                          textInputAction:   TextInputAction.done,
                          obscureText:       _obscureApiKey,
                          autocorrect:       false,
                          enableSuggestions: false,
                          onSubmitted:       (_) => _launch(),
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
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Hint sécurité
                        Row(children: [
                          Icon(Icons.shield_outlined, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            'Stockée localement. Jamais envoyée à un tiers.',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          )),
                        ]),
                        const SizedBox(height: 16),

                        // Remember me
                        Row(children: [
                          Checkbox(
                            value:     _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v ?? true),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            child: const Text('Se souvenir de moi'),
                          ),
                        ]),
                        const SizedBox(height: 20),

                        // Bouton lancer
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _launch,
                          icon: _isLoading
                              ? SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: scheme.onPrimary))
                              : const Icon(Icons.bar_chart_rounded),
                          label: Text(_isLoading ? 'Connexion…' : "Lancer l'analyse"),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                        // Bloc erreur
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: scheme.onErrorContainer, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_errorMessage!,
                                  style: text.bodySmall
                                      ?.copyWith(color: scheme.onErrorContainer))),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Séparateur "ou" ───────────────────────────
                  Row(children: [
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ou',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                  ]),

                  const SizedBox(height: 16),

                  // ── Card import JSON ──────────────────────────
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Icon(Icons.upload_file_rounded, size: 20, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(L.setupImportJson,
                              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 8),
                        Text(L.setupImportHintLabel,
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text(L.setupImportNote,
                            style: text.bodySmall?.copyWith(
                                fontFamily: 'monospace', color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 12),

                        TextField(
                          controller:  _jsonCtrl,
                          maxLines:    4,
                          minLines:    3,
                          autocorrect: false,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          decoration: InputDecoration(
                            hintText: L.setupImportFormat,
                            hintStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: _applyJson,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text(L.importRestore),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Lien API Last.fm ──────────────────────────
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('https://www.last.fm/api/account/create');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon:  const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Obtenir une clé API gratuitement'),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _FirstLoadScreen — shown once on first connection to prefetch all data
// ══════════════════════════════════════════════════════════════════════════

class _FirstLoadScreen extends StatefulWidget {
  final String username;
  final String apiKey;
  final LastFmService service;
  final int totalScrobbles;

  const _FirstLoadScreen({
    required this.username,
    required this.apiKey,
    required this.service,
    required this.totalScrobbles,
  });

  @override
  State<_FirstLoadScreen> createState() => _FirstLoadScreenState();
}

class _FirstLoadScreenState extends State<_FirstLoadScreen>
    with SingleTickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  // Steps shown to the user while loading
  static const _steps = [
    ('🎵', 'Chargement de ton profil…'),
    ('📊', 'Récupération de tes top artistes…'),
    ('💿', 'Récupération de tes top albums…'),
    ('🎶', 'Récupération de tes top tracks…'),
    ('🕐', 'Analyse des écoutes récentes…'),
    ('📅', 'Construction du calendrier musical…'),
    ('🏆', 'Calcul des classements…'),
    ('✨', 'Finalisation…'),
  ];

  int    _stepIndex   = 0;
  double _progress    = 0.0;
  bool   _done        = false;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startPrefetch();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startPrefetch() async {
    // Animate steps while the real prefetch runs in background
    final stepDuration = Duration(
      milliseconds: (_steps.length > 0) ? 600 : 500,
    );

    // Kick off the actual data loading
    final prefetchFuture = _runPrefetch();

    // Cycle through visual steps at a steady pace
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() {
        _stepIndex = i;
        _progress  = (i + 1) / _steps.length;
      });
      await Future.delayed(stepDuration);
    }

    // Wait for the real fetch to finish before navigating
    await prefetchFuture;

    if (!mounted) return;
    setState(() { _done = true; _progress = 1.0; });

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => HomeScreen(
          username: widget.username,
          apiKey:   widget.apiKey,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  Future<void> _runPrefetch() async {
    try {
      await DataCache.init();
      await PrefetchService.prefetchAll(widget.service, force: true);
    } catch (_) {
      // Non-blocking: app works fine without prefetch
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final step   = _steps[_stepIndex.clamp(0, _steps.length - 1)];

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // ── Pulsing icon ──────────────────────────────────────────
              ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color:  scheme.primary.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.headphones_rounded,
                      size: 48, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 36),

              // ── Title ─────────────────────────────────────────────────
              Text('LastStats',
                  style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: scheme.primary)),
              const SizedBox(height: 8),
              Text(
                'Bienvenue, ${widget.username} !',
                style: text.titleMedium?.copyWith(color: scheme.onSurface),
              ),
              if (widget.totalScrobbles > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${_fmtLarge(widget.totalScrobbles)} scrobbles à analyser',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 48),

              // ── Progress bar ──────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
              const SizedBox(height: 20),

              // ── Current step ──────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Row(
                  key: ValueKey(_stepIndex),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(step.$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _done ? '✅ Tout est prêt !' : step.$2,
                        style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // ── Tip ───────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'Chargement unique — tes données seront mises en cache pour une expérience instantanée.',
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  )),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtLarge(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}