import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../common/retro_widgets.dart';
import 'edit_tags_page.dart';
import 'mobile_widgets.dart';

AppServices get _s => AppServices.I;

/// Plays [list] from [i] and shows Now Playing.
Future<void> playAndShow(BuildContext context, List<Track> list, int i) async {
  await _s.player.playList(list, i);
  if (context.mounted) openNowPlaying(context);
}

// ---------------------------------------------------------------------------
// Songs
// ---------------------------------------------------------------------------

class SongList extends StatefulWidget {
  const SongList({
    super.key,
    required this.tracks,
    this.searchable = true,
    this.showArt = false,
    this.numbered = false,
    this.playlist,
    this.header,
  });

  final List<Track> tracks;
  final bool searchable;
  final bool showArt;
  final bool numbered;
  final Playlist? playlist;
  final Widget? header;

  @override
  State<SongList> createState() => _SongListState();
}

class _SongListState extends State<SongList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.tracks;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all
            .where((t) => '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(q))
            .toList();
    final extra = (widget.searchable ? 1 : 0) + (widget.header != null ? 1 : 0) + 1;
    return ListView.builder(
      itemCount: list.length + extra,
      itemBuilder: (context, i) {
        var idx = i;
        if (widget.searchable) {
          if (idx == 0) return _searchBox();
          idx--;
        }
        if (widget.header != null) {
          if (idx == 0) return widget.header!;
          idx--;
        }
        if (idx == 0) {
          return RetroRow(
            title: 'Shuffle',
            height: 44,
            leading: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.shuffle, color: Color(0xFF2E5FAE)),
            ),
            highlight: true,
            onTap: list.isEmpty
                ? null
                : () async {
                    if (!_s.settings.shuffle) _s.player.toggleShuffle();
                    await playAndShow(context, list,
                        DateTime.now().microsecond % list.length);
                  },
          );
        }
        idx--;
        final t = list[idx];
        final playing = _s.player.current?.path == t.path;
        return RetroRow(
          title: t.title.isEmpty ? 'Untitled' : t.title,
          subtitle: widget.numbered ? t.displayArtist : '${t.displayArtist} — ${t.displayAlbum}',
          leading: widget.showArt
              ? Thumb(t, size: 50)
              : (widget.numbered
                  ? SizedBox(
                      width: 36,
                      child: Text(t.trackNo > 0 ? '${t.trackNo}' : '',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                    )
                  : null),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (playing)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.volume_up, size: 18, color: Color(0xFF2E5FAE)),
              ),
            Text(formatDuration(t.durationMs),
                style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 13)),
          ]),
          onTap: () => playAndShow(context, list, idx),
          onLongPress: () => songActions(context, t, playlist: widget.playlist),
        );
      },
    );
  }

  Widget _searchBox() => Container(
        color: const Color(0xFFD1D8DF),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: SizedBox(
          height: 32,
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF9AA4AE)),
              ),
            ),
          ),
        ),
      );
}

/// Long-press menu for a song.
Future<void> songActions(BuildContext context, Track t, {Playlist? playlist}) async {
  final v = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${t.displayArtist} — ${t.displayAlbum}'),
        ),
        const Divider(height: 1),
        ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Add to Playlist…'),
            onTap: () => Navigator.pop(ctx, 'add')),
        ListTile(
            leading: const Icon(Icons.album),
            title: const Text('Go to Album'),
            onTap: () => Navigator.pop(ctx, 'album')),
        ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Info'),
            onTap: () => Navigator.pop(ctx, 'edit')),
        if (playlist != null)
          ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Remove from Playlist'),
              onTap: () => Navigator.pop(ctx, 'remove')),
        ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete File', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(ctx, 'delete')),
      ]),
    ),
  );
  if (!context.mounted || v == null) return;
  switch (v) {
    case 'add':
      await addToPlaylistSheet(context, [t]);
      break;
    case 'album':
      final album = _s.library.allTracks.where((x) => x.albumKey == t.albumKey).toList();
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AlbumPage(title: t.displayAlbum, tracks: album)));
      break;
    case 'edit':
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => EditTagsPage(track: t)));
      break;
    case 'remove':
      await _s.library.removeFromPlaylist(playlist!, [t]);
      break;
    case 'delete':
      final ok = await confirm(context,
          title: 'Delete Song',
          message: 'Delete “${t.title}” from this device?',
          ok: 'Delete');
      if (ok) {
        if (_s.player.current?.path == t.path) await _s.player.stop();
        await Plat.trashFiles([t.path]);
        await _s.library.deleteTracks([t], deleteFiles: false);
      }
      break;
  }
}

Future<void> addToPlaylistSheet(BuildContext context, List<Track> tracks) async {
  final pls = _s.library.playlists;
  final v = await showModalBottomSheet<Object>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New Playlist…'),
            onTap: () => Navigator.pop(ctx, 'new')),
        for (final pl in pls)
          ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(pl.name),
              onTap: () => Navigator.pop(ctx, pl)),
      ]),
    ),
  );
  if (!context.mounted || v == null) return;
  if (v == 'new') {
    final name = await promptText(context, title: 'New Playlist', ok: 'Save');
    if (name != null && name.trim().isNotEmpty) {
      await _s.library.createPlaylist(name, tracks);
    }
  } else if (v is Playlist) {
    await _s.library.addToPlaylist(v, tracks);
  }
}

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------

class SongsTab extends StatelessWidget {
  const SongsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_s.library, _s.player]),
      builder: (context, _) {
        final list = List.of(_s.library.allTracks)
          ..sort((a, b) => sortKeyOf(a.title).compareTo(sortKeyOf(b.title)));
        return SongList(tracks: list);
      },
    );
  }
}

class ArtistsTab extends StatelessWidget {
  const ArtistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s.library,
      builder: (context, _) {
        final byArtist = <String, List<Track>>{};
        for (final t in _s.library.allTracks) {
          (byArtist[t.displayAlbumArtist] ??= []).add(t);
        }
        final names = byArtist.keys.toList()
          ..sort((a, b) => sortKeyOf(a).compareTo(sortKeyOf(b)));
        final rows = <Widget>[];
        String? letter;
        for (final n in names) {
          final l = firstLetter(n);
          if (l != letter) {
            rows.add(SectionHeader(l));
            letter = l;
          }
          final tracks = byArtist[n]!;
          final albums = tracks.map((t) => t.albumKey).toSet().length;
          rows.add(RetroRow(
            title: n,
            subtitle: '$albums album${albums == 1 ? '' : 's'}, ${tracks.length} song${tracks.length == 1 ? '' : 's'}',
            chevron: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ArtistPage(name: n, tracks: tracks))),
          ));
        }
        if (rows.isEmpty) return const EmptyLibrary();
        return ListView(children: rows);
      },
    );
  }
}

class AlbumsTab extends StatelessWidget {
  const AlbumsTab({super.key, this.tracks});
  final List<Track>? tracks;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s.library,
      builder: (context, _) {
        final albums = _s.library.albumsOf(tracks ?? _s.library.allTracks)
          ..sort((a, b) => sortKeyOf(a.title).compareTo(sortKeyOf(b.title)));
        if (albums.isEmpty) return const EmptyLibrary();
        return ListView.builder(
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return RetroRow(
              title: a.title,
              subtitle: a.artist,
              height: 60,
              leading: Thumb(a.tracks.first, size: 59),
              chevron: true,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AlbumPage(title: a.title, tracks: a.tracks))),
            );
          },
        );
      },
    );
  }
}

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s.library,
      builder: (context, _) {
        final lib = _s.library;
        return ListView(children: [
          RetroRow(
            title: 'Add Playlist…',
            highlight: true,
            leading: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(Icons.add_circle, color: Color(0xFF2E5FAE)),
            ),
            onTap: () async {
              final name = await promptText(context, title: 'New Playlist', ok: 'Save');
              if (name != null && name.trim().isNotEmpty) {
                await lib.createPlaylist(name);
              }
            },
          ),
          for (final k in SmartList.values)
            RetroRow(
              title: switch (k) {
                SmartList.recentlyAdded => 'Recently Added',
                SmartList.recentlyPlayed => 'Recently Played',
                SmartList.topPlayed => 'Top 25 Most Played',
              },
              leading: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(Icons.settings_suggest, color: Color(0xFF8A57C9)),
              ),
              chevron: true,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ListenableBuilder(
                  listenable: lib,
                  builder: (context, _) => RetroPage(
                    title: 'Playlist',
                    backLabel: 'Playlists',
                    body: SongList(tracks: lib.smartList(k), showArt: true),
                  ),
                ),
              )),
            ),
          for (final pl in lib.playlists)
            RetroRow(
              title: pl.name,
              subtitle: '${pl.paths.length} song${pl.paths.length == 1 ? '' : 's'}',
              leading: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Icon(Icons.queue_music, color: Color(0xFF3E7BD6)),
              ),
              chevron: true,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaylistPage(playlist: pl),
              )),
              onLongPress: () => _playlistMenu(context, pl),
            ),
        ]);
      },
    );
  }

  Future<void> _playlistMenu(BuildContext context, Playlist pl) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete Playlist', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (v == 'rename') {
      final name = await promptText(context, title: 'Rename Playlist', initial: pl.name);
      if (name != null && name.trim().isNotEmpty) {
        await _s.library.renamePlaylist(pl, name.trim());
      }
    } else if (v == 'delete') {
      final ok = await confirm(context,
          title: 'Delete Playlist', message: 'Delete “${pl.name}”?', ok: 'Delete');
      if (ok) await _s.library.deletePlaylist(pl);
    }
  }
}

class GenresPage extends StatelessWidget {
  const GenresPage({super.key});

  @override
  Widget build(BuildContext context) {
    final byGenre = <String, List<Track>>{};
    for (final t in _s.library.allTracks) {
      (byGenre[t.displayGenre] ??= []).add(t);
    }
    final names = byGenre.keys.toList()..sort();
    return RetroPage(
      title: 'Genres',
      backLabel: 'More',
      body: ListView(children: [
        for (final g in names)
          RetroRow(
            title: g,
            subtitle: '${byGenre[g]!.length} songs',
            chevron: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RetroPage(
                title: g,
                backLabel: 'Genres',
                body: AlbumsTab(tracks: byGenre[g]),
              ),
            )),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Drill-down pages
// ---------------------------------------------------------------------------

class ArtistPage extends StatelessWidget {
  const ArtistPage({super.key, required this.name, required this.tracks});
  final String name;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final albums = _s.library.albumsOf(tracks);
    return RetroPage(
      title: name,
      backLabel: 'Artists',
      body: ListView(children: [
        RetroRow(
          title: 'All Songs',
          highlight: true,
          chevron: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RetroPage(
                  title: name,
                  body: SongList(tracks: tracks, searchable: false, showArt: true)))),
        ),
        for (final a in albums)
          RetroRow(
            title: a.title,
            subtitle: a.year > 0 ? '${a.year}' : null,
            height: 60,
            leading: Thumb(a.tracks.first, size: 59),
            chevron: true,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AlbumPage(title: a.title, tracks: a.tracks))),
          ),
      ]),
    );
  }
}

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key, required this.title, required this.tracks});
  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final first = tracks.isNotEmpty ? tracks.first : null;
    final total = _s.library.totalDuration(tracks);
    return RetroPage(
      title: title,
      body: ListenableBuilder(
        listenable: _s.player,
        builder: (context, _) => SongList(
          tracks: tracks,
          searchable: false,
          numbered: true,
          header: first == null
              ? null
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFE8EBEE), Color(0xFFC9CFD5)],
                    ),
                  ),
                  child: Row(children: [
                    Thumb(first, size: 100),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(first.displayAlbumArtist,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(first.displayAlbum, style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 6),
                          Text(
                              '${first.year > 0 ? 'Released ${first.year}\n' : ''}'
                              '${tracks.length} songs, ${(total / 60000).round()} mins',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF555555))),
                        ],
                      ),
                    ),
                  ]),
                ),
        ),
      ),
    );
  }
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_s.library, _s.player]),
      builder: (context, _) => RetroPage(
        title: playlist.name,
        backLabel: 'Playlists',
        body: SongList(
          tracks: _s.library.playlistTracks(playlist),
          showArt: true,
          playlist: playlist,
        ),
      ),
    );
  }
}

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = _s.player;
    return Scaffold(
      appBar: const RetroNavBar(title: 'Up Next', showBack: true, showNowPlaying: false),
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) {
          final q = p.queue;
          return ListView.builder(
            itemCount: q.length,
            itemBuilder: (context, i) {
              final t = q[i];
              final cur = p.current?.path == t.path;
              return RetroRow(
                title: t.title,
                subtitle: t.displayArtist,
                highlight: cur,
                leading: Thumb(t, size: 50),
                onTap: () => p.jumpTo(i),
              );
            },
          );
        },
      ),
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = _s.library;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.library_music, size: 64, color: Color(0xFFB5B5B5)),
          const SizedBox(height: 12),
          Text(
            lib.scanning ? 'Looking for music…' : 'No music found',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            lib.scanning
                ? lib.scanStatus
                : 'Copy your music folder to\n${lib.root}\n(or choose another folder in More ▸ Settings).',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF777777)),
          ),
        ]),
      ),
    );
  }
}
