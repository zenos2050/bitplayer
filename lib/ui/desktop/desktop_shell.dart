import 'dart:ui' show AppExitType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';
import 'album_grid.dart';
import 'browser_columns.dart';
import 'cd_view.dart';
import 'desktop_actions.dart';
import 'desktop_controller.dart';
import 'preferences_dialog.dart';
import 'source_list.dart';
import 'top_bar.dart';
import 'track_table.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final DesktopController ctrl = DesktopController();
  late final DesktopActions actions = DesktopActions(ctrl);
  final _search = TextEditingController();
  final _rootFocus = FocusNode(debugLabel: 'root');

  AppServices get s => AppServices.I;

  @override
  void dispose() {
    ctrl.dispose();
    _search.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  bool get _editingText {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_editingText) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final mod = hw.isControlPressed || hw.isMetaPressed;
    final k = e.logicalKey;
    final p = s.player;
    void Function()? action;
    if (k == LogicalKeyboardKey.space && !mod) {
      action = () {
        if (p.current == null) {
          actions.playSelectedOrFirst();
        } else {
          p.playPause();
        }
      };
    } else if (mod) {
      if (k == LogicalKeyboardKey.arrowRight) {
        action = p.next;
      } else if (k == LogicalKeyboardKey.arrowLeft) {
        action = p.previous;
      } else if (k == LogicalKeyboardKey.arrowUp) {
        action = () => p.setVolume(p.volume + 10);
      } else if (k == LogicalKeyboardKey.arrowDown) {
        action = () => p.setVolume(p.volume - 10);
      } else if (k == LogicalKeyboardKey.keyI) {
        action = () => actions.getInfo(context);
      } else if (k == LogicalKeyboardKey.keyN) {
        action = () => actions.newPlaylist(context);
      } else if (k == LogicalKeyboardKey.keyA) {
        action = ctrl.selectAll;
      } else if (k == LogicalKeyboardKey.keyB) {
        action = () => s.settings.update((x) => x.showBrowser = !x.showBrowser);
      } else if (k == LogicalKeyboardKey.keyO) {
        action = () => actions.addToLibrary(context, folder: false);
      } else if (k == LogicalKeyboardKey.comma) {
        action = () => showPreferences(context);
      } else if (k == LogicalKeyboardKey.keyE) {
        action = _ejectFirst;
      }
    }
    if (action != null) action();
    final handled = action != null;
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _ejectFirst() {
    final cd = s.cd;
    if (cd == null || cd.discs.isEmpty) return;
    final src = ctrl.source;
    cd.eject(src is CdSource ? src.disc : cd.discs.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 12, color: RetroColors.text),
          child: Column(
            children: [
              _menuBar(context),
              TopBar(ctrl: ctrl, searchController: _search),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: 200, child: SourceList(ctrl: ctrl)),
                    const VerticalDivider(width: 1, color: Color(0xFF8E98A6)),
                    Expanded(child: _main()),
                  ],
                ),
              ),
              _bottomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _main() {
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, s.settings]),
      builder: (context, _) {
        final src = ctrl.source;
        if (src is CdSource) {
          return CdView(key: ValueKey(src.id), disc: src.disc);
        }
        return Column(
          children: [
            if (s.settings.showBrowser) ...[
              BrowserColumns(ctrl: ctrl),
              const Divider(height: 1, color: RetroColors.headerBorder),
            ],
            Expanded(
              child: s.settings.viewMode == 'albums'
                  ? AlbumGrid(ctrl: ctrl)
                  : TrackTable(ctrl: ctrl, actions: actions),
            ),
          ],
        );
      },
    );
  }

  Widget _bottomBar(BuildContext context) {
    return BrushedMetal(
      height: 36,
      topBorder: true,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ListenableBuilder(
        listenable: Listenable.merge(
            [ctrl, s.settings, s.library, if (s.cd != null) s.cd!]),
        builder: (context, _) {
          final src = ctrl.source;
          final repeat = s.settings.repeat;
          return Row(
            children: [
              MetalButton(
                  icon: Icons.add,
                  tooltip: 'New Playlist',
                  onTap: () => actions.newPlaylist(context)),
              const SizedBox(width: 6),
              MetalButton(
                  icon: Icons.shuffle,
                  tooltip: 'Shuffle',
                  active: s.settings.shuffle,
                  onTap: s.player.toggleShuffle),
              const SizedBox(width: 2),
              MetalButton(
                  icon: repeat == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                  tooltip: 'Repeat: ${repeat.name}',
                  active: repeat != LoopMode.off,
                  onTap: s.player.cycleRepeat),
              const SizedBox(width: 2),
              MetalButton(
                  icon: Icons.image,
                  tooltip: 'Show / hide artwork',
                  active: s.settings.showArtwork,
                  onTap: () =>
                      s.settings.update((x) => x.showArtwork = !x.showArtwork)),
              Expanded(
                child: Center(
                  child: Text(_status(),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2C2C2C))),
                ),
              ),
              if (src is CdSource) ...[
                MetalButton(
                  icon: Icons.download,
                  label: s.cd!.importing ? 'Stop' : 'Import CD',
                  onTap: () async {
                    if (s.cd!.importing) {
                      s.cd!.cancelImport();
                    } else {
                      final err = await s.cd!.importDisc(src.disc);
                      if (err != null && context.mounted) {
                        showMessage(context, 'Import CD', err);
                      }
                    }
                  },
                ),
                const SizedBox(width: 4),
                MetalButton(
                    icon: Icons.eject,
                    tooltip: 'Eject',
                    onTap: () => s.cd!.eject(src.disc)),
                const SizedBox(width: 6),
              ],
              MetalButton(
                  icon: Icons.view_column,
                  tooltip: 'Browser',
                  active: s.settings.showBrowser,
                  onTap: () =>
                      s.settings.update((x) => x.showBrowser = !x.showBrowser)),
            ],
          );
        },
      ),
    );
  }

  String _status() {
    if (s.library.scanning && s.library.scanStatus.isNotEmpty) {
      return s.library.scanStatus;
    }
    final src = ctrl.source;
    final list = ctrl.visibleTracks;
    final n = list.length;
    final time = s.library.totalDuration(list);
    if (src is CdSource) {
      return '$n song${n == 1 ? '' : 's'}, ${formatTime(time)} total time';
    }
    final size = s.library.totalSize(list);
    return '$n song${n == 1 ? '' : 's'}, ${formatTime(time)}, ${_bytes(size)}';
  }

  String formatTime(int ms) {
    final h = ms / 3600000.0;
    if (h >= 24) return '${(h / 24).toStringAsFixed(1)} days';
    if (h >= 1) return '${h.toStringAsFixed(1)} hours';
    final m = ms ~/ 60000;
    final sec = (ms % 60000) ~/ 1000;
    return '$m:${sec.toString().padLeft(2, '0')} minutes';
  }

  String _bytes(int b) {
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  Widget _menuBar(BuildContext context) {
    MenuItemButton item(String label, VoidCallback? onPressed,
            {SingleActivator? shortcut}) =>
        MenuItemButton(
          onPressed: onPressed,
          shortcut: shortcut,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        );
    SingleActivator ctl(LogicalKeyboardKey k) => Plat.isMacOS
        ? SingleActivator(k, meta: true)
        : SingleActivator(k, control: true);

    return Container(
      color: const Color(0xFFF2F2F2),
      child: Row(
        children: [
          Expanded(
            child: MenuBar(
              style: const MenuStyle(
                backgroundColor: WidgetStatePropertyAll(Color(0xFFF2F2F2)),
                elevation: WidgetStatePropertyAll(0.0),
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
              ),
              children: [
                SubmenuButton(
                  menuChildren: [
                    item('New Playlist', () => actions.newPlaylist(context),
                        shortcut: ctl(LogicalKeyboardKey.keyN)),
                    item('New Playlist from Selection',
                        () => actions.newPlaylist(context, from: ctrl.selectedTracks)),
                    const Divider(height: 1),
                    item('Add File to Library…',
                        () => actions.addToLibrary(context, folder: false),
                        shortcut: ctl(LogicalKeyboardKey.keyO)),
                    item('Add Folder to Library…',
                        () => actions.addToLibrary(context, folder: true)),
                    const Divider(height: 1),
                    item('Show in ${Plat.fileManagerName}', () {
                      final sel = ctrl.selectedTracks;
                      if (sel.isNotEmpty) Plat.revealInFileManager(sel.first.path);
                    }),
                    item('Open Music Folder', () => Plat.openFolder(s.library.root)),
                    const Divider(height: 1),
                    item('Exit', () => ServicesBinding.instance.exitApplication(AppExitType.required)),
                  ],
                  child: const Text('File', style: TextStyle(fontSize: 12)),
                ),
                SubmenuButton(
                  menuChildren: [
                    item('Select All', ctrl.selectAll,
                        shortcut: ctl(LogicalKeyboardKey.keyA)),
                    item('Get Info', () => actions.getInfo(context),
                        shortcut: ctl(LogicalKeyboardKey.keyI)),
                    item('Delete', () => actions.deleteSelection(context),
                        shortcut: const SingleActivator(LogicalKeyboardKey.delete)),
                    const Divider(height: 1),
                    item('Preferences…', () => showPreferences(context),
                        shortcut: ctl(LogicalKeyboardKey.comma)),
                  ],
                  child: const Text('Edit', style: TextStyle(fontSize: 12)),
                ),
                SubmenuButton(
                  menuChildren: [
                    item('Play / Pause', s.player.playPause,
                        shortcut: const SingleActivator(LogicalKeyboardKey.space)),
                    item('Next Song', s.player.next,
                        shortcut: ctl(LogicalKeyboardKey.arrowRight)),
                    item('Previous Song', s.player.previous,
                        shortcut: ctl(LogicalKeyboardKey.arrowLeft)),
                    const Divider(height: 1),
                    item('Shuffle', s.player.toggleShuffle),
                    item('Repeat (Off / All / One)', s.player.cycleRepeat),
                    const Divider(height: 1),
                    item('Volume Up', () => s.player.setVolume(s.player.volume + 10),
                        shortcut: ctl(LogicalKeyboardKey.arrowUp)),
                    item('Volume Down', () => s.player.setVolume(s.player.volume - 10),
                        shortcut: ctl(LogicalKeyboardKey.arrowDown)),
                    if (s.cd != null) ...[
                      const Divider(height: 1),
                      item('Eject Disc', _ejectFirst,
                          shortcut: ctl(LogicalKeyboardKey.keyE)),
                    ],
                  ],
                  child: const Text('Controls', style: TextStyle(fontSize: 12)),
                ),
                SubmenuButton(
                  menuChildren: [
                    item('as List',
                        () => s.settings.update((x) => x.viewMode = 'list')),
                    item('as Album Grid',
                        () => s.settings.update((x) => x.viewMode = 'albums')),
                    const Divider(height: 1),
                    item('Show / Hide Browser',
                        () => s.settings.update((x) => x.showBrowser = !x.showBrowser),
                        shortcut: ctl(LogicalKeyboardKey.keyB)),
                    item('Show / Hide Artwork',
                        () => s.settings.update((x) => x.showArtwork = !x.showArtwork)),
                  ],
                  child: const Text('View', style: TextStyle(fontSize: 12)),
                ),
                SubmenuButton(
                  menuChildren: [
                    item('Rescan Library', s.library.scan),
                    if (s.cd != null) ...[
                      item('Get CD Track Names', () {
                        final src = ctrl.source;
                        if (src is CdSource) s.cd!.lookup(src.disc);
                      }),
                      item('Import CD', () async {
                        final src = ctrl.source;
                        if (src is CdSource) {
                          final err = await s.cd!.importDisc(src.disc);
                          if (err != null && context.mounted) {
                            showMessage(context, 'Import CD', err);
                          }
                        }
                      }),
                    ],
                  ],
                  child: const Text('Advanced', style: TextStyle(fontSize: 12)),
                ),
                SubmenuButton(
                  menuChildren: [
                    item('About BitPlayer', () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'BitPlayer',
                        applicationVersion: '1.0.0',
                        applicationIcon: const Icon(Icons.album, size: 40),
                        children: const [
                          Text('A classic, iTunes-style music player.\n'
                              'Playback by libmpv (media_kit). CD track names from '
                              'MusicBrainz; artwork from the Cover Art Archive. '
                              'Encoding by ffmpeg.'),
                        ],
                      );
                    }),
                  ],
                  child: const Text('Help', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
