import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';
import 'desktop_controller.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.ctrl, required this.searchController});

  final DesktopController ctrl;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final player = AppServices.I.player;
    final settings = AppServices.I.settings;
    return BrushedMetal(
      height: 76,
      bottomBorder: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ListenableBuilder(
            listenable: player,
            builder: (_, __) => Row(children: [
              AquaRoundButton(
                  icon: Icons.fast_rewind,
                  tooltip: 'Previous',
                  onTap: player.previous),
              const SizedBox(width: 5),
              AquaRoundButton(
                  icon: player.playing ? Icons.pause : Icons.play_arrow,
                  size: 40,
                  tooltip: player.playing ? 'Pause' : 'Play',
                  onTap: () {
                    if (player.current == null) {
                      final list = ctrl.visibleTracks;
                      if (list.isNotEmpty) {
                        final sel = ctrl.selectedTracks;
                        final idx = sel.isEmpty ? 0 : list.indexOf(sel.first);
                        player.playList(list, idx < 0 ? 0 : idx);
                        return;
                      }
                    }
                    player.playPause();
                  }),
              const SizedBox(width: 5),
              AquaRoundButton(
                  icon: Icons.fast_forward, tooltip: 'Next', onTap: player.next),
            ]),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.volume_mute, size: 14, color: Color(0xFF404040)),
          SizedBox(
            width: 96,
            child: ListenableBuilder(
              listenable: player,
              builder: (_, __) => SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 4,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                  activeTrackColor: Color(0xFF555555),
                  inactiveTrackColor: Color(0xFF9E9E9E),
                  thumbColor: Color(0xFFF4F4F4),
                ),
                child: Slider(
                  value: player.volume.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  onChanged: player.setVolume,
                ),
              ),
            ),
          ),
          const Icon(Icons.volume_up, size: 14, color: Color(0xFF404040)),
          const SizedBox(width: 16),
          const Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 480, minWidth: 260),
                child: StatusLcd(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          ListenableBuilder(
            listenable: settings,
            builder: (_, __) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  MetalButton(
                    icon: Icons.view_list,
                    tooltip: 'View as list',
                    active: settings.viewMode == 'list',
                    onTap: () => settings.update((s) => s.viewMode = 'list'),
                  ),
                  const SizedBox(width: 2),
                  MetalButton(
                    icon: Icons.view_module,
                    tooltip: 'View as album grid',
                    active: settings.viewMode == 'albums',
                    onTap: () => settings.update((s) => s.viewMode = 'albums'),
                  ),
                  const SizedBox(width: 2),
                  MetalButton(
                    icon: Icons.view_column,
                    tooltip: 'Show / hide browser (Ctrl+B)',
                    active: settings.showBrowser,
                    onTap: () => settings.update((s) => s.showBrowser = !s.showBrowser),
                  ),
                ]),
                const SizedBox(height: 3),
                const Text('View',
                    style: TextStyle(fontSize: 10, color: Color(0xFF3A3A3A))),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RetroSearchField(
                controller: searchController,
                onChanged: ctrl.setSearch,
              ),
              const SizedBox(height: 3),
              const Text('Search',
                  style: TextStyle(fontSize: 10, color: Color(0xFF3A3A3A))),
            ],
          ),
        ],
      ),
    );
  }
}

/// The status LCD: now playing, import progress, or library updates.
class StatusLcd extends StatefulWidget {
  const StatusLcd({super.key});

  @override
  State<StatusLcd> createState() => _StatusLcdState();
}

class _StatusLcdState extends State<StatusLcd> {
  bool _altLine = false;
  bool _showTotal = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _altLine = !_altLine);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.I;
    final listenables = <Listenable>[s.player, s.library, if (s.cd != null) s.cd!];
    return LcdBox(
      child: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (context, _) {
          final cd = s.cd;
          if (cd != null && cd.importing) return _importing(cd.importTitle,
              cd.importFraction, cd.importSpeed, cd.importRemaining);
          final t = s.player.current;
          if (t != null) return _nowPlaying(t);
          if (s.library.scanning) {
            return _message(s.library.scanStatus.isEmpty
                ? 'Updating Library…'
                : s.library.scanStatus,
                fraction: s.library.scanProgress);
          }
          return _idle();
        },
      ),
    );
  }

  Widget _idle() => const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album, size: 22, color: RetroColors.lcdDim),
            SizedBox(width: 8),
            Text('RetroTunes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ],
        ),
      );

  Widget _message(String text, {double? fraction}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (fraction != null) ...[
              const SizedBox(height: 5),
              LcdScrubber(fraction: fraction, height: 9),
            ],
          ],
        ),
      );

  Widget _importing(String title, double f, double speed, Duration remaining) {
    final rem = formatDuration(remaining.inMilliseconds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Importing “$title”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
              speed > 0
                  ? 'Time remaining: $rem (${speed.toStringAsFixed(1)}x)'
                  : 'Starting…',
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 3),
          LcdScrubber(fraction: f, height: 9),
        ],
      ),
    );
  }

  Widget _nowPlaying(Track t) {
    final p = AppServices.I.player;
    final line2 = _altLine ? t.displayAlbum : t.displayArtist;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(t.title.isEmpty ? 'Untitled' : t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Text(line2,
                key: ValueKey(line2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ),
          StreamBuilder<Duration>(
            stream: p.positionStream,
            builder: (context, _) {
              final pos = p.position.inMilliseconds;
              var dur = p.duration.inMilliseconds;
              if (dur <= 0) dur = t.durationMs;
              final f = dur > 0 ? pos / dur : 0.0;
              return Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(formatDuration(pos),
                        style: const TextStyle(fontSize: 10)),
                  ),
                  Expanded(
                    child: LcdScrubber(
                      fraction: f,
                      onSeek: dur > 0
                          ? (x) => p.seek(Duration(milliseconds: (x * dur).round()))
                          : null,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showTotal = !_showTotal),
                    child: SizedBox(
                      width: 44,
                      child: Text(
                        _showTotal
                            ? formatDuration(dur)
                            : '-${formatDuration((dur - pos).clamp(0, dur))}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
