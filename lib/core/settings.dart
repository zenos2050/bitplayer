import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform.dart';

enum LoopMode { off, all, one }

enum RipFormat { mp3, aac, alac, flac, ogg, wav }

extension RipFormatInfo on RipFormat {
  String get label => switch (this) {
        RipFormat.mp3 => 'MP3 Encoder',
        RipFormat.aac => 'AAC Encoder',
        RipFormat.alac => 'Apple Lossless Encoder',
        RipFormat.flac => 'FLAC Encoder',
        RipFormat.ogg => 'Ogg Vorbis Encoder',
        RipFormat.wav => 'WAV Encoder',
      };
  String get extension => switch (this) {
        RipFormat.mp3 => 'mp3',
        RipFormat.aac => 'm4a',
        RipFormat.alac => 'm4a',
        RipFormat.flac => 'flac',
        RipFormat.ogg => 'ogg',
        RipFormat.wav => 'wav',
      };
}

/// Persistent application settings (JSON file in the app support folder).
class Settings extends ChangeNotifier {
  late File _file;
  late String supportDir;

  String libraryPath = '';
  String ffmpegPath = '';
  RipFormat ripFormat = RipFormat.mp3;

  /// MP3 bitrate in kbps; 0 = VBR V0.
  int mp3Bitrate = 320;
  bool keepOrganized = true;
  bool autoLookupCd = true;
  bool ejectAfterImport = false;
  bool playWhileImporting = false;
  double volume = 80;
  bool shuffle = false;
  LoopMode repeat = LoopMode.off;
  bool showBrowser = false;
  bool showArtwork = true;
  String viewMode = 'list'; // list | albums

  Future<void> load() async {
    final dir = await getApplicationSupportDirectory();
    supportDir = dir.path;
    await dir.create(recursive: true);
    _file = File(p.join(dir.path, 'settings.json'));
    if (await _file.exists()) {
      try {
        final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        libraryPath = (j['libraryPath'] ?? '') as String;
        ffmpegPath = (j['ffmpegPath'] ?? '') as String;
        ripFormat = RipFormat.values.firstWhere(
            (f) => f.name == j['ripFormat'],
            orElse: () => RipFormat.mp3);
        mp3Bitrate = (j['mp3Bitrate'] ?? 320) as int;
        keepOrganized = (j['keepOrganized'] ?? true) as bool;
        autoLookupCd = (j['autoLookupCd'] ?? true) as bool;
        ejectAfterImport = (j['ejectAfterImport'] ?? false) as bool;
        playWhileImporting = (j['playWhileImporting'] ?? false) as bool;
        volume = ((j['volume'] ?? 80) as num).toDouble();
        shuffle = (j['shuffle'] ?? false) as bool;
        repeat = LoopMode.values.firstWhere((r) => r.name == j['repeat'],
            orElse: () => LoopMode.off);
        showBrowser = (j['showBrowser'] ?? false) as bool;
        showArtwork = (j['showArtwork'] ?? true) as bool;
        viewMode = (j['viewMode'] ?? 'list') as String;
      } catch (_) {}
    }
    if (libraryPath.isEmpty) {
      libraryPath = await defaultLibraryPath();
    }
  }

  Future<void> save() async {
    final j = {
      'libraryPath': libraryPath,
      'ffmpegPath': ffmpegPath,
      'ripFormat': ripFormat.name,
      'mp3Bitrate': mp3Bitrate,
      'keepOrganized': keepOrganized,
      'autoLookupCd': autoLookupCd,
      'ejectAfterImport': ejectAfterImport,
      'playWhileImporting': playWhileImporting,
      'volume': volume,
      'shuffle': shuffle,
      'repeat': repeat.name,
      'showBrowser': showBrowser,
      'showArtwork': showArtwork,
      'viewMode': viewMode,
    };
    try {
      await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(j));
    } catch (_) {}
  }

  void update(void Function(Settings s) change) {
    change(this);
    notifyListeners();
    save();
  }

  static Future<String> defaultLibraryPath() async {
    if (Plat.isAndroid) {
      return '/storage/emulated/0/Music';
    }
    if (Plat.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, 'Music');
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        (await getApplicationDocumentsDirectory()).path;
    return p.join(home, 'Music', 'BitPlayer');
  }
}
