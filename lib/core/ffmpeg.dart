import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'platform.dart';
import 'settings.dart';

/// Locates and drives ffmpeg (desktop only). ffmpeg is used to encode CD
/// rips and to write tags for formats the pure-Dart writer doesn't handle.
class Ffmpeg {
  static String? _cached;

  /// Returns a usable ffmpeg executable path, or null.
  static Future<String?> locate(Settings s, {bool refresh = false}) async {
    if (!Plat.isDesktop) return null;
    if (!refresh && _cached != null && File(_cached!).existsSync()) {
      return _cached;
    }
    final candidates = <String>[];
    if (s.ffmpegPath.isNotEmpty) candidates.add(s.ffmpegPath);
    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (Plat.isWindows) {
      candidates.add(p.join(exeDir, 'ffmpeg.exe'));
      final local = Platform.environment['LOCALAPPDATA'];
      if (local != null) {
        candidates.add(p.join(local, 'Microsoft', 'WinGet', 'Links', 'ffmpeg.exe'));
      }
      candidates.add(r'C:\ffmpeg\bin\ffmpeg.exe');
      final pf = Platform.environment['ProgramFiles'];
      if (pf != null) candidates.add(p.join(pf, 'ffmpeg', 'bin', 'ffmpeg.exe'));
      final choco = Platform.environment['ChocolateyInstall'];
      if (choco != null) candidates.add(p.join(choco, 'bin', 'ffmpeg.exe'));
      final user = Platform.environment['USERPROFILE'];
      if (user != null) {
        candidates.add(p.join(user, 'scoop', 'shims', 'ffmpeg.exe'));
      }
    } else {
      candidates.addAll([
        '/opt/homebrew/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/usr/bin/ffmpeg',
        p.join(exeDir, 'ffmpeg'),
      ]);
    }
    for (final c in candidates) {
      if (File(c).existsSync()) return _cached = c;
    }
    // Fall back to PATH lookup.
    try {
      final r = await Process.run(Plat.isWindows ? 'where' : 'which', ['ffmpeg']);
      if (r.exitCode == 0) {
        final first = (r.stdout as String)
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && File(first).existsSync()) return _cached = first;
      }
    } catch (_) {}
    return null;
  }

  /// Installs ffmpeg with winget (Windows). Returns the process output.
  static Future<ProcessResult> installWithWinget() {
    return Process.run('winget', [
      'install',
      '--id',
      'Gyan.FFmpeg',
      '-e',
      '--accept-source-agreements',
      '--accept-package-agreements',
    ]);
  }

  static List<String> metadataArgs(TagData t) {
    final args = <String>[];
    void m(String k, String? v) {
      if (v != null && v.trim().isNotEmpty) {
        args.addAll(['-metadata', '$k=${v.trim()}']);
      } else {
        args.addAll(['-metadata', '$k=']);
      }
    }

    m('title', t.title);
    m('artist', t.artist);
    m('album_artist', t.albumArtist);
    m('album', t.album);
    m('genre', t.genre);
    m('date', (t.year ?? 0) > 0 ? '${t.year}' : null);
    m('track', (t.track ?? 0) > 0
        ? ((t.trackTotal ?? 0) > 0 ? '${t.track}/${t.trackTotal}' : '${t.track}')
        : null);
    m('disc', (t.disc ?? 0) > 0
        ? ((t.discTotal ?? 0) > 0 ? '${t.disc}/${t.discTotal}' : '${t.disc}')
        : null);
    m('composer', t.composer);
    m('comment', t.comment);
    return args;
  }

  /// Rewrites tags of [path] by remuxing with `-c copy`.
  static Future<void> writeTags(String ffmpeg, String path, TagData t) async {
    final ext = p.extension(path);
    final tmp = '${p.withoutExtension(path)}.rttmp$ext';
    final args = [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-i', path,
      '-map', '0',
      '-map_metadata', '0',
      '-c', 'copy',
      ...metadataArgs(t),
      tmp,
    ];
    final r = await Process.run(ffmpeg, args);
    if (r.exitCode != 0) {
      try {
        File(tmp).deleteSync();
      } catch (_) {}
      throw Exception('ffmpeg failed: ${r.stderr}');
    }
    final bak = '$path.rtbak';
    await File(path).rename(bak);
    try {
      await File(tmp).rename(path);
    } catch (e) {
      await File(bak).rename(path);
      rethrow;
    }
    try {
      await File(bak).delete();
    } catch (_) {}
  }

  /// Builds the encoder arguments for a rip.
  /// [rawPcmInput] = true reads 44.1 kHz / 16-bit / stereo PCM from stdin.
  static List<String> encodeArgs({
    required bool rawPcmInput,
    String? inputFile,
    String? coverFile,
    required RipFormat format,
    required int mp3Bitrate,
    required TagData tags,
    required String output,
  }) {
    final args = <String>['-y', '-hide_banner', '-loglevel', 'error'];
    if (rawPcmInput) {
      args.addAll(['-f', 's16le', '-ar', '44100', '-ac', '2', '-i', 'pipe:0']);
    } else {
      args.addAll(['-i', inputFile!]);
    }
    final artOk = coverFile != null &&
        (format == RipFormat.mp3 ||
            format == RipFormat.flac ||
            format == RipFormat.aac ||
            format == RipFormat.alac);
    if (artOk) args.addAll(['-i', coverFile]);
    args.addAll(['-map', '0:a']);
    if (artOk) {
      args.addAll(['-map', '1:v', '-c:v', 'copy', '-disposition:v:0', 'attached_pic']);
    }
    switch (format) {
      case RipFormat.mp3:
        args.addAll(['-c:a', 'libmp3lame']);
        if (mp3Bitrate <= 0) {
          args.addAll(['-q:a', '0']);
        } else {
          args.addAll(['-b:a', '${mp3Bitrate}k']);
        }
        args.addAll(['-id3v2_version', '3']);
        if (artOk) {
          args.addAll(['-metadata:s:v', 'title=Album cover',
            '-metadata:s:v', 'comment=Cover (front)']);
        }
        break;
      case RipFormat.aac:
        args.addAll(['-c:a', 'aac', '-b:a', '256k']);
        break;
      case RipFormat.alac:
        args.addAll(['-c:a', 'alac']);
        break;
      case RipFormat.flac:
        args.addAll(['-c:a', 'flac', '-compression_level', '8']);
        break;
      case RipFormat.ogg:
        args.addAll(['-c:a', 'libvorbis', '-q:a', '8']);
        break;
      case RipFormat.wav:
        args.addAll(['-c:a', 'pcm_s16le']);
        break;
    }
    args.addAll(metadataArgs(tags));
    args.add(output);
    return args;
  }
}
