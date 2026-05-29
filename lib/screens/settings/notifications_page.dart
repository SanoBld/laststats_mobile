// lib/screens/settings/notifications_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_state.dart';
import '../../services/notification_service.dart';
import '../../services/notification_worker.dart';

// ── Prefs keys (mirrors notification_worker.dart) ────────────────────────────
const _kMilestoneEnabled  = 'ls_notif_milestone_enabled';
const _kMilestoneInterval = 'ls_notif_milestone_interval';
const _kDailyEnabled      = 'ls_notif_daily_enabled';
const _kDailyHour         = 'ls_notif_daily_hour';
const _kDailyMin          = 'ls_notif_daily_min';
const _kWeeklyEnabled     = 'ls_notif_weekly_enabled';
const _kWeeklyDay         = 'ls_notif_weekly_day';
const _kWeeklyHour        = 'ls_notif_weekly_hour';
const _kWeeklyMin         = 'ls_notif_weekly_min';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Permission
  bool _hasPermission = false;
  bool _checkingPerm  = true;

  // Milestone
  bool _milestoneOn       = false;
  int  _milestoneInterval = 500;
  final _intervalCtrl     = TextEditingController();

  // Daily recap
  bool _dailyOn   = false;
  int  _dailyHour = 21;
  int  _dailyMin  = 0;

  // Weekly recap
  bool _weeklyOn   = false;
  int  _weeklyDay  = 1; // 1=Mon
  int  _weeklyHour = 20;
  int  _weeklyMin  = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final perm  = await NotificationService.hasPermission();

    if (!mounted) return;
    setState(() {
      _hasPermission     = perm;
      _checkingPerm      = false;

      _milestoneOn       = prefs.getBool(_kMilestoneEnabled)  ?? false;
      _milestoneInterval = prefs.getInt(_kMilestoneInterval)  ?? 500;

      _dailyOn   = prefs.getBool(_kDailyEnabled) ?? false;
      _dailyHour = prefs.getInt(_kDailyHour)     ?? 21;
      _dailyMin  = prefs.getInt(_kDailyMin)      ?? 0;

      _weeklyOn   = prefs.getBool(_kWeeklyEnabled) ?? false;
      _weeklyDay  = prefs.getInt(_kWeeklyDay)      ?? 1;
      _weeklyHour = prefs.getInt(_kWeeklyHour)     ?? 20;
      _weeklyMin  = prefs.getInt(_kWeeklyMin)      ?? 0;

      _intervalCtrl.text = _milestoneInterval.toString();
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMilestoneEnabled,  _milestoneOn);
    await prefs.setInt(_kMilestoneInterval,  _milestoneInterval);
    await prefs.setBool(_kDailyEnabled,      _dailyOn);
    await prefs.setInt(_kDailyHour,          _dailyHour);
    await prefs.setInt(_kDailyMin,           _dailyMin);
    await prefs.setBool(_kWeeklyEnabled,     _weeklyOn);
    await prefs.setInt(_kWeeklyDay,          _weeklyDay);
    await prefs.setInt(_kWeeklyHour,         _weeklyHour);
    await prefs.setInt(_kWeeklyMin,          _weeklyMin);
    // Re-schedule WorkManager tasks to reflect new settings
    await NotificationWorker.scheduleAll();
  }

  Future<void> _requestPermission() async {
    final granted = await NotificationService.requestPermission();
    if (!mounted) return;
    setState(() => _hasPermission = granted);
  }

  // ── Toggle helpers ───────────────────────────────────────────────────────

  void _setMilestone(bool v) {
    setState(() => _milestoneOn = v);
    _save();
  }

  void _setDaily(bool v) {
    setState(() => _dailyOn = v);
    _save();
  }

  void _setWeekly(bool v) {
    setState(() => _weeklyOn = v);
    _save();
  }

  Future<void> _pickTime({
    required int hour,
    required int minute,
    required void Function(int h, int m) onPicked,
  }) async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (result != null && mounted) {
      setState(() => onPicked(result.hour, result.minute));
      _save();
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isEn   = localeNotifier.value == 'en';

    return Scaffold(
      appBar: AppBar(
        title: Text(isEn ? 'Notifications' : 'Notifications'),
        centerTitle: false,
      ),
      body: _checkingPerm
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Permission banner ─────────────────────────────────
                if (!_hasPermission) ...[
                  _PermissionBanner(isEn: isEn, onRequest: _requestPermission),
                  const SizedBox(height: 16),
                ],

                // ── How it works note ──────────────────────────────────
                _InfoNote(
                  isEn: isEn,
                  icon: Icons.info_outline_rounded,
                  text: isEn
                      ? 'Notifications run in the background via WorkManager. '
                        'The app does not need to be open. '
                        'An internet connection is required to fetch scrobble data.'
                      : 'Les notifications tournent en arrière-plan via WorkManager. '
                        "L'app n'a pas besoin d'être ouverte. "
                        'Une connexion internet est nécessaire pour récupérer les données.',
                ),
                const SizedBox(height: 24),

                // ── Milestone ─────────────────────────────────────────
                _SectionLabel(
                    isEn ? 'Scrobble milestones' : 'Jalons de scrobbles', scheme),
                const SizedBox(height: 8),
                _NotifCard(
                  scheme:   scheme,
                  icon:     Icons.flag_rounded,
                  iconBg:   scheme.primaryContainer,
                  iconFg:   scheme.onPrimaryContainer,
                  title:    isEn ? 'Milestone reached' : 'Jalon atteint',
                  subtitle: isEn
                      ? 'Get notified every X scrobbles'
                      : 'Notification tous les X scrobbles',
                  enabled:  _milestoneOn,
                  onToggle: _hasPermission ? _setMilestone : null,
                  child: _milestoneOn
                      ? _MilestoneConfig(
                          isEn:     isEn,
                          interval: _milestoneInterval,
                          ctrl:     _intervalCtrl,
                          scheme:   scheme,
                          text:     text,
                          onChange: (v) {
                            setState(() => _milestoneInterval = v);
                            NotificationWorker.resetMilestoneCount();
                            _save();
                          },
                        )
                      : null,
                ),
                const SizedBox(height: 24),

                // ── Recaps ────────────────────────────────────────────
                _SectionLabel(
                    isEn ? 'Listening recaps' : 'Récapitulatifs', scheme),
                const SizedBox(height: 8),

                // Daily
                _NotifCard(
                  scheme:   scheme,
                  icon:     Icons.today_rounded,
                  iconBg:   scheme.secondaryContainer,
                  iconFg:   scheme.onSecondaryContainer,
                  title:    isEn ? 'Daily recap' : 'Récap quotidien',
                  subtitle: isEn
                      ? 'Daily scrobble count + top artist'
                      : 'Scrobbles du jour + artiste favori',
                  enabled:  _dailyOn,
                  onToggle: _hasPermission ? _setDaily : null,
                  child: _dailyOn
                      ? _TimePicker(
                          isEn:   isEn,
                          hour:   _dailyHour,
                          minute: _dailyMin,
                          scheme: scheme,
                          text:   text,
                          onTap: () => _pickTime(
                            hour:    _dailyHour,
                            minute:  _dailyMin,
                            onPicked: (h, m) {
                              _dailyHour = h;
                              _dailyMin  = m;
                            },
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),

                // Weekly
                _NotifCard(
                  scheme:   scheme,
                  icon:     Icons.date_range_rounded,
                  iconBg:   scheme.tertiaryContainer,
                  iconFg:   scheme.onTertiaryContainer,
                  title:    isEn ? 'Weekly recap' : 'Récap hebdomadaire',
                  subtitle: isEn
                      ? 'Weekly scrobble count + top artist'
                      : 'Scrobbles de la semaine + artiste favori',
                  enabled:  _weeklyOn,
                  onToggle: _hasPermission ? _setWeekly : null,
                  child: _weeklyOn
                      ? _WeeklyConfig(
                          isEn:   isEn,
                          day:    _weeklyDay,
                          hour:   _weeklyHour,
                          minute: _weeklyMin,
                          scheme: scheme,
                          text:   text,
                          onDayChanged: (d) {
                            setState(() => _weeklyDay = d);
                            _save();
                          },
                          onTimeTap: () => _pickTime(
                            hour:    _weeklyHour,
                            minute:  _weeklyMin,
                            onPicked: (h, m) {
                              _weeklyHour = h;
                              _weeklyMin  = m;
                            },
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

// ── Permission banner ─────────────────────────────────────────────────────────

class _PermissionBanner extends StatelessWidget {
  final bool isEn;
  final VoidCallback onRequest;
  const _PermissionBanner({required this.isEn, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.notifications_off_rounded,
            color: scheme.onErrorContainer, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(
            isEn ? 'Notifications disabled' : 'Notifications désactivées',
            style: TextStyle(
                color: scheme.onErrorContainer, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            isEn
                ? 'Grant permission so LastStats can send you alerts.'
                : "Accordez la permission pour que LastStats puisse vous envoyer des alertes.",
            style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: onRequest,
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onErrorContainer,
              foregroundColor: scheme.errorContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(isEn ? 'Grant permission' : 'Autoriser'),
          ),
        ])),
      ]),
    );
  }
}

// ── Info note ─────────────────────────────────────────────────────────────────

class _InfoNote extends StatelessWidget {
  final bool isEn;
  final IconData icon;
  final String text;
  const _InfoNote({required this.isEn, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
            style: TextStyle(
                fontSize: 13, color: scheme.onSurfaceVariant, height: 1.4))),
      ]),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme scheme;
  const _SectionLabel(this.label, this.scheme);

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: scheme.primary,
        letterSpacing: 0.6),
  );
}

// ── Notification card ─────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final ColorScheme scheme;
  final IconData   icon;
  final Color      iconBg, iconFg;
  final String     title, subtitle;
  final bool       enabled;
  final void Function(bool)? onToggle;
  final Widget? child; // expanded config section

  const _NotifCard({
    required this.scheme,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onToggle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.4),
          width: enabled ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                  color: iconBg, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: iconFg, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant, height: 1.3)),
            ])),
            Switch(
              value:    enabled,
              onChanged: onToggle,
            ),
          ]),
        ),

        // Config section (animated expand)
        if (child != null) ...[
          Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: child!,
          ),
        ],
      ]),
    );
  }
}

// ── Milestone config: interval input ─────────────────────────────────────────

class _MilestoneConfig extends StatelessWidget {
  final bool isEn;
  final int  interval;
  final TextEditingController ctrl;
  final ColorScheme scheme;
  final TextTheme   text;
  final void Function(int) onChange;
  const _MilestoneConfig({
    required this.isEn,
    required this.interval,
    required this.ctrl,
    required this.scheme,
    required this.text,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        isEn ? 'Notify every X scrobbles' : 'Notifier tous les X scrobbles',
        style: text.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
      ),
      const SizedBox(height: 10),
      Row(children: [
        // Quick-pick chips
        for (final v in [100, 250, 500, 1000])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label:      Text('$v'),
              selected:   interval == v,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                ctrl.text = '$v';
                onChange(v);
              },
            ),
          ),
      ]),
      const SizedBox(height: 10),
      // Custom value field
      SizedBox(
        height: 44,
        child: TextField(
          controller:   ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText:     isEn ? 'Custom value' : 'Valeur personnalisée',
            border:        const OutlineInputBorder(),
            isDense:       true,
            suffixText:    isEn ? 'scrobbles' : 'scrobbles',
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          onSubmitted: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null && parsed > 0) onChange(parsed);
          },
        ),
      ),
    ]);
  }
}

// ── Time picker row ───────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  final bool   isEn;
  final int    hour, minute;
  final ColorScheme scheme;
  final TextTheme   text;
  final VoidCallback onTap;
  const _TimePicker({
    required this.isEn,
    required this.hour,
    required this.minute,
    required this.scheme,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return Row(children: [
      Text(
        isEn ? 'Notify at' : 'Notifier à',
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(width: 12),
      FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Text('$hh:$mm',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}

// ── Weekly config: day picker + time ─────────────────────────────────────────

class _WeeklyConfig extends StatelessWidget {
  final bool isEn;
  final int  day, hour, minute;
  final ColorScheme scheme;
  final TextTheme   text;
  final void Function(int) onDayChanged;
  final VoidCallback onTimeTap;
  const _WeeklyConfig({
    required this.isEn,
    required this.day,
    required this.hour,
    required this.minute,
    required this.scheme,
    required this.text,
    required this.onDayChanged,
    required this.onTimeTap,
  });

  @override
  Widget build(BuildContext context) {
    final days = isEn
        ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        isEn ? 'Day of the week' : 'Jour de la semaine',
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: List.generate(7, (i) {
        final dayNum = i + 1;
        return FilterChip(
          label:       Text(days[i]),
          selected:    day == dayNum,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onDayChanged(dayNum),
        );
      })),
      const SizedBox(height: 12),
      Row(children: [
        Text(
          isEn ? 'Notify at' : 'Notifier à',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(
          onPressed: onTimeTap,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Text('$hh:$mm',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    ]);
  }
}