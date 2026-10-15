import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/library.dart';
import '../../core/models.dart';
import '../../core/tags/tag_writer.dart';
import '../common/retro_widgets.dart';
import 'mobile_widgets.dart';

/// Edit a song's tags on the phone (MP3 and FLAC are written natively).
class EditTagsPage extends StatefulWidget {
  const EditTagsPage({super.key, required this.track});
  final Track track;

  @override
  State<EditTagsPage> createState() => _EditTagsPageState();
}

class _EditTagsPageState extends State<EditTagsPage> {
  late final Map<String, TextEditingController> c;
  late final Map<String, String> initial;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    String n(int v) => v > 0 ? '$v' : '';
    initial = {
      'Name': t.title,
      'Artist': t.artist,
      'Album Artist': t.albumArtist,
      'Album': t.album,
      'Genre': t.genre,
      'Year': n(t.year),
      'Track': n(t.trackNo),
      'Track Count': n(t.trackTotal),
      'Disc': n(t.discNo),
      'Composer': t.composer,
      'Comments': t.comment,
    };
    c = {for (final e in initial.entries) e.key: TextEditingController(text: e.value)};
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  String? _txt(String k) => c[k]!.text != initial[k] ? c[k]!.text.trim() : null;
  int? _num(String k) =>
      c[k]!.text != initial[k] ? (int.tryParse(c[k]!.text.trim()) ?? 0) : null;

  Future<void> _save() async {
    final e = TagEdit()
      ..title = _txt('Name')
      ..artist = _txt('Artist')
      ..albumArtist = _txt('Album Artist')
      ..album = _txt('Album')
      ..genre = _txt('Genre')
      ..composer = _txt('Composer')
      ..comment = _txt('Comments')
      ..year = _num('Year')
      ..track = _num('Track')
      ..trackTotal = _num('Track Count')
      ..disc = _num('Disc');
    if (e.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final s = AppServices.I;
    await s.artwork.invalidate(widget.track);
    final resume = await s.player.suspendFor([widget.track.path]);
    final errors = await s.library.editTracks([widget.track], e);
    await resume();
    if (!mounted) return;
    setState(() => _saving = false);
    if (errors.isNotEmpty) {
      showMessage(context, 'Could not save', errors.join('\n'));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final writable = canWriteNatively(widget.track.path);
    return Scaffold(
      appBar: RetroNavBar(
        title: 'Info',
        showBack: true,
        backLabel: 'Cancel',
        showNowPlaying: false,
        actions: [
          if (writable)
            NavAction(icon: _saving ? Icons.hourglass_top : Icons.check, onTap: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (!writable)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'On the phone, song info can be edited for MP3 and FLAC files. '
                'Edit other formats on the desktop app.',
                style: TextStyle(color: Color(0xFF8A4B00)),
              ),
            ),
          for (final k in c.keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: c[k],
                enabled: writable,
                keyboardType: const {'Year', 'Track', 'Track Count', 'Disc'}.contains(k)
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: k,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(widget.track.path,
              style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
        ],
      ),
    );
  }
}
