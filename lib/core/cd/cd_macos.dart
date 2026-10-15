// macOS audio CDs: the system mounts them under /Volumes as a folder of
// "N Audio Track.aiff" files plus a hidden .TOC.plist with the real TOC.
// Playback opens the .aiff files directly; ripping feeds them to ffmpeg.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'cd_models.dart';

List<CdDisc> macScanDiscs() {
  final out = <CdDisc>[];
  final volumes = Directory('/Volumes');
  if (!volumes.existsSync()) return out;
  for (final v in volumes.listSync(followLinks: false)) {
    if (v is! Directory) continue;
    try {
      final disc = _readVolume(v.path);
      if (disc != null) out.add(disc);
    } catch (_) {}
  }
  return out;
}

CdDisc? _readVolume(String mount) {
  final dir = Directory(mount);
  final aiffs = <int, String>{};
  for (final e in dir.listSync(followLinks: false)) {
    if (e is! File) continue;
    final name = p.basename(e.path);
    if (!name.toLowerCase().endsWith('.aiff')) continue;
    final m = RegExp(r'^(\d+)').firstMatch(name);
    if (m != null) aiffs[int.parse(m.group(1)!)] = e.path;
  }
  final tocFile = File(p.join(mount, '.TOC.plist'));
  if (aiffs.isEmpty && !tocFile.existsSync()) return null;

  if (tocFile.existsSync()) {
    try {
      final plist = parsePlist(tocFile.readAsStringSync());
      final sessions = (plist as Map)['Sessions'] as List;
      final entries = <(int, int, bool)>[];
      var first = 99, last = 0, leadout = 0;
      for (final s in sessions.cast<Map>()) {
        final f = (s['First Track'] as int?) ?? 1;
        final l = (s['Last Track'] as int?) ?? 1;
        if (f < first) first = f;
        if (l > last) last = l;
        final lo = (s['Leadout Block'] as int?) ?? 0;
        if (lo > leadout) leadout = lo;
        for (final t in ((s['Track Array'] as List?) ?? const []).cast<Map>()) {
          final point = (t['Point'] as int?) ?? 0;
          final start = (t['Start Block'] as int?) ?? 0;
          final data = (t['Data'] as bool?) ?? false;
          if (point >= 1 && point <= 99) entries.add((point, start, !data));
        }
      }
      entries.sort((a, b) => a.$1.compareTo(b.$1));
      if (entries.isNotEmpty) {
        final tracks = <CdTocTrack>[];
        for (var i = 0; i < entries.length; i++) {
          final (n, start, audio) = entries[i];
          var end = i + 1 < entries.length ? entries[i + 1].$2 : leadout;
          if (audio && i + 1 < entries.length && !entries[i + 1].$3) end -= 11400;
          tracks.add(CdTocTrack(
            number: n,
            startLba: start,
            lengthSectors: end - start,
            isAudio: audio,
            filePath: aiffs[n],
          ));
        }
        return CdDisc(
          drive: mount,
          label: p.basename(mount),
          firstTrack: first,
          lastTrack: last,
          leadoutLba: leadout,
          tracks: tracks,
        );
      }
    } catch (_) {}
  }

  // No usable TOC: estimate from AIFF sizes (disc lookup may then fail).
  final nums = aiffs.keys.toList()..sort();
  var lba = 0;
  final tracks = <CdTocTrack>[];
  for (final n in nums) {
    final size = File(aiffs[n]!).lengthSync();
    final sectors = size ~/ 2352;
    tracks.add(CdTocTrack(
        number: n,
        startLba: lba,
        lengthSectors: sectors,
        isAudio: true,
        filePath: aiffs[n]));
    lba += sectors;
  }
  return CdDisc(
    drive: mount,
    label: p.basename(mount),
    firstTrack: nums.first,
    lastTrack: nums.last,
    leadoutLba: lba,
    tracks: tracks,
  );
}

Future<void> macEject(String mount) async {
  try {
    await Process.run('diskutil', ['eject', mount]);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Minimal XML property list parser.
// ---------------------------------------------------------------------------

Object? parsePlist(String xml) {
  final tokens = RegExp(r'<(/?)([A-Za-z]+)[^>]*?(/?)>|([^<]+)', dotAll: true)
      .allMatches(xml)
      .toList();
  var i = 0;

  Object? value() {
    while (i < tokens.length) {
      final t = tokens[i];
      final text = t.group(4);
      if (text != null) {
        i++;
        continue; // whitespace between elements
      }
      final closing = t.group(1) == '/';
      final name = t.group(2)!;
      final selfClosing = t.group(3) == '/';
      i++;
      if (closing) return null;
      if (name == 'plist' || name == 'xml' || name == 'DOCTYPE') continue;
      if (selfClosing) {
        if (name == 'true') return true;
        if (name == 'false') return false;
        if (name == 'dict') return <String, Object?>{};
        if (name == 'array') return <Object?>[];
        return null;
      }
      switch (name) {
        case 'dict':
          final map = <String, Object?>{};
          while (i < tokens.length) {
            final k = tokens[i];
            if (k.group(4) != null) {
              i++;
              continue;
            }
            if (k.group(1) == '/' && k.group(2) == 'dict') {
              i++;
              break;
            }
            if (k.group(2) == 'key') {
              i++;
              final keyText = (i < tokens.length && tokens[i].group(4) != null)
                  ? _unescape(tokens[i++].group(4)!)
                  : '';
              i++; // </key>
              map[keyText] = value();
            } else {
              i++;
            }
          }
          return map;
        case 'array':
          final list = <Object?>[];
          while (i < tokens.length) {
            final k = tokens[i];
            if (k.group(4) != null) {
              i++;
              continue;
            }
            if (k.group(1) == '/' && k.group(2) == 'array') {
              i++;
              break;
            }
            list.add(value());
          }
          return list;
        default:
          var text = '';
          if (i < tokens.length && tokens[i].group(4) != null) {
            text = tokens[i++].group(4)!;
          }
          i++; // closing tag
          switch (name) {
            case 'integer':
              return int.tryParse(text.trim());
            case 'real':
              return double.tryParse(text.trim());
            case 'string':
              return _unescape(text);
            default:
              return text.trim();
          }
      }
    }
    return null;
  }

  return value();
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
