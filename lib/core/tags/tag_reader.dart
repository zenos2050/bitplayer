// Pure-Dart audio tag reader.
//
// Supports:
//   MP3      ID3v2.2 / 2.3 / 2.4, ID3v1, duration via Xing/Info/VBRI or CBR
//   FLAC     Vorbis comments, PICTURE blocks, STREAMINFO duration
//   OGG/OPUS Vorbis comments (Vorbis + Opus), duration from final granule
//   M4A/MP4  iTunes ilst atoms, mvhd duration
//   WAV      RIFF INFO + embedded ID3 chunk, duration
//   AIFF     COMM duration + embedded ID3 chunk
//
// All functions are synchronous so they can be run inside a background
// isolate (see LibraryService), keeping the UI responsive while scanning.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models.dart';
import 'id3_genres.dart';

/// File extensions treated as music.
const Set<String> audioExtensions = {
  'mp3', 'mp2', 'm4a', 'm4b', 'mp4', 'aac', 'alac', 'flac', 'ogg', 'oga',
  'opus', 'wav', 'aif', 'aiff', 'aifc', 'wma', 'ape', 'wv', 'mpc', 'dsf',
  'dff', 'tta', 'mka', 'webm',
};

bool isAudioFile(String path) {
  final i = path.lastIndexOf('.');
  if (i < 0) return false;
  return audioExtensions.contains(path.substring(i + 1).toLowerCase());
}

String _ext(String path) {
  final i = path.lastIndexOf('.');
  return i < 0 ? '' : path.substring(i + 1).toLowerCase();
}

/// Reads tags from [path]. Never throws; returns an empty [TagData] on error.
/// When [withPicture] is true the embedded front cover (if any) is returned.
TagData readTags(String path, {bool withPicture = false}) {
  RandomAccessFile? raf;
  final t = TagData();
  try {
    raf = File(path).openSync();
    final len = raf.lengthSync();
    switch (_ext(path)) {
      case 'mp3':
      case 'mp2':
      case 'aac':
        _readMp3(raf, len, t, withPicture);
        break;
      case 'flac':
        _readFlac(raf, len, t, withPicture);
        break;
      case 'ogg':
      case 'oga':
      case 'opus':
        _readOgg(raf, len, t, withPicture);
        break;
      case 'm4a':
      case 'm4b':
      case 'mp4':
      case 'alac':
        _readMp4(raf, len, t, withPicture);
        break;
      case 'wav':
        _readWav(raf, len, t, withPicture);
        break;
      case 'aif':
      case 'aiff':
      case 'aifc':
        _readAiff(raf, len, t, withPicture);
        break;
      default:
        // Formats we can play but not parse: try a leading ID3 tag (APE/WV
        // files sometimes have one), otherwise rely on the path fallback.
        final head = _read(raf, 0, 10);
        if (head.length == 10 && _isId3(head, 0)) {
          final size = _syncsafe(head, 6);
          _parseId3v2(_read(raf, 0, 10 + size), t, withPicture);
        }
    }
  } catch (_) {
    // Corrupt / unreadable file: return whatever we have.
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
  return t;
}

/// Derives tag values from the folder layout
/// `<Artist>/<Album>/<NN Title>.ext` for files without tags.
TagData fallbackFromPath(String filePath) {
  final parts = filePath.split(RegExp(r'[\\/]'));
  final name = parts.isNotEmpty ? parts.last : filePath;
  final dot = name.lastIndexOf('.');
  var base = dot > 0 ? name.substring(0, dot) : name;
  int? track;
  int? disc;
  final m = RegExp(r'^(?:(\d)-)?(\d{1,3})[\s._-]+(.+)$').firstMatch(base);
  if (m != null) {
    disc = m.group(1) != null ? int.tryParse(m.group(1)!) : null;
    track = int.tryParse(m.group(2)!);
    base = m.group(3)!.trim();
  }
  final album = parts.length >= 2 ? parts[parts.length - 2] : null;
  final artist = parts.length >= 3 ? parts[parts.length - 3] : null;
  return TagData(
    title: base,
    album: album,
    artist: artist,
    track: track,
    disc: disc,
  );
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

Uint8List _read(RandomAccessFile raf, int pos, int n) {
  if (n <= 0) return Uint8List(0);
  raf.setPositionSync(pos);
  return raf.readSync(n);
}

int _be16(List<int> b, int o) => (b[o] << 8) | b[o + 1];
int _be32(List<int> b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _be64(List<int> b, int o) => (_be32(b, o) << 32) | _be32(b, o + 4);
int _le16(List<int> b, int o) => b[o] | (b[o + 1] << 8);
int _le32(List<int> b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
int _le64(List<int> b, int o) => _le32(b, o) | (_le32(b, o + 4) << 32);
int _syncsafe(List<int> b, int o) =>
    ((b[o] & 0x7F) << 21) |
    ((b[o + 1] & 0x7F) << 14) |
    ((b[o + 2] & 0x7F) << 7) |
    (b[o + 3] & 0x7F);

String _ascii(List<int> b, int o, int n) {
  if (o + n > b.length) return '';
  return latin1.decode(b.sublist(o, o + n));
}

bool _isId3(List<int> b, int o) =>
    b.length >= o + 3 && b[o] == 0x49 && b[o + 1] == 0x44 && b[o + 2] == 0x33;

String _stripNul(String s) {
  var end = s.length;
  while (end > 0 && s.codeUnitAt(end - 1) == 0) {
    end--;
  }
  return s.substring(0, end);
}

String _decodeUtf16(List<int> b, {bool defaultLittleEndian = true}) {
  var o = 0;
  var le = defaultLittleEndian;
  if (b.length >= 2) {
    if (b[0] == 0xFF && b[1] == 0xFE) {
      le = true;
      o = 2;
    } else if (b[0] == 0xFE && b[1] == 0xFF) {
      le = false;
      o = 2;
    }
  }
  final units = <int>[];
  for (; o + 1 < b.length; o += 2) {
    final u = le ? (b[o] | (b[o + 1] << 8)) : ((b[o] << 8) | b[o + 1]);
    units.add(u);
  }
  return String.fromCharCodes(units);
}

/// Decodes ID3 text with the given encoding byte (0 latin1, 1 UTF-16 BOM,
/// 2 UTF-16BE, 3 UTF-8).
String _id3Text(int enc, List<int> b) {
  String s;
  switch (enc) {
    case 1:
      s = _decodeUtf16(b);
      break;
    case 2:
      s = _decodeUtf16(b, defaultLittleEndian: false);
      break;
    case 3:
      s = utf8.decode(b, allowMalformed: true);
      break;
    default:
      s = latin1.decode(b);
  }
  return s;
}

/// Index of the string terminator for [enc] starting at [start], or -1.
int _findTerm(List<int> d, int start, int enc) {
  if (enc == 1 || enc == 2) {
    for (var i = start; i + 1 < d.length; i += 2) {
      if (d[i] == 0 && d[i + 1] == 0) return i;
    }
    return -1;
  }
  for (var i = start; i < d.length; i++) {
    if (d[i] == 0) return i;
  }
  return -1;
}

int _termLen(int enc) => (enc == 1 || enc == 2) ? 2 : 1;

Uint8List _deUnsync(List<int> b) {
  final tmp = <int>[];
  for (var i = 0; i < b.length; i++) {
    tmp.add(b[i]);
    if (b[i] == 0xFF && i + 1 < b.length && b[i + 1] == 0x00) i++;
  }
  return Uint8List.fromList(tmp);
}

/// Parses "3/12" style numbers.
(int?, int?) _parsePair(String s) {
  final parts = s.trim().split('/');
  final a = parts.isNotEmpty ? int.tryParse(parts[0].trim()) : null;
  final b = parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
  return (a, b);
}

int? _parseYear(String s) {
  final m = RegExp(r'(\d{4})').firstMatch(s);
  return m == null ? null : int.tryParse(m.group(1)!);
}

String _firstValue(String s) {
  s = _stripNul(s);
  final i = s.indexOf('\u0000');
  final v = i >= 0 ? s.substring(0, i) : s;
  return v.trim();
}

// ---------------------------------------------------------------------------
// ID3v2
// ---------------------------------------------------------------------------

const _v22map = {
  'TT2': 'TIT2', 'TP1': 'TPE1', 'TP2': 'TPE2', 'TAL': 'TALB', 'TCO': 'TCON',
  'TYE': 'TYER', 'TRK': 'TRCK', 'TPA': 'TPOS', 'TCM': 'TCOM', 'COM': 'COMM',
  'PIC': 'PIC',
};

/// Parses a complete ID3v2 tag (header included) into [t].
void _parseId3v2(Uint8List tag, TagData t, bool withPicture) {
  if (tag.length < 10 || !_isId3(tag, 0)) return;
  final ver = tag[3];
  if (ver < 2 || ver > 4) return;
  final flags = tag[5];
  final size = _syncsafe(tag, 6);
  var body = tag.sublist(10, math.min(10 + size, tag.length));
  if (ver <= 3 && (flags & 0x80) != 0) body = _deUnsync(body);

  var pos = 0;
  if ((flags & 0x40) != 0 && ver >= 3 && body.length >= 4) {
    pos = ver == 3 ? 4 + _be32(body, 0) : _syncsafe(body, 0);
  }
  final idLen = ver == 2 ? 3 : 4;
  final hdrLen = ver == 2 ? 6 : 10;

  while (pos + hdrLen <= body.length) {
    if (body[pos] == 0) break; // padding
    final id = _ascii(body, pos, idLen);
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) break;
    int fsize;
    var fmtFlags = 0;
    if (ver == 2) {
      fsize = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5];
    } else if (ver == 4) {
      fsize = _syncsafe(body, pos + 4);
      // Some taggers wrote plain sizes in v2.4; detect and correct.
      final plain = _be32(body, pos + 4);
      if (plain != fsize &&
          pos + hdrLen + plain <= body.length &&
          (pos + hdrLen + fsize > body.length ||
              !_looksLikeFrame(body, pos + hdrLen + fsize))) {
        if (_looksLikeFrame(body, pos + hdrLen + plain) ||
            pos + hdrLen + plain == body.length) {
          fsize = plain;
        }
      }
      fmtFlags = body[pos + 9];
    } else {
      fsize = _be32(body, pos + 4);
      fmtFlags = body[pos + 9];
    }
    pos += hdrLen;
    if (fsize <= 0 || pos + fsize > body.length) break;
    var data = body.sublist(pos, pos + fsize);
    pos += fsize;

    if (ver == 3) {
      if ((fmtFlags & 0xC0) != 0) continue; // compressed / encrypted
      if ((fmtFlags & 0x20) != 0 && data.isNotEmpty) data = data.sublist(1);
    } else if (ver == 4) {
      if ((fmtFlags & 0x0C) != 0) continue; // compressed / encrypted
      var skip = 0;
      if ((fmtFlags & 0x40) != 0) skip += 1; // grouping id
      if ((fmtFlags & 0x01) != 0) skip += 4; // data length indicator
      if (skip > 0) {
        if (data.length < skip) continue;
        data = data.sublist(skip);
      }
      if ((fmtFlags & 0x02) != 0) data = _deUnsync(data);
    }
    final key = ver == 2 ? (_v22map[id] ?? id) : id;
    _id3Frame(key, data, t, withPicture);
  }
}

bool _looksLikeFrame(List<int> b, int o) {
  if (o + 4 > b.length) return false;
  if (b[o] == 0) return true; // padding
  for (var i = 0; i < 4; i++) {
    final c = b[o + i];
    final ok = (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39);
    if (!ok) return false;
  }
  return true;
}

void _id3Frame(String id, Uint8List d, TagData t, bool withPicture) {
  if (d.isEmpty) return;
  if (id.startsWith('T') && id != 'TXXX') {
    final text = _firstValue(_id3Text(d[0], d.sublist(1)));
    if (text.isEmpty) return;
    switch (id) {
      case 'TIT2':
        t.title ??= text;
        break;
      case 'TPE1':
        t.artist ??= text;
        break;
      case 'TPE2':
        t.albumArtist ??= text;
        break;
      case 'TALB':
        t.album ??= text;
        break;
      case 'TCON':
        t.genre ??= resolveId3Genre(text);
        break;
      case 'TYER':
      case 'TDRC':
      case 'TDOR':
      case 'TORY':
        t.year ??= _parseYear(text);
        break;
      case 'TRCK':
        {
          final (a, b) = _parsePair(text);
          t.track ??= a;
          t.trackTotal ??= b;
        }
        break;
      case 'TPOS':
        {
          final (a, b) = _parsePair(text);
          t.disc ??= a;
          t.discTotal ??= b;
        }
        break;
      case 'TCOM':
        t.composer ??= text;
        break;
    }
    return;
  }
  if (id == 'COMM') {
    if (d.length < 5) return;
    final enc = d[0];
    final term = _findTerm(d, 4, enc);
    if (term < 0) return;
    final desc = _id3Text(enc, d.sublist(4, term));
    if (desc.startsWith('iTun')) return; // iTunNORM, iTunSMPB, ...
    final text = _stripNul(_id3Text(enc, d.sublist(term + _termLen(enc))));
    if (text.trim().isNotEmpty) t.comment ??= text.trim();
    return;
  }
  if (id == 'APIC' || id == 'PIC') {
    t.hasArt = true;
    if (!withPicture) return;
    final enc = d[0];
    int typePos;
    String mime;
    if (id == 'PIC') {
      if (d.length < 6) return;
      final fmt = _ascii(d, 1, 3).toUpperCase();
      mime = fmt == 'PNG' ? 'image/png' : 'image/jpeg';
      typePos = 4;
    } else {
      final mEnd = _findTerm(d, 1, 0);
      if (mEnd < 0) return;
      mime = latin1.decode(d.sublist(1, mEnd));
      typePos = mEnd + 1;
    }
    if (typePos >= d.length) return;
    final picType = d[typePos];
    final dEnd = _findTerm(d, typePos + 1, enc);
    if (dEnd < 0) return;
    final start = dEnd + _termLen(enc);
    if (start >= d.length) return;
    if (t.picture == null || picType == 3) {
      t.picture = Uint8List.fromList(d.sublist(start));
      t.pictureMime = mime.isEmpty ? 'image/jpeg' : mime;
    }
  }
}

void _parseId3v1(Uint8List b, TagData t) {
  if (b.length < 128 || _ascii(b, 0, 3) != 'TAG') return;
  String f(int o, int n) => _stripNul(latin1.decode(b.sublist(o, o + n))).trim();
  final title = f(3, 30);
  final artist = f(33, 30);
  final album = f(63, 30);
  final year = f(93, 4);
  if (title.isNotEmpty) t.title ??= title;
  if (artist.isNotEmpty) t.artist ??= artist;
  if (album.isNotEmpty) t.album ??= album;
  t.year ??= _parseYear(year);
  if (b[125] == 0 && b[126] != 0) t.track ??= b[126];
  final g = b[127];
  if (g < id3Genres.length) t.genre ??= id3Genres[g];
}

// ---------------------------------------------------------------------------
// MP3
// ---------------------------------------------------------------------------

const _brV1 = [
  [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
];
const _brV2 = [
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
];
const _srTable = {
  3: [44100, 48000, 32000],
  2: [22050, 24000, 16000],
  0: [11025, 12000, 8000],
};

void _readMp3(RandomAccessFile raf, int len, TagData t, bool withPicture) {
  var audioStart = 0;
  final head = _read(raf, 0, 10);
  if (head.length == 10 && _isId3(head, 0)) {
    final size = _syncsafe(head, 6);
    final footer = (head[5] & 0x10) != 0 ? 10 : 0;
    _parseId3v2(_read(raf, 0, 10 + size), t, withPicture);
    audioStart = 10 + size + footer;
  }
  var hasV1 = false;
  if (len >= 128) {
    final v1 = _read(raf, len - 128, 128);
    if (_ascii(v1, 0, 3) == 'TAG') {
      hasV1 = true;
      _parseId3v1(v1, t);
    }
  }
  t.durationMs = _mp3Duration(raf, len, audioStart, hasV1);
}

int _mp3Duration(RandomAccessFile raf, int len, int start, bool hasV1) {
  final buf = _read(raf, start, 65536);
  for (var i = 0; i + 4 < buf.length; i++) {
    if (buf[i] != 0xFF || (buf[i + 1] & 0xE0) != 0xE0) continue;
    final verBits = (buf[i + 1] >> 3) & 3; // 0 = 2.5, 2 = v2, 3 = v1
    final layerBits = (buf[i + 1] >> 1) & 3; // 1 = L3, 2 = L2, 3 = L1
    final brIdx = buf[i + 2] >> 4;
    final srIdx = (buf[i + 2] >> 2) & 3;
    if (verBits == 1 || layerBits == 0 || brIdx == 0 || brIdx == 15 || srIdx == 3) {
      continue;
    }
    final layer = 4 - layerBits; // 1..3
    final sr = _srTable[verBits]![srIdx];
    final kbps = (verBits == 3 ? _brV1 : _brV2)[layer - 1][brIdx];
    final spf = layer == 1 ? 384 : (layer == 2 || verBits == 3 ? 1152 : 576);
    final mono = (buf[i + 3] >> 6) == 3;
    final sideInfo = verBits == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17);

    final xo = i + 4 + sideInfo;
    if (xo + 12 <= buf.length) {
      final tag = _ascii(buf, xo, 4);
      if (tag == 'Xing' || tag == 'Info') {
        final flags = _be32(buf, xo + 4);
        if ((flags & 1) != 0) {
          final frames = _be32(buf, xo + 8);
          if (frames > 0) return frames * spf * 1000 ~/ sr;
        }
      }
    }
    final vo = i + 4 + 32;
    if (vo + 18 <= buf.length && _ascii(buf, vo, 4) == 'VBRI') {
      final frames = _be32(buf, vo + 14);
      if (frames > 0) return frames * spf * 1000 ~/ sr;
    }
    final audioBytes = len - (start + i) - (hasV1 ? 128 : 0);
    if (kbps > 0 && audioBytes > 0) return audioBytes * 8 ~/ kbps;
    return 0;
  }
  return 0;
}

// ---------------------------------------------------------------------------
// FLAC + Vorbis comments
// ---------------------------------------------------------------------------

void _readFlac(RandomAccessFile raf, int len, TagData t, bool withPicture) {
  var pos = 0;
  final head = _read(raf, 0, 10);
  if (head.length == 10 && _isId3(head, 0)) {
    pos = 10 + _syncsafe(head, 6);
  }
  if (_ascii(_read(raf, pos, 4), 0, 4) != 'fLaC') return;
  pos += 4;
  while (pos + 4 <= len) {
    final h = _read(raf, pos, 4);
    if (h.length < 4) break;
    final last = (h[0] & 0x80) != 0;
    final type = h[0] & 0x7F;
    final blen = (h[1] << 16) | (h[2] << 8) | h[3];
    pos += 4;
    if (type == 0 && blen >= 18) {
      final s = _read(raf, pos, blen);
      final sr = (s[10] << 12) | (s[11] << 4) | (s[12] >> 4);
      final total = ((s[13] & 0x0F) << 32) |
          (s[14] << 24) |
          (s[15] << 16) |
          (s[16] << 8) |
          s[17];
      if (sr > 0) t.durationMs = total * 1000 ~/ sr;
    } else if (type == 4) {
      _parseVorbisComment(_read(raf, pos, blen), 0, t, withPicture);
    } else if (type == 6) {
      t.hasArt = true;
      if (withPicture) _applyFlacPicture(_read(raf, pos, blen), t);
    }
    pos += blen;
    if (last) break;
  }
}

void _applyFlacPicture(Uint8List b, TagData t) {
  try {
    final type = _be32(b, 0);
    final mlen = _be32(b, 4);
    final mime = latin1.decode(b.sublist(8, 8 + mlen));
    var o = 8 + mlen;
    final dlen = _be32(b, o);
    o += 4 + dlen + 16;
    final plen = _be32(b, o);
    o += 4;
    if (o + plen > b.length) return;
    if (t.picture == null || type == 3) {
      t.picture = Uint8List.fromList(b.sublist(o, o + plen));
      t.pictureMime = mime;
    }
  } catch (_) {}
}

void _parseVorbisComment(Uint8List d, int off, TagData t, bool withPicture) {
  if (off + 8 > d.length) return;
  final vlen = _le32(d, off);
  off += 4 + vlen;
  if (off + 4 > d.length) return;
  final count = _le32(d, off);
  off += 4;
  for (var i = 0; i < count && off + 4 <= d.length; i++) {
    final l = _le32(d, off);
    off += 4;
    if (l < 0 || off + l > d.length) break;
    final s = utf8.decode(d.sublist(off, off + l), allowMalformed: true);
    off += l;
    final eq = s.indexOf('=');
    if (eq <= 0) continue;
    _applyVorbis(s.substring(0, eq).toUpperCase(), s.substring(eq + 1), t,
        withPicture);
  }
}

void _applyVorbis(String key, String value, TagData t, bool withPicture) {
  final v = value.trim();
  if (v.isEmpty) return;
  switch (key) {
    case 'TITLE':
      t.title ??= v;
      break;
    case 'ARTIST':
      t.artist ??= v;
      break;
    case 'ALBUMARTIST':
    case 'ALBUM ARTIST':
    case 'ALBUM_ARTIST':
      t.albumArtist ??= v;
      break;
    case 'ALBUM':
      t.album ??= v;
      break;
    case 'GENRE':
      t.genre ??= v;
      break;
    case 'DATE':
    case 'YEAR':
    case 'ORIGINALDATE':
      t.year ??= _parseYear(v);
      break;
    case 'TRACKNUMBER':
      final (a, b) = _parsePair(v);
      t.track ??= a;
      t.trackTotal ??= b;
      break;
    case 'TRACKTOTAL':
    case 'TOTALTRACKS':
      t.trackTotal ??= int.tryParse(v);
      break;
    case 'DISCNUMBER':
      final (a, b) = _parsePair(v);
      t.disc ??= a;
      t.discTotal ??= b;
      break;
    case 'DISCTOTAL':
    case 'TOTALDISCS':
      t.discTotal ??= int.tryParse(v);
      break;
    case 'COMPOSER':
      t.composer ??= v;
      break;
    case 'COMMENT':
    case 'DESCRIPTION':
      t.comment ??= v;
      break;
    case 'METADATA_BLOCK_PICTURE':
      t.hasArt = true;
      if (withPicture) {
        try {
          _applyFlacPicture(base64.decode(v), t);
        } catch (_) {}
      }
      break;
    case 'COVERART':
      t.hasArt = true;
      if (withPicture && t.picture == null) {
        try {
          t.picture = base64.decode(v);
          t.pictureMime = 'image/jpeg';
        } catch (_) {}
      }
      break;
  }
}

// ---------------------------------------------------------------------------
// OGG (Vorbis / Opus)
// ---------------------------------------------------------------------------

void _readOgg(RandomAccessFile raf, int len, TagData t, bool withPicture) {
  final packets = <Uint8List>[];
  var cur = BytesBuilder(copy: false);
  var pos = 0;
  int? serial;
  var budget = 32 * 1024 * 1024;
  while (packets.length < 2 && pos + 27 <= len && budget > 0) {
    final h = _read(raf, pos, 27);
    if (h.length < 27 || _ascii(h, 0, 4) != 'OggS') break;
    final pageSerial = _le32(h, 14);
    final nseg = h[26];
    final segs = _read(raf, pos + 27, nseg);
    var payloadLen = 0;
    for (final s in segs) {
      payloadLen += s;
    }
    final payload = _read(raf, pos + 27 + nseg, payloadLen);
    pos += 27 + nseg + payloadLen;
    budget -= payloadLen;
    serial ??= pageSerial;
    if (pageSerial != serial) continue;
    var o = 0;
    for (final s in segs) {
      if (o + s > payload.length) break;
      cur.add(payload.sublist(o, o + s));
      o += s;
      if (s < 255) {
        packets.add(cur.takeBytes());
        cur = BytesBuilder(copy: false);
        if (packets.length >= 2) break;
      }
    }
  }
  if (packets.isEmpty) return;
  final p0 = packets[0];
  var sampleRate = 0;
  var preSkip = 0;
  var opus = false;
  if (p0.length >= 16 && p0[0] == 1 && _ascii(p0, 1, 6) == 'vorbis') {
    sampleRate = _le32(p0, 12);
  } else if (p0.length >= 12 && _ascii(p0, 0, 8) == 'OpusHead') {
    opus = true;
    preSkip = _le16(p0, 10);
    sampleRate = 48000;
  }
  if (packets.length > 1) {
    final p1 = packets[1];
    if (!opus && p1.length > 7 && p1[0] == 3 && _ascii(p1, 1, 6) == 'vorbis') {
      _parseVorbisComment(p1, 7, t, withPicture);
    } else if (opus && p1.length > 8 && _ascii(p1, 0, 8) == 'OpusTags') {
      _parseVorbisComment(p1, 8, t, withPicture);
    }
  }
  if (sampleRate > 0) {
    final tailLen = math.min(len, 65536 * 2);
    final tail = _read(raf, len - tailLen, tailLen);
    for (var i = tail.length - 27; i >= 0; i--) {
      if (tail[i] == 0x4F &&
          tail[i + 1] == 0x67 &&
          tail[i + 2] == 0x67 &&
          tail[i + 3] == 0x53) {
        final granule = _le64(tail, i + 6);
        if (granule > 0) {
          t.durationMs = (granule - preSkip) * 1000 ~/ sampleRate;
          break;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// MP4 / M4A
// ---------------------------------------------------------------------------

typedef _AtomVisitor = void Function(String type, int start, int end);

void _atoms(Uint8List d, int start, int end, _AtomVisitor f) {
  var pos = start;
  while (pos + 8 <= end) {
    var size = _be32(d, pos);
    final type = _ascii(d, pos + 4, 4);
    var hdr = 8;
    if (size == 1) {
      if (pos + 16 > end) break;
      size = _be64(d, pos + 8);
      hdr = 16;
    } else if (size == 0) {
      size = end - pos;
    }
    if (size < hdr || pos + size > end) break;
    f(type, pos + hdr, pos + size);
    pos += size;
  }
}

void _readMp4(RandomAccessFile raf, int len, TagData t, bool withPicture) {
  var pos = 0;
  while (pos + 8 <= len) {
    final h = _read(raf, pos, 16);
    if (h.length < 8) break;
    var size = _be32(h, 0);
    final type = _ascii(h, 4, 4);
    var hdr = 8;
    if (size == 1 && h.length >= 16) {
      size = _be64(h, 8);
      hdr = 16;
    } else if (size == 0) {
      size = len - pos;
    }
    if (size < hdr) break;
    if (type == 'moov') {
      if (size > 128 * 1024 * 1024) break;
      final moov = _read(raf, pos + hdr, size - hdr);
      _parseMoov(moov, t, withPicture);
      break;
    }
    pos += size;
  }
}

void _parseMoov(Uint8List m, TagData t, bool withPicture) {
  _atoms(m, 0, m.length, (type, s, e) {
    if (type == 'mvhd' && e - s >= 20) {
      final v = m[s];
      int scale, dur;
      if (v == 1 && e - s >= 32) {
        scale = _be32(m, s + 20);
        dur = _be64(m, s + 24);
      } else {
        scale = _be32(m, s + 12);
        dur = _be32(m, s + 16);
      }
      if (scale > 0) t.durationMs = dur * 1000 ~/ scale;
    } else if (type == 'udta') {
      _atoms(m, s, e, (t2, s2, e2) {
        if (t2 != 'meta') return;
        // 'meta' is usually a full box (4 bytes version/flags) in iTunes files.
        final off = (e2 - s2 >= 8 && _ascii(m, s2 + 4, 4) == 'hdlr') ? 0 : 4;
        _atoms(m, s2 + off, e2, (t3, s3, e3) {
          if (t3 != 'ilst') return;
          _atoms(m, s3, e3, (key, s4, e4) {
            _atoms(m, s4, e4, (dt, s5, e5) {
              if (dt != 'data' || e5 - s5 < 8) return;
              final dataType = _be32(m, s5) & 0xFFFFFF;
              _mp4Item(key, dataType, m.sublist(s5 + 8, e5), t, withPicture);
            });
          });
        });
      });
    }
  });
}

void _mp4Item(String key, int type, Uint8List v, TagData t, bool withPicture) {
  String text() => utf8.decode(v, allowMalformed: true).trim();
  switch (key) {
    case '©nam':
      t.title ??= text();
      break;
    case '©ART':
      t.artist ??= text();
      break;
    case 'aART':
      t.albumArtist ??= text();
      break;
    case '©alb':
      t.album ??= text();
      break;
    case '©gen':
      t.genre ??= text();
      break;
    case 'gnre':
      if (v.length >= 2) {
        final g = _be16(v, 0) - 1;
        if (g >= 0 && g < id3Genres.length) t.genre ??= id3Genres[g];
      }
      break;
    case '©day':
      t.year ??= _parseYear(text());
      break;
    case 'trkn':
      if (v.length >= 6) {
        final a = _be16(v, 2), b = _be16(v, 4);
        if (a > 0) t.track ??= a;
        if (b > 0) t.trackTotal ??= b;
      }
      break;
    case 'disk':
      if (v.length >= 6) {
        final a = _be16(v, 2), b = _be16(v, 4);
        if (a > 0) t.disc ??= a;
        if (b > 0) t.discTotal ??= b;
      }
      break;
    case '©wrt':
      t.composer ??= text();
      break;
    case '©cmt':
      t.comment ??= text();
      break;
    case 'covr':
      t.hasArt = true;
      if (withPicture && t.picture == null && v.isNotEmpty) {
        t.picture = Uint8List.fromList(v);
        t.pictureMime = type == 14 ? 'image/png' : 'image/jpeg';
      }
      break;
  }
}

// ---------------------------------------------------------------------------
// WAV / AIFF
// ---------------------------------------------------------------------------

void _readWav(RandomAccessFile raf, int len, TagData t, bool withPicture) {
  final h = _read(raf, 0, 12);
  if (h.length < 12 || _ascii(h, 0, 4) != 'RIFF' || _ascii(h, 8, 4) != 'WAVE') {
    return;
  }
  var pos = 12;
  var byteRate = 0;
  var dataSize = 0;
  while (pos + 8 <= len) {
    final ch = _read(raf, pos, 8);
    if (ch.length < 8) break;
    final id = _ascii(ch, 0, 4);
    var size = _le32(ch, 4);
    final start = pos + 8;
    if (id == 'data') {
      if (size == 0xFFFFFFFF || start + size > len) size = len - start;
      dataSize = size;
    } else if (id == 'fmt ') {
      final f = _read(raf, start, math.min(size, 40));
      if (f.length >= 12) byteRate = _le32(f, 8);
    } else if (id == 'LIST' && size >= 4) {
      final l = _read(raf, start, math.min(size, 1 << 20));
      if (_ascii(l, 0, 4) == 'INFO') {
        var o = 4;
        while (o + 8 <= l.length) {
          final sid = _ascii(l, o, 4);
          final ssz = _le32(l, o + 4);
          if (o + 8 + ssz > l.length) break;
          final val = _stripNul(
                  utf8.decode(l.sublist(o + 8, o + 8 + ssz), allowMalformed: true))
              .trim();
          if (val.isNotEmpty) {
            switch (sid) {
              case 'INAM':
                t.title ??= val;
                break;
              case 'IART':
                t.artist ??= val;
                break;
              case 'IPRD':
                t.album ??= val;
                break;
              case 'IGNR':
                t.genre ??= val;
                break;
              case 'ICRD':
                t.year ??= _parseYear(val);
                break;
              case 'ITRK':
              case 'IPRT':
                t.track ??= _parsePair(val).$1;
                break;
              case 'ICMT':
                t.comment ??= val;
                break;
            }
          }
          o += 8 + ssz + (ssz & 1);
        }
      }
    } else if (id == 'id3 ' || id == 'ID3 ') {
      final tag = _read(raf, start, size);
      // Tags already found in the ID3 chunk take precedence over INFO.
      final tmp = TagData();
      _parseId3v2(tag, tmp, withPicture);
      _merge(tmp, t);
    }
    if (size < 0) break;
    pos = start + size + (size & 1);
  }
  if (byteRate > 0 && dataSize > 0) {
    t.durationMs = dataSize * 1000 ~/ byteRate;
  }
}

void _readAiff(RandomAccessFile raf, int len, TagData t, bool withPicture) {
  final h = _read(raf, 0, 12);
  if (h.length < 12 || _ascii(h, 0, 4) != 'FORM') return;
  final form = _ascii(h, 8, 4);
  if (form != 'AIFF' && form != 'AIFC') return;
  var pos = 12;
  while (pos + 8 <= len) {
    final ch = _read(raf, pos, 8);
    if (ch.length < 8) break;
    final id = _ascii(ch, 0, 4);
    final size = _be32(ch, 4);
    final start = pos + 8;
    if (id == 'COMM' && size >= 18) {
      final c = _read(raf, start, 18);
      final frames = _be32(c, 2);
      final rate = _ext80(c, 8);
      if (rate > 0) t.durationMs = (frames * 1000 / rate).round();
    } else if (id == 'ID3 ' || id == 'id3 ') {
      final tmp = TagData();
      _parseId3v2(_read(raf, start, size), tmp, withPicture);
      _merge(tmp, t);
    } else if (id == 'NAME') {
      t.title ??= _stripNul(latin1.decode(_read(raf, start, size))).trim();
    }
    pos = start + size + (size & 1);
  }
}

double _ext80(List<int> b, int o) {
  final exp = ((b[o] & 0x7F) << 8) | b[o + 1];
  final hi = _be32(b, o + 2).toDouble();
  final lo = _be32(b, o + 6).toDouble();
  final mant = hi * 4294967296.0 + lo;
  if (exp == 0 && mant == 0) return 0;
  return mant * math.pow(2, exp - 16383 - 63);
}

void _merge(TagData from, TagData into) {
  into.title = from.title ?? into.title;
  into.artist = from.artist ?? into.artist;
  into.albumArtist = from.albumArtist ?? into.albumArtist;
  into.album = from.album ?? into.album;
  into.genre = from.genre ?? into.genre;
  into.year = from.year ?? into.year;
  into.track = from.track ?? into.track;
  into.trackTotal = from.trackTotal ?? into.trackTotal;
  into.disc = from.disc ?? into.disc;
  into.discTotal = from.discTotal ?? into.discTotal;
  into.composer = from.composer ?? into.composer;
  into.comment = from.comment ?? into.comment;
  into.hasArt = into.hasArt || from.hasArt;
  if (from.picture != null) {
    into.picture = from.picture;
    into.pictureMime = from.pictureMime;
  }
}
