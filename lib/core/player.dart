import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'library.dart';
import 'models.dart';
import 'settings.dart';

/// Playback engine: wraps a libmpv player (media_kit) and owns the play
/// queue, shuffle / repeat and play counts.
class PlayerController extends ChangeNotifier {
  PlayerController(this.settings, this.library) {
    player = Player(configuration: PlayerConfiguration(title: 'RetroTunes'));
    _subs.addAll([
      player.stream.playing.listen((_) => notifyListeners()),
      player.stream.completed.listen((done) {
        if (done && !_suspended) _onCompleted();
      }),
      player.stream.duration.listen((d) {
        final t = current;
        if (t != null && !t.isCd && d.inMilliseconds > 0) {
          library.updateDuration(t.path, d.inMilliseconds);
        }
        notifyListeners();
      }),
      player.stream.error.listen((e) {
        lastError = e;
        notifyListeners();
        // Skip unplayable files instead of stalling.
        if (current != null) {
          Timer(const Duration(milliseconds: 800), () => next(auto: true));
        }
      }),
    ]);
    player.setVolume(settings.volume);
  }

  final Settings settings;
  final LibraryService library;
  late final Player player;
  final List<StreamSubscription> _subs = [];
  final Random _rng = Random();

  List<Track> _queue = [];
  List<int> _order = [];
  int _pos = -1;
  bool _countedCurrent = false;
  bool _suspended = false;
  String? lastError;

  /// Optional hook for the system media session (mobile).
  void Function()? onTrackChanged;

  List<Track> get queue => _queue;
  Track? get current =>
      (_pos >= 0 && _pos < _order.length) ? _queue[_order[_pos]] : null;
  bool get playing => player.state.playing;
  bool get hasNext => _pos + 1 < _order.length || settings.repeat == RepeatMode.all;
  Duration get position => player.state.position;
  Duration get duration => player.state.duration;
  Stream<Duration> get positionStream => player.stream.position;

  bool get shuffle => settings.shuffle;
  RepeatMode get repeat => settings.repeat;
  double get volume => settings.volume;

  /// Plays [tracks] starting at [index] (the visible list becomes the queue).
  Future<void> playList(List<Track> tracks, int index) async {
    if (tracks.isEmpty) return;
    _maybeCountSkip();
    _queue = List.of(tracks);
    _buildOrder(startIndex: index.clamp(0, tracks.length - 1));
    await _openCurrent();
  }

  void _buildOrder({required int startIndex}) {
    _order = List.generate(_queue.length, (i) => i);
    if (settings.shuffle) {
      _order.remove(startIndex);
      _order.shuffle(_rng);
      _order.insert(0, startIndex);
      _pos = 0;
    } else {
      _pos = startIndex;
    }
  }

  Future<void> _openCurrent() async {
    final t = current;
    if (t == null) return;
    lastError = null;
    _countedCurrent = false;
    await player.open(Media(t.path), play: true);
    notifyListeners();
    onTrackChanged?.call();
  }

  Future<void> playPause() async {
    if (current == null) {
      // Nothing queued: play the whole library.
      final all = library.allTracks;
      if (all.isNotEmpty) await playList(all, 0);
      return;
    }
    await player.playOrPause();
  }

  Future<void> play() => current == null ? playPause() : player.play();
  Future<void> pause() => player.pause();

  Future<void> stop() async {
    await player.stop();
    _pos = -1;
    _queue = [];
    _order = [];
    notifyListeners();
    onTrackChanged?.call();
  }

  Future<void> next({bool auto = false}) async {
    if (_order.isEmpty) return;
    if (!auto) _maybeCountSkip();
    if (_pos + 1 < _order.length) {
      _pos++;
    } else if (settings.repeat == RepeatMode.all) {
      if (settings.shuffle) _order.shuffle(_rng);
      _pos = 0;
    } else {
      await player.stop();
      _pos = -1;
      notifyListeners();
      onTrackChanged?.call();
      return;
    }
    await _openCurrent();
  }

  Future<void> previous() async {
    if (_order.isEmpty) return;
    if (player.state.position.inSeconds >= 3 || _pos == 0) {
      await player.seek(Duration.zero);
      return;
    }
    _maybeCountSkip();
    _pos--;
    await _openCurrent();
  }

  Future<void> seek(Duration d) => player.seek(d);

  Future<void> jumpTo(int queueIndex) async {
    final i = _order.indexOf(queueIndex);
    if (i < 0) return;
    _maybeCountSkip();
    _pos = i;
    await _openCurrent();
  }

  void setVolume(double v) {
    v = v.clamp(0, 100).toDouble();
    player.setVolume(v);
    settings.volume = v;
    settings.save();
    notifyListeners();
  }

  void toggleShuffle() {
    final cur = _pos >= 0 && _pos < _order.length ? _order[_pos] : 0;
    settings.update((s) => s.shuffle = !s.shuffle);
    if (_queue.isNotEmpty) {
      if (settings.shuffle) {
        _buildOrder(startIndex: cur);
      } else {
        _order = List.generate(_queue.length, (i) => i);
        _pos = cur;
      }
    }
    notifyListeners();
  }

  void cycleRepeat() {
    settings.update((s) => s.repeat =
        RepeatMode.values[(s.repeat.index + 1) % RepeatMode.values.length]);
    notifyListeners();
  }

  void _onCompleted() {
    final t = current;
    if (t != null && !_countedCurrent) {
      _countedCurrent = true;
      if (!t.isCd) library.markPlayed(t);
    }
    if (settings.repeat == RepeatMode.one) {
      player.seek(Duration.zero).then((_) => player.play());
      _countedCurrent = false;
      return;
    }
    next(auto: true);
  }

  /// iTunes counted a play when you'd heard most of a song.
  void _maybeCountSkip() {
    final t = current;
    if (t == null || _countedCurrent || t.isCd) return;
    final d = player.state.duration.inMilliseconds;
    final pos = player.state.position.inMilliseconds;
    if (d > 0 && pos > d * 0.5) {
      _countedCurrent = true;
      library.markPlayed(t);
    }
  }

  /// Windows locks files that are open for playback, so before a tag write
  /// or move of the current song we close it and reopen it afterwards.
  /// Returns a callback that resumes playback at the same position.
  Future<Future<void> Function()> suspendFor(Iterable<String> paths) async {
    final t = current;
    final set = paths.toSet();
    if (t == null || !set.contains(t.path)) return () async {};
    final pos = player.state.position;
    final wasPlaying = player.state.playing;
    _suspended = true;
    await player.stop();
    return () async {
      final cur = current;
      if (cur == null) {
        _suspended = false;
        return;
      }
      await player.open(Media(cur.path), play: false);
      try {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 3));
        await player.seek(pos);
      } catch (_) {}
      _suspended = false;
      if (wasPlaying) await player.play();
      notifyListeners();
      onTrackChanged?.call();
    };
  }

  /// Called when the library changes paths (e.g. a retag moved a file).
  void remapPath(String from, String to) {
    for (final t in _queue) {
      if (t.path == from) t.path = to;
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
