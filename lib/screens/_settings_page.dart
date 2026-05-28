// ignore_for_file: unused_import
// lib/screens/_settings_page.dart
// ══════════════════════════════════════════════════════════════════════════
//  Settings tab — navigation hub to sub-pages.
//  All options are grouped by theme in dedicated pages.
// ══════════════════════════════════════════════════════════════════════════
part of 'home_screen.dart';

// ── Card data model ───────────────────────────────────────────────────────────

class _SettingsCardData {
  final IconData icon;
  final Color Function(ColorScheme) iconBgColor;
  final Color Function(ColorScheme) iconFgColor;
  final String Function() title;
  final String Function() subtitle;
  final Widget Function(String username) pageBuilder;

  const _SettingsCardData({
    required this.icon,
    required this.iconBgColor,
    required this.iconFgColor,
    required this.title,
    required this.subtitle,
    required this.pageBuilder,
  });
}

// ── Main settings page (hub) ──────────────────────────────────────────────────

class _SettingsPage extends StatefulWidget {
  final String username;
  const _SettingsPage({required this.username});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  UpdateInfo? _updateInfo;
  bool        _checkingUpdate = false;
  bool        _autoUpdate     = true;

  @override
  void initState() {
    super.initState();
    _loadAndCheck();
    localeNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    localeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  Future<void> _loadAndCheck() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    _autoUpdate = p.getBool('ls_auto_update_check') ?? true;
    if (!_autoUpdate) return;
    final last = p.getInt('ls_last_update_check') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 1).inMilliseconds) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      await p.setInt('ls_last_update_check', DateTime.now().millisecondsSinceEpoch);
      setState(() { _updateInfo = info; _checkingUpdate = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  List<_SettingsCardData> _buildCards() => [
    _SettingsCardData(
      icon: Icons.palette_rounded,
      iconBgColor: (s) => s.primaryContainer,
      iconFgColor: (s) => s.onPrimaryContainer,
      title:    () => L.settingsAppearance,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Theme, accent color, Material You'
          : 'Thème, couleur d\'accent, Material You',
      pageBuilder: (_) => const AppearancePage(),
    ),
    _SettingsCardData(
      icon: Icons.dashboard_rounded,
      iconBgColor: (s) => s.secondaryContainer,
      iconFgColor: (s) => s.onSecondaryContainer,
      title:    () => L.settingsDashboardSection,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Header image, visible sections, stat cards'
          : 'Image d\'en-tête, sections visibles, cartes de stats',
      pageBuilder: (_) => const DashboardSettingsPage(),
    ),
    _SettingsCardData(
      icon: Icons.rocket_launch_rounded,
      iconBgColor: (s) => s.tertiaryContainer,
      iconFgColor: (s) => s.onTertiaryContainer,
      title:    () => L.settingsStartupPage,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Tab displayed on app launch'
          : 'Onglet affiché au démarrage',
      pageBuilder: (_) => const StartupPage(),
    ),
    _SettingsCardData(
      icon: Icons.translate_rounded,
      iconBgColor: (s) => Color.lerp(s.primaryContainer, s.secondaryContainer, 0.5)!,
      iconFgColor: (s) => s.onPrimaryContainer,
      title:    () => L.settingsLanguage,
      subtitle: () => localeNotifier.value == 'en'
          ? 'French · English'
          : 'Français · English',
      pageBuilder: (_) => const LanguagePage(),
    ),
    _SettingsCardData(
      icon: Icons.person_rounded,
      iconBgColor: (s) => s.primaryContainer,
      iconFgColor: (s) => s.onPrimaryContainer,
      title:    () => L.settingsAccount,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Connected Last.fm profile, sign out'
          : 'Profil Last.fm connecté, déconnexion',
      pageBuilder: (u) => AccountPage(username: u),
    ),
    _SettingsCardData(
      icon: Icons.storage_rounded,
      iconBgColor: (s) => Color.lerp(s.primaryContainer, s.tertiaryContainer, 0.5)!,
      iconFgColor: (s) => s.onPrimaryContainer,
      title:    () => localeNotifier.value == 'en' ? 'Cache' : 'Cache',
      subtitle: () => localeNotifier.value == 'en'
          ? 'History, images, API data'
          : 'Historique, images, données API',
      pageBuilder: (_) => const CachePage(),
    ),
    _SettingsCardData(
      icon: Icons.backup_rounded,
      iconBgColor: (s) => s.secondaryContainer,
      iconFgColor: (s) => s.onSecondaryContainer,
      title:    () => L.settingsBackup,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Export & restore your settings'
          : 'Exporter et restaurer vos paramètres',
      pageBuilder: (_) => const BackupPage(),
    ),
    _SettingsCardData(
      icon: Icons.system_update_rounded,
      iconBgColor: (s) => s.tertiaryContainer,
      iconFgColor: (s) => s.onTertiaryContainer,
      title:    () => L.settingsUpdates,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Check for new versions'
          : 'Vérifier les nouvelles versions',
      pageBuilder: (_) => const UpdatesPage(),
    ),
    _SettingsCardData(
      icon: Icons.info_outline_rounded,
      iconBgColor: (s) => Color.lerp(s.tertiaryContainer, s.surface, 0.4)!,
      iconFgColor: (s) => s.onTertiaryContainer,
      title:    () => L.settingsAbout,
      subtitle: () => localeNotifier.value == 'en'
          ? 'Version, source code, credits'
          : 'Version, code source, crédits',
      pageBuilder: (_) => const AboutPage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final text    = Theme.of(context).textTheme;
    final isEn    = localeNotifier.value == 'en';
    final cards   = _buildCards();
    final initial = widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?';

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(L.settingsTitle,
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),

              // Compact profile card
              GestureDetector(
                onTap: () => _push(context, AccountPage(username: widget.username)),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: scheme.primary,
                      child: Text(initial, style: TextStyle(
                          fontSize: 20, color: scheme.onPrimary, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.username,
                          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(L.settingsConnectedProfile,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ])),
                    Icon(Icons.chevron_right_rounded, color: scheme.primary),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // ── PC / Desktop layout mode ──────────────────────────────
              _PcModeCard(isEn: isEn),
              const SizedBox(height: 12),

              // Update available banner
              if (_updateInfo != null)
                _UpdateBanner(
                  info: _updateInfo!,
                  onTap: () => _push(context, const UpdatesPage()),
                ),
              if (_updateInfo != null) const SizedBox(height: 12),

              // "Restart required" notice
              const _RestartNotice(),
              const SizedBox(height: 20),
            ]),
          )),

          // ── Category grid ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _CategoryCard(
                  data:     cards[i],
                  username: widget.username,
                  badge:    (i == 6 && _updateInfo != null) ? '!' : null,
                  onTap: () => _push(ctx, cards[i].pageBuilder(widget.username)),
                ),
                childCount: cards.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:   2,
                crossAxisSpacing: 12,
                mainAxisSpacing:  12,
                childAspectRatio: 1.1,
              ),
            ),
          ),

          // ── Footer ─────────────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Column(children: [
              const Divider(),
              const SizedBox(height: 10),
              Text('LastStats Mobile v${UpdateService.currentVersion}',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              if (_checkingUpdate) ...[
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  Text(isEn ? 'Checking for updates…' : 'Vérification des mises à jour…',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ],
              const SizedBox(height: 8),
            ]),
          )),
        ],
      ),
    );
  }

  void _push(BuildContext ctx, Widget page) {
    Navigator.push(ctx, MaterialPageRoute(builder: (_) => page));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  PC / Desktop layout mode card
// ══════════════════════════════════════════════════════════════════════════════

class _PcModeCard extends StatefulWidget {
  final bool isEn;
  const _PcModeCard({required this.isEn});

  @override
  State<_PcModeCard> createState() => _PcModeCardState();
}

class _PcModeCardState extends State<_PcModeCard> {
  String _mode = pcModeNotifier.value;

  @override
  void initState() {
    super.initState();
    pcModeNotifier.addListener(_sync);
  }

  @override
  void dispose() {
    pcModeNotifier.removeListener(_sync);
    super.dispose();
  }

  void _sync() => setState(() => _mode = pcModeNotifier.value);

  Future<void> _update(String newMode) async {
    pcModeNotifier.value = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ls_pc_mode', newMode);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = widget.isEn;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ─────────────────────────────────────────────────────
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.desktop_windows_outlined,
                color: scheme.onSecondaryContainer, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isEn ? 'Navigation layout' : 'Disposition de navigation',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              isEn
                  ? 'Side rail on wide screens, bottom bar on mobile'
                  : 'Rail latéral sur grand écran, barre bas sur mobile',
              style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant, height: 1.3),
            ),
          ])),
        ]),
        const SizedBox(height: 14),

        // ── Segmented button ────────────────────────────────────────────
        // Three segments: Auto / Side rail / Bottom bar
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment<String>(
                value: 'auto',
                icon:  const Icon(Icons.auto_mode_rounded, size: 16),
                label: Text(isEn ? 'Auto' : 'Auto'),
              ),
              ButtonSegment<String>(
                value: 'on',
                icon:  const Icon(Icons.view_sidebar_outlined, size: 16),
                label: Text(isEn ? 'Side rail' : 'Rail latéral'),
              ),
              ButtonSegment<String>(
                value: 'off',
                icon:  const Icon(Icons.view_headline_rounded, size: 16),
                label: Text(isEn ? 'Bottom bar' : 'Barre bas'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (sel) => _update(sel.first),
            style: SegmentedButton.styleFrom(
              // Keep the button compact to fit all 3 labels on narrow screens
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(vertical: -1),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ── Hint line ───────────────────────────────────────────────────
        Row(children: [
          Icon(Icons.info_outline_rounded,
              size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(
            _modeHint(isEn),
            style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                height: 1.3),
          )),
        ]),
      ]),
    );
  }

  /// Short explanatory hint that adapts to the current selection.
  String _modeHint(bool isEn) {
    switch (_mode) {
      case 'on':
        return isEn
            ? 'Side rail always visible. Labels expand above 1200 dp.'
            : 'Rail latéral toujours visible. Labels étendus au-delà de 1200 dp.';
      case 'off':
        return isEn
            ? 'Bottom navigation bar on all screen sizes.'
            : 'Barre de navigation basse sur toutes les tailles d\'écran.';
      default: // 'auto'
        return isEn
            ? 'Side rail above 720 dp, bottom bar below.'
            : 'Rail latéral au-delà de 720 dp, barre basse en dessous.';
    }
  }
}

// ── Category card ─────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final _SettingsCardData data;
  final String username;
  final String? badge;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.data,
    required this.username,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          padding: const EdgeInsets.all(16),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Icon
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: data.iconBgColor(scheme),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, color: data.iconFgColor(scheme), size: 24),
              ),
              const Spacer(),
              // Title
              Text(data.title(),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              // Subtitle
              Text(data.subtitle(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant, height: 1.3)),
            ]),

            // Notification badge (e.g. update available)
            if (badge != null)
              Positioned(
                top: 0, right: 0,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                      color: scheme.tertiary, shape: BoxShape.circle),
                  child: Center(child: Text(badge!,
                      style: TextStyle(color: scheme.onTertiary,
                          fontSize: 11, fontWeight: FontWeight.w800))),
                ),
              ),

            // Arrow
            Positioned(
              bottom: 0, right: 0,
              child: Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Update banner ─────────────────────────────────────────────────────────────

class _UpdateBanner extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onTap;
  const _UpdateBanner({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(Icons.system_update_rounded, color: scheme.onTertiaryContainer, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(L.settingsUpdateBanner(info.version),
                style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer)),
            Text(isEn ? 'Tap to download' : 'Touchez pour télécharger',
                style: text.bodySmall?.copyWith(
                    color: scheme.onTertiaryContainer.withValues(alpha: 0.7))),
          ])),
          Icon(Icons.chevron_right_rounded, color: scheme.onTertiaryContainer),
        ]),
      ),
    );
  }
}

// ── Restart notice ────────────────────────────────────────────────────────────

class _RestartNotice extends StatelessWidget {
  const _RestartNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.restart_alt_rounded, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(
          isEn
              ? 'Some settings require restarting the app to take full effect.'
              : 'Certains paramètres nécessitent un redémarrage de l\'app pour être pleinement appliqués.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        )),
      ]),
    );
  }
}