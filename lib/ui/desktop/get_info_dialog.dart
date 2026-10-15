import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/artwork.dart';
import '../../core/library.dart';
import '../../core/models.dart';
import '../../core/tags/tag_writer.dart';
import '../common/retro_widgets.dart';

/// iTunes-style "Get Info" for one or many songs. Writes tags into the files.
Future<void> showGetInfo(BuildContext context, List<Track> tracks) {
  return showDialog<void>(
    context: context,
    builder: (_) => _GetInfoDialog(tracks: tracks),
  );
}

class _Field {
  _Field(this.label, this.initial, {this.mixed = false, this.numeric = false})
      : c = TextEditingController(text: initial);
  final String label;
  final String initial;
  final bool mixed;
  final bool numeric;
  final TextEditingController c;
  bool get dirty => c.text != initial;
}

class _GetInfoDialog extends StatefulWidget {
  const _GetInfoDialog({required this.tracks});
  final List<Track> tracks;

  @override
  State<_GetInfoDialog> createState() => _GetInfoDialogState();
}

class _GetInfoDialogState extends State<_GetInfoDialog> {
  late final Map<String, _Field> f;
  Uint8List? _art;
  PictureEdit? _picEdit;
  bool _saving = false;
  int _tab = 0;
  late bool _organize;

  List<Track> get tracks => widget.tracks;
  bool get multi => tracks.length > 1;

  @override
  void initState() {
    super.initState();
    _organize = AppServices.I.settings.keepOrganized;
    _Field mk(String label, String Function(Track) get, {bool numeric = false}) {
      final values = tracks.map(get).toSet();
      final same = values.length == 1;
      return _Field(label, same ? values.first : '', mixed: !same, numeric: numeric);
    }

    String n(int v) => v > 0 ? '$v' : '';
    f = {
      'title': mk('Name', (t) => t.title),
      'artist': mk('Artist', (t) => t.artist),
      'albumArtist': mk('Album Artist', (t) => t.albumArtist),
      'album': mk('Album', (t) => t.album),
      'genre': mk('Genre', (t) => t.genre),
      'year': mk('Year', (t) => n(t.year), numeric: true),
      'track': mk('Track', (t) => n(t.trackNo), numeric: true),
      'trackTotal': mk('of', (t) => n(t.trackTotal), numeric: true),
      'disc': mk('Disc', (t) => n(t.discNo), numeric: true),
      'discTotal': mk('of', (t) => n(t.discTotal), numeric: true),
      'composer': mk('Composer', (t) => t.composer),
      'comment': mk('Comments', (t) => t.comment),
    };
    _loadArt();
  }

  Future<void> _loadArt() async {
    final pic = await ArtworkCache.embeddedPicture(tracks.first.path);
    if (mounted) setState(() => _art = pic);
  }

  @override
  void dispose() {
    for (final x in f.values) {
      x.c.dispose();
    }
    super.dispose();
  }

  Widget _text(String key, {double? width, int maxLines = 1}) {
    final x = f[key]!;
    final field = TextField(
      controller: x.c,
      maxLines: maxLines,
      keyboardType: x.numeric ? TextInputType.number : null,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: x.mixed ? 'Mixed' : null,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }

  Widget _labeled(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF444444))),
            const SizedBox(height: 2),
            child,
          ],
        ),
      );

  Widget _info() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _labeled('Name', _text('title')),
          _labeled('Artist', _text('artist')),
          Row(children: [
            Expanded(child: _labeled('Album Artist', _text('albumArtist'))),
            const SizedBox(width: 10),
            SizedBox(width: 70, child: _labeled('Year', _text('year'))),
          ]),
          _labeled('Album', _text('album')),
          Row(children: [
            Expanded(child: _labeled('Genre', _text('genre'))),
            const SizedBox(width: 10),
            _labeled(
                'Track Number',
                Row(children: [
                  _text('track', width: 46),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4), child: Text('of')),
                  _text('trackTotal', width: 46),
                ])),
            const SizedBox(width: 10),
            _labeled(
                'Disc Number',
                Row(children: [
                  _text('disc', width: 40),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4), child: Text('of')),
                  _text('discTotal', width: 40),
                ])),
          ]),
          _labeled('Composer', _text('composer')),
          _labeled('Comments', _text('comment', maxLines: 3)),
        ],
      ),
    );
  }

  Widget _summary() {
    final t = tracks.first;
    final s = AppServices.I.library;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 90,
                child: Text('$k:',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF555555)))),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 11))),
          ]),
        );
    if (multi) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        kv('Songs', '${tracks.length}'),
        kv('Total time', formatDuration(s.totalDuration(tracks))),
        kv('Size', formatBytes(s.totalSize(tracks))),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ArtworkImage(track: t, size: 96),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(t.displayArtist),
          Text(t.displayAlbum),
          const SizedBox(height: 10),
          kv('Kind', t.kind),
          kv('Size', formatBytes(t.sizeBytes)),
          kv('Time', formatDuration(t.durationMs)),
          kv('Play Count', '${t.playCount}'),
          if (t.lastPlayedMs > 0)
            kv('Last Played', DateTime.fromMillisecondsSinceEpoch(t.lastPlayedMs).toString().substring(0, 16)),
          kv('Date Added', DateTime.fromMillisecondsSinceEpoch(t.dateAddedMs).toString().substring(0, 16)),
          kv('Where', t.path),
        ]),
      ),
    ]);
  }

  Widget _artwork() {
    final canWrite = tracks.every((t) => canWriteNatively(t.path));
    Widget preview;
    if (_picEdit != null && _picEdit!.remove) {
      preview = const Center(child: Text('Artwork will be removed'));
    } else if (_picEdit?.bytes != null) {
      preview = Image.memory(_picEdit!.bytes!, fit: BoxFit.contain);
    } else if (_art != null) {
      preview = Image.memory(_art!, fit: BoxFit.contain);
    } else {
      preview = ArtworkImage(track: tracks.first);
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFAAAAAA)),
            ),
            child: preview,
          ),
        ),
        const SizedBox(height: 8),
        if (!canWrite)
          const Text(
            'Embedded artwork can be changed for MP3 and FLAC files. For other '
            'formats, put a cover.jpg in the album folder.',
            style: TextStyle(fontSize: 11, color: Color(0xFF8A4B00)),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          OutlinedButton(
            onPressed: canWrite
                ? () => setState(() => _picEdit = const PictureEdit.remove())
                : null,
            child: const Text('Remove'),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: canWrite ? _pickArt : null, child: const Text('Add…')),
        ]),
      ],
    );
  }

  Future<void> _pickArt() async {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose Artwork',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    final path = r?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final mime = path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    setState(() => _picEdit = PictureEdit.set(bytes, mime));
  }

  Future<void> _save() async {
    final edit = TagEdit();
    String? txt(String k) => f[k]!.dirty ? f[k]!.c.text.trim() : null;
    int? numVal(String k) => f[k]!.dirty ? (int.tryParse(f[k]!.c.text.trim()) ?? 0) : null;
    edit
      ..title = txt('title')
      ..artist = txt('artist')
      ..albumArtist = txt('albumArtist')
      ..album = txt('album')
      ..genre = txt('genre')
      ..composer = txt('composer')
      ..comment = txt('comment')
      ..year = numVal('year')
      ..track = numVal('track')
      ..trackTotal = numVal('trackTotal')
      ..disc = numVal('disc')
      ..discTotal = numVal('discTotal');
    if (edit.isEmpty && _picEdit == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final s = AppServices.I;
    // Forget artwork of the albums before & after the edit.
    for (final t in tracks) {
      await s.artwork.invalidate(t);
    }
    final prevOrganize = s.settings.keepOrganized;
    s.settings.keepOrganized = _organize;
    final resume = await s.player.suspendFor(tracks.map((t) => t.path));
    final errors = await s.library.editTracks(tracks, edit, picture: _picEdit);
    await resume();
    s.settings.keepOrganized = prevOrganize;
    for (final t in tracks) {
      final updated = s.library.byPath(t.path);
      if (updated != null) await s.artwork.invalidate(updated);
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (errors.isNotEmpty) {
      showMessage(context, 'Some changes could not be saved', errors.join('\n'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = multi ? 'Multiple Song Information' : tracks.first.title;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 540,
        height: 470,
        child: Column(
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 0, label: Text('Summary')),
                ButtonSegment(value: 1, label: Text('Info')),
                ButtonSegment(value: 2, label: Text('Artwork')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_tab) {
                0 => SingleChildScrollView(child: _summary()),
                1 => _info(),
                _ => _artwork(),
              },
            ),
          ],
        ),
      ),
      actions: [
        Row(children: [
          Checkbox(
            value: _organize,
            onChanged: (v) => setState(() => _organize = v ?? false),
          ),
          const Text('Rename & move file to match', style: TextStyle(fontSize: 12)),
          const Spacer(),
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('OK'),
          ),
        ]),
      ],
    );
  }
}
