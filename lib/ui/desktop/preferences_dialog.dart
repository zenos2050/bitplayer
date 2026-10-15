import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/ffmpeg.dart';
import '../../core/platform.dart';
import '../../core/settings.dart';
import '../common/retro_widgets.dart';

Future<void> showPreferences(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _PrefsDialog());

class _PrefsDialog extends StatefulWidget {
  const _PrefsDialog();

  @override
  State<_PrefsDialog> createState() => _PrefsDialogState();
}

class _PrefsDialogState extends State<_PrefsDialog> {
  int _tab = 0;
  String? _ffmpegFound;
  bool _checking = true;
  bool _installing = false;
  late final TextEditingController _ffmpegCtl;

  Settings get s => AppServices.I.settings;

  @override
  void initState() {
    super.initState();
    _ffmpegCtl = TextEditingController(text: s.ffmpegPath);
    _detect();
  }

  @override
  void dispose() {
    _ffmpegCtl.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() => _checking = true);
    final f = await Ffmpeg.locate(s, refresh: true);
    if (mounted) {
      setState(() {
        _ffmpegFound = f;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Preferences', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 520,
        height: 380,
        child: Column(
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.tune, size: 16), label: Text('General')),
                ButtonSegment(value: 1, icon: Icon(Icons.album, size: 16), label: Text('Importing')),
              ],
              selected: {_tab},
              onSelectionChanged: (v) => setState(() => _tab = v.first),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListenableBuilder(
                listenable: s,
                builder: (context, _) =>
                    SingleChildScrollView(child: _tab == 0 ? _general() : _importing()),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }

  Widget _general() {
    final lib = AppServices.I.library;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Music folder location', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFBBBBBB)),
          ),
          child: SelectableText(s.libraryPath, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Row(children: [
          OutlinedButton(
            onPressed: () async {
              final dir = await FilePicker.platform
                  .getDirectoryPath(dialogTitle: 'Choose Music Folder');
              if (dir != null) await lib.changeRoot(dir);
            },
            child: const Text('Change…'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Plat.openFolder(s.libraryPath),
            child: Text('Open in ${Plat.fileManagerName}'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: lib.scan, child: const Text('Rescan Now')),
        ]),
        const SizedBox(height: 14),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.keepOrganized,
          onChanged: (v) => s.update((x) => x.keepOrganized = v ?? true),
          title: const Text('Keep music folder organized'),
          subtitle: const Text(
              'Places files into Artist / Album folders and renames them '
              '“NN Title” when you edit song info.'),
        ),
        const SizedBox(height: 6),
        const Text(
          'The music folder is the library. You can add, rename, move or retag '
          'files with any other program — RetroTunes notices the changes. '
          'Playlists are stored as .m3u8 files in the “Playlists” subfolder, so '
          'copying the whole folder to your phone brings them along.',
          style: TextStyle(fontSize: 11, color: Color(0xFF555555)),
        ),
      ],
    );
  }

  Widget _importing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const SizedBox(width: 110, child: Text('Import using:')),
          DropdownButton<RipFormat>(
            value: s.ripFormat,
            items: [
              for (final f in RipFormat.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (f) => s.update((x) => x.ripFormat = f ?? RipFormat.mp3),
          ),
        ]),
        if (s.ripFormat == RipFormat.mp3)
          Row(children: [
            const SizedBox(width: 110, child: Text('Setting:')),
            DropdownButton<int>(
              value: s.mp3Bitrate,
              items: const [
                DropdownMenuItem(value: 128, child: Text('Good Quality (128 kbps)')),
                DropdownMenuItem(value: 192, child: Text('High Quality (192 kbps)')),
                DropdownMenuItem(value: 256, child: Text('Higher Quality (256 kbps)')),
                DropdownMenuItem(value: 320, child: Text('Highest Quality (320 kbps)')),
                DropdownMenuItem(value: 0, child: Text('VBR (V0, ~245 kbps)')),
              ],
              onChanged: (v) => s.update((x) => x.mp3Bitrate = v ?? 320),
            ),
          ]),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.autoLookupCd,
          onChanged: (v) => s.update((x) => x.autoLookupCd = v ?? true),
          title: const Text('Automatically retrieve CD track names from MusicBrainz'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: s.ejectAfterImport,
          onChanged: (v) => s.update((x) => x.ejectAfterImport = v ?? false),
          title: const Text('Eject CD after importing'),
        ),
        const Divider(),
        const Text('Encoder (ffmpeg)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(
            _checking
                ? Icons.hourglass_empty
                : (_ffmpegFound != null ? Icons.check_circle : Icons.error),
            size: 16,
            color: _checking
                ? Colors.grey
                : (_ffmpegFound != null ? Colors.green : Colors.red),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _checking
                  ? 'Looking for ffmpeg…'
                  : (_ffmpegFound ?? 'ffmpeg not found — needed for MP3/AAC/FLAC/ALAC/OGG imports.'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ffmpegCtl,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Custom ffmpeg path (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => s.update((x) => x.ffmpegPath = v.trim()),
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: () async {
              final r = await FilePicker.platform.pickFiles(dialogTitle: 'Locate ffmpeg');
              final path = r?.files.single.path;
              if (path != null) {
                _ffmpegCtl.text = path;
                s.update((x) => x.ffmpegPath = path);
                await _detect();
              }
            },
            child: const Text('Browse…'),
          ),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: _detect, child: const Text('Detect')),
        ]),
        const SizedBox(height: 8),
        if (Plat.isWindows)
          Row(children: [
            FilledButton.icon(
              onPressed: _installing ? null : _install,
              icon: _installing
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download, size: 16),
              label: Text(_installing ? 'Installing…' : 'Install ffmpeg (winget)'),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Runs: winget install Gyan.FFmpeg',
                  style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
            ),
          ])
        else if (Plat.isMacOS)
          const Text('Install with Homebrew:  brew install ffmpeg',
              style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    try {
      final r = await Ffmpeg.installWithWinget();
      await _detect();
      if (!mounted) return;
      if (_ffmpegFound == null) {
        showMessage(context, 'Install ffmpeg',
            'winget finished with code ${r.exitCode}.\n\n${r.stdout}\n${r.stderr}\n\n'
            'If ffmpeg was installed, restart RetroTunes or click Detect.');
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, 'Install ffmpeg',
            'Could not run winget: $e\n\nInstall ffmpeg manually and point to ffmpeg.exe above.');
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }
}
