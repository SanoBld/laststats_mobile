import 'dart:convert';
import 'package:http/http.dart' as http;

class LastFmService {
  final String apiKey;
  final String username;

  static const _host    = 'ws.audioscrobbler.com';
  static const _path    = '/2.0/';
  static const _timeout = Duration(seconds: 15);

  const LastFmService({required this.apiKey, required this.username});

  // ── Core request ────────────────────────────────────────
  Future<dynamic> _call(Map<String, String> params) async {
    final uri = Uri.https(_host, _path, {
      ...params,
      'api_key': apiKey,
      'format':  'json',
    });
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body['error'] != null) {
      throw Exception(body['message'] ?? 'Erreur API Last.fm');
    }
    return body;
  }

  static List<dynamic> _asList(dynamic v) =>
      v == null ? [] : (v is List ? v : [v]);

  // ── User ────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getUserInfo({String? user}) async {
    final d = await _call({'method': 'user.getInfo', 'user': user ?? username});
    return d['user'] as Map<String, dynamic>?;
  }

  // ── Top lists ───────────────────────────────────────────
  Future<List<dynamic>> getTopArtists({
    String period = 'overall',
    int limit = 50,
    int page = 1,
    String? user,
  }) async {
    final d = await _call({
      'method': 'user.getTopArtists',
      'user':   user ?? username,
      'period': period,
      'limit':  '$limit',
      'page':   '$page',
    });
    return _asList(d['topartists']?['artist']);
  }

  Future<List<dynamic>> getTopAlbums({
    String period = 'overall',
    int limit = 50,
    int page = 1,
    String? user,
  }) async {
    final d = await _call({
      'method': 'user.getTopAlbums',
      'user':   user ?? username,
      'period': period,
      'limit':  '$limit',
      'page':   '$page',
    });
    return _asList(d['topalbums']?['album']);
  }

  Future<List<dynamic>> getTopTracks({
    String period = 'overall',
    int limit = 50,
    int page = 1,
    String? user,
  }) async {
    final d = await _call({
      'method': 'user.getTopTracks',
      'user':   user ?? username,
      'period': period,
      'limit':  '$limit',
      'page':   '$page',
    });
    return _asList(d['toptracks']?['track']);
  }

  // ── Recent tracks ───────────────────────────────────────
  Future<Map<String, dynamic>> getRecentTracks({
    int limit = 50,
    int page  = 1,
    int? from,
    int? to,
    String? user,
  }) async {
    final p = <String, String>{
      'method': 'user.getRecentTracks',
      'user':   user ?? username,
      'limit':  '$limit',
      'page':   '$page',
    };
    if (from != null) p['from'] = '$from';
    if (to   != null) p['to']   = '$to';
    final d = await _call(p);
    return (d['recenttracks'] as Map<String, dynamic>?) ?? {};
  }

  /// Returns the currently playing track, or null if nothing is playing.
  Future<Map<String, dynamic>?> getNowPlaying() async {
    try {
      final d      = await getRecentTracks(limit: 1);
      final tracks = _asList(d['track']);
      if (tracks.isEmpty) return null;
      final first = tracks.first as Map<String, dynamic>;
      return first['@attr']?['nowplaying'] == 'true' ? first : null;
    } catch (_) {
      return null;
    }
  }

  // ── Monthly scrobble counts (12 parallel requests) ──────
  Future<Map<String, int>> getMonthlyScrobbles({int months = 12}) async {
    final now   = DateTime.now();
    final keys  = <String>[];
    final futs  = <Future>[];

    for (var i = months - 1; i >= 0; i--) {
      // Dart handles month underflow correctly (e.g. month 0 → December)
      final from = DateTime(now.year, now.month - i,     1);
      final to   = DateTime(now.year, now.month - i + 1, 1);
      keys.add('${from.year}-${from.month.toString().padLeft(2, '0')}');
      futs.add(
        _call({
          'method': 'user.getRecentTracks',
          'user':   username,
          'from':   '${from.millisecondsSinceEpoch ~/ 1000}',
          'to':     '${to.millisecondsSinceEpoch   ~/ 1000}',
          'limit':  '1',
        }).catchError((_) => <String, dynamic>{}),
      );
    }

    final results = await Future.wait(futs);
    return {
      for (var i = 0; i < keys.length; i++)
        keys[i]: int.tryParse(
          ((results[i] as Map?))?['recenttracks']?['@attr']?['total']
              ?.toString() ?? '0',
        ) ?? 0,
    };
  }

  // ── Loved tracks ────────────────────────────────────────
  Future<List<dynamic>> getLovedTracks({int limit = 50}) async {
    final d = await _call({
      'method': 'user.getLovedTracks',
      'user':   username,
      'limit':  '$limit',
    });
    return _asList(d['lovedtracks']?['track']);
  }

  // ── Artist info (Mainstream vs Gems) ────────────────────
  Future<int?> getArtistListeners(String artist) async {
    try {
      final d = await _call({
        'method':   'artist.getInfo',
        'artist':   artist,
        'username': username,
      });
      return int.tryParse(
          d['artist']?['stats']?['listeners']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }
}
