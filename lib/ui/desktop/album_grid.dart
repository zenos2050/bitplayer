import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';
import 'desktop_controller.dart';

/// Album-art grid view (iTunes 7 "Grid View").
class AlbumGrid extends StatefulWidget {
  const AlbumGrid({super.key, required this.ctrl});
  final DesktopController ctrl;

  @override
  State<AlbumGrid> createState() => _AlbumGridState();
}

class _AlbumGridState extends State<AlbumGrid> {
  String? _selectedKey;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.ctrl, s.library]),
      builder: (context, _) {
        final albums = s.library.albumsOf(widget.ctrl.visibleTracks);
        if (albums.isEmpty) {
          return const Center(
              child: Text('No albums', style: TextStyle(color: RetroColors.textDim)));
        }
        return Container(
          color: const Color(0xFF262626),
          child: Scrollbar(
            controller: _scroll,
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.78,
              ),
              itemCount: albums.length,
              itemBuilder: (context, i) => _tile(albums[i]),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(AlbumInfo a) {
    final sel = a.key == _selectedKey;
    return GestureDetector(
      onTapDown: (_) => setState(() => _selectedKey = a.key),
      onDoubleTap: () => AppServices.I.player.playList(a.tracks, 0),
      onSecondaryTapDown: (d) => _menu(a, d.globalPosition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: sel ? const Color(0xFF79A8F0) : const Color(0xFF444444),
                    width: sel ? 3 : 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
                ],
              ),
              child: ArtworkImage(track: a.tracks.first, size: 170),
            ),
          ),
          const SizedBox(height: 6),
          Text(a.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(a.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFAFAFAF), fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _menu(AlbumInfo a, Offset pos) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'play', height: 28, child: Text('Play Album')),
        PopupMenuItem(value: 'show', height: 28, child: Text('Show Songs')),
      ],
    );
    if (v == 'play') {
      await AppServices.I.player.playList(a.tracks, 0);
    } else if (v == 'show') {
      final c = widget.ctrl;
      AppServices.I.settings.update((s) => s.viewMode = 'list');
      c.browse(genre: null);
      c.browse(artist: a.artist);
      c.browse(album: a.title);
      c.selection
        ..clear()
        ..addAll(a.tracks.map((t) => t.path));
      c.refresh();
    }
  }
}
