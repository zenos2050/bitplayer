// Pure-Dart tag writer for MP3 (ID3v2.3 / v2.4 + ID3v1) and FLAC.
// Other formats are written through ffmpeg on desktop (see ffmpeg.dart).
//
// Unknown frames / comment fields already in the file are preserved.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models.dart';
import 'id3_genres.dart';

/// Picture change requested alongside a tag write.
class PictureEdit {
  final Uint8List? bytes; // null + remove == true => remove art
  final String mime;
  final bool remove;
  const PictureEdit.set(this.bytes, this.mime) : remove = false;
  const PictureEdit.remove()
      : bytes = null,
        mime = '',
        remove = true;
}

bool canWriteNatively(String path) {
  final e = path.toLowerCase();
  return e.endsWith('.mp3') || e.endsWith('.flac');
}

/// Writes [t] into [path]. Throws on failure.
void writeTagsNative(String path, TagData t, {PictureEdit? picture}) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.mp3')) {
    _writeMp3(path, t, picture);
  } else if (lower.endsWith('.flac')) {
    _writeFlac(path, t, picture);
  } else {
    throw UnsupportedError('Native tag writing not supported for $path');
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

int _be32(List<int> b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _le32(List<int> b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
int _syncsafe(List<int> b, int o) =>
    ((b[o] & 0x7F) << 21) |
    ((b[o + 1] & 0x7F) << 14) |
    ((b[o + 2] & 0x7F) << 7) |
    (b[o + 3] & 0x7F);

List<int> _be32b(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _le32b(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _syncsafeb(int v) =>
    [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

Uint8List _readAt(RandomAccessFile raf, int pos, int n) {
  if (n <= 0) return Uint8List(0);
  raf.setPositionSync(pos);
  return raf.readSync(n);
}

/// Replaces [path] with a new file made of [prefix] followed by the bytes of
/// the original file starting at [copyFrom]. Done via a temp file + rename so
/// the original is never left half-written.
void _rewrite(String path, List<int> prefix, int copyFrom) {
  final tmpPath = '$path.rttmp';
  final bakPath = '$path.rtbak';
  final src = File(path).openSync();
  final dst = File(tmpPath).openSync(mode: FileMode.write);
  try {
    dst.writeFromSync(prefix);
    final len = src.lengthSync();
    src.setPositionSync(copyFrom);
    const chunk = 1 << 20;
    var remaining = len - copyFrom;
    while (remaining > 0) {
      final data = src.readSync(remaining < chunk ? remaining : chunk);
      if (data.isEmpty) break;
      dst.writeFromSync(data);
      remaining -= data.length;
    }
    dst.flushSync();
  } finally {
    src.closeSync();
    dst.closeSync();
  }
  final orig = File(path);
  final bak = File(bakPath);
  if (bak.existsSync()) bak.deleteSync();
  orig.renameSync(bakPath);
  try {
    File(tmpPath).renameSync(path);
  } catch (e) {
    // Put the original back.
    File(bakPath).renameSync(path);
    rethrow;
  }
  try {
    File(bakPath).deleteSync();
  } catch (_) {}
}

String? _nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

String _pair(int? a, int? b) {
  if (a == null || a == 0) return '';
  if (b == null || b == 0) return '$a';
  return '$a/$b';
}

// ---------------------------------------------------------------------------
// MP3 / ID3v2
// ---------------------------------------------------------------------------

class _Frame {
  final String id;
  final int flags; // 16 bit, as stored
  final Uint8List data;
  _Frame(this.id, this.flags, this.data);
}

const _managedIds = {
  'TIT2', 'TPE1', 'TPE2', 'TALB', 'TCON', 'TYER', 'TDRC', 'TDAT', 'TIME',
  'TRCK', 'TPOS', 'TCOM',
};

const _v22to23 = {
  'TT1': 'TIT1', 'TT3': 'TIT3', 'TP3': 'TPE3', 'TP4': 'TPE4', 'TXT': 'TEXT',
  'TLA': 'TLAN', 'TBP': 'TBPM', 'TCR': 'TCOP', 'TEN': 'TENC', 'TPB': 'TPUB',
  'TRC': 'TSRC', 'ULT': 'USLT', 'TXX': 'TXXX',
};

void _writeMp3(String path, TagData t, PictureEdit? picture) {
  final raf = File(path).openSync();
  int oldTotal = 0;
  int ver = 3;
  final frames = <_Frame>[];
  Uint8List? v1;
  int fileLen = 0;
  try {
    fileLen = raf.lengthSync();
    final head = _readAt(raf, 0, 10);
    if (head.length == 10 &&
        head[0] == 0x49 &&
        head[1] == 0x44 &&
        head[2] == 0x33) {
      final oldVer = head[3];
      final flags = head[5];
      final size = _syncsafe(head, 6);
      oldTotal = 10 + size + ((oldVer == 4 && (flags & 0x10) != 0) ? 10 : 0);
      final tag = _readAt(raf, 0, 10 + size);
      _collectFrames(tag, frames);
      ver = oldVer == 4 ? 4 : 3;
    }
    if (fileLen >= 128) {
      final tail = _readAt(raf, fileLen - 128, 128);
      if (tail[0] == 0x54 && tail[1] == 0x41 && tail[2] == 0x47) v1 = tail;
    }
  } finally {
    raf.closeSync();
  }

  // Drop the frames we manage, then add fresh ones.
  frames.removeWhere((f) {
    if (_managedIds.contains(f.id)) return true;
    if (f.id == 'COMM') return !_isItunesComment(f.data);
    if (f.id == 'APIC') return picture != null;
    return false;
  });
  void addText(String id, String? value) {
    final v = _nz(value);
    if (v == null) return;
    frames.add(_Frame(id, 0, _encodeText(v, ver)));
  }

  addText('TIT2', t.title);
  addText('TPE1', t.artist);
  addText('TPE2', t.albumArtist);
  addText('TALB', t.album);
  addText('TCON', t.genre);
  if (t.year != null && t.year! > 0) addText(ver == 4 ? 'TDRC' : 'TYER', '${t.year}');
  addText('TRCK', _pair(t.track, t.trackTotal));
  addText('TPOS', _pair(t.disc, t.discTotal));
  addText('TCOM', t.composer);
  final comment = _nz(t.comment);
  if (comment != null) frames.add(_Frame('COMM', 0, _encodeComment(comment, ver)));
  if (picture != null && !picture.remove && picture.bytes != null) {
    final apic = BytesBuilder()
      ..addByte(0)
      ..add(latin1.encode(picture.mime))
      ..addByte(0)
      ..addByte(3) // front cover
      ..addByte(0) // empty description
      ..add(picture.bytes!);
    frames.add(_Frame('APIC', 0, apic.takeBytes()));
  }

  final body = BytesBuilder();
  for (final f in frames) {
    body.add(latin1.encode(f.id));
    body.add(ver == 4 ? _syncsafeb(f.data.length) : _be32b(f.data.length));
    body.addByte((f.flags >> 8) & 0xFF);
    body.addByte(f.flags & 0xFF);
    body.add(f.data);
  }
  final framesBytes = body.takeBytes();

  if (oldTotal > 0 && framesBytes.length <= oldTotal - 10) {
    // Fits in the existing tag: overwrite in place, padding with zeros.
    final tag = BytesBuilder()
      ..add([0x49, 0x44, 0x33, ver, 0, 0])
      ..add(_syncsafeb(oldTotal - 10))
      ..add(framesBytes)
      ..add(Uint8List(oldTotal - 10 - framesBytes.length));
    final w = File(path).openSync(mode: FileMode.append);
    try {
      w.setPositionSync(0);
      w.writeFromSync(tag.takeBytes());
      if (v1 != null) {
        w.setPositionSync(fileLen - 128);
        w.writeFromSync(_buildV1(t, v1));
      }
    } finally {
      w.closeSync();
    }
  } else {
    const padding = 2048;
    final tag = BytesBuilder()
      ..add([0x49, 0x44, 0x33, ver, 0, 0])
      ..add(_syncsafeb(framesBytes.length + padding))
      ..add(framesBytes)
      ..add(Uint8List(padding));
    _rewrite(path, tag.takeBytes(), oldTotal);
    if (v1 != null) {
      final w = File(path).openSync(mode: FileMode.append);
      try {
        final l = w.lengthSync();
        w.setPositionSync(l - 128);
        w.writeFromSync(_buildV1(t, v1));
      } finally {
        w.closeSync();
      }
    }
  }
}

bool _isItunesComment(Uint8List d) {
  if (d.length < 5) return false;
  final enc = d[0];
  final descBytes = d.sublist(4);
  String desc;
  if (enc == 1 || enc == 2) {
    final units = <int>[];
    var o = 0;
    var le = enc == 1;
    if (descBytes.length >= 2 && descBytes[0] == 0xFF && descBytes[1] == 0xFE) {
      o = 2;
      le = true;
    } else if (descBytes.length >= 2 &&
        descBytes[0] == 0xFE &&
        descBytes[1] == 0xFF) {
      o = 2;
      le = false;
    }
    for (; o + 1 < descBytes.length; o += 2) {
      final u = le
          ? descBytes[o] | (descBytes[o + 1] << 8)
          : (descBytes[o] << 8) | descBytes[o + 1];
      if (u == 0) break;
      units.add(u);
    }
    desc = String.fromCharCodes(units);
  } else {
    final end = descBytes.indexOf(0);
    desc = latin1.decode(end < 0 ? descBytes : descBytes.sublist(0, end),
        allowInvalid: true);
  }
  return desc.startsWith('iTun');
}

/// Reads the frames of an existing tag so unknown frames can be preserved.
void _collectFrames(Uint8List tag, List<_Frame> out) {
  final ver = tag[3];
  final flags = tag[5];
  final size = _syncsafe(tag, 6);
  var body = tag.sublist(10, (10 + size).clamp(10, tag.length));
  if (ver <= 3 && (flags & 0x80) != 0) {
    final tmp = <int>[];
    for (var i = 0; i < body.length; i++) {
      tmp.add(body[i]);
      if (body[i] == 0xFF && i + 1 < body.length && body[i + 1] == 0) i++;
    }
    body = Uint8List.fromList(tmp);
  }
  var pos = 0;
  if ((flags & 0x40) != 0 && ver >= 3 && body.length >= 4) {
    pos = ver == 3 ? 4 + _be32(body, 0) : _syncsafe(body, 0);
  }
  final idLen = ver == 2 ? 3 : 4;
  final hdrLen = ver == 2 ? 6 : 10;
  while (pos + hdrLen <= body.length) {
    if (body[pos] == 0) break;
    final id = latin1.decode(body.sublist(pos, pos + idLen));
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(id)) break;
    int fsize;
    var fl = 0;
    if (ver == 2) {
      fsize = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5];
    } else if (ver == 4) {
      fsize = _syncsafe(body, pos + 4);
      fl = (body[pos + 8] << 8) | body[pos + 9];
    } else {
      fsize = _be32(body, pos + 4);
      fl = (body[pos + 8] << 8) | body[pos + 9];
    }
    pos += hdrLen;
    if (fsize <= 0 || pos + fsize > body.length) break;
    var data = body.sublist(pos, pos + fsize);
    pos += fsize;

    if (ver == 2) {
      // Convert the few v2.2 frames worth keeping to v2.3.
      if (id == 'PIC' && data.length > 5) {
        final fmt = latin1.decode(data.sublist(1, 4)).toUpperCase();
        final mime = fmt == 'PNG' ? 'image/png' : 'image/jpeg';
        final conv = BytesBuilder()
          ..addByte(data[0])
          ..add(latin1.encode(mime))
          ..addByte(0)
          ..add(data.sublist(4));
        out.add(_Frame('APIC', 0, conv.takeBytes()));
      } else if (_v22to23.containsKey(id)) {
        out.add(_Frame(_v22to23[id]!, 0, data));
      } else if (id == 'COM') {
        out.add(_Frame('COMM', 0, data));
      } else if (id == 'TT2' || id == 'TP1' || id == 'TP2' || id == 'TAL') {
        // managed; dropped by caller anyway
      }
      continue;
    }
    if (ver == 4) {
      final fmt = fl & 0xFF;
      if ((fmt & 0x0C) == 0) {
        // Decode per-frame unsync / data length / grouping so the frame can
        // be stored cleanly with flags cleared.
        var skip = 0;
        if ((fmt & 0x40) != 0) skip += 1;
        if ((fmt & 0x01) != 0) skip += 4;
        if (skip > 0 && data.length >= skip) data = data.sublist(skip);
        if ((fmt & 0x02) != 0) {
          final tmp = <int>[];
          for (var i = 0; i < data.length; i++) {
            tmp.add(data[i]);
            if (data[i] == 0xFF && i + 1 < data.length && data[i + 1] == 0) i++;
          }
          data = Uint8List.fromList(tmp);
        }
        fl = fl & 0xFF00; // keep status flags only
      }
    } else if (ver == 3) {
      // v2.3 frames are stored exactly as they were.
    }
    out.add(_Frame(id, fl, data));
  }
}

Uint8List _encodeText(String v, int ver) {
  final b = BytesBuilder();
  if (ver == 4) {
    b.addByte(3);
    b.add(utf8.encode(v));
  } else if (v.codeUnits.every((c) => c < 0x100)) {
    b.addByte(0);
    b.add(latin1.encode(v));
  } else {
    b.addByte(1);
    b.add(_utf16le(v));
  }
  return b.takeBytes();
}

List<int> _utf16le(String s) {
  final out = <int>[0xFF, 0xFE];
  for (final u in s.codeUnits) {
    out
      ..add(u & 0xFF)
      ..add(u >> 8);
  }
  return out;
}

Uint8List _encodeComment(String v, int ver) {
  final b = BytesBuilder();
  if (ver == 4) {
    b
      ..addByte(3)
      ..add(latin1.encode('eng'))
      ..addByte(0)
      ..add(utf8.encode(v));
  } else if (v.codeUnits.every((c) => c < 0x100)) {
    b
      ..addByte(0)
      ..add(latin1.encode('eng'))
      ..addByte(0)
      ..add(latin1.encode(v));
  } else {
    b
      ..addByte(1)
      ..add(latin1.encode('eng'))
      ..add([0xFF, 0xFE, 0, 0])
      ..add(_utf16le(v));
  }
  return b.takeBytes();
}

Uint8List _buildV1(TagData t, Uint8List old) {
  final out = Uint8List.fromList(old);
  void put(int o, int n, String? s) {
    final v = (s ?? '').codeUnits.map((c) => c < 0x100 ? c : 0x3F).toList();
    for (var i = 0; i < n; i++) {
      out[o + i] = i < v.length ? v[i] : 0;
    }
  }

  put(3, 30, t.title);
  put(33, 30, t.artist);
  put(63, 30, t.album);
  put(93, 4, (t.year ?? 0) > 0 ? '${t.year}' : '');
  put(97, 28, t.comment);
  out[125] = 0;
  out[126] = (t.track ?? 0).clamp(0, 255);
  final g = id3Genres.indexWhere(
      (x) => x.toLowerCase() == (t.genre ?? '').toLowerCase());
  out[127] = g >= 0 ? g : 255;
  return out;
}

// ---------------------------------------------------------------------------
// FLAC
// ---------------------------------------------------------------------------

const _managedVorbis = {
  'TITLE', 'ARTIST', 'ALBUMARTIST', 'ALBUM ARTIST', 'ALBUM_ARTIST', 'ALBUM',
  'GENRE', 'DATE', 'YEAR', 'TRACKNUMBER', 'TRACKTOTAL', 'TOTALTRACKS',
  'DISCNUMBER', 'DISCTOTAL', 'TOTALDISCS', 'COMPOSER', 'COMMENT',
  'DESCRIPTION',
};

class _Block {
  final int type;
  final Uint8List data;
  _Block(this.type, this.data);
}

void _writeFlac(String path, TagData t, PictureEdit? picture) {
  final raf = File(path).openSync();
  int flacStart = 0;
  int audioStart = 0;
  final blocks = <_Block>[];
  try {
    final head = _readAt(raf, 0, 10);
    if (head.length == 10 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) {
      flacStart = 10 + _syncsafe(head, 6);
    }
    final magic = _readAt(raf, flacStart, 4);
    if (latin1.decode(magic) != 'fLaC') {
      throw const FormatException('Not a FLAC file');
    }
    var pos = flacStart + 4;
    final len = raf.lengthSync();
    while (pos + 4 <= len) {
      final h = _readAt(raf, pos, 4);
      final last = (h[0] & 0x80) != 0;
      final type = h[0] & 0x7F;
      final blen = (h[1] << 16) | (h[2] << 8) | h[3];
      pos += 4;
      blocks.add(_Block(type, _readAt(raf, pos, blen)));
      pos += blen;
      if (last) break;
    }
    audioStart = pos;
  } finally {
    raf.closeSync();
  }

  // Vorbis comment block.
  var vendor = 'BitPlayer';
  final keep = <String>[];
  final vcIndex = blocks.indexWhere((b) => b.type == 4);
  if (vcIndex >= 0) {
    final d = blocks[vcIndex].data;
    var o = 0;
    final vlen = _le32(d, o);
    vendor = utf8.decode(d.sublist(4, 4 + vlen), allowMalformed: true);
    o = 4 + vlen;
    final count = _le32(d, o);
    o += 4;
    for (var i = 0; i < count && o + 4 <= d.length; i++) {
      final l = _le32(d, o);
      o += 4;
      if (o + l > d.length) break;
      final s = utf8.decode(d.sublist(o, o + l), allowMalformed: true);
      o += l;
      final eq = s.indexOf('=');
      final key = eq > 0 ? s.substring(0, eq).toUpperCase() : '';
      if (_managedVorbis.contains(key)) continue;
      if (picture != null && key == 'METADATA_BLOCK_PICTURE') continue;
      keep.add(s);
    }
  }
  void add(String k, String? v) {
    final s = _nz(v);
    if (s != null) keep.add('$k=$s');
  }

  add('TITLE', t.title);
  add('ARTIST', t.artist);
  add('ALBUMARTIST', t.albumArtist);
  add('ALBUM', t.album);
  add('GENRE', t.genre);
  if ((t.year ?? 0) > 0) add('DATE', '${t.year}');
  if ((t.track ?? 0) > 0) add('TRACKNUMBER', '${t.track}');
  if ((t.trackTotal ?? 0) > 0) add('TRACKTOTAL', '${t.trackTotal}');
  if ((t.disc ?? 0) > 0) add('DISCNUMBER', '${t.disc}');
  if ((t.discTotal ?? 0) > 0) add('DISCTOTAL', '${t.discTotal}');
  add('COMPOSER', t.composer);
  add('COMMENT', t.comment);

  final vc = BytesBuilder();
  final vb = utf8.encode(vendor);
  vc
    ..add(_le32b(vb.length))
    ..add(vb)
    ..add(_le32b(keep.length));
  for (final s in keep) {
    final e = utf8.encode(s);
    vc
      ..add(_le32b(e.length))
      ..add(e);
  }
  final vcBlock = _Block(4, vc.takeBytes());

  final out = <_Block>[];
  for (final b in blocks) {
    if (b.type == 1) continue; // padding: recomputed
    if (b.type == 4) continue;
    if (b.type == 6 && picture != null) continue;
    out.add(b);
  }
  // STREAMINFO must stay first; put comments right after it.
  out.insert(out.isEmpty ? 0 : 1, vcBlock);
  if (picture != null && !picture.remove && picture.bytes != null) {
    final mime = latin1.encode(picture.mime);
    final pb = BytesBuilder()
      ..add(_be32b(3))
      ..add(_be32b(mime.length))
      ..add(mime)
      ..add(_be32b(0)) // description length
      ..add(_be32b(0)) // width
      ..add(_be32b(0)) // height
      ..add(_be32b(0)) // depth
      ..add(_be32b(0)) // colors
      ..add(_be32b(picture.bytes!.length))
      ..add(picture.bytes!);
    out.add(_Block(6, pb.takeBytes()));
  }
  for (final b in out) {
    if (b.data.length >= (1 << 24)) {
      throw const FormatException('Metadata block too large');
    }
  }

  var needed = 0;
  for (final b in out) {
    needed += 4 + b.data.length;
  }
  final available = audioStart - flacStart - 4;

  List<int> serialize(List<_Block> list) {
    final bb = BytesBuilder();
    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      final last = i == list.length - 1;
      bb
        ..addByte((last ? 0x80 : 0) | b.type)
        ..addByte((b.data.length >> 16) & 0xFF)
        ..addByte((b.data.length >> 8) & 0xFF)
        ..addByte(b.data.length & 0xFF)
        ..add(b.data);
    }
    return bb.takeBytes();
  }

  if (needed == available || available - needed >= 4) {
    if (available - needed >= 4) {
      out.add(_Block(1, Uint8List(available - needed - 4)));
    }
    final bytes = serialize(out);
    final w = File(path).openSync(mode: FileMode.append);
    try {
      w.setPositionSync(flacStart + 4);
      w.writeFromSync(bytes);
    } finally {
      w.closeSync();
    }
  } else {
    out.add(_Block(1, Uint8List(4096)));
    final prefix = BytesBuilder();
    if (flacStart > 0) {
      final r = File(path).openSync();
      try {
        prefix.add(_readAt(r, 0, flacStart));
      } finally {
        r.closeSync();
      }
    }
    prefix
      ..add(latin1.encode('fLaC'))
      ..add(serialize(out));
    _rewrite(path, prefix.takeBytes(), audioStart);
  }
}

/// Convenience: build the managed values of a track.
TagData tagDataFromTrack(Track tr) => tr.toTagData();
