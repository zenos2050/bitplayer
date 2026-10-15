import 'dart:typed_data';

/// Tag values read from (or written to) an audio file.
class TagData {
  String? title;
  String? artist;
  String? albumArtist;
  String? album;
  String? genre;
  int? year;
  int? track;
  int? trackTotal;
  int? disc;
  int? discTotal;
  String? composer;
  String? comment;

  /// Duration in milliseconds, 0 if unknown.
  int durationMs;

  /// True if the file carries embedded cover art.
  bool hasArt;

  /// Embedded picture (only filled when explicitly requested).
  Uint8List? picture;
  String? pictureMime;

  TagData({
    this.title,
    this.artist,
    this.albumArtist,
    this.album,
    this.genre,
    this.year,
    this.track,
    this.trackTotal,
    this.disc,
    this.discTotal,
    this.composer,
    this.comment,
    this.durationMs = 0,
    this.hasArt = false,
    this.picture,
    this.pictureMime,
  });

  bool get isEmpty =>
      _blank(title) && _blank(artist) && _blank(album) && _blank(albumArtist);

  static bool _blank(String? s) => s == null || s.trim().isEmpty;
}

/// A song in the library (or on an audio CD / in the play queue).
class Track {
  /// Absolute file path, or a URI for CD tracks.
  String path;
  String title;
  String artist;
  String albumArtist;
  String album;
  String genre;
  int year;
  int trackNo;
  int trackTotal;
  int discNo;
  int discTotal;
  String composer;
  String comment;
  int durationMs;
  int sizeBytes;
  int mtimeMs;
  bool hasArt;

  // Library-only data (not stored in the file).
  int playCount;
  int lastPlayedMs;
  int dateAddedMs;
  int rating; // 0..5 stars

  /// Set for tracks that are played straight from an audio CD.
  bool isCd;

  Track({
    required this.path,
    this.title = '',
    this.artist = '',
    this.albumArtist = '',
    this.album = '',
    this.genre = '',
    this.year = 0,
    this.trackNo = 0,
    this.trackTotal = 0,
    this.discNo = 0,
    this.discTotal = 0,
    this.composer = '',
    this.comment = '',
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.mtimeMs = 0,
    this.hasArt = false,
    this.playCount = 0,
    this.lastPlayedMs = 0,
    this.dateAddedMs = 0,
    this.rating = 0,
    this.isCd = false,
  });

  String get displayArtist => artist.isNotEmpty
      ? artist
      : (albumArtist.isNotEmpty ? albumArtist : 'Unknown Artist');
  String get displayAlbumArtist => albumArtist.isNotEmpty
      ? albumArtist
      : (artist.isNotEmpty ? artist : 'Unknown Artist');
  String get displayAlbum => album.isNotEmpty ? album : 'Unknown Album';
  String get displayGenre => genre.isNotEmpty ? genre : 'Unknown';

  /// Key used to group tracks into albums.
  String get albumKey =>
      '${displayAlbumArtist.toLowerCase()}\u0000${displayAlbum.toLowerCase()}';

  String get extension {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1).toLowerCase();
  }

  String get kind {
    switch (extension) {
      case 'mp3':
        return 'MPEG audio file';
      case 'm4a':
      case 'm4b':
      case 'mp4':
      case 'aac':
        return 'AAC / Apple audio file';
      case 'flac':
        return 'FLAC audio file';
      case 'ogg':
      case 'oga':
        return 'Ogg Vorbis file';
      case 'opus':
        return 'Opus audio file';
      case 'wav':
        return 'WAV audio file';
      case 'aif':
      case 'aiff':
      case 'aifc':
        return 'AIFF audio file';
      case 'wma':
        return 'Windows Media audio file';
      default:
        return isCd ? 'Audio CD track' : '${extension.toUpperCase()} audio file';
    }
  }

  void applyTags(TagData t) {
    title = t.title?.trim() ?? '';
    artist = t.artist?.trim() ?? '';
    albumArtist = t.albumArtist?.trim() ?? '';
    album = t.album?.trim() ?? '';
    genre = t.genre?.trim() ?? '';
    year = t.year ?? 0;
    trackNo = t.track ?? 0;
    trackTotal = t.trackTotal ?? 0;
    discNo = t.disc ?? 0;
    discTotal = t.discTotal ?? 0;
    composer = t.composer?.trim() ?? '';
    comment = t.comment?.trim() ?? '';
    if (t.durationMs > 0) durationMs = t.durationMs;
    hasArt = t.hasArt;
  }

  TagData toTagData() => TagData(
        title: title,
        artist: artist,
        albumArtist: albumArtist,
        album: album,
        genre: genre,
        year: year == 0 ? null : year,
        track: trackNo == 0 ? null : trackNo,
        trackTotal: trackTotal == 0 ? null : trackTotal,
        disc: discNo == 0 ? null : discNo,
        discTotal: discTotal == 0 ? null : discTotal,
        composer: composer,
        comment: comment,
        durationMs: durationMs,
        hasArt: hasArt,
      );

  Map<String, dynamic> toJson() => {
        'p': path,
        't': title,
        'a': artist,
        'aa': albumArtist,
        'al': album,
        'g': genre,
        'y': year,
        'tn': trackNo,
        'tt': trackTotal,
        'dn': discNo,
        'dt': discTotal,
        'c': composer,
        'cm': comment,
        'd': durationMs,
        's': sizeBytes,
        'm': mtimeMs,
        'art': hasArt,
        'pc': playCount,
        'lp': lastPlayedMs,
        'da': dateAddedMs,
        'r': rating,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        path: j['p'] as String,
        title: (j['t'] ?? '') as String,
        artist: (j['a'] ?? '') as String,
        albumArtist: (j['aa'] ?? '') as String,
        album: (j['al'] ?? '') as String,
        genre: (j['g'] ?? '') as String,
        year: (j['y'] ?? 0) as int,
        trackNo: (j['tn'] ?? 0) as int,
        trackTotal: (j['tt'] ?? 0) as int,
        discNo: (j['dn'] ?? 0) as int,
        discTotal: (j['dt'] ?? 0) as int,
        composer: (j['c'] ?? '') as String,
        comment: (j['cm'] ?? '') as String,
        durationMs: (j['d'] ?? 0) as int,
        sizeBytes: (j['s'] ?? 0) as int,
        mtimeMs: (j['m'] ?? 0) as int,
        hasArt: (j['art'] ?? false) as bool,
        playCount: (j['pc'] ?? 0) as int,
        lastPlayedMs: (j['lp'] ?? 0) as int,
        dateAddedMs: (j['da'] ?? 0) as int,
        rating: (j['r'] ?? 0) as int,
      );
}

/// A user playlist, stored as an .m3u8 file in `<library>/Playlists`.
class Playlist {
  String name;
  String filePath;
  List<String> paths;

  Playlist({required this.name, required this.filePath, List<String>? paths})
      : paths = paths ?? [];
}

/// Built-in "smart" lists shown in the source list.
enum SmartList { recentlyAdded, recentlyPlayed, topPlayed }

/// Summary of an album, used by album grids.
class AlbumInfo {
  final String key;
  final String title;
  final String artist;
  final int year;
  final List<Track> tracks;
  AlbumInfo(this.key, this.title, this.artist, this.year, this.tracks);
}

String formatDuration(int ms, {bool forceHours = false}) {
  if (ms <= 0) return '0:00';
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0 || forceHours) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// "3.2 days" / "5:12:30" style total time used in the status bar.
String formatTotalTime(int ms) {
  final hours = ms / 3600000.0;
  if (hours >= 24) return '${(hours / 24).toStringAsFixed(1)} days';
  if (hours >= 1) return '${hours.toStringAsFixed(1)} hours';
  return '${(ms / 60000).toStringAsFixed(0)} minutes';
}
