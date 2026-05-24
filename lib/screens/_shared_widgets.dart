// ignore_for_file: unused_import
part of 'home_screen.dart';

// ── Reusable entrance animation: fade + subtle upward slide ──────────────────
// Wrap any list item with this to get a gentle slide-in on first render.
class _FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  const _FadeSlideIn({
    required this.child,
    this.delay    = Duration.zero,
    this.duration = const Duration(milliseconds: 350),
  });

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: widget.duration);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () { if (mounted) _ctrl.forward(); });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child:   SlideTransition(position: _slide, child: widget.child),
  );
}

// ── Pulsing status dot (used in NowPlayingCard and friend cards) ──────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({required this.color, this.size = 7});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.75, end: 1.25)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Container(
      width:  widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        // Soft outer glow that breathes with the scale
        boxShadow: [
          BoxShadow(
            color:      widget.color.withValues(alpha: 0.55),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
    ),
  );
}

/// Widget d'image intelligent avec résolution asynchrone.
/// Converti en StatefulWidget pour mémoriser le Future de résolution :
/// le resolver n'est appelé qu'une seule fois (ou si l'URL source change),
/// ce qui évite les clignotements lors des rebuilds du parent (ex: refresh).
class _SmartImage extends StatefulWidget {
  final String? initialUrl;
  final Future<String> Function() resolver;
  final double size, borderRadius;
  const _SmartImage({required this.resolver, required this.size,
      required this.borderRadius, this.initialUrl});

  static const _ph = '2a96cbd8b46e442fc41c2b86b821562f';

  @override
  State<_SmartImage> createState() => _SmartImageState();
}

class _SmartImageState extends State<_SmartImage> {
  Future<String>? _future;
  String?         _resolvedUrl;   // URL déjà résolue → pas de FutureBuilder
  String?         _lastInitialUrl;

  bool get _needsResolve =>
      widget.initialUrl == null ||
      widget.initialUrl!.isEmpty ||
      widget.initialUrl!.contains(_SmartImage._ph);

  @override
  void initState() {
    super.initState();
    _lastInitialUrl = widget.initialUrl;
    if (!_needsResolve) {
      _resolvedUrl = widget.initialUrl;
    } else {
      _future = widget.resolver();
    }
  }

  @override
  void didUpdateWidget(_SmartImage old) {
    super.didUpdateWidget(old);
    // Relancer uniquement si l'URL source a changé (piste différente)
    if (widget.initialUrl != _lastInitialUrl) {
      _lastInitialUrl = widget.initialUrl;
      _resolvedUrl    = null;
      if (!_needsResolve) {
        _resolvedUrl = widget.initialUrl;
        _future      = null;
      } else {
        _future = widget.resolver();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // URL already available — skip FutureBuilder entirely
    if (_resolvedUrl != null && _resolvedUrl!.isNotEmpty) {
      return _img(_resolvedUrl!, scheme);
    }
    if (!_needsResolve) {
      return _img(widget.initialUrl!, scheme);
    }

    return FutureBuilder<String>(
      future: _future,
      builder: (_, snap) {
        final Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = _loading(scheme);
        } else {
          final url = snap.data ?? '';
          // Persist result so future rebuilds skip the FutureBuilder
          if (url.isNotEmpty && _resolvedUrl == null) _resolvedUrl = url;
          child = url.isEmpty ? _fallback(scheme) : _img(url, scheme);
        }
        // Smooth fade between the loading placeholder and the resolved image
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: KeyedSubtree(
            key: ValueKey(snap.connectionState == ConnectionState.done
                ? (snap.data ?? 'fallback')
                : 'loading'),
            child: child,
          ),
        );
      },
    );
  }

  Widget _img(String url, ColorScheme s) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: Image.network(url, width: widget.size, height: widget.size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(s)));

  Widget _loading(ColorScheme s) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: Container(width: widget.size, height: widget.size,
      color: s.surfaceContainerHighest,
      child: Center(child: SizedBox(
        width:  widget.size * 0.4,
        height: widget.size * 0.4,
        child: CircularProgressIndicator(
            strokeWidth: 1.5, color: s.primary.withValues(alpha: 0.5))))));

  Widget _fallback(ColorScheme s) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.borderRadius),
    child: Container(width: widget.size, height: widget.size,
      color: s.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded,
          color: s.onSurfaceVariant, size: widget.size * 0.5)));
}

class _SectionHeader extends StatelessWidget {
  final String title; final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, color: scheme.primary, size: 20), const SizedBox(width: 8),
      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _ItemTile extends StatelessWidget {
  final String name, sub, imageUrl, rank;
  final Future<String>? imageFuture;
  final String? plays;
  const _ItemTile({required this.name, required this.sub, required this.imageUrl,
      required this.rank, this.imageFuture, this.plays});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(children: [
          SizedBox(width: 28, child: Text(rank, textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          _SmartImage(size: 48, borderRadius: 8, initialUrl: imageUrl,
              resolver: imageFuture != null ? () => imageFuture! : () => Future.value('')),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ])),
          if (plays != null) Padding(padding: const EdgeInsets.only(left: 8),
            child: Text(plays!, style: text.bodySmall
                ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600))),
        ])));
  }
}

class _ErrorView extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded), label: Text(L.commonRetry)),
      ])));
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _extractImage(dynamic images) {
  if (images == null) return '';
  final list = images is List ? images : [];
  if (list.isEmpty) return '';
  try {
    final large = list.lastWhere(
        (i) => i is Map && i['size'] == 'extralarge', orElse: () => list.last);
    return (large is Map ? large['#text'] ?? '' : '').toString();
  } catch (_) { return ''; }
}

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000)    return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}


String _fmtDate(String raw) {
  if (raw.isEmpty) return '';
  try {
    final parts = raw.split(', ');
    return parts.length == 2 ? '${parts[0]} · ${parts[1]}' : raw;
  } catch (_) { return raw; }
}

/// Converts a track's Unix timestamp (date['uts']) to the device's local time
/// and returns "DD Mmm · HH:MM". Falls back to _fmtDate if uts is absent.
String _fmtTrackDateLocal(Map t) {
  final uts = t['date']?['uts']?.toString() ?? '';
  if (uts.isNotEmpty) {
    final sec = int.tryParse(uts);
    if (sec != null) {
      final dt  = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
      final mon = L.months[dt.month]; // localised month abbreviations
      final h   = dt.hour.toString().padLeft(2, '0');
      final m   = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} $mon · $h:$m';
    }
  }
  return _fmtDate((t['date']?['#text'] ?? '').toString());
}