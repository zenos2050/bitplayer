import 'package:flutter/foundation.dart';

import '../../core/app_services.dart';
import '../../core/cd/cd_service.dart';
import '../../core/library.dart';
import '../../core/models.dart';

/// What is selected in the source list.
sealed class Source {
  const Source();
  String get id;
  String get title;
}

class LibrarySource extends Source {
  const LibrarySource();
  @override
  String get id => 'library';
  @override
  String get title => 'Music';
}

class SmartSource extends Source {
  const SmartSource(this.kind);
  final SmartList kind;
  @override
  String get id => 'smart:${kind.name}';
  @override
  String get title => switch (kind) {
        SmartList.recentlyAdded => 'Recently Added',
        SmartList.recentlyPlayed => 'Recently Played',
        SmartList.topPlayed => 'Top 25 Most Played',
      };
}

class PlaylistSource extends Source {
  const PlaylistSource(this.playlist);
  final Playlist playlist;
  @override
  String get id => 'pl:${playlist.filePath}';
  @override
  String get title => playlist.name;
}

class CdSource extends Source {
  const CdSource(this.disc);
  final CdDiscState disc;
  @override
  String get id => 'cd:${disc.disc.identity}';
  @override
  String get title => disc.title;
}

enum SortKey { none, name, time, artist, album, genre, rating, plays, year, added }

/// UI state of the desktop window (selection, sorting, filters, view).
class DesktopController extends ChangeNotifier {
  DesktopController() {
    _lib.addListener(_onLibrary);
    AppServices.I.cd?.addListener(_onCd);
  }

  final LibraryService _lib = AppServices.I.library;

  Source source = const LibrarySource();
  String search = '';
  SortKey sortKey = SortKey.none;
  bool ascending = true;
  String? browseGenre;
  String? browseArtist;
  String? browseAlbum;

  /// Selected track paths.
  final Set<String> selection = {};
  int? _anchor;

  String? _cacheSig;
  List<Track> _cache = const [];

  @override
  void dispose() {
    _lib.removeListener(_onLibrary);
    AppServices.I.cd?.removeListener(_onCd);
    super.dispose();
  }

  void _onLibrary() {
    // Drop playlist selection if the playlist vanished.
    final s = source;
    if (s is PlaylistSource && !_lib.playlists.contains(s.playlist)) {
      final match = _lib.playlists
          .where((p) => p.filePath == s.playlist.filePath)
          .toList();
      source = match.isNotEmpty ? PlaylistSource(match.first) : const LibrarySource();
    }
    notifyListeners();
  }

  void _onCd() {
    final s = source;
    if (s is CdSource && !(AppServices.I.cd?.discs.contains(s.disc) ?? false)) {
      source = const LibrarySource();
    }
    notifyListeners();
  }

  void select(Source s) {
    source = s;
    selection.clear();
    _anchor = null;
    browseGenre = browseArtist = browseAlbum = null;
    sortKey = SortKey.none;
    notifyListeners();
  }

  bool isSelected(Source s) => s.id == source.id;

  void setSearch(String v) {
    search = v;
    notifyListeners();
  }

  void sortBy(SortKey k) {
    if (sortKey == k) {
      ascending = !ascending;
    } else {
      sortKey = k;
      ascending = true;
    }
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Track lists
  // -------------------------------------------------------------------------

  List<Track> baseTracks() {
    final s = source;
    return switch (s) {
      LibrarySource() => _lib.allTracks,
      SmartSource(:final kind) => _lib.smartList(kind),
      PlaylistSource(:final playlist) => _lib.playlistTracks(playlist),
      CdSource(:final disc) => disc.tracks,
    };
  }

  List<Track> _searched() {
    final base = baseTracks();
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return base;
    final words = q.split(RegExp(r'\s+'));
    return base.where((t) {
      final hay =
          '${t.title} ${t.artist} ${t.albumArtist} ${t.album} ${t.genre} ${t.composer}'
              .toLowerCase();
      return words.every(hay.contains);
    }).toList();
  }

  /// Genres / artists / albums for the column browser.
  List<String> browserGenres() {
    final set = <String>{for (final t in _searched()) t.displayGenre};
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> browserArtists() {
    final set = <String>{
      for (final t in _searched())
        if (browseGenre == null || t.displayGenre == browseGenre) t.displayAlbumArtist
    };
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> browserAlbums() {
    final set = <String>{
      for (final t in _searched())
        if ((browseGenre == null || t.displayGenre == browseGenre) &&
            (browseArtist == null || t.displayAlbumArtist == browseArtist))
          t.displayAlbum
    };
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  void browse({Object? genre = _keep, Object? artist = _keep, Object? album = _keep}) {
    if (genre != _keep) {
      browseGenre = genre as String?;
      browseArtist = null;
      browseAlbum = null;
    }
    if (artist != _keep) {
      browseArtist = artist as String?;
      browseAlbum = null;
    }
    if (album != _keep) browseAlbum = album as String?;
    selection.clear();
    notifyListeners();
  }

  static const _keep = Object();

  /// The tracks currently shown in the song list.
  List<Track> get visibleTracks {
    final sig = '${_lib.version}|${source.id}|$search|$browseGenre|$browseArtist|'
        '$browseAlbum|$sortKey|$ascending|${AppServices.I.cd?.hashCode}';
    if (sig == _cacheSig && source is! CdSource) return _cache;
    var list = _searched();
    if (browseGenre != null || browseArtist != null || browseAlbum != null) {
      list = list
          .where((t) =>
              (browseGenre == null || t.displayGenre == browseGenre) &&
              (browseArtist == null || t.displayAlbumArtist == browseArtist) &&
              (browseAlbum == null || t.displayAlbum == browseAlbum))
          .toList();
    }
    if (sortKey != SortKey.none) {
      list = List.of(list);
      int cmpS(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
      int c(Track a, Track b) {
        final r = switch (sortKey) {
          SortKey.name => cmpS(a.title, b.title),
          SortKey.time => a.durationMs.compareTo(b.durationMs),
          SortKey.artist => cmpS(a.displayArtist, b.displayArtist) != 0
              ? cmpS(a.displayArtist, b.displayArtist)
              : LibraryService.compareAlbumOrder(a, b),
          SortKey.album => cmpS(a.displayAlbum, b.displayAlbum) != 0
              ? cmpS(a.displayAlbum, b.displayAlbum)
              : LibraryService.compareAlbumOrder(a, b),
          SortKey.genre => cmpS(a.displayGenre, b.displayGenre) != 0
              ? cmpS(a.displayGenre, b.displayGenre)
              : LibraryService.compareAlbumOrder(a, b),
          SortKey.rating => a.rating.compareTo(b.rating),
          SortKey.plays => a.playCount.compareTo(b.playCount),
          SortKey.year => a.year.compareTo(b.year),
          SortKey.added => a.dateAddedMs.compareTo(b.dateAddedMs),
          SortKey.none => 0,
        };
        return ascending ? r : -r;
      }

      list.sort(c);
    }
    _cacheSig = sig;
    _cache = list;
    return list;
  }

  // -------------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------------

  List<Track> get selectedTracks =>
      visibleTracks.where((t) => selection.contains(t.path)).toList();

  void clickRow(int index, {bool ctrl = false, bool shift = false}) {
    final list = visibleTracks;
    if (index < 0 || index >= list.length) return;
    final path = list[index].path;
    if (shift && _anchor != null) {
      final a = _anchor!.clamp(0, list.length - 1);
      final lo = a < index ? a : index;
      final hi = a < index ? index : a;
      if (!ctrl) selection.clear();
      for (var i = lo; i <= hi; i++) {
        selection.add(list[i].path);
      }
    } else if (ctrl) {
      if (!selection.remove(path)) selection.add(path);
      _anchor = index;
    } else {
      selection
        ..clear()
        ..add(path);
      _anchor = index;
    }
    notifyListeners();
  }

  /// Right-click keeps an existing multi-selection.
  void ensureSelected(int index) {
    final list = visibleTracks;
    if (index < 0 || index >= list.length) return;
    if (!selection.contains(list[index].path)) clickRow(index);
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(visibleTracks.map((t) => t.path));
    notifyListeners();
  }

  void moveSelection(int delta, {bool shift = false}) {
    final list = visibleTracks;
    if (list.isEmpty) return;
    var cur = _anchor ?? -1;
    if (selection.isNotEmpty && _anchor == null) {
      cur = list.indexWhere((t) => selection.contains(t.path));
    }
    final next = (cur + delta).clamp(0, list.length - 1);
    if (shift) {
      selection.add(list[next].path);
      _anchor = next;
      notifyListeners();
    } else {
      clickRow(next);
    }
  }

  int? get anchor => _anchor;

  void refresh() => notifyListeners();
}
