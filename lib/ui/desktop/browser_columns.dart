import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../common/retro_theme.dart';
import 'desktop_controller.dart';

/// The Genre | Artist | Album column browser.
class BrowserColumns extends StatelessWidget {
  const BrowserColumns({super.key, required this.ctrl});
  final DesktopController ctrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListenableBuilder(
        listenable: Listenable.merge([ctrl, AppServices.I.library]),
        builder: (context, _) {
          final genres = ctrl.browserGenres();
          final artists = ctrl.browserArtists();
          final albums = ctrl.browserAlbums();
          return Row(
            children: [
              Expanded(
                child: _Column(
                  title: 'Genre',
                  allLabel: 'All (${genres.length} Genre${genres.length == 1 ? '' : 's'})',
                  items: genres,
                  selected: ctrl.browseGenre,
                  onSelect: (v) => ctrl.browse(genre: v),
                ),
              ),
              const VerticalDivider(width: 1, color: RetroColors.headerBorder),
              Expanded(
                child: _Column(
                  title: 'Artist',
                  allLabel:
                      'All (${artists.length} Artist${artists.length == 1 ? '' : 's'})',
                  items: artists,
                  selected: ctrl.browseArtist,
                  onSelect: (v) => ctrl.browse(artist: v),
                ),
              ),
              const VerticalDivider(width: 1, color: RetroColors.headerBorder),
              Expanded(
                child: _Column(
                  title: 'Album',
                  allLabel: 'All (${albums.length} Album${albums.length == 1 ? '' : 's'})',
                  items: albums,
                  selected: ctrl.browseAlbum,
                  onSelect: (v) => ctrl.browse(album: v),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.allLabel,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String allLabel;
  final List<String> items;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 20,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [RetroColors.headerTop, RetroColors.headerBottom],
            ),
            border: Border(bottom: BorderSide(color: RetroColors.headerBorder)),
          ),
          child: Text(title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: ListView.builder(
              itemExtent: 18,
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                final value = i == 0 ? null : items[i - 1];
                final isSel = value == selected;
                return GestureDetector(
                  onTapDown: (_) => onSelect(value),
                  child: Container(
                    color: isSel
                        ? RetroColors.rowSel
                        : (i.isOdd ? RetroColors.rowAlt : Colors.white),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      i == 0 ? allLabel : value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSel ? Colors.white : RetroColors.text,
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
