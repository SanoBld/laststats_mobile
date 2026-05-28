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
  void initState() {
    super.initState();
    localeNotifier.addListener(_onLocale);
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_onLocale);
    _usernameCtrl.dispose();
    _apikeyCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _onLocale() => setState(() {});

  Future<void> _setLocale(String code) async {
    localeNotifier.value = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ls_locale', code);
  }

  // ── Parse JSON inline → remplit les champs ────────────────────────────
  // Accepte deux formats :
  //   • Format simple   : {"username":"…","api_key":"…"}
  //   • Format backup   : {"app":"LastStats","prefs":{"ls_username":"…","ls_apikey":"…",…}}
  void _applyJson() {
    final raw = _jsonCtrl.text.trim();
    if (raw.isEmpty) return;
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;

      String username = '';
      String apiKey   = '';

      // ── Format backup LastStats ──────────────────────────────────────
      if (data['app'] == 'LastStats' && data['prefs'] is Map) {
        final prefs = data['prefs'] as Map<String, dynamic>;
        // Préférer le compte actif via ls_accounts si disponible
        final accountsRaw = prefs['ls_accounts'];
        final activeIdx   = (prefs['ls_active_account'] as num?)?.toInt() ?? 0;
        if (accountsRaw != null) {
          try {
            final accounts = jsonDecode(accountsRaw.toString()) as List;
            if (accounts.isNotEmpty) {
              final acc = accounts[activeIdx.clamp(0, accounts.length - 1)]
                  as Map<String, dynamic>;
              username = (acc['username'] ?? '').toString().trim();
              apiKey   = (acc['apiKey']   ?? '').toString().trim();
            }
          } catch (_) {}
        }
        // Fallback sur ls_username / ls_apikey (mono-compte ou ancienne version)
        if (username.isEmpty) {
          username = (prefs['ls_username'] ?? '').toString().trim();
        }
        if (apiKey.isEmpty) {
          apiKey = (prefs['ls_apikey'] ?? '').toString().trim();
        }
        // Fallback sur les champs racine du backup (username / api_key)
        if (username.isEmpty) {
          username = (data['username'] ?? '').toString().trim();
        }
        if (apiKey.isEmpty) {
          apiKey = (data['api_key'] ?? data['apiKey'] ?? '').toString().trim();
        }
      } else {
        // ── Format simple ──────────────────────────────────────────────
        username = (data['username'] ?? '').toString().trim();
        apiKey   = (data['api_key'] ?? data['apiKey'] ?? data['api-key'] ?? '').toString().trim();
      }

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
      setState(() => _errorMessage = localeNotifier.value == 'en'
          ? 'Please fill both fields.' : 'Remplis les deux champs.');
      return;
    }
    if (apiKey.length != 32) {
      setState(() => _errorMessage = localeNotifier.value == 'en'
          ? 'API key must be 32 characters.' : 'La clé API doit faire 32 caractères.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final service  = LastFmService(apiKey: apiKey, username: username);
      final userInfo = await service.getUserInfo();

      if (userInfo == null) throw Exception(
          localeNotifier.value == 'en' ? 'Profile not found.' : 'Profil introuvable.');

      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('ls_username', username);
        await prefs.setString('ls_apikey',   apiKey);
      }

      final totalScrobbles =
          int.tryParse(userInfo['playcount']?.toString() ?? '0') ?? 0;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => _FirstLoadScreen(
            username:       username,
            apiKey:         apiKey,
            service:        service,
            totalScrobbles: totalScrobbles,
          ),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 350),
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
    final isEn   = localeNotifier.value == 'en';

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

                  // ── Language toggle ───────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LangChip(
                        flag: '🇫🇷', label: 'Français',
                        selected: !isEn,
                        onTap: () => _setLocale('fr'),
                        scheme: scheme, text: text,
                      ),
                      const SizedBox(width: 10),
                      _LangChip(
                        flag: '🇬🇧', label: 'English',
                        selected: isEn,
                        onTap: () => _setLocale('en'),
                        scheme: scheme, text: text,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ── Logo ──────────────────────────────────────
                  Column(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/images/icon-512.png',
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
                    Text(
                      isEn ? 'Your Last.fm stats, reinvented.'
                           : 'Tes stats Last.fm, réinventées.',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
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
                        Text(
                          isEn ? 'Analyse a profile' : 'Analyser un profil',
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 24),

                        // Username
                        TextField(
                          controller:      _usernameCtrl,
                          textInputAction: TextInputAction.next,
                          autocorrect:     false,
                          decoration: InputDecoration(
                            labelText:  isEn ? 'Last.fm username' : 'Pseudo Last.fm',
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
                            labelText: isEn ? 'Last.fm API key' : 'Clé API Last.fm',
                            hintText:  isEn ? '32-character hex key' : 'Clé hexadécimale de 32 caractères',
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
                            isEn ? 'Stored locally. Never sent to a third party.'
                                 : 'Stockée localement. Jamais envoyée à un tiers.',
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
                            child: Text(isEn ? 'Remember me' : 'Se souvenir de moi'),
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
                          label: Text(_isLoading
                              ? (isEn ? 'Connecting…' : 'Connexion…')
                              : (isEn ? 'Start analysis' : "Lancer l'analyse")),
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
                      child: Text(isEn ? 'or' : 'ou',
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
                      label: Text(isEn
                          ? 'Get a free API key'
                          : 'Obtenir une clé API gratuitement'),
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

// ── Language chip ─────────────────────────────────────────────────────────────

class _LangChip extends StatelessWidget {
  final String flag, label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final TextTheme text;

  const _LangChip({
    required this.flag,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 7),
            Text(
              label,
              style: text.labelMedium?.copyWith(
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _FirstLoadScreen — affiché UNE SEULE FOIS à la première connexion
//
//  • Écoute [PrefetchService.progressNotifier] pour afficher en temps réel
//    les 12 étapes de l'import (tops toutes périodes, mensuel, loved…)
//  • Checklist animée : ✓ étapes terminées, ⏳ étape active, barre de progression
//  • Compteur de scrobbles affiché pendant le chargement
//  • Navigue vers HomeScreen dès que l'import est complet (600 ms de délai
//    pour que l'état "Importé !" soit visible)
// ══════════════════════════════════════════════════════════════════════════

class _FirstLoadScreen extends StatefulWidget {
  final String      username;
  final String      apiKey;
  final LastFmService service;
  final int         totalScrobbles;

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
    with TickerProviderStateMixin {

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulse;

  PrefetchState _state = const PrefetchState(
    currentStep: '', fraction: 0, completedSteps: [], isComplete: false,
  );
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // Fade-in
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // Pulsing icon
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Écoute la progression
    PrefetchService.progressNotifier.addListener(_onProgress);

    // Lance l'import complet avec suivi (force: true → toujours re-fetcher)
    PrefetchService.prefetchAllWithProgress(widget.service, force: true);
  }

  void _onProgress() {
    if (!mounted) return;
    setState(() => _state = PrefetchService.progressNotifier.value);
    if (_state.isComplete) _scheduleNavigation();
  }

  void _scheduleNavigation() {
    if (_navigated) return;
    _navigated = true;
    // Délai court pour laisser le temps de voir "Importé !"
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomeScreen(
            username:   widget.username,
            apiKey:     widget.apiKey,
          ),
          transitionsBuilder: (_, anim, __, child) {
            final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.06),
                end:   Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 550),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    PrefetchService.progressNotifier.removeListener(_onProgress);
    super.dispose();
  }

  String _t(String fr, String en) =>
      localeNotifier.value == 'en' ? en : fr;

  static String _fmtLarge(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return Scaffold(
      backgroundColor: scheme.surface,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height
                           - MediaQuery.of(context).padding.top
                           - MediaQuery.of(context).padding.bottom
                           - 48, // padding vertical × 2
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [

                const Spacer(flex: 2),

                // ── Icône pulsante ────────────────────────────────────────
                ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color:      scheme.primary.withValues(alpha: 0.22),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(Icons.headphones_rounded,
                        size: 44, color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Titre + bienvenue ─────────────────────────────────────
                Text('LastStats',
                    style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: scheme.primary)),
                const SizedBox(height: 6),
                Text(
                  isEn ? 'Welcome, ${widget.username}!'
                       : 'Bienvenue, ${widget.username}\u00a0!',
                  style: text.titleMedium?.copyWith(
                      color: scheme.onSurface, fontWeight: FontWeight.w600),
                ),

                // ── Badge compteur de scrobbles ───────────────────────────
                if (widget.totalScrobbles > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.library_music_rounded,
                          size: 14, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 7),
                      Text(
                        isEn
                            ? '${_fmtLarge(widget.totalScrobbles)} scrobbles to import'
                            : '${_fmtLarge(widget.totalScrobbles)} scrobbles à importer',
                        style: text.labelMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                ],

                const Spacer(flex: 2),

                // ── Checklist temps réel ──────────────────────────────────
                _FirstLoadChecklist(
                  state:  _state,
                  scheme: scheme,
                  text:   text,
                  t:      _t,
                ),
                const SizedBox(height: 22),

                // ── Barre de progression ──────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _state.fraction),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value:      v,
                      minHeight:  6,
                      backgroundColor: scheme.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Étape courante (légende sous la barre) ────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    _state.isComplete
                        ? _t('✨ Import terminé !', '✨ Import complete!')
                        : _state.currentStep.isEmpty
                            ? _t('Connexion à Last.fm…', 'Connecting to Last.fm…')
                            : _state.currentStep,
                    key: ValueKey(_state.isComplete ? 'done' : _state.currentStep),
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(flex: 1),

                // ── Note "import unique" ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(children: [
                    Icon(Icons.bolt_rounded, size: 15, color: scheme.tertiary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      isEn
                          ? 'One-time import — future launches will be instant.'
                          : 'Import unique — les prochains lancements seront instantanés.',
                      style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    )),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
            ),          // fin Column
          ),            // fin IntrinsicHeight
        ),              // fin ConstrainedBox
      ),                // fin SingleChildScrollView
    ),                  // fin SafeArea
  ),                    // fin FadeTransition
);
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  _FirstLoadChecklist — checklist animée des étapes d'import
// ══════════════════════════════════════════════════════════════════════════

class _FirstLoadChecklist extends StatefulWidget {
  final PrefetchState state;
  final ColorScheme   scheme;
  final TextTheme     text;
  final String Function(String fr, String en) t;

  const _FirstLoadChecklist({
    required this.state,
    required this.scheme,
    required this.text,
    required this.t,
  });

  @override
  State<_FirstLoadChecklist> createState() => _FirstLoadChecklistState();
}

class _FirstLoadChecklistState extends State<_FirstLoadChecklist> {
  final _sc = ScrollController();

  @override
  void didUpdateWidget(_FirstLoadChecklist old) {
    super.didUpdateWidget(old);
    // Auto-scroll vers le bas à chaque nouvelle étape
    if (widget.state.completedSteps.length != old.state.completedSteps.length ||
        widget.state.currentStep != old.state.currentStep) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) {
          _sc.animateTo(
            _sc.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state      = widget.state;
    final scheme     = widget.scheme;
    final text       = widget.text;
    final t          = widget.t;
    final hasContent = state.completedSteps.isNotEmpty ||
        state.currentStep.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 340),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: hasContent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── En-tête fixe ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    t('Import de tes données', 'Importing your data'),
                    style: text.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                // ── Liste scrollable des étapes ────────────────────────────
                Flexible(
                  child: ListView(
                    controller: _sc,
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      // Étapes complètes
                      ...state.completedSteps.map((label) => _StepRow(
                        label:  label,
                        status: _RowStatus.done,
                        scheme: scheme,
                        text:   text,
                      )),

                      // Étape active
                      if (state.currentStep.isNotEmpty && !state.isComplete)
                        _StepRow(
                          label:  state.currentStep,
                          status: _RowStatus.active,
                          scheme: scheme,
                          text:   text,
                        ),

                      // Message final
                      if (state.isComplete)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Icon(Icons.rocket_launch_rounded,
                                size: 15, color: scheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              t('Importé !', 'Imported!'),
                              style: text.bodySmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            )
          // Placeholder avant la 1ère étape
          : Row(children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                t('Connexion à Last.fm…', 'Connecting to Last.fm…'),
                style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant),
              ),
            ]),
    );
  }
}



enum _RowStatus { done, active }

class _StepRow extends StatelessWidget {
  final String      label;
  final _RowStatus  status;
  final ColorScheme scheme;
  final TextTheme   text;

  const _StepRow({
    required this.label,
    required this.status,
    required this.scheme,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = status == _RowStatus.done;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        // Icône de statut
        SizedBox(
          width: 18, height: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: isDone
                ? Icon(Icons.check_circle_rounded,
                    size: 18, color: scheme.primary,
                    key: const ValueKey('done'))
                : CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(scheme.primary),
                    key: const ValueKey('active')),
          ),
        ),
        const SizedBox(width: 10),

        // Label
        Expanded(
          child: Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: isDone ? scheme.onSurface : scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // Coche secondaire pour les étapes terminées
        if (isDone)
          Icon(Icons.check_rounded,
              size: 14, color: scheme.primary.withValues(alpha: 0.6)),
      ]),
    );
  }
}