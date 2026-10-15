import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_services.dart';
import 'core/platform.dart';
import 'ui/common/retro_theme.dart';
import 'ui/desktop/desktop_shell.dart';
import 'ui/mobile/mobile_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppServices.init();
  runApp(const RetroTunesApp());
}

class RetroTunesApp extends StatelessWidget {
  const RetroTunesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RetroTunes',
      debugShowCheckedModeBanner: false,
      theme: Plat.isDesktop ? RetroTheme.desktop() : RetroTheme.mobile(),
      home: Plat.isDesktop ? const DesktopShell() : const MobileShell(),
    );
  }
}
