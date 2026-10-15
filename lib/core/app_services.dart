import 'artwork.dart';
import 'audio_handler.dart';
import 'cd/cd_service.dart';
import 'library.dart';
import 'platform.dart';
import 'player.dart';
import 'settings.dart';

/// Service locator for the app's long-lived objects.
class AppServices {
  AppServices._(this.settings, this.library, this.player, this.artwork, this.cd);

  static late final AppServices I;

  final Settings settings;
  final LibraryService library;
  final PlayerController player;
  final ArtworkCache artwork;
  final CdService? cd;
  RetroAudioHandler? audioHandler;

  static Future<AppServices> init() async {
    final settings = Settings();
    await settings.load();
    final library = LibraryService(settings);
    await library.init();
    final artwork = ArtworkCache(settings.supportDir);
    final player = PlayerController(settings, library);
    final cd = Plat.supportsCd ? CdService(settings, library, artwork) : null;
    final s = AppServices._(settings, library, player, artwork, cd);
    I = s;
    if (Plat.isMobile) {
      try {
        s.audioHandler = await RetroAudioHandler.create(player, artwork);
      } catch (_) {
        // Media session unavailable: playback still works in the foreground.
      }
    } else {
      // Desktop: scan right away and start watching for CDs.
      library.start();
      cd?.start();
    }
    return s;
  }
}
