import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../common/retro_theme.dart';
import 'desktop_actions.dart';
import 'desktop_controller.dart';

class _Col {
  const _Col(this.label, this.sort, {this.width, this.flex, this.right = false});
  final String label;
  final SortKey? sort;
  final double? width;
  final int? flex;
  final bool right;
}

const _rowH = 19.0;

/// The striped song list.
class TrackTable extends StatefulWidget {
  const TrackTable({super.key, required this.ctrl, required this.actions});
  final DesktopController ctrl;
  final DesktopActions actions;

  @override
  State<TrackTable> createState() => _TrackTableState();
}

class _TrackTableState extends State<TrackTable> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'track-table');

  DesktopController get ctrl => widget.ctrl;

  List<_Col> _cols() {
    final pl = ctrl.source is PlaylistSource;
    return [
      if (pl) const _Col('#', null, width: 34, right: true),
      const _Col('', null, width: 20),
      const _Col('Name', SortKey.name, flex: 30),
      const _Col('Time', SortKey.time, width: 52, right: true),
      const _Col('Artist', SortKey.artist, flex: 20),
      const _Col('Album', SortKey.album, flex: 20),
      const _Col('Genre', SortKey.genre, flex: 10),
      const _Col('Year', SortKey.year, width: 46, right: true),
      const _Col('My Rating', SortKey.rating, width: 78),
      const _Col('Plays', SortKey.plays, width: 46, right: true),
    ];
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final top = index * _rowH;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowH > _scroll.offset + view) {
      _scroll.jumpTo(top + _rowH - view);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      ctrl.moveSelection(key == LogicalKeyboardKey.arrowDown ? 1 : -1, shift: shift);
      final a = ctrl.anchor;
      if (a != null) _ensureVisible(a);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      widget.actions.playSelectedOrFirst();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      widget.actions.deleteSelection(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: Listenable.merge([ctrl, s.library, s.player, _focus]),
        builder: (context, _) {
          final cols = _cols();
          final tracks = ctrl.visibleTracks;
          final playingPath = s.player.current?.path;
          final focused = _focus.hasFocus;
          return Column(
            children: [
              _header(cols),
              Expanded(
                child: tracks.isEmpty
                    ? _empty()
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          itemExtent: _rowH,
                          itemCount: tracks.length,
                          itemBuilder: (context, i) => _row(
                              context, cols, tracks, i, playingPath, focused),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty() {
    final s = AppServices.I;
    final src = ctrl.source;
    String msg;
    if (ctrl.search.isNotEmpty) {
      msg = 'No songs match “${ctrl.search}”.';
    } else if (src is PlaylistSource) {
      msg = 'This playlist is empty.\nDrag songs here from your library.';
    } else if (src is LibrarySource) {
      msg = s.library.scanning
          ? 'Looking for music…'
          : 'Your library is empty.\n\nCopy music into\n${s.library.root}\n'
              'or use File ▸ Add Folder to Library, or insert a CD and import it.';
    } else {
      msg = 'No songs.';
    }
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: Text(msg,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: RetroColors.textDim)),
    );
  }

  Widget _header(List<_Col> cols) {
    return Container(
      height: 20,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RetroColors.headerTop, RetroColors.headerBottom],
        ),
        border: Border(bottom: BorderSide(color: RetroColors.headerBorder)),
      ),
      child: Row(
        children: [
          for (final c in cols)
            _sized(
              c,
              InkWell(
                onTap: c.sort == null ? null : () => ctrl.sortBy(c.sort!),
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFFC2C2C2))),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: c.right ? Alignment.centerRight : Alignment.centerLeft,
                  child: Row(
                    mainAxisAlignment:
                        c.right ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(c.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: ctrl.sortKey == c.sort && c.sort != null
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                      ),
                      if (c.sort != null && ctrl.sortKey == c.sort)
                        Icon(ctrl.ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            size: 14),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sized(_Col c, Widget child) => c.width != null
      ? SizedBox(width: c.width, child: child)
      : Expanded(flex: c.flex ?? 1, child: child);

  Widget _row(BuildContext context, List<_Col> cols, List<Track> tracks, int i,
      String? playingPath, bool focused) {
    final t = tracks[i];
    final selected = ctrl.selection.contains(t.path);
    final bg = selected
        ? (focused ? RetroColors.rowSel : RetroColors.rowSelInactive)
        : (i.isOdd ? RetroColors.rowAlt : Colors.white);
    final fg = selected && focused ? Colors.white : RetroColors.text;
    final style = TextStyle(fontSize: 12, color: fg, height: 1.1);
    final playing = t.path == playingPath;

    Widget cell(_Col c, Widget child) => _sized(
          c,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Align(
                alignment: c.right ? Alignment.centerRight : Alignment.centerLeft,
                child: child),
          ),
        );
    Widget text(String s) =>
        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

    final cells = <Widget>[];
    for (final c in cols) {
      switch (c.label) {
        case '#':
          cells.add(cell(c, text('${i + 1}')));
          break;
        case '':
          cells.add(cell(
              c,
              playing
                  ? Icon(
                      AppServices.I.player.playing ? Icons.volume_up : Icons.volume_mute,
                      size: 13,
                      color: selected && focused ? Colors.white : const Color(0xFF2F64C4))
                  : const SizedBox.shrink()));
          break;
        case 'Name':
          cells.add(cell(c, text(t.title.isEmpty ? 'Untitled' : t.title)));
          break;
        case 'Time':
          cells.add(cell(c, text(formatDuration(t.durationMs))));
          break;
        case 'Artist':
          cells.add(cell(c, text(t.artist)));
          break;
        case 'Album':
          cells.add(cell(c, text(t.album)));
          break;
        case 'Genre':
          cells.add(cell(c, text(t.genre)));
          break;
        case 'Year':
          cells.add(cell(c, text(t.year > 0 ? '${t.year}' : '')));
          break;
        case 'My Rating':
          cells.add(cell(c, _stars(t, selected, focused)));
          break;
        case 'Plays':
          cells.add(cell(c, text(t.playCount > 0 ? '${t.playCount}' : '')));
          break;
      }
    }

    final row = Container(
      color: bg,
      child: Row(children: cells),
    );

    final sel = selected ? ctrl.selectedTracks : [t];
    return Draggable<List<Track>>(
      data: sel,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xDD3D80DF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            sel.length == 1 ? (sel.first.title) : '${sel.length} songs',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _focus.requestFocus();
          final hw = HardwareKeyboard.instance;
          ctrl.clickRow(i,
              ctrl: hw.isControlPressed || hw.isMetaPressed, shift: hw.isShiftPressed);
        },
        onDoubleTap: () => widget.actions.playIndex(i),
        onSecondaryTapDown: (d) {
          _focus.requestFocus();
          ctrl.ensureSelected(i);
          widget.actions.showTrackMenu(context, d.globalPosition);
        },
        child: row,
      ),
    );
  }

  Widget _stars(Track t, bool selected, bool focused) {
    if (t.isCd) return const SizedBox.shrink();
    final color = selected && focused ? Colors.white : const Color(0xFF444444);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= 5; n++)
          GestureDetector(
            onTap: () => AppServices.I.library
                .setRating([t], t.rating == n ? n - 1 : n),
            child: Padding(
              padding: const EdgeInsets.only(right: 1),
              child: n <= t.rating
                  ? Icon(Icons.star, size: 12, color: color)
                  : (selected
                      ? Icon(Icons.circle, size: 3.5, color: color)
                      : const SizedBox(width: 12)),
            ),
          ),
      ],
    );
  }
}
