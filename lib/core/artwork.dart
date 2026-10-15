import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'tags/tag_reader.dart';

/// Extracts album artwork (embedded or folder.jpg/cover.jpg) and caches it
/// on disk, one image per album.
class ArtworkCache {
  ArtworkCache(this.supportDir);

  final String supportDir;
  final Map<String, Future<File?>> _pending = {};

  /// Extra art for non-library tracks (CD tracks), keyed by path.
  final Map<String, String> overrides = {};

  String get _dir => p.join(supportDir, 'artwork');

  String _hash(String s) => sha1.convert(utf8.encode(s)).toString();

  /// Returns a cached image file for the album of [t], or null.
  Future<File?> forTrack(Track t) {
    final override = overrides[t.path];
    if (override != null) return Future.value(File(override));
    final key = t.albumKey;
    return _pending[key] ??= _load(t, key);
  }

  Future<File?> _load(Track t, String key) async {
    final file = File(p.join(_dir, '${_hash(key)}.img'));
    final none = File(p.join(_dir, '${_hash(key)}.none'));
    if (await file.exists()) return file;
    if (await none.exists()) {
      // Negative result older than a day gets retried.
      final age = DateTime.now().difference(await none.lastModified());
      if (age.inHours < 24) return null;
    }
    if (t.isCd) return null;
    final bytes = await _extractInIsolate(t.path);
    await Directory(_dir).create(recursive: true);
    if (bytes == null) {
      try {
        await none.writeAsString('');
      } catch (_) {}
      return null;
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Forget the cached art for an album (after an edit).
  Future<void> invalidate(Track t) async {
    final key = t.albumKey;
    _pending.remove(key);
    final file = File(p.join(_dir, '${_hash(key)}.img'));
    final none = File(p.join(_dir, '${_hash(key)}.none'));
    try {
      if (await file.exists()) {
        await FileImage(file).evict();
        await file.delete();
      }
      if (await none.exists()) await none.delete();
    } catch (_) {}
  }

  /// Reads the embedded picture of a single file (for the Get Info dialog).
  static Future<Uint8List?> embeddedPicture(String path) => _extractInIsolate(path);
}

Future<Uint8List?> _extractInIsolate(String path) =>
    Isolate.run(() => _extractArt(path));

Uint8List? _extractArt(String path) {
  final t = readTags(path, withPicture: true);
  if (t.picture != null && t.picture!.isNotEmpty) return t.picture;
  // Folder images, in iTunes / Windows Media Player / foobar order.
  final dir = Directory(p.dirname(path));
  if (!dir.existsSync()) return null;
  const preferred = [
    'cover', 'folder', 'front', 'albumart', 'album', 'albumartsmall',
  ];
  List<File> images;
  try {
    images = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final e = p.extension(f.path).toLowerCase();
          return e == '.jpg' || e == '.jpeg' || e == '.png';
        })
        .toList();
  } catch (_) {
    return null;
  }
  if (images.isEmpty) return null;
  images.sort((a, b) {
    int rank(File f) {
      final n = p.basenameWithoutExtension(f.path).toLowerCase();
      for (var i = 0; i < preferred.length; i++) {
        if (n == preferred[i] || n.startsWith(preferred[i])) return i;
      }
      return preferred.length;
    }

    return rank(a).compareTo(rank(b));
  });
  try {
    return images.first.readAsBytesSync();
  } catch (_) {
    return null;
  }
}
