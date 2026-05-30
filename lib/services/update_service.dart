import 'dart:convert';
import 'package:http/http.dart' as http;

// ══════════════════════════════════════════════════════════════════════════
//  UpdateService — checks for new versions via GitHub Releases
//
//  👉 Set [_repo] to your GitHub repository.
//     Releases must be tagged as "v1.2.3".
// ══════════════════════════════════════════════════════════════════════════

class UpdateService {
  UpdateService._();

  // ─── Set to your own repository ───────────────────────────────────────
  static const _repo           = 'sanobld/LastStats';        // owner/repo
  static const currentVersion  = '2.6.0';                   // current version
  // ───────────────────────────────────────────────────────────────────────

  static const _timeout = Duration(seconds: 10);

  /// Returns an [UpdateInfo] if a newer version exists,
  /// or `null` if the app is up to date (or on network error).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/$_repo/releases/latest',
      );
      final res = await http.get(uri, headers: {
        'Accept': 'application/vnd.github.v3+json',
      }).timeout(_timeout);

      if (res.statusCode != 200) return null;

      final data   = jsonDecode(utf8.decode(res.bodyBytes));
      final tag    = (data['tag_name'] ?? '').toString();
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;

      if (latest.isEmpty) return null;
      if (!_isNewer(latest, currentVersion)) return null;

      // Get the URL of the first .apk asset if it exists
      String? apkUrl;
      final assets = data['assets'] as List?;
      if (assets != null) {
        for (final asset in assets) {
          final name = (asset['name'] ?? '').toString().toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = (asset['browser_download_url'] ?? '').toString();
            break;
          }
        }
      }

      return UpdateInfo(
        version:    latest,
        releaseUrl: (data['html_url']  ?? '').toString(),
        apkUrl:     apkUrl,
        notes:      (data['body']      ?? '').toString(),
        publishedAt: _parseDate(data['published_at']?.toString()),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Compare semver X.Y.Z ───────────────────────────────────────────────
  static bool _isNewer(String latest, String current) {
    final l = _parts(latest);
    final c = _parts(current);
    for (var i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.split('.').map((s) => int.tryParse(s) ?? 0).toList();

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try { return DateTime.parse(s); } catch (_) { return null; }
  }
}

// ══════════════════════════════════════════════════════════════════════════

class UpdateInfo {
  final String    version;
  final String    releaseUrl;
  final String?   apkUrl;
  final String    notes;
  final DateTime? publishedAt;

  const UpdateInfo({
    required this.version,
    required this.releaseUrl,
    this.apkUrl,
    required this.notes,
    this.publishedAt,
  });

  bool get hasApk => apkUrl != null && apkUrl!.isNotEmpty;
}