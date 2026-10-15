import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'artwork.dart';
import 'player.dart';

/// Bridges [PlayerController] to the OS media session on Android / iOS:
/// lock-screen controls, notification, headset buttons, background audio.
class RetroAudioHandler extends BaseAudioHandler with SeekHandler {
  RetroAudioHandler(this.c, this.art) {
    c.addListener(_pushState);
    c.onTrackChanged = _pushItem;
    _posSub = c.positionStream.listen((pos) {
      // Re-sync the system's extrapolated position after jumps.
      final last = playbackState.value.updatePosition;
      if ((pos - last).inSeconds.abs() > 2 && !c.playing) _pushState();
    });
    _pushState();
  }

  final PlayerController c;
  final ArtworkCache art;
  StreamSubscription<Duration>? _posSub;
  bool _wasPlaying = false;

  static Future<RetroAudioHandler> create(PlayerController c, ArtworkCache art) async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final handler = await AudioService.init(
      builder: () => RetroAudioHandler(c, art),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.solus.bitplayer.playback',
        androidNotificationChannelName: 'BitPlayer playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    // Pause when headphones are unplugged / a call comes in.
    session.becomingNoisyEventStream.listen((_) => c.pause());
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        handler._wasPlaying = c.playing;
        if (event.type != AudioInterruptionType.duck) c.pause();
      } else if (handler._wasPlaying &&
          event.type == AudioInterruptionType.pause) {
        c.play();
      }
    });
    return handler;
  }

  void _pushState() {
    final playing = c.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: c.current == null
          ? AudioProcessingState.idle
          : AudioProcessingState.ready,
      playing: playing,
      updatePosition: c.position,
      speed: 1.0,
    ));
  }

  Future<void> _pushItem() async {
    final t = c.current;
    if (t == null) {
      mediaItem.add(null);
      _pushState();
      return;
    }
    var item = MediaItem(
      id: t.path,
      title: t.title.isEmpty ? 'Untitled' : t.title,
      artist: t.displayArtist,
      album: t.displayAlbum,
      duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
    );
    mediaItem.add(item);
    _pushState();
    final f = await art.forTrack(t);
    if (f != null && c.current == t) {
      item = item.copyWith(artUri: Uri.file(f.path));
      mediaItem.add(item);
    }
  }

  @override
  Future<void> play() => c.play();
  @override
  Future<void> pause() => c.pause();
  @override
  Future<void> stop() async {
    await c.pause();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await c.seek(position);
    _pushState();
  }

  @override
  Future<void> skipToNext() => c.next();
  @override
  Future<void> skipToPrevious() => c.previous();

  Future<void> dispose() async {
    await _posSub?.cancel();
    c.removeListener(_pushState);
  }
}
