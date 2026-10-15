import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';
import 'desktop_controller.dart';

class SourceList extends StatelessWidget {
  const SourceList({super.key, required this.ctrl});
  final DesktopController ctrl;

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    return Container(
      color: RetroColors.sourceBg,
      child: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge(
                  [ctrl, s.library, if (s.cd != null) s.cd!]),
              builder: (context, _) {
                final discs = s.cd?.discs ?? const [];
                return ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  children: [
                    const _Header('LIBRARY'),
                    _SourceRow(
                      ctrl: ctrl,
                      source: const LibrarySource(),
                      icon: Icons.library_music,
                      iconColor: const Color(0xFF4A78C2),
                    ),
                    if (discs.isNotEmpty) const _Header('DEVICES'),
                    for (final d in discs)
                      _SourceRow(
                        ctrl: ctrl,
                        source: CdSource(d),
                        icon: Icons.album,
                        iconColor: const Color(0xFF6A6A6A),
                        trailing: IconButton(
                          tooltip: 'Eject',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 18),
                          iconSize: 14,
                          icon: const Icon(Icons.eject),
                          onPressed: () => s.cd!.eject(d),
                        ),
                      ),
                    const _Header('PLAYLISTS'),
                    for (final k in SmartList.values)
                      _SourceRow(
                        ctrl: ctrl,
                        source: SmartSource(k),
                        icon: Icons.settings_suggest,
                        iconColor: const Color(0xFF8A57C9),
                      ),
                    for (final pl in s.library.playlists)
                      _SourceRow(
                        ctrl: ctrl,
                        source: PlaylistSource(pl),
                        icon: Icons.queue_music,
                        iconColor: const Color(0xFF3E7BD6),
                        playlist: pl,
                      ),
                  ],
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([s.settings, ctrl, s.player]),
            builder: (context, _) {
              if (!s.settings.showArtwork) return const SizedBox.shrink();
              final sel = ctrl.selection.isNotEmpty ? ctrl.selectedTracks : const <Track>[];
              final t = sel.isNotEmpty ? sel.first : s.player.current;
              return Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF9AA4B2))),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 20,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(gradient: metalGradient),
                      child: Text(
                          sel.isNotEmpty ? 'Selected Song' : 'Now Playing',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    AspectRatio(
                      aspectRatio: 1,
                      child: t == null
                          ? Container(
                              color: Colors.white,
                              alignment: Alignment.center,
                              child: const Text('Nothing\nPlaying',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFFAAAAAA))),
                            )
                          : ArtworkImage(key: ValueKey(t.albumKey + t.path), track: t),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 3),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: RetroColors.sourceHeader,
                letterSpacing: 0.4)),
      );
}

class _SourceRow extends StatefulWidget {
  const _SourceRow({
    required this.ctrl,
    required this.source,
    required this.icon,
    required this.iconColor,
    this.trailing,
    this.playlist,
  });

  final DesktopController ctrl;
  final Source source;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final Playlist? playlist;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.ctrl.isSelected(widget.source);
    final pl = widget.playlist;
    Widget row = GestureDetector(
      onTapDown: (_) => widget.ctrl.select(widget.source),
      onDoubleTap: pl == null ? null : () => _rename(context, pl),
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      child: Container(
        height: 22,
        padding: const EdgeInsets.only(left: 14, right: 6),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [RetroColors.sourceSelTop, RetroColors.sourceSelBottom])
              : null,
          color: _hover ? const Color(0xFFB9C9E8) : null,
          border: _hover ? Border.all(color: RetroColors.rowSel, width: 2) : null,
        ),
        child: Row(
          children: [
            Icon(widget.icon,
                size: 16, color: selected ? Colors.white : widget.iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.source.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : RetroColors.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (widget.trailing != null)
              IconTheme(
                data: IconThemeData(color: selected ? Colors.white : Colors.black54),
                child: widget.trailing!,
              ),
          ],
        ),
      ),
    );

    // Playlists (and the library) accept songs dragged from the song list.
    if (pl != null) {
      row = DragTarget<List<Track>>(
        onWillAcceptWithDetails: (_) {
          setState(() => _hover = true);
          return true;
        },
        onLeave: (_) => setState(() => _hover = false),
        onAcceptWithDetails: (d) {
          setState(() => _hover = false);
          AppServices.I.library.addToPlaylist(pl, d.data);
        },
        builder: (_, __, ___) => row,
      );
    }
    return row;
  }

  Future<void> _rename(BuildContext context, Playlist pl) async {
    final name = await promptText(context, title: 'Rename Playlist', initial: pl.name);
    if (name != null && name.trim().isNotEmpty) {
      await AppServices.I.library.renamePlaylist(pl, name.trim());
    }
  }

  Future<void> _menu(BuildContext context, Offset pos) async {
    final pl = widget.playlist;
    final src = widget.source;
    widget.ctrl.select(src);
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'play', height: 28, child: Text('Play')),
      const PopupMenuItem(value: 'shuffle', height: 28, child: Text('Shuffle Play')),
      if (pl != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'rename', height: 28, child: Text('Rename')),
        const PopupMenuItem(value: 'reveal', height: 28, child: Text('Show Playlist File')),
        const PopupMenuItem(value: 'delete', height: 28, child: Text('Delete')),
      ],
      if (src is CdSource) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'lookup', height: 28, child: Text('Get Track Names')),
        const PopupMenuItem(value: 'eject', height: 28, child: Text('Eject')),
      ],
    ];
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: items,
    );
    if (!context.mounted || v == null) return;
    final s = AppServices.I;
    final tracks = widget.ctrl.baseTracks();
    switch (v) {
      case 'play':
        if (tracks.isNotEmpty) await s.player.playList(tracks, 0);
        break;
      case 'shuffle':
        if (tracks.isNotEmpty) {
          if (!s.settings.shuffle) s.player.toggleShuffle();
          await s.player.playList(tracks, (DateTime.now().millisecond) % tracks.length);
        }
        break;
      case 'rename':
        await _rename(context, pl!);
        break;
      case 'reveal':
        await _reveal(pl!);
        break;
      case 'delete':
        final ok = await confirm(context,
            title: 'Delete Playlist',
            message: 'Delete the playlist “${pl!.name}”? The songs stay in your library.',
            ok: 'Delete');
        if (ok) await s.library.deletePlaylist(pl);
        break;
      case 'lookup':
        await s.cd?.lookup((src as CdSource).disc);
        break;
      case 'eject':
        await s.cd?.eject((src as CdSource).disc);
        break;
    }
  }

  Future<void> _reveal(Playlist pl) => Plat.revealInFileManager(pl.filePath);
}
