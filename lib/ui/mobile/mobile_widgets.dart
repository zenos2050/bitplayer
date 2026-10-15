import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import '../common/retro_theme.dart';
import '../common/retro_widgets.dart';
import 'now_playing.dart';

/// Glossy blue-gray navigation bar from iPhone OS 1–3.
class RetroNavBar extends StatelessWidget implements PreferredSizeWidget {
  const RetroNavBar({
    super.key,
    required this.title,
    this.showBack = false,
    this.backLabel = 'Back',
    this.showNowPlaying = true,
    this.actions = const [],
  });

  final String title;
  final bool showBack;
  final String backLabel;
  final bool showNowPlaying;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RetroColors.navTop, RetroColors.navMid, RetroColors.navBottom],
          stops: [0, 0.5, 1],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF2D3642))),
      ),
      child: SizedBox(
        height: 46,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 96),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Color(0x88000000), offset: Offset(0, -1))],
                ),
              ),
            ),
            if (showBack)
              Positioned(
                left: 6,
                child: _BarButton(
                  label: backLabel,
                  back: true,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
            Positioned(
              right: 6,
              child: Row(children: [
                ...actions,
                if (showNowPlaying)
                  ListenableBuilder(
                    listenable: AppServices.I.player,
                    builder: (context, _) => AppServices.I.player.current == null
                        ? const SizedBox.shrink()
                        : _BarButton(
                            label: 'Now\nPlaying',
                            forward: true,
                            onTap: () => openNowPlaying(context),
                          ),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.onTap,
    this.back = false,
    this.forward = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool back;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 31,
        padding: EdgeInsets.only(left: back ? 4 : 9, right: forward ? 4 : 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF3D4B5E)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9AAAC0), Color(0xFF5A7193)],
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (back) const Icon(Icons.chevron_left, color: Colors.white, size: 20),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: label.contains('\n') ? 10 : 13,
                height: 1.05,
                fontWeight: FontWeight.w700,
              )),
          if (forward) const Icon(Icons.chevron_right, color: Colors.white, size: 18),
        ]),
      ),
    );
  }
}

/// Small action button for the nav bar (e.g. "Edit", "+").
class NavAction extends StatelessWidget {
  const NavAction({super.key, required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 31,
            width: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF3D4B5E)),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF9AAAC0), Color(0xFF5A7193)],
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      );
}

/// A pushed screen with the retro nav bar.
class RetroPage extends StatelessWidget {
  const RetroPage({
    super.key,
    required this.title,
    required this.body,
    this.backLabel = 'Back',
    this.actions = const [],
  });

  final String title;
  final Widget body;
  final String backLabel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: RetroNavBar(
          title: title, showBack: true, backLabel: backLabel, actions: actions),
      body: body,
    );
  }
}

/// Classic white list row with gray separator.
class RetroRow extends StatelessWidget {
  const RetroRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.chevron = false,
    this.height = 50,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool chevron;
  final double height;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      highlightColor: const Color(0xFF0A62E4),
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFDADADA))),
        ),
        child: Row(children: [
          if (leading != null) leading! else const SizedBox(width: 12),
          if (leading != null) const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: highlight ? const Color(0xFF2E5FAE) : Colors.black)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF7F7F7F))),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (chevron)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.chevron_right, color: Color(0xFFA9A9A9)),
            )
          else
            const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

/// Gray A–Z section header.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 23,
        padding: const EdgeInsets.only(left: 12),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xE6A5B1BA), Color(0xE6B8C1C7)],
          ),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 1))])),
      );
}

/// Square thumbnail for list rows.
class Thumb extends StatelessWidget {
  const Thumb(this.track, {super.key, this.size = 50});
  final Track track;
  final double size;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: ArtworkImage(track: track, size: size));
}

/// Opens the Now Playing screen.
void openNowPlaying(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder(
    pageBuilder: (_, __, ___) => const NowPlayingScreen(),
    transitionsBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(anim),
      child: child,
    ),
  ));
}

String firstLetter(String s) {
  final t = s.trim();
  if (t.isEmpty) return '#';
  var x = t;
  if (x.toLowerCase().startsWith('the ') && x.length > 4) x = x.substring(4);
  final c = x[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
}

/// Sort key ignoring a leading "The ".
String sortKeyOf(String s) {
  final l = s.trim().toLowerCase();
  return l.startsWith('the ') ? l.substring(4) : l;
}
