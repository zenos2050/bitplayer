import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/cd/cd_service.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';

/// Audio CD view: editable track names, check boxes, Import CD.
class CdView extends StatefulWidget {
  const CdView({super.key, required this.disc});
  final CdDiscState disc;

  @override
  State<CdView> createState() => _CdViewState();
}

class _SyncedField {
  final TextEditingController c = TextEditingController();
  final FocusNode f = FocusNode();
  void sync(String value) {
    if (!f.hasFocus && c.text != value) c.text = value;
  }

  void dispose() {
    c.dispose();
    f.dispose();
  }
}

class _CdViewState extends State<CdView> {
  final _artist = _SyncedField();
  final _album = _SyncedField();
  final _genre = _SyncedField();
  final _year = _SyncedField();
  final List<_SyncedField> _titles = [];
  final List<_SyncedField> _trackArtists = [];

  CdService get cd => AppServices.I.cd!;
  CdDiscState get d => widget.disc;

  @override
  void initState() {
    super.initState();
    _sync();
    cd.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant CdView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.disc != widget.disc) {
      for (final f in [_artist, _album, _genre, _year, ..._titles, ..._trackArtists]) {
        f.c.text = '';
      }
      _sync();
    }
  }

  @override
  void dispose() {
    cd.removeListener(_sync);
    for (final f in [_artist, _album, _genre, _year, ..._titles, ..._trackArtists]) {
      f.dispose();
    }
    super.dispose();
  }

  /// Copies model values into the text fields (outside of build).
  void _sync() {
    _ensureFields();
    _artist.sync(d.albumArtist);
    _album.sync(d.album);
    _genre.sync(d.genre);
    _year.sync(d.year > 0 ? '${d.year}' : '');
    for (var i = 0; i < d.tracks.length; i++) {
      _titles[i].sync(d.tracks[i].title);
      _trackArtists[i].sync(d.tracks[i].artist);
    }
  }

  void _ensureFields() {
    while (_titles.length < d.tracks.length) {
      _titles.add(_SyncedField());
      _trackArtists.add(_SyncedField());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([cd, AppServices.I.player]),
      builder: (context, _) {
        _ensureFields();
        return Column(
          children: [
            _header(context),
            _tableHeader(),
            Expanded(
              child: ListView.builder(
                itemExtent: 24,
                itemCount: d.tracks.length,
                itemBuilder: (context, i) => _row(i),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _field(String label, _SyncedField f, ValueChanged<String> onChanged,
      {double width = 260}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              width: 50,
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF444444)))),
          const SizedBox(width: 6),
          SizedBox(
            width: width,
            height: 22,
            child: TextField(
              controller: f.c,
              focusNode: f.f,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final settings = AppServices.I.settings;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F4F4), Color(0xFFDDDDDD)],
        ),
        border: Border(bottom: BorderSide(color: RetroColors.headerBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: 'Click to choose album artwork',
            child: GestureDetector(
              onTap: _chooseCover,
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF999999))),
                child: d.coverPath != null
                    ? ArtworkImage(track: d.tracks.first, size: 104)
                    : const ArtworkImage(track: null, size: 104),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Artist', _artist, (v) => cd.setAlbumField(d, artist: v)),
              _field('Album', _album, (v) => cd.setAlbumField(d, album: v)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _field('Genre', _genre, (v) => cd.setAlbumField(d, genre: v), width: 150),
                _field('Year', _year,
                    (v) => cd.setAlbumField(d, year: int.tryParse(v.trim()) ?? 0),
                    width: 54),
              ]),
              if (d.discTotal > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Text('Disc ${d.discNo} of ${d.discTotal}',
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  cd.importing
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                          onPressed: cd.cancelImport,
                          icon: const Icon(Icons.stop, size: 16),
                          label: const Text('Stop Importing'))
                      : FilledButton.icon(
                          onPressed: () => _import(context),
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Import CD')),
                  OutlinedButton.icon(
                    onPressed: d.lookingUp ? null : () => cd.lookup(d),
                    icon: const Icon(Icons.travel_explore, size: 16),
                    label: const Text('Get Track Names'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => cd.eject(d),
                    icon: const Icon(Icons.eject, size: 16),
                    label: const Text('Eject'),
                  ),
                ]),
                const SizedBox(height: 6),
                if (d.releases.length > 1)
                  DropdownButton<int>(
                    isDense: true,
                    isExpanded: true,
                    value: d.releaseIndex,
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                    items: [
                      for (var i = 0; i < d.releases.length; i++)
                        DropdownMenuItem(
                            value: i,
                            child: Text(d.releases[i].summary,
                                overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (i) {
                      if (i != null) cd.applyRelease(d, i);
                    },
                  ),
                if (d.lookingUp)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Row(children: [
                      SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 6),
                      Text('Getting track names from MusicBrainz…',
                          style: TextStyle(fontSize: 11)),
                    ]),
                  )
                else if (d.lookupMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(d.lookupMessage!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8A4B00))),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Import as ${settings.ripFormat.label.replaceAll(' Encoder', '')}'
                  '${settings.ripFormat == RipFormat.mp3 ? (settings.mp3Bitrate > 0 ? ' ${settings.mp3Bitrate} kbps' : ' VBR') : ''}'
                  ' into ${AppServices.I.library.root}',
                  style: const TextStyle(fontSize: 11, color: RetroColors.textDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    final all = d.include.every((x) => x);
    Widget h(String t, {double? w, int? flex, bool right = false}) {
      final child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Align(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      );
      return w != null ? SizedBox(width: w, child: child) : Expanded(flex: flex ?? 1, child: child);
    }

    return Container(
      height: 22,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RetroColors.headerTop, RetroColors.headerBottom],
        ),
        border: Border(bottom: BorderSide(color: RetroColors.headerBorder)),
      ),
      child: Row(children: [
        SizedBox(
          width: 30,
          child: Checkbox(
            value: all,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              for (var i = 0; i < d.include.length; i++) {
                d.include[i] = v ?? false;
              }
              cd.touch();
            },
          ),
        ),
        h('', w: 22),
        h('#', w: 30, right: true),
        h('Name', flex: 3),
        h('Time', w: 52, right: true),
        h('Artist', flex: 2),
      ]),
    );
  }

  Widget _row(int i) {
    final t = d.tracks[i];
    final playing = AppServices.I.player.current?.path == t.path;
    final state = d.ripState[i];
    Widget status;
    switch (state) {
      case RipState.ripping:
        status = const SizedBox(
            width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2));
        break;
      case RipState.done:
        status = const Icon(Icons.check_circle, size: 14, color: Color(0xFF2E9B3A));
        break;
      case RipState.error:
        status = const Icon(Icons.error, size: 14, color: Colors.red);
        break;
      case RipState.queued:
        status = const Icon(Icons.schedule, size: 14, color: Color(0xFF888888));
        break;
      case RipState.none:
        status = playing
            ? const Icon(Icons.volume_up, size: 14, color: Color(0xFF2F64C4))
            : const SizedBox.shrink();
    }
    InputDecoration deco() => const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        );
    return Container(
      color: i.isOdd ? RetroColors.rowAlt : Colors.white,
      child: Row(children: [
        SizedBox(
          width: 30,
          child: Checkbox(
            value: d.include[i],
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              d.include[i] = v ?? false;
              cd.touch();
            },
          ),
        ),
        SizedBox(width: 22, child: Center(child: status)),
        SizedBox(
          width: 30,
          child: GestureDetector(
            onDoubleTap: () => AppServices.I.player.playList(d.tracks, i),
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Text('${t.trackNo}',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Row(children: [
            IconButton(
              tooltip: 'Play',
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              icon: const Icon(Icons.play_arrow),
              onPressed: () => AppServices.I.player.playList(d.tracks, i),
            ),
            Expanded(
              child: TextField(
                controller: _titles[i].c,
                focusNode: _titles[i].f,
                style: const TextStyle(fontSize: 12),
                decoration: deco(),
                onChanged: (v) => t.title = v,
              ),
            ),
          ]),
        ),
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text(formatDuration(t.durationMs),
                textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
          ),
        ),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _trackArtists[i].c,
            focusNode: _trackArtists[i].f,
            style: const TextStyle(fontSize: 12),
            decoration: deco(),
            onChanged: (v) => t.artist = v,
          ),
        ),
      ]),
    );
  }

  Future<void> _chooseCover() async {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose Album Artwork',
      type: FileType.image,
    );
    final path = r?.files.single.path;
    if (path != null) cd.setCover(d, path);
  }

  Future<void> _import(BuildContext context) async {
    final err = await cd.importDisc(d);
    if (err != null && context.mounted) showMessage(context, 'Import CD', err);
  }
}
