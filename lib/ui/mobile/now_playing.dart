import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../common/retro_widgets.dart';
import 'mobile_lists.dart';

/// Full-screen "Now Playing" in the style of the original iPhone iPod app:
/// black, big cover with a reflection, glossy control panel.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppServices.I.player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: Listenable.merge([p, AppServices.I.settings]),
        builder: (context, _) {
          final t = p.current;
          if (t == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              _topBar(context, t),
              _scrubber(t),
              Expanded(child: _artwork(t)),
              _controls(context),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(BuildContext context, Track t) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A4A4A), Color(0xFF151515)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF000000))),
      ),
      child: SizedBox(
        height: 58,
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(t.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 12)),
                Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(t.displayAlbum,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Up Next',
            icon: const Icon(Icons.format_list_bulleted, color: Colors.white),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const QueuePage())),
          ),
        ]),
      ),
    );
  }

  Widget _scrubber(Track t) {
    final p = AppServices.I.player;
    final s = AppServices.I.settings;
    return Container(
      color: const Color(0xCC1A1A1A),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(children: [
        IconButton(
          icon: Icon(s.repeat == LoopMode.one ? Icons.repeat_one : Icons.repeat,
              color: s.repeat == LoopMode.off ? Colors.white54 : const Color(0xFF5AA0FF)),
          onPressed: p.cycleRepeat,
        ),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: p.positionStream,
            builder: (context, _) {
              final pos = p.position.inMilliseconds;
              var dur = p.duration.inMilliseconds;
              if (dur <= 0) dur = t.durationMs;
              return Row(children: [
                SizedBox(
                  width: 42,
                  child: Text(formatDuration(pos),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                Expanded(
                  child: SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 3,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: Color(0xFF8DB4E8),
                      inactiveTrackColor: Color(0xFF555555),
                      thumbColor: Colors.white,
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0,
                      onChanged: dur > 0
                          ? (v) => p.seek(Duration(milliseconds: (v * dur).round()))
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text('-${formatDuration((dur - pos).clamp(0, dur))}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ]);
            },
          ),
        ),
        IconButton(
          icon: Icon(Icons.shuffle,
              color: s.shuffle ? const Color(0xFF5AA0FF) : Colors.white54),
          onPressed: p.toggleShuffle,
        ),
      ]),
    );
  }

  Widget _artwork(Track t) {
    return LayoutBuilder(builder: (context, c) {
      final size = (c.maxWidth < c.maxHeight * 0.78 ? c.maxWidth : c.maxHeight * 0.78)
          .clamp(100.0, 600.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: ArtworkImage(key: ValueKey(t.path), track: t, size: size),
          ),
          // Reflection
          SizedBox(
            width: size,
            height: (c.maxHeight - size).clamp(0.0, size * 0.25),
            child: ClipRect(
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: Transform(
                  alignment: Alignment.topCenter,
                  transform: Matrix4.diagonal3Values(1, -1, 1),
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    maxHeight: size,
                    child: ArtworkImage(track: t, size: size),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _controls(BuildContext context) {
    final p = AppServices.I.player;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3A3A), Color(0xFF111111), Color(0xFF000000)],
          stops: [0, 0.5, 1],
        ),
        border: Border(top: BorderSide(color: Color(0xFF555555))),
      ),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 44,
              icon: const Icon(Icons.fast_rewind, color: Colors.white),
              onPressed: p.previous,
            ),
            IconButton(
              iconSize: 56,
              icon: Icon(p.playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
              onPressed: p.playPause,
            ),
            IconButton(
              iconSize: 44,
              icon: const Icon(Icons.fast_forward, color: Colors.white),
              onPressed: p.next,
            ),
          ],
        ),
        Row(children: [
          const Icon(Icons.volume_mute, color: Colors.white70, size: 18),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 4,
                activeTrackColor: Color(0xFFDDDDDD),
                inactiveTrackColor: Color(0xFF444444),
                thumbColor: Color(0xFFF2F2F2),
              ),
              child: Slider(
                value: p.volume.clamp(0.0, 100.0),
                max: 100,
                onChanged: p.setVolume,
              ),
            ),
          ),
          const Icon(Icons.volume_up, color: Colors.white70, size: 18),
        ]),
      ]),
    );
  }
}
