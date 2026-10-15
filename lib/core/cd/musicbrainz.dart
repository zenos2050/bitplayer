// CD track-name lookup via MusicBrainz (the free successor to Gracenote /
// CDDB that iTunes used) plus album art from the Cover Art Archive.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cd_models.dart';

class MusicBrainz {
  static const _ua = 'BitPlayer/1.0 ( personal music player; https://musicbrainz.org )';
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// MusicBrainz allows ~1 request/second.
  static Future<void> _throttle() async {
    final wait = const Duration(milliseconds: 1100) - DateTime.now().difference(_last);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
  }

  static Future<(int, List<int>)> _get(Uri uri, {bool json = true}) async {
    await _throttle();
    final client = HttpClient()
      ..userAgent = _ua
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      if (json) req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      return (res.statusCode, bytes);
    } finally {
      client.close(force: true);
    }
  }

  static String _credit(Object? credits) {
    if (credits is! List) return '';
    return credits
        .cast<Map>()
        .map((c) => '${c['name'] ?? ''}${c['joinphrase'] ?? ''}')
        .join()
        .trim();
  }

  /// Looks up [disc]; returns candidate releases (best first).
  static Future<List<MbRelease>> lookup(CdDisc disc) async {
    final id = disc.musicBrainzId;
    final uri = Uri.parse('https://musicbrainz.org/ws/2/discid/$id'
        '?toc=${disc.musicBrainzToc}&inc=recordings+artist-credits&fmt=json');
    final (status, body) = await _get(uri);
    if (status == 404) return [];
    if (status != 200) throw HttpException('MusicBrainz returned HTTP $status');
    final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    final releases = (j['releases'] as List?) ?? const [];
    final audioCount = disc.audioTracks.length;
    final out = <MbRelease>[];
    for (final r in releases.cast<Map<String, dynamic>>()) {
      final media = ((r['media'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (media.isEmpty) continue;
      Map<String, dynamic>? medium;
      for (final m in media) {
        final discs = ((m['discs'] as List?) ?? const []).cast<Map>();
        if (discs.any((d) => d['id'] == id)) {
          medium = m;
          break;
        }
      }
      medium ??= media.firstWhere(
          (m) => (m['track-count'] ?? (m['tracks'] as List?)?.length) == audioCount,
          orElse: () => media.first);
      final albumArtist = _credit(r['artist-credit']);
      final tracks = <MbTrack>[];
      for (final t in ((medium['tracks'] as List?) ?? const []).cast<Map>()) {
        final title = (t['title'] ?? (t['recording'] as Map?)?['title'] ?? '') as String;
        var artist = _credit(t['artist-credit']);
        if (artist.isEmpty) artist = _credit((t['recording'] as Map?)?['artist-credit']);
        tracks.add(MbTrack(title, artist.isEmpty ? albumArtist : artist));
      }
      final date = (r['date'] ?? '') as String;
      out.add(MbRelease(
        id: r['id'] as String,
        title: (r['title'] ?? '') as String,
        artist: albumArtist,
        year: date.length >= 4 ? (int.tryParse(date.substring(0, 4)) ?? 0) : 0,
        country: (r['country'] ?? '') as String,
        discNo: (medium['position'] as int?) ?? 1,
        discTotal: media.length,
        tracks: tracks,
      ));
    }
    return out;
  }

  /// Most-voted genre for a release (release or release-group level).
  static Future<String?> genre(String releaseId) async {
    try {
      final (status, body) = await _get(Uri.parse(
          'https://musicbrainz.org/ws/2/release/$releaseId?inc=genres+release-groups&fmt=json'));
      if (status != 200) return null;
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      List genres = (j['genres'] as List?) ?? const [];
      if (genres.isEmpty) {
        genres = ((j['release-group'] as Map?)?['genres'] as List?) ?? const [];
      }
      if (genres.isEmpty) {
        // Fall back to a release-group lookup with genres.
        final rgId = (j['release-group'] as Map?)?['id'];
        if (rgId != null) {
          final (s2, b2) = await _get(Uri.parse(
              'https://musicbrainz.org/ws/2/release-group/$rgId?inc=genres&fmt=json'));
          if (s2 == 200) {
            genres = ((jsonDecode(utf8.decode(b2)) as Map)['genres'] as List?) ?? const [];
          }
        }
      }
      if (genres.isEmpty) return null;
      final sorted = genres.cast<Map>().toList()
        ..sort((a, b) => ((b['count'] ?? 0) as int).compareTo((a['count'] ?? 0) as int));
      final name = (sorted.first['name'] ?? '') as String;
      if (name.isEmpty) return null;
      // Title case: "alternative rock" -> "Alternative Rock"
      return name
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
    } catch (_) {
      return null;
    }
  }

  /// Front cover (500px) from the Cover Art Archive.
  static Future<Uint8List?> cover(String releaseId) async {
    try {
      final client = HttpClient()
        ..userAgent = _ua
        ..connectionTimeout = const Duration(seconds: 15);
      try {
        final req = await client
            .getUrl(Uri.parse('https://coverartarchive.org/release/$releaseId/front-500'));
        req.followRedirects = true;
        req.maxRedirects = 8;
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) return null;
        final b = BytesBuilder(copy: false);
        await for (final c in res) {
          b.add(c);
        }
        final bytes = b.takeBytes();
        return bytes.isEmpty ? null : bytes;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }
}
