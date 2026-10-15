import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../artwork.dart';
import '../ffmpeg.dart';
import '../library.dart';
import '../models.dart';
import '../platform.dart';
import '../settings.dart';
import 'cd_macos.dart';
import 'cd_models.dart';
import 'cd_server.dart';
import 'cd_windows.dart';
import 'musicbrainz.dart';

enum RipState { none, queued, ripping, done, error }

/// A disc in a drive plus the (editable) track info shown in the CD view.
class CdDiscState {
  CdDiscState(this.disc, this.tracks)
      : include = List.filled(tracks.length, true),
        ripState = List.filled(tracks.length, RipState.none);

  final CdDisc disc;
  final List<Track> tracks;
  final List<bool> include;
  final List<RipState> ripState;

  List<MbRelease> releases = [];
  int releaseIndex = 0;
  String albumArtist = '';
  String album = '';
  String genre = '';
  int year = 0;
  int discNo = 1;
  int discTotal = 1;
  String? coverPath;
  bool lookingUp = false;
  String? lookupMessage;

  String get title => album.isNotEmpty ? album : 'Audio CD';

  TagData tagsFor(int i) {
    final t = tracks[i];
    return TagData(
      title: t.title,
      artist: t.artist.isNotEmpty ? t.artist : albumArtist,
      albumArtist: albumArtist,
      album: album,
      genre: genre,
      year: year > 0 ? year : null,
      track: t.trackNo,
      trackTotal: tracks.length,
      disc: discTotal > 1 ? discNo : null,
      discTotal: discTotal > 1 ? discTotal : null,
    );
  }
}

/// Detects audio CDs, looks up track names, plays and imports (rips) them.
class CdService extends ChangeNotifier {
  CdService(this.settings, this.library, this.artwork);

  final Settings settings;
  final LibraryService library;
  final ArtworkCache artwork;

  final List<CdDiscState> discs = [];
  Timer? _poll;
  bool _polling = false;

  // Import progress (shown in the LCD).
  bool importing = false;
  String importTitle = '';
  double importFraction = 0;
  double importSpeed = 0; // x realtime
  Duration importRemaining = Duration.zero;
  String? importError;
  SendPort? _cancelPort;
  Process? _macProc;
  bool _cancelRequested = false;

  void start() {
    if (!Plat.supportsCd) return;
    _scan();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _scan());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_polling) return;
    _polling = true;
    try {
      final found = await _scanInIsolate(Plat.isWindows);
      final ids = found.map((d) => d.identity).toSet();
      var changed = false;
      discs.removeWhere((s) {
        final gone = !ids.contains(s.disc.identity);
        if (gone) changed = true;
        return gone;
      });
      for (final d in found) {
        if (discs.any((s) => s.disc.identity == d.identity)) continue;
        final st = await _newState(d);
        discs.add(st);
        changed = true;
        if (settings.autoLookupCd) lookup(st);
      }
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('CD scan failed: $e');
    } finally {
      _polling = false;
    }
  }

  Future<CdDiscState> _newState(CdDisc d) async {
    int? port;
    if (Plat.isWindows) port = await CdStreamServer.ensureStarted();
    final tracks = <Track>[];
    for (final t in d.audioTracks) {
      final uri = Plat.isWindows
          ? CdStreamServer.trackUrl(port!, d.drive, t.startLba, t.lengthSectors)
          : (t.filePath ?? '');
      tracks.add(Track(
        path: uri,
        title: 'Track ${t.number}',
        trackNo: t.number,
        durationMs: t.durationMs,
        isCd: true,
      ));
    }
    return CdDiscState(d, tracks);
  }

  // -------------------------------------------------------------------------
  // Track names
  // -------------------------------------------------------------------------

  Future<void> lookup(CdDiscState st) async {
    st.lookingUp = true;
    st.lookupMessage = 'Getting track names…';
    notifyListeners();
    try {
      final releases = await MusicBrainz.lookup(st.disc);
      st.releases = releases;
      if (releases.isEmpty) {
        st.lookupMessage = 'No match found on MusicBrainz. Enter the names '
            'yourself, or submit this disc at musicbrainz.org.';
      } else {
        st.lookupMessage = null;
        await applyRelease(st, 0);
      }
    } catch (e) {
      st.lookupMessage = 'Could not reach MusicBrainz ($e).';
    } finally {
      st.lookingUp = false;
      notifyListeners();
    }
  }

  Future<void> applyRelease(CdDiscState st, int index) async {
    if (index < 0 || index >= st.releases.length) return;
    final r = st.releases[index];
    st.releaseIndex = index;
    st.albumArtist = r.artist;
    st.album = r.title;
    st.year = r.year;
    st.discNo = r.discNo;
    st.discTotal = r.discTotal;
    for (var i = 0; i < st.tracks.length; i++) {
      final t = st.tracks[i];
      final mb = i < r.tracks.length ? r.tracks[i] : null;
      if (mb != null) {
        t.title = mb.title;
        t.artist = mb.artist;
      }
      t.album = r.title;
      t.albumArtist = r.artist;
      t.year = r.year;
      t.trackTotal = st.tracks.length;
    }
    notifyListeners();

    final genre = await MusicBrainz.genre(r.id);
    if (genre != null && st.genre.isEmpty) setAlbumField(st, genre: genre);

    final cover = await MusicBrainz.cover(r.id);
    if (cover != null) {
      final dir = Directory(p.join(settings.supportDir, 'cdart'));
      await dir.create(recursive: true);
      final f = File(p.join(dir.path, '${r.id}.jpg'));
      await f.writeAsBytes(cover, flush: true);
      st.coverPath = f.path;
      for (final t in st.tracks) {
        artwork.overrides[t.path] = f.path;
      }
    }
    notifyListeners();
  }

  void setAlbumField(CdDiscState st,
      {String? artist, String? album, String? genre, int? year}) {
    if (artist != null) st.albumArtist = artist;
    if (album != null) st.album = album;
    if (genre != null) st.genre = genre;
    if (year != null) st.year = year;
    for (final t in st.tracks) {
      if (artist != null && (t.artist.isEmpty || t.artist == t.albumArtist)) {
        t.artist = artist;
      }
      t.albumArtist = st.albumArtist;
      t.album = st.album;
      t.genre = st.genre;
      t.year = st.year;
    }
    notifyListeners();
  }

  void setCover(CdDiscState st, String path) {
    st.coverPath = path;
    for (final t in st.tracks) {
      artwork.overrides[t.path] = path;
    }
    notifyListeners();
  }

  void touch() => notifyListeners();

  Future<void> eject(CdDiscState st) async {
    if (Plat.isWindows) {
      await _ejectInIsolate(st.disc.drive);
    } else {
      await macEject(st.disc.drive);
    }
    discs.remove(st);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Import (rip)
  // -------------------------------------------------------------------------

  /// Rips the checked tracks of [st] into the library.
  /// Returns an error message, or null on success.
  Future<String?> importDisc(CdDiscState st, {List<int>? only}) async {
    if (importing) return 'An import is already in progress.';
    final format = settings.ripFormat;
    final ffmpeg = await Ffmpeg.locate(settings);
    if (ffmpeg == null && format != RipFormat.wav) {
      return 'ffmpeg was not found. RetroTunes uses ffmpeg to encode '
          '${format.label.replaceAll(' Encoder', '')} files.\n\n'
          '${Plat.isWindows ? 'Open Preferences → Importing and click “Install ffmpeg”, '
              'or run: winget install Gyan.FFmpeg' : 'Install it with Homebrew: brew install ffmpeg'}';
    }
    if (Plat.isMacOS && ffmpeg == null) {
      return 'ffmpeg is required for importing on macOS (brew install ffmpeg).';
    }
    final indices = only ??
        [for (var i = 0; i < st.tracks.length; i++) if (st.include[i]) i];
    if (indices.isEmpty) return 'No songs are checked for import.';

    importing = true;
    importError = null;
    _cancelRequested = false;
    for (final i in indices) {
      st.ripState[i] = RipState.queued;
    }
    notifyListeners();

    final errors = <String>[];
    for (final i in indices) {
      if (_cancelRequested) {
        st.ripState[i] = RipState.none;
        continue;
      }
      final tags = st.tagsFor(i);
      final out = organizedPath(library.root, tags, format.extension);
      st.ripState[i] = RipState.ripping;
      importTitle = tags.title ?? 'Track ${i + 1}';
      importFraction = 0;
      notifyListeners();
      try {
        await Directory(p.dirname(out)).create(recursive: true);
        final f = File(out);
        if (await f.exists()) await f.delete();
        final toc = st.disc.audioTracks[i];
        final args = Ffmpeg.encodeArgs(
          rawPcmInput: Plat.isWindows,
          inputFile: Plat.isWindows ? null : toc.filePath,
          coverFile: st.coverPath,
          format: format,
          mp3Bitrate: settings.mp3Bitrate,
          tags: tags,
          output: out,
        );
        final started = DateTime.now();
        void progress(double f) {
          importFraction = f;
          final elapsed = DateTime.now().difference(started).inMilliseconds;
          if (elapsed > 500 && f > 0) {
            importSpeed = (toc.durationMs * f) / elapsed;
            importRemaining = Duration(
                milliseconds: (elapsed / f * (1 - f)).round());
          }
          notifyListeners();
        }

        if (Plat.isWindows) {
          await _ripWindows(st.disc.drive, toc, ffmpeg, args, out, progress);
        } else {
          await _ripMac(ffmpeg!, args, toc.durationMs, progress);
        }
        if (_cancelRequested) {
          try {
            await File(out).delete();
          } catch (_) {}
          st.ripState[i] = RipState.none;
          continue;
        }
        st.ripState[i] = RipState.done;
        await library.addOrRefresh([out]);
      } catch (e) {
        st.ripState[i] = RipState.error;
        errors.add('${tags.title}: $e');
        try {
          await File(out).delete();
        } catch (_) {}
      }
      notifyListeners();
    }
    importing = false;
    importTitle = '';
    importFraction = 0;
    _cancelPort = null;
    _macProc = null;
    notifyListeners();
    if (errors.isEmpty && !_cancelRequested && settings.ejectAfterImport) {
      await eject(st);
    }
    if (errors.isNotEmpty) {
      importError = errors.join('\n');
      notifyListeners();
      return 'Some songs could not be imported:\n${errors.join('\n')}';
    }
    return null;
  }

  void cancelImport() {
    _cancelRequested = true;
    _cancelPort?.send('cancel');
    _macProc?.kill();
  }

  Future<void> _ripWindows(String letter, CdTocTrack toc, String? ffmpeg,
      List<String> args, String out, void Function(double) progress) async {
    final rp = ReceivePort();
    final completer = Completer<void>();
    final isolate = await Isolate.spawn(_winRipMain, <Object?>[
      rp.sendPort,
      letter,
      toc.startLba,
      toc.lengthSectors,
      ffmpeg,
      args,
      out,
    ]);
    rp.listen((msg) {
      if (msg is Map) {
        if (msg['control'] is SendPort) {
          _cancelPort = msg['control'] as SendPort;
          if (_cancelRequested) _cancelPort!.send('cancel');
        } else if (msg['p'] != null) {
          progress((msg['p'] as num).toDouble());
        } else if (msg['done'] == true) {
          if (!completer.isCompleted) completer.complete();
        } else if (msg['error'] != null) {
          if (!completer.isCompleted) completer.completeError(msg['error'] as String);
        }
      }
    });
    try {
      await completer.future;
    } finally {
      rp.close();
      isolate.kill(priority: Isolate.beforeNextEvent);
    }
  }

  Future<void> _ripMac(String ffmpeg, List<String> args, int durationMs,
      void Function(double) progress) async {
    final full = [...args];
    full.insertAll(full.length - 1, ['-progress', 'pipe:1', '-nostats']);
    final proc = await Process.start(ffmpeg, full);
    _macProc = proc;
    final err = StringBuffer();
    proc.stderr.transform(const SystemEncoding().decoder).listen(err.write);
    await for (final line in proc.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())) {
      final m = RegExp(r'^out_time_(?:us|ms)=(\d+)').firstMatch(line);
      if (m != null && durationMs > 0) {
        final ms = int.parse(m.group(1)!) / 1000;
        progress((ms / durationMs).clamp(0, 1).toDouble());
      }
    }
    final code = await proc.exitCode;
    if (code != 0 && !_cancelRequested) {
      throw Exception('ffmpeg exited with $code: $err');
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate entry points
// ---------------------------------------------------------------------------

Future<List<CdDisc>> _scanInIsolate(bool windows) =>
    Isolate.run(() => windows ? winScanDiscs() : macScanDiscs());

Future<bool> _ejectInIsolate(String letter) => Isolate.run(() => winEject(letter));

/// Rip one track on Windows: raw sectors -> ffmpeg stdin (or a WAV file).
Future<void> _winRipMain(List<Object?> a) async {
  final sp = a[0] as SendPort;
  final letter = a[1] as String;
  final start = a[2] as int;
  final len = a[3] as int;
  final ffmpeg = a[4] as String?;
  final args = (a[5] as List).cast<String>();
  final out = a[6] as String;

  final control = ReceivePort();
  var cancelled = false;
  control.listen((m) {
    if (m == 'cancel') cancelled = true;
  });
  sp.send({'control': control.sendPort});

  final reader = WinCdReader.open(letter);
  if (reader == null) {
    sp.send({'error': 'Could not open drive $letter:'});
    control.close();
    return;
  }
  Process? proc;
  RandomAccessFile? wav;
  final err = StringBuffer();
  try {
    if (ffmpeg != null) {
      proc = await Process.start(ffmpeg, args);
      proc.stdout.drain<void>();
      proc.stderr.transform(const SystemEncoding().decoder).listen(err.write);
    } else {
      wav = File(out).openSync(mode: FileMode.write);
      wav.writeFromSync(wavHeader(len * sectorBytes));
    }
    const chunk = 26; // ~0.35 s of audio per read
    var lba = start;
    while (lba < start + len && !cancelled) {
      final n = (start + len - lba) < chunk ? start + len - lba : chunk;
      final data = reader.read(lba, n);
      if (proc != null) {
        proc.stdin.add(data);
        await proc.stdin.flush();
      } else {
        wav!.writeFromSync(data);
        await Future<void>.delayed(Duration.zero); // let 'cancel' arrive
      }
      lba += n;
      sp.send({'p': (lba - start) / len});
    }
    if (proc != null) {
      await proc.stdin.close();
      if (cancelled) proc.kill();
      final code = await proc.exitCode;
      if (!cancelled && code != 0) {
        sp.send({'error': 'ffmpeg exited with code $code. ${err.toString().trim()}'});
        return;
      }
    }
    if (!cancelled && reader.errorSectors > 0) {
      debugPrint('Rip of $out had ${reader.errorSectors} unreadable sectors');
    }
    sp.send({'done': true});
  } catch (e) {
    sp.send({'error': e.toString()});
  } finally {
    wav?.closeSync();
    reader.close();
    control.close();
  }
}
