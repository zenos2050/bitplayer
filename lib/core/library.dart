import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ffmpeg.dart';
import 'models.dart';
import 'platform.dart';
import 'settings.dart';
import 'tags/tag_reader.dart';
import 'tags/tag_writer.dart';

/// Field edits from the Get Info dialog. A null field means "unchanged";
/// an empty string / 0 clears the value.
class TagEdit {
  String? title, artist, albumArtist, album, genre, composer, comment;
  int? year, track, trackTotal, disc, discTotal;

  bool get isEmpty =>
      title == null &&
      artist == null &&
      albumArtist == null &&
      album == null &&
      genre == null &&
      composer == null &&
      comment == null &&
      year == null &&
      track == null &&
      trackTotal == null &&
      disc == null &&
      discTotal == null;

  TagData applyTo(TagData t) {
    if (title != null) t.title = title;
    if (artist != null) t.artist = artist;
    if (albumArtist != null) t.albumArtist = albumArtist;
    if (album != null) t.album = album;
    if (genre != null) t.genre = genre;
    if (composer != null) t.composer = composer;
    if (comment != null) t.comment = comment;
    if (year != null) t.year = year == 0 ? null : year;
    if (track != null) t.track = track == 0 ? null : track;
    if (trackTotal != null) t.trackTotal = trackTotal == 0 ? null : trackTotal;
    if (disc != null) t.disc = disc == 0 ? null : disc;
    if (discTotal != null) t.discTotal = discTotal == 0 ? null : discTotal;
    return t;
  }
}

/// The music library: an index of every audio file under the library folder
/// plus the .m3u8 playlists in `<library>/Playlists`.
///
/// The folder on disk is the source of truth. Files can be added, renamed,
/// moved, retagged or deleted with any other tool; the library picks the
/// changes up on the next scan (automatic on desktop via a folder watcher).
class LibraryService extends ChangeNotifier {
  LibraryService(this.settings);

  final Settings settings;
  final Map<String, Track> _tracks = {};
  List<Playlist> playlists = [];

  bool scanning = false;
  String scanStatus = '';
  double scanProgress = 0;
  int version = 0;

  late File _indexFile;
  StreamSubscription<FileSystemEvent>? _watchSub;
  Timer? _watchDebounce;
  Timer? _saveDebounce;
  bool _rescanRequested = false;
  List<Track>? _sortedCache;

  String get root => settings.libraryPath;
  String get playlistDir => p.join(root, 'Playlists');

  static String _key(String path) =>
      Plat.isWindows ? p.normalize(path).toLowerCase() : p.normalize(path);

  // -------------------------------------------------------------------------
  // Startup / persistence
  // -------------------------------------------------------------------------

  Future<void> init() async {
    _indexFile = File(p.join(settings.supportDir, 'library.json'));
    await _loadIndex();
    await loadPlaylists();
    _changed();
  }

  /// Called after storage permission is available (mobile) or at start.
  Future<void> start() async {
    if (Plat.isDesktop) {
      try {
        await Directory(root).create(recursive: true);
        await Directory(playlistDir).create(recursive: true);
      } catch (_) {}
      _startWatcher();
    }
    await scan();
  }

  Future<void> _loadIndex() async {
    _tracks.clear();
    if (!await _indexFile.exists()) return;
    try {
      final raw = await _indexFile.readAsString();
      final list = await _decodeIndexInIsolate(raw);
      for (final m in list) {
        final t = Track.fromJson(m);
        _tracks[_key(t.path)] = t;
      }
    } catch (_) {
      _tracks.clear();
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), saveIndex);
  }

  Future<void> saveIndex() async {
    final data = _tracks.values.map((t) => t.toJson()).toList();
    try {
      final text = jsonEncode({'version': 1, 'root': root, 'tracks': data});
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      if (await _indexFile.exists()) await _indexFile.delete();
      await tmp.rename(_indexFile.path);
    } catch (_) {}
  }

  void _changed() {
    version++;
    _sortedCache = null;
    notifyListeners();
  }

  /// Switches to a different library folder.
  Future<void> changeRoot(String newRoot) async {
    settings.update((s) => s.libraryPath = newRoot);
    await _watchSub?.cancel();
    _watchSub = null;
    _tracks.clear();
    playlists = [];
    _changed();
    await saveIndex();
    await loadPlaylists();
    await start();
  }

  // -------------------------------------------------------------------------
  // Scanning
  // -------------------------------------------------------------------------

  void _startWatcher() {
    if (!Plat.isWindows && !Plat.isMacOS) return; // recursive watch support
    _watchSub?.cancel();
    try {
      _watchSub = Directory(root).watch(recursive: true).listen((e) {
        final path = e.path;
        if (path.endsWith('.rttmp') ||
            path.endsWith('.rtbak') ||
            path.contains('.rttmp.')) {
          return;
        }
        _watchDebounce?.cancel();
        _watchDebounce = Timer(const Duration(seconds: 3), () {
          scan();
          if (p.isWithin(playlistDir, path) || p.equals(playlistDir, path)) {
            loadPlaylists();
          }
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Incrementally scans the library folder.
  Future<void> scan() async {
    if (scanning) {
      _rescanRequested = true;
      return;
    }
    scanning = true;
    scanStatus = 'Scanning library…';
    scanProgress = 0;
    notifyListeners();
    try {
      final rootPath = root;
      final firstRun = _tracks.isEmpty;
      final listing = await _listInIsolate(rootPath);

      final seen = <String>{};
      final toParse = <_FileStat>[];
      for (final f in listing) {
        final k = _key(f.path);
        seen.add(k);
        final existing = _tracks[k];
        if (existing == null ||
            existing.sizeBytes != f.size ||
            existing.mtimeMs != f.mtime) {
          toParse.add(f);
        }
      }
      // Remove deleted files.
      final removed = _tracks.keys.where((k) => !seen.contains(k)).toList();
      for (final k in removed) {
        _tracks.remove(k);
      }

      const batchSize = 150;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < toParse.length; i += batchSize) {
        final batch = toParse.sublist(
            i, (i + batchSize) > toParse.length ? toParse.length : i + batchSize);
        final paths = batch.map((b) => b.path).toList();
        final sizes = batch.map((b) => b.size).toList();
        final mtimes = batch.map((b) => b.mtime).toList();
        final parsed = await _parseInIsolate(paths, sizes, mtimes);
        for (final m in parsed) {
          final t = Track.fromJson(m);
          final k = _key(t.path);
          final old = _tracks[k];
          if (old != null) {
            t.playCount = old.playCount;
            t.lastPlayedMs = old.lastPlayedMs;
            t.rating = old.rating;
            t.dateAddedMs = old.dateAddedMs;
            if (t.durationMs == 0) t.durationMs = old.durationMs;
          } else {
            t.dateAddedMs = firstRun ? t.mtimeMs : now;
          }
          _tracks[k] = t;
        }
        scanProgress = (i + batch.length) / toParse.length;
        scanStatus = 'Updating library: ${i + batch.length} of ${toParse.length}';
        _changed();
      }
      if (toParse.isNotEmpty || removed.isNotEmpty) {
        _changed();
        _scheduleSave();
      }
    } catch (e) {
      debugPrint('Scan failed: $e');
    } finally {
      scanning = false;
      scanStatus = '';
      notifyListeners();
    }
    if (_rescanRequested) {
      _rescanRequested = false;
      await scan();
    }
  }

  /// Scans specific files right away (after a rip or import).
  Future<void> addOrRefresh(List<String> paths) async {
    final stats = <_FileStat>[];
    for (final path in paths) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final st = f.statSync();
      stats.add(_FileStat(path, st.size, st.modified.millisecondsSinceEpoch));
    }
    if (stats.isEmpty) return;
    final pathsL = stats.map((s) => s.path).toList();
    final sizes = stats.map((s) => s.size).toList();
    final mtimes = stats.map((s) => s.mtime).toList();
    final parsed = await _parseInIsolate(pathsL, sizes, mtimes);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final m in parsed) {
      final t = Track.fromJson(m);
      final old = _tracks[_key(t.path)];
      if (old != null) {
        t.playCount = old.playCount;
        t.lastPlayedMs = old.lastPlayedMs;
        t.rating = old.rating;
        t.dateAddedMs = old.dateAddedMs;
      } else {
        t.dateAddedMs = now;
      }
      _tracks[_key(t.path)] = t;
    }
    _changed();
    _scheduleSave();
  }

  // -------------------------------------------------------------------------
  // Queries
  // -------------------------------------------------------------------------

  int get count => _tracks.length;
  Track? byPath(String path) => _tracks[_key(path)];

  /// All tracks sorted by album artist / album / disc / track.
  List<Track> get allTracks {
    return _sortedCache ??= (_tracks.values.toList()..sort(compareAlbumOrder));
  }

  static int compareAlbumOrder(Track a, Track b) {
    var c = a.displayAlbumArtist
        .toLowerCase()
        .compareTo(b.displayAlbumArtist.toLowerCase());
    if (c != 0) return c;
    c = a.displayAlbum.toLowerCase().compareTo(b.displayAlbum.toLowerCase());
    if (c != 0) return c;
    c = a.discNo.compareTo(b.discNo);
    if (c != 0) return c;
    c = a.trackNo.compareTo(b.trackNo);
    if (c != 0) return c;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  List<Track> smartList(SmartList kind) {
    final all = _tracks.values.toList();
    switch (kind) {
      case SmartList.recentlyAdded:
        all.sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
        return all.take(200).toList();
      case SmartList.recentlyPlayed:
        final played = all.where((t) => t.lastPlayedMs > 0).toList()
          ..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
        return played.take(100).toList();
      case SmartList.topPlayed:
        final played = all.where((t) => t.playCount > 0).toList()
          ..sort((a, b) => b.playCount.compareTo(a.playCount));
        return played.take(25).toList();
    }
  }

  List<Track> playlistTracks(Playlist pl) {
    final out = <Track>[];
    for (final path in pl.paths) {
      final t = byPath(path);
      if (t != null) out.add(t);
    }
    return out;
  }

  List<AlbumInfo> albumsOf(Iterable<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      (map[t.albumKey] ??= []).add(t);
    }
    final out = map.entries.map((e) {
      final list = e.value..sort(compareAlbumOrder);
      final f = list.first;
      return AlbumInfo(e.key, f.displayAlbum, f.displayAlbumArtist,
          list.map((t) => t.year).fold(0, (a, b) => a > b ? a : b), list);
    }).toList();
    out.sort((a, b) {
      final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      return c != 0 ? c : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  int totalDuration(Iterable<Track> t) =>
      t.fold(0, (sum, x) => sum + x.durationMs);
  int totalSize(Iterable<Track> t) => t.fold(0, (sum, x) => sum + x.sizeBytes);

  // -------------------------------------------------------------------------
  // Play statistics
  // -------------------------------------------------------------------------

  void markPlayed(Track t) {
    final lib = byPath(t.path);
    if (lib == null) return;
    lib.playCount++;
    lib.lastPlayedMs = DateTime.now().millisecondsSinceEpoch;
    version++;
    _sortedCache = null;
    notifyListeners();
    _scheduleSave();
  }

  void updateDuration(String path, int ms) {
    final lib = byPath(path);
    if (lib == null || ms <= 0 || (lib.durationMs - ms).abs() < 1500) return;
    lib.durationMs = ms;
    _changed();
    _scheduleSave();
  }

  void setRating(List<Track> tracks, int rating) {
    for (final t in tracks) {
      byPath(t.path)?.rating = rating;
    }
    _changed();
    _scheduleSave();
  }

  // -------------------------------------------------------------------------
  // Editing / organizing
  // -------------------------------------------------------------------------

  /// Applies [edit] to [tracks], writing tags into the files.
  /// Returns a list of human readable errors (empty on success).
  Future<List<String>> editTracks(List<Track> tracks, TagEdit edit,
      {PictureEdit? picture}) async {
    final errors = <String>[];
    final ffmpeg = await Ffmpeg.locate(settings);
    final refreshed = <String>[];
    for (final tr in tracks) {
      final path = tr.path;
      final data = edit.applyTo(tr.toTagData());
      try {
        if (canWriteNatively(path)) {
          await writeTagsInIsolate(path, data, picture);
        } else if (ffmpeg != null) {
          if (!edit.isEmpty) await Ffmpeg.writeTags(ffmpeg, path, data);
          if (picture != null) {
            errors.add('${p.basename(path)}: artwork can only be changed for MP3 and FLAC files.');
          }
        } else {
          errors.add('${p.basename(path)}: editing ${p.extension(path)} files '
              'needs ffmpeg (desktop) — only MP3 and FLAC can be edited here.');
          continue;
        }
        var finalPath = path;
        if (settings.keepOrganized && p.isWithin(root, path)) {
          finalPath = await _organize(path, data);
        }
        refreshed.add(finalPath);
      } catch (e) {
        errors.add('${p.basename(path)}: $e');
      }
    }
    await addOrRefresh(refreshed);
    return errors;
  }

  /// Moves [path] to its organized location; returns the new path.
  Future<String> _organize(String path, TagData t) async {
    final target = organizedPath(root, t, p.extension(path).replaceFirst('.', ''));
    if (p.equals(target, path)) return path;
    final unique = _uniquePath(target, except: path);
    await Directory(p.dirname(unique)).create(recursive: true);
    final old = _tracks.remove(_key(path));
    await File(path).rename(unique);
    if (old != null) {
      old.path = unique;
      _tracks[_key(unique)] = old;
    }
    await _replaceInPlaylists({_key(path): unique});
    await _pruneEmptyDirs(p.dirname(path));
    return unique;
  }

  String _uniquePath(String target, {String? except}) {
    if (!File(target).existsSync()) return target;
    if (except != null && p.equals(target, except)) return target;
    final dir = p.dirname(target);
    final base = p.basenameWithoutExtension(target);
    final ext = p.extension(target);
    for (var i = 2; i < 1000; i++) {
      final c = p.join(dir, '$base $i$ext');
      if (!File(c).existsSync()) return c;
    }
    return target;
  }

  Future<void> _pruneEmptyDirs(String dir) async {
    var d = dir;
    while (p.isWithin(root, d) && !p.equals(d, playlistDir)) {
      final directory = Directory(d);
      try {
        if (!directory.existsSync()) break;
        final entries = directory.listSync();
        // Ignore leftover OS junk files.
        final real = entries.where((e) {
          final n = p.basename(e.path).toLowerCase();
          return n != 'desktop.ini' && n != '.ds_store' && n != 'thumbs.db';
        });
        if (real.isNotEmpty) break;
        for (final e in entries) {
          e.deleteSync();
        }
        directory.deleteSync();
      } catch (_) {
        break;
      }
      d = p.dirname(d);
    }
  }

  /// Copies (or, for files already inside the library, simply indexes)
  /// [sources] — files or folders — into the library.
  Future<int> importPaths(List<String> sources) async {
    final files = <String>[];
    for (final s in sources) {
      if (FileSystemEntity.isDirectorySync(s)) {
        final list = await _listInIsolate(s);
        files.addAll(list.map((f) => f.path));
      } else if (isAudioFile(s)) {
        files.add(s);
      }
    }
    final added = <String>[];
    var done = 0;
    scanning = true;
    for (final f in files) {
      done++;
      scanStatus = 'Importing $done of ${files.length}';
      scanProgress = done / files.length;
      notifyListeners();
      try {
        if (p.isWithin(root, f)) {
          added.add(f);
          continue;
        }
        final tags = await _readTagsForImport(f);
        final target = _uniquePath(
            organizedPath(root, tags, p.extension(f).replaceFirst('.', '')));
        await Directory(p.dirname(target)).create(recursive: true);
        await File(f).copy(target);
        added.add(target);
      } catch (e) {
        debugPrint('Import failed for $f: $e');
      }
    }
    scanning = false;
    scanStatus = '';
    await addOrRefresh(added);
    return added.length;
  }

  /// Removes tracks from the library, optionally deleting the files.
  Future<void> deleteTracks(List<Track> tracks, {required bool deleteFiles}) async {
    final keys = tracks.map((t) => _key(t.path)).toSet();
    for (final t in tracks) {
      _tracks.remove(_key(t.path));
      if (deleteFiles) {
        try {
          await File(t.path).delete();
          await _pruneEmptyDirs(p.dirname(t.path));
        } catch (_) {}
      }
    }
    for (final pl in playlists) {
      final before = pl.paths.length;
      pl.paths.removeWhere((x) => keys.contains(_key(x)));
      if (pl.paths.length != before) await savePlaylist(pl);
    }
    _changed();
    _scheduleSave();
  }

  // -------------------------------------------------------------------------
  // Playlists (.m3u8)
  // -------------------------------------------------------------------------

  Future<void> loadPlaylists() async {
    final dir = Directory(playlistDir);
    final result = <Playlist>[];
    if (await dir.exists()) {
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final ext = p.extension(e.path).toLowerCase();
        if (ext != '.m3u8' && ext != '.m3u') continue;
        try {
          result.add(await _parsePlaylist(e));
        } catch (_) {}
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    playlists = result;
    _changed();
  }

  Future<Playlist> _parsePlaylist(File f) async {
    final bytes = await f.readAsBytes();
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final base = p.dirname(f.path);
    final paths = <String>[];
    for (var line in const LineSplitter().convert(text)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('file://')) {
        try {
          line = Uri.parse(line).toFilePath();
        } catch (_) {}
      }
      final native = line.replaceAll(RegExp(r'[\\/]'), p.separator);
      var full = p.isAbsolute(native) ? native : p.normalize(p.join(base, native));
      if (!File(full).existsSync()) {
        full = _resolveBySuffix(line) ?? full;
      }
      paths.add(full);
    }
    return Playlist(
        name: p.basenameWithoutExtension(f.path), filePath: f.path, paths: paths);
  }

  /// Finds a library track whose path ends with the same Artist/Album/file
  /// segments — makes playlists portable between computers and phones.
  String? _resolveBySuffix(String entry) {
    final segs = entry
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty && s != '..' && s != '.')
        .toList();
    if (segs.isEmpty) return null;
    final tail = segs.sublist(segs.length >= 3 ? segs.length - 3 : 0);
    final suffix = tail.join('/').toLowerCase();
    for (final t in _tracks.values) {
      final norm = t.path.replaceAll('\\', '/').toLowerCase();
      if (norm.endsWith(suffix)) return t.path;
    }
    return null;
  }

  Future<void> savePlaylist(Playlist pl) async {
    await Directory(p.dirname(pl.filePath)).create(recursive: true);
    final sb = StringBuffer('#EXTM3U\n');
    final base = p.dirname(pl.filePath);
    for (final path in pl.paths) {
      final t = byPath(path);
      if (t != null) {
        sb.writeln('#EXTINF:${t.durationMs ~/ 1000},${t.displayArtist} - ${t.title}');
      }
      final rel = p.isWithin(base, path) || p.isWithin(root, path)
          ? p.relative(path, from: base)
          : path;
      sb.writeln(rel.replaceAll('\\', '/'));
    }
    await File(pl.filePath).writeAsString(sb.toString(), encoding: utf8);
    _changed();
  }

  Future<Playlist> createPlaylist(String name, [List<Track> tracks = const []]) async {
    var clean = sanitizeName(name.trim().isEmpty ? 'untitled playlist' : name.trim());
    var path = p.join(playlistDir, '$clean.m3u8');
    var i = 2;
    while (File(path).existsSync()) {
      path = p.join(playlistDir, '$clean $i.m3u8');
      i++;
    }
    final pl = Playlist(
        name: p.basenameWithoutExtension(path),
        filePath: path,
        paths: tracks.map((t) => t.path).toList());
    await savePlaylist(pl);
    playlists = [...playlists, pl]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _changed();
    return pl;
  }

  Future<void> addToPlaylist(Playlist pl, List<Track> tracks) async {
    pl.paths.addAll(tracks.map((t) => t.path));
    await savePlaylist(pl);
  }

  Future<void> removeFromPlaylist(Playlist pl, List<Track> tracks) async {
    final keys = tracks.map((t) => _key(t.path)).toSet();
    pl.paths.removeWhere((x) => keys.contains(_key(x)));
    await savePlaylist(pl);
  }

  Future<void> movePlaylistItem(Playlist pl, int from, int to) async {
    if (from < 0 || from >= pl.paths.length) return;
    final item = pl.paths.removeAt(from);
    pl.paths.insert(to.clamp(0, pl.paths.length), item);
    await savePlaylist(pl);
  }

  Future<void> renamePlaylist(Playlist pl, String name) async {
    final clean = sanitizeName(name);
    final newPath = p.join(p.dirname(pl.filePath), '$clean.m3u8');
    if (p.equals(newPath, pl.filePath) || File(newPath).existsSync()) return;
    await File(pl.filePath).rename(newPath);
    pl.filePath = newPath;
    pl.name = clean;
    await savePlaylist(pl);
    playlists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _changed();
  }

  Future<void> deletePlaylist(Playlist pl) async {
    try {
      await File(pl.filePath).delete();
    } catch (_) {}
    playlists = playlists.where((x) => x != pl).toList();
    _changed();
  }

  Future<void> _replaceInPlaylists(Map<String, String> moves) async {
    for (final pl in playlists) {
      var changed = false;
      for (var i = 0; i < pl.paths.length; i++) {
        final to = moves[_key(pl.paths[i])];
        if (to != null) {
          pl.paths[i] = to;
          changed = true;
        }
      }
      if (changed) await savePlaylist(pl);
    }
  }
}

// ---------------------------------------------------------------------------
// Naming
// ---------------------------------------------------------------------------

const _reserved = {
  'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6',
  'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6',
  'LPT7', 'LPT8', 'LPT9',
};

/// Makes a string safe as a file or folder name on Windows, macOS, Android.
String sanitizeName(String s, {int maxLen = 80}) {
  var out = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  while (out.endsWith('.') || out.endsWith(' ')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.length > maxLen) out = out.substring(0, maxLen).trim();
  if (out.isEmpty) out = 'Unknown';
  if (_reserved.contains(out.toUpperCase())) out = '${out}_';
  return out;
}

/// `<root>/<Album Artist>/<Album>/<D-><NN> <Title>.<ext>`
String organizedPath(String root, TagData t, String ext) {
  String pick(String? a, String fallback) =>
      (a == null || a.trim().isEmpty) ? fallback : a.trim();
  final artist = sanitizeName(pick(t.albumArtist, pick(t.artist, 'Unknown Artist')));
  final album = sanitizeName(pick(t.album, 'Unknown Album'));
  final title = sanitizeName(pick(t.title, 'Untitled'), maxLen: 100);
  var prefix = '';
  final disc = t.disc ?? 0;
  final discTotal = t.discTotal ?? 0;
  if (disc > 0 && (discTotal > 1 || disc > 1)) prefix = '$disc-';
  final track = t.track ?? 0;
  if (track > 0) {
    prefix += '${track.toString().padLeft(2, '0')} ';
  } else {
    prefix = '';
  }
  return p.join(root, artist, album, '$prefix$title.$ext');
}

// ---------------------------------------------------------------------------
// Isolate helpers (top-level so they can run in Isolate.run)
// ---------------------------------------------------------------------------

class _FileStat {
  final String path;
  final int size;
  final int mtime;
  _FileStat(this.path, this.size, this.mtime);
}

List<_FileStat> _listAudioFiles(String rootPath) {
  final out = <_FileStat>[];
  final root = Directory(rootPath);
  if (!root.existsSync()) return out;
  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue; // hidden / macOS resource forks
      if (e is Directory) {
        stack.add(e);
      } else if (e is File && isAudioFile(e.path)) {
        if (e.path.endsWith('.rttmp') || e.path.contains('.rttmp.')) continue;
        try {
          final st = e.statSync();
          out.add(_FileStat(e.path, st.size, st.modified.millisecondsSinceEpoch));
        } catch (_) {}
      }
    }
  }
  return out;
}

List<Map<String, dynamic>> _parseBatch(
    List<String> paths, List<int> sizes, List<int> mtimes) {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < paths.length; i++) {
    final path = paths[i];
    final t = readTags(path);
    final fb = fallbackFromPath(path);
    if (t.title == null || t.title!.trim().isEmpty) t.title = fb.title;
    if (t.isEmpty || (t.artist == null && t.albumArtist == null)) {
      t.artist ??= fb.artist;
    }
    if (t.album == null || t.album!.trim().isEmpty) t.album = fb.album;
    t.track ??= fb.track;
    t.disc ??= fb.disc;
    final tr = Track(path: path, sizeBytes: sizes[i], mtimeMs: mtimes[i])
      ..applyTags(t);
    out.add(tr.toJson());
  }
  return out;
}

// Isolate entry points live at top level so their closures capture nothing
// but their arguments (capturing `this` would make them unsendable).

Future<List<Map<String, dynamic>>> _decodeIndexInIsolate(String raw) =>
    Isolate.run(() {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['tracks'] as List).cast<Map<String, dynamic>>();
    });

Future<List<_FileStat>> _listInIsolate(String root) =>
    Isolate.run(() => _listAudioFiles(root));

Future<List<Map<String, dynamic>>> _parseInIsolate(
        List<String> paths, List<int> sizes, List<int> mtimes) =>
    Isolate.run(() => _parseBatch(paths, sizes, mtimes));

Future<void> writeTagsInIsolate(String path, TagData data, PictureEdit? picture) =>
    Isolate.run(() => writeTagsNative(path, data, picture: picture));

Future<TagData> _readTagsForImport(String f) => Isolate.run(() {
      final t = readTags(f);
      final fb = fallbackFromPath(f);
      t.title ??= fb.title;
      t.artist ??= fb.artist;
      t.album ??= fb.album;
      t.track ??= fb.track;
      return t;
    });
