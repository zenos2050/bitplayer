import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_services.dart';
import '../../core/platform.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';
import 'mobile_lists.dart';
import 'mobile_widgets.dart';

/// Phone app: iPod-style tabs (Playlists, Artists, Songs, Albums, More).
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> with WidgetsBindingObserver {
  int _tab = 1;
  bool? _hasAccess;

  AppServices get s => AppServices.I;

  static const _tabs = [
    ('Playlists', Icons.queue_music),
    ('Artists', Icons.person),
    ('Songs', Icons.music_note),
    ('Albums', Icons.album),
    ('More', Icons.more_horiz),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess(request: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings / Files: re-check access and rescan.
    if (state == AppLifecycleState.resumed) {
      if (_hasAccess == true) {
        s.library.scan();
        s.library.loadPlaylists();
      } else {
        _checkAccess(request: false);
      }
    }
  }

  Future<void> _checkAccess({required bool request}) async {
    var ok = true;
    if (Plat.isAndroid) {
      ok = await _androidAccess(request: request);
    } else if (Plat.isIOS) {
      await Directory(s.library.root).create(recursive: true);
      await Directory(s.library.playlistDir).create(recursive: true);
    }
    if (!mounted) return;
    setState(() => _hasAccess = ok);
    if (ok) await s.library.start();
  }

  Future<bool> _androidAccess({required bool request}) async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.audio.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    if (!request) return false;
    // "All files access" lets BitPlayer edit tags & playlists in place.
    final m = await Permission.manageExternalStorage.request();
    if (m.isGranted) return true;
    final a = await Permission.audio.request();
    if (a.isGranted) return true;
    final st = await Permission.storage.request();
    return st.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAccess == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_hasAccess == false) return _welcome();
    final title = _tabs[_tab].$1;
    return Scaffold(
      appBar: RetroNavBar(title: title),
      body: IndexedStack(
        index: _tab,
        children: [
          const PlaylistsTab(),
          const ArtistsTab(),
          const SongsTab(),
          const AlbumsTab(),
          _MoreTab(onChangeFolder: _changeFolder),
        ],
      ),
      bottomNavigationBar: _tabBar(),
    );
  }

  Widget _tabBar() {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RetroColors.tabTop, RetroColors.tabBottom],
        ),
        border: Border(top: BorderSide(color: Color(0xFF5A5A5A))),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _tab = i),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    decoration: _tab == i
                        ? BoxDecoration(
                            color: const Color(0x33FFFFFF),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShaderMask(
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: _tab == i
                                ? const [Color(0xFF9FD5FF), Color(0xFF2A88E8)]
                                : const [Color(0xFFAAAAAA), Color(0xFF777777)],
                          ).createShader(r),
                          child: Icon(_tabs[i].$2, size: 28, color: Colors.white),
                        ),
                        Text(_tabs[i].$1,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _tab == i ? Colors.white : const Color(0xFF9A9A9A))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _welcome() {
    return Scaffold(
      appBar: const RetroNavBar(title: 'BitPlayer', showNowPlaying: false),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.album, size: 96, color: RetroColors.navBottom),
            const SizedBox(height: 16),
            const Text('Welcome to BitPlayer',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(
              'BitPlayer plays the music in your\n${s.library.root}\nfolder.\n\n'
              'Allow “All files access” so it can also edit song info and '
              'save playlists next to your music.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF555555)),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _checkAccess(request: true),
              child: const Text('Allow Access'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeFolder() async {
    if (Plat.isIOS) {
      showMessage(context, 'Music Folder',
          'On iPhone, BitPlayer uses its own folder. Open the Files app → '
          'On My iPhone → BitPlayer → Music and copy your music there.');
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Music Folder');
    if (dir != null) await s.library.changeRoot(dir);
    if (mounted) setState(() {});
  }
}

class _MoreTab extends StatelessWidget {
  const _MoreTab({required this.onChangeFolder});
  final VoidCallback onChangeFolder;

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    return ListenableBuilder(
      listenable: s.library,
      builder: (context, _) => ListView(children: [
        RetroRow(
          title: 'Genres',
          leading: const Padding(
              padding: EdgeInsets.only(left: 12), child: Icon(Icons.category)),
          chevron: true,
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const GenresPage())),
        ),
        const SectionHeader('Library'),
        RetroRow(
          title: 'Music Folder',
          subtitle: s.library.root,
          leading: const Padding(
              padding: EdgeInsets.only(left: 12), child: Icon(Icons.folder)),
          chevron: true,
          onTap: onChangeFolder,
        ),
        RetroRow(
          title: s.library.scanning ? 'Scanning…' : 'Rescan Library',
          subtitle: s.library.scanning
              ? s.library.scanStatus
              : '${s.library.count} songs, ${s.library.playlists.length} playlists',
          leading: const Padding(
              padding: EdgeInsets.only(left: 12), child: Icon(Icons.refresh)),
          onTap: s.library.scanning
              ? null
              : () async {
                  await s.library.loadPlaylists();
                  await s.library.scan();
                },
        ),
        const SectionHeader('About'),
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'BitPlayer 1.0\n\n'
            'Your music folder uses the same Artist / Album layout as the desktop app, '
            'with playlists as .m3u8 files in the Playlists folder. Copy or sync the '
            'whole folder (USB, Syncthing, etc.) to keep phone and computer in step.',
            style: TextStyle(color: Color(0xFF555555)),
          ),
        ),
      ]),
    );
  }
}
