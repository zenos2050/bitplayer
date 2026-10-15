import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../common/retro_widgets.dart';
import 'desktop_controller.dart';
import 'get_info_dialog.dart';

/// Commands shared by the menu bar, context menus and keyboard shortcuts.
class DesktopActions {
  DesktopActions(this.ctrl);
  final DesktopController ctrl;

  AppServices get s => AppServices.I;

  Future<void> playSelectedOrFirst() async {
    final list = ctrl.visibleTracks;
    if (list.isEmpty) return;
    final sel = ctrl.selectedTracks;
    final idx = sel.isEmpty ? 0 : list.indexOf(sel.first);
    await s.player.playList(list, idx < 0 ? 0 : idx);
  }

  Future<void> playIndex(int index) async {
    final list = ctrl.visibleTracks;
    if (index < 0 || index >= list.length) return;
    await s.player.playList(list, index);
  }

  Future<void> getInfo(BuildContext context, [List<Track>? tracks]) async {
    final t = tracks ?? ctrl.selectedTracks;
    if (t.isEmpty || t.any((x) => x.isCd)) return;
    await showGetInfo(context, t);
    ctrl.refresh();
  }

  Future<void> newPlaylist(BuildContext context, {List<Track>? from}) async {
    final name = await promptText(context,
        title: 'New Playlist', initial: 'untitled playlist', ok: 'Create');
    if (name == null) return;
    final pl = await s.library.createPlaylist(name, from ?? const []);
    ctrl.select(PlaylistSource(pl));
  }

  Future<void> addToPlaylistMenu(
      BuildContext context, Offset pos, List<Track> tracks) async {
    final pls = s.library.playlists;
    final v = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'new', height: 28, child: Text('New Playlist…')),
        if (pls.isNotEmpty) const PopupMenuDivider(),
        for (final pl in pls)
          PopupMenuItem(value: pl, height: 28, child: Text(pl.name)),
      ],
    );
    if (!context.mounted || v == null) return;
    if (v == 'new') {
      await newPlaylist(context, from: tracks);
    } else if (v is Playlist) {
      await s.library.addToPlaylist(v, tracks);
    }
  }

  Future<void> deleteSelection(BuildContext context) async {
    final tracks = ctrl.selectedTracks;
    if (tracks.isEmpty) return;
    final src = ctrl.source;
    if (src is CdSource) return;
    if (src is PlaylistSource) {
      await s.library.removeFromPlaylist(src.playlist, tracks);
      ctrl.selection.clear();
      ctrl.refresh();
      return;
    }
    final n = tracks.length;
    final ok = await confirm(
      context,
      title: 'Delete ${n == 1 ? 'Song' : '$n Songs'}',
      message: 'Your library mirrors the music folder, so removing '
          '${n == 1 ? 'this song' : 'these songs'} moves the '
          '${n == 1 ? 'file' : 'files'} to the '
          '${Plat.isWindows ? 'Recycle Bin' : 'Trash'}. Continue?',
      ok: 'Move to ${Plat.isWindows ? 'Recycle Bin' : (Plat.isMacOS ? 'Trash' : 'Delete')}',
    );
    if (!ok) return;
    final cur = s.player.current;
    if (cur != null && tracks.any((t) => t.path == cur.path)) await s.player.stop();
    final gone = await Plat.trashFiles(tracks.map((t) => t.path).toList());
    final goneSet = gone.toSet();
    await s.library.deleteTracks(
        tracks.where((t) => goneSet.contains(t.path)).toList(),
        deleteFiles: false);
    ctrl.selection.clear();
    ctrl.refresh();
    if (gone.length < tracks.length && context.mounted) {
      showMessage(context, 'Delete',
          '${tracks.length - gone.length} file(s) could not be removed.');
    }
  }

  Future<void> addToLibrary(BuildContext context, {required bool folder}) async {
    List<String> paths = [];
    if (folder) {
      final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Add Folder to Library');
      if (dir != null) paths = [dir];
    } else {
      final r = await FilePicker.platform.pickFiles(
        dialogTitle: 'Add to Library',
        allowMultiple: true,
        type: FileType.audio,
      );
      paths = r?.paths.whereType<String>().toList() ?? [];
    }
    if (paths.isEmpty) return;
    final n = await s.library.importPaths(paths);
    if (context.mounted) {
      showMessage(context, 'Add to Library',
          '$n song${n == 1 ? '' : 's'} added to ${s.library.root}.');
    }
  }

  Future<void> showTrackMenu(BuildContext context, Offset pos) async {
    final tracks = ctrl.selectedTracks;
    if (tracks.isEmpty) return;
    final src = ctrl.source;
    final isCd = src is CdSource;
    final inPlaylist = src is PlaylistSource;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'play', height: 28, child: Text('Play')),
        if (!isCd) ...[
          const PopupMenuItem(value: 'info', height: 28, child: Text('Get Info')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'addto', height: 28, child: Text('Add to Playlist…')),
          const PopupMenuItem(
              value: 'newfrom', height: 28, child: Text('New Playlist from Selection')),
          if (inPlaylist && tracks.length == 1) ...[
            const PopupMenuItem(value: 'up', height: 28, child: Text('Move Up')),
            const PopupMenuItem(value: 'down', height: 28, child: Text('Move Down')),
          ],
          const PopupMenuDivider(),
          PopupMenuItem(
              value: 'reveal',
              height: 28,
              child: Text('Show in ${Plat.fileManagerName}')),
          PopupMenuItem(
              value: 'delete',
              height: 28,
              child: Text(inPlaylist ? 'Remove from Playlist' : 'Delete…')),
        ],
      ],
    );
    if (!context.mounted || v == null) return;
    switch (v) {
      case 'play':
        await playSelectedOrFirst();
        break;
      case 'info':
        await getInfo(context, tracks);
        break;
      case 'addto':
        await addToPlaylistMenu(context, pos, tracks);
        break;
      case 'newfrom':
        await newPlaylist(context, from: tracks);
        break;
      case 'up':
      case 'down':
        final pl = (src as PlaylistSource).playlist;
        final list = ctrl.visibleTracks;
        final i = list.indexOf(tracks.first);
        final from = pl.paths.indexOf(tracks.first.path);
        if (i >= 0 && from >= 0) {
          await s.library.movePlaylistItem(pl, from, v == 'up' ? from - 1 : from + 1);
        }
        break;
      case 'reveal':
        await Plat.revealInFileManager(tracks.first.path);
        break;
      case 'delete':
        await deleteSelection(context);
        break;
    }
  }
}
