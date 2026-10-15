import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One entry of a CD table of contents.
class CdTocTrack {
  final int number;
  final int startLba;
  final int lengthSectors;
  final bool isAudio;

  /// macOS: the .aiff file the OS exposes for this track.
  final String? filePath;

  const CdTocTrack({
    required this.number,
    required this.startLba,
    required this.lengthSectors,
    required this.isAudio,
    this.filePath,
  });

  /// 75 sectors per second.
  int get durationMs => lengthSectors * 1000 ~/ 75;
}

/// An audio CD in a drive.
class CdDisc {
  /// "D" (Windows drive letter) or "/Volumes/Audio CD" (macOS mount point).
  final String drive;
  final String label;
  final int firstTrack;
  final int lastTrack;
  final int leadoutLba;
  final List<CdTocTrack> tracks;

  CdDisc({
    required this.drive,
    required this.label,
    required this.firstTrack,
    required this.lastTrack,
    required this.leadoutLba,
    required this.tracks,
  });

  List<CdTocTrack> get audioTracks => tracks.where((t) => t.isAudio).toList();

  /// Values used for the MusicBrainz disc id. For Enhanced CDs (audio
  /// session followed by a data track) the data track is excluded and the
  /// leadout is moved back by 11400 sectors, as MusicBrainz specifies.
  (int first, int last, int leadout, List<int> offsets) get _idParts {
    var last = lastTrack;
    var leadout = leadoutLba;
    final byNum = {for (final t in tracks) t.number: t};
    final lastT = byNum[lastTrack];
    if (lastT != null && !lastT.isAudio && lastTrack > firstTrack) {
      last = lastTrack - 1;
      leadout = lastT.startLba - 11400;
    }
    final offsets = <int>[];
    for (var n = firstTrack; n <= last; n++) {
      offsets.add((byNum[n]?.startLba ?? 0) + 150);
    }
    return (firstTrack, last, leadout + 150, offsets);
  }

  String get musicBrainzId {
    final (first, last, leadout, offsets) = _idParts;
    String h2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');
    String h8(int v) => v.toRadixString(16).toUpperCase().padLeft(8, '0');
    final sb = StringBuffer()
      ..write(h2(first))
      ..write(h2(last))
      ..write(h8(leadout));
    for (var i = 1; i <= 99; i++) {
      final idx = i - first;
      sb.write(h8(i >= first && i <= last ? offsets[idx] : 0));
    }
    final digest = sha1.convert(ascii.encode(sb.toString())).bytes;
    return base64
        .encode(digest)
        .replaceAll('+', '.')
        .replaceAll('/', '_')
        .replaceAll('=', '-');
  }

  /// TOC string for MusicBrainz fuzzy matching.
  String get musicBrainzToc {
    final (first, last, leadout, offsets) = _idParts;
    return [first, last, leadout, ...offsets].join('+');
  }

  /// Stable identity for "is this still the same disc?".
  String get identity => '$drive|$musicBrainzId';

  int get totalMs => audioTracks.fold(0, (s, t) => s + t.durationMs);
}

/// A candidate release returned by MusicBrainz.
class MbRelease {
  final String id;
  final String title;
  final String artist;
  final int year;
  final String country;
  final int discNo;
  final int discTotal;
  final List<MbTrack> tracks;
  String? genre;

  MbRelease({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.country,
    required this.discNo,
    required this.discTotal,
    required this.tracks,
    this.genre,
  });

  String get summary {
    final bits = <String>[
      if (year > 0) '$year',
      if (country.isNotEmpty) country,
      if (discTotal > 1) 'disc $discNo of $discTotal',
    ];
    return '$artist — $title${bits.isEmpty ? '' : ' (${bits.join(', ')})'}';
  }
}

class MbTrack {
  final String title;
  final String artist;
  MbTrack(this.title, this.artist);
}
