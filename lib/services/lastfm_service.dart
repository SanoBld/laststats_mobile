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

  // ── Monthly scrobble counts ──────────────────────────────
  Future<Map<String, int>> getMonthlyScrobbles({int months = 12}) async {
    final now   = DateTime.now();
    final keys  = <String>[];
    final futs  = <Future>[];

    for (var i = months - 1; i >= 0; i--) {
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

  // ── Artist info (global + user context) ─────────────────
  Future<Map<String, dynamic>?> getArtistInfo(String artist) async {
    try {
      final d = await _call({
        'method':   'artist.getInfo',
        'artist':   artist,
        'username': username,
        'lang':     'fr',
        'autocorrect': '1',
      });
      return d['artist'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<int?> getArtistListeners(String artist) async {
    final info = await getArtistInfo(artist);
    return int.tryParse(info?['stats']?['listeners']?.toString() ?? '');
  }

  // ── Artist top tracks (global) ───────────────────────────
  Future<List<dynamic>> getArtistTopTracks(String artist, {int limit = 10}) async {
    try {
      final d = await _call({
        'method':      'artist.getTopTracks',
        'artist':      artist,
        'limit':       '$limit',
        'autocorrect': '1',
      });
      return _asList(d['toptracks']?['track']);
    } catch (_) {
      return [];
    }
  }

  // ── Artist top albums (global) ───────────────────────────
  Future<List<dynamic>> getArtistTopAlbums(String artist, {int limit = 10}) async {
    try {
      final d = await _call({
        'method':      'artist.getTopAlbums',
        'artist':      artist,
        'limit':       '$limit',
        'autocorrect': '1',
      });
      return _asList(d['topalbums']?['album']);
    } catch (_) {
      return [];
    }
  }

  // ── Artist top tags (global) ────────────────────────────
  Future<List<dynamic>> getArtistTopTags(String artist) async {
    try {
      final d = await _call({
        'method':      'artist.getTopTags',
        'artist':      artist,
        'autocorrect': '1',
      });
      final tags = d['toptags']?['tag'];
      if (tags == null) return [];
      return tags is List ? tags : [tags];
    } catch (_) {
      return [];
    }
  }

  // ── Album info (global + user context) ──────────────────
  Future<Map<String, dynamic>?> getAlbumInfo(String album, String artist) async {
    try {
      final d = await _call({
        'method':   'album.getInfo',
        'album':    album,
        'artist':   artist,
        'username': username,
        'lang':     'fr',
        'autocorrect': '1',
      });
      return d['album'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Track info (global + user context) ──────────────────
  Future<Map<String, dynamic>?> getTrackInfo(String track, String artist) async {
    try {
      final d = await _call({
        'method':   'track.getInfo',
        'track':    track,
        'artist':   artist,
        'username': username,
        'autocorrect': '1',
      });
      return d['track'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // ── Friends ─────────────────────────────────────────────
  /// Returns the friend list of [username].
  /// Pass [withRecentTrack] = true to include each friend's most recent
  /// (or currently playing) track in the response — saves extra requests.
  Future<List<dynamic>> getFriends({
    int  limit          = 50,
    int  page           = 1,
    bool withRecentTrack = true,
  }) async {
    final d = await _call({
      'method':       'user.getFriends',
      'user':         username,
      'limit':        '$limit',
      'page':         '$page',
      'recenttracks': withRecentTrack ? '1' : '0',
    });
    return _asList(d['friends']?['user']);
  }

  // ── User rank for an item over a period ─────────────────
  /// Returns (rank, playcount) for an artist/album/track in user's top-200.
  Future<({int rank, int plays})> getUserItemStats({
    required String type,   // 'artists' | 'albums' | 'tracks'
    required String name,
    String artistName = '',
    String period    = 'overall',
  }) async {
    final List<dynamic> items;
    if (type == 'artists') {
      items = await getTopArtists(period: period, limit: 200);
    } else if (type == 'albums') {
      items = await getTopAlbums(period: period, limit: 200);
    } else {
      items = await getTopTracks(period: period, limit: 200);
    }

    for (var i = 0; i < items.length; i++) {
      final n = (items[i]['name'] ?? '').toString();
      final a = type != 'artists' ? (items[i]['artist']?['name'] ?? '').toString() : '';
      final match = n == name && (type == 'artists' || a == artistName);
      if (match) {
        final plays = int.tryParse((items[i]['playcount'] ?? '0').toString()) ?? 0;
        return (rank: i + 1, plays: plays);
      }
    }
    return (rank: -1, plays: 0);
  }

  // ── Global search ────────────────────────────────────────

  /// Searches Last.fm users by username.
  /// Tries user.search first; falls back to user.getInfo for exact matching
  /// (user.search is notoriously unreliable and often returns empty).
  Future<List<dynamic>> searchUsers(
    String query, {
    int limit = 15,
    int page  = 1,
  }) async {
    try {
      final d = await _call({
        'method': 'user.search',
        'user':   query,
        'limit':  '$limit',
        'page':   '$page',
      });
      final raw = d['results']?['usermatches']?['user'];
      // Last.fm returns "" (empty string) when there are no results
      if (raw == null || raw is String) { return await _searchUserFallback(query); }
      final list = _asList(raw);
      final results = list.whereType<Map>().toList();
      // If search returned nothing, try exact match via user.getInfo
      if (results.isEmpty) { return await _searchUserFallback(query); }
      return results;
    } on Exception catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('no user') || msg.contains('not found') ||
          msg.contains('http 400') || msg.contains('http 403')) {
        return await _searchUserFallback(query);
      }
      rethrow;
    }
  }

  /// Fallback: looks up a user by exact username via user.getInfo.
  /// Returns a single-element list on success, or [] if not found.
  Future<List<dynamic>> _searchUserFallback(String query) async {
    try {
      final info = await getUserInfo(user: query);
      if (info == null) return [];
      return [info];
    } catch (_) {
      return [];
    }
  }

  /// Searches artists globally via artist.search.
  Future<List<dynamic>> searchArtists(
    String query, {
    int limit = 15,
    int page  = 1,
  }) async {
    final d = await _call({
      'method': 'artist.search',
      'artist': query,
      'limit':  '$limit',
      'page':   '$page',
    });
    return _asList(d['results']?['artistmatches']?['artist']);
  }

  /// Searches albums globally via album.search.
  Future<List<dynamic>> searchAlbums(
    String query, {
    int limit = 15,
    int page  = 1,
  }) async {
    final d = await _call({
      'method': 'album.search',
      'album':  query,
      'limit':  '$limit',
      'page':   '$page',
    });
    return _asList(d['results']?['albummatches']?['album']);
  }

  /// Searches tracks globally via track.search.
  Future<List<dynamic>> searchTracks(
    String query, {
    int limit = 15,
    int page  = 1,
  }) async {
    final d = await _call({
      'method': 'track.search',
      'track':  query,
      'limit':  '$limit',
      'page':   '$page',
    });
    return _asList(d['results']?['trackmatches']?['track']);
  }
}