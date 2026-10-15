import 'package:flutter_test/flutter_test.dart';

import 'package:bitplayer/core/library.dart';
import 'package:bitplayer/core/models.dart';

void main() {
  test('sanitizeName strips illegal file name characters', () {
    expect(sanitizeName('AC/DC: Back in Black?'), 'AC_DC_ Back in Black_');
    expect(sanitizeName('CON'), 'CON_');
    expect(sanitizeName('  '), 'Unknown');
  });

  test('organizedPath builds Artist/Album/NN Title', () {
    final p = organizedPath(
        '/m', TagData(artist: 'Artist', album: 'Album', title: 'Song', track: 3), 'mp3');
    expect(p.replaceAll('\\', '/'), '/m/Artist/Album/03 Song.mp3');
  });

  test('formatDuration', () {
    expect(formatDuration(61000), '1:01');
    expect(formatDuration(3723000), '1:02:03');
  });
}
