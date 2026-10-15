import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/models.dart';
import 'retro_theme.dart';

/// Brushed-metal panel used for the title and bottom bars.
class BrushedMetal extends StatelessWidget {
  const BrushedMetal({
    super.key,
    required this.child,
    this.height,
    this.topBorder = false,
    this.bottomBorder = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double? height;
  final bool topBorder;
  final bool bottomBorder;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          gradient: metalGradient,
          border: Border(
            top: topBorder
                ? const BorderSide(color: RetroColors.metalEdge)
                : BorderSide.none,
            bottom: bottomBorder
                ? const BorderSide(color: RetroColors.metalEdge)
                : BorderSide.none,
          ),
        ),
        child: CustomPaint(painter: _BrushPainter(), child: child),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(1977);
    final paint = Paint()..strokeWidth = 1;
    for (double y = 0.5; y < size.height; y += 1) {
      final light = rng.nextBool();
      final a = rng.nextInt(14);
      paint.color = (light ? Colors.white : Colors.black).withAlpha(a);
      final start = rng.nextDouble() * size.width * 0.3;
      canvas.drawLine(Offset(start, y),
          Offset(size.width - rng.nextDouble() * size.width * 0.3, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Round glossy "aqua" transport button.
class AquaRoundButton extends StatefulWidget {
  const AquaRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 30,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  @override
  State<AquaRoundButton> createState() => _AquaRoundButtonState();
}

class _AquaRoundButtonState extends State<AquaRoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final btn = GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _down
                ? const [Color(0xFFB8B8B8), Color(0xFF8E8E8E)]
                : const [RetroColors.aquaTop, RetroColors.aquaBottom],
          ),
          border: Border.all(color: RetroColors.aquaRim, width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x55FFFFFF), offset: Offset(0, 1), blurRadius: 0),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // glossy highlight
            Positioned(
              top: s * 0.06,
              child: Container(
                width: s * 0.7,
                height: s * 0.38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(s),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
            Icon(widget.icon, size: s * 0.55, color: const Color(0xFF2E2E2E)),
          ],
        ),
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}

/// Small glossy rectangular button (bottom bar / toolbar).
class MetalButton extends StatelessWidget {
  const MetalButton({
    super.key,
    this.icon,
    this.label,
    required this.onTap,
    this.active = false,
    this.tooltip,
    this.width,
  });

  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final bool active;
  final String? tooltip;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = !enabled
        ? const Color(0xFF9A9A9A)
        : (active ? const Color(0xFF1F63D6) : const Color(0xFF333333));
    Widget b = InkWell(
      onTap: onTap,
      child: Container(
        height: 22,
        width: width ?? (label == null ? 30 : null),
        padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF7A7A7A)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: active
                ? const [Color(0xFFDCE6F5), Color(0xFFB4C4DE)]
                : const [Color(0xFFFDFDFD), Color(0xFFD0D0D0)],
          ),
        ),
        alignment: Alignment.center,
        child: label == null
            ? Icon(icon, size: 15, color: color)
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                ],
                Text(label!,
                    style: TextStyle(
                        fontSize: 11, color: color, fontWeight: FontWeight.w500)),
              ]),
      ),
    );
    if (tooltip != null) b = Tooltip(message: tooltip!, child: b);
    return b;
  }
}

/// The famous status "LCD".
class LcdBox extends StatelessWidget {
  const LcdBox({super.key, required this.child, this.height = 52});
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: RetroColors.lcdBorder),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [RetroColors.lcdTop, RetroColors.lcdBottom],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x88FFFFFF), offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x33000000), width: 2)),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: RetroColors.lcdText, fontSize: 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Progress bar with a diamond knob, as in the iTunes LCD.
class LcdScrubber extends StatelessWidget {
  const LcdScrubber({
    super.key,
    required this.fraction,
    this.onSeek,
    this.height = 12,
  });

  final double fraction;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      void seek(Offset local) {
        if (onSeek == null || c.maxWidth <= 0) return;
        onSeek!((local.dx / c.maxWidth).clamp(0.0, 1.0));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seek(d.localPosition),
        onHorizontalDragUpdate: (d) => seek(d.localPosition),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _ScrubPainter(fraction.clamp(0.0, 1.0))),
        ),
      );
    });
  }
}

class _ScrubPainter extends CustomPainter {
  _ScrubPainter(this.f);
  final double f;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - 3.5, size.width, 7), const Radius.circular(3.5));
    canvas.drawRRect(track, Paint()..color = const Color(0x22000000));
    canvas.drawRRect(
        track,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = RetroColors.lcdDim);
    final fill = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, cy - 3.5, size.width * f, 7), const Radius.circular(3.5));
    canvas.drawRRect(fill, Paint()..color = const Color(0xFF60664C));
    final x = (size.width * f).clamp(4.0, size.width - 4);
    final path = Path()
      ..moveTo(x, cy - 5.5)
      ..lineTo(x + 5, cy)
      ..lineTo(x, cy + 5.5)
      ..lineTo(x - 5, cy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF151510));
  }

  @override
  bool shouldRepaint(covariant _ScrubPainter old) => old.f != f;
}

/// Capsule search box.
class RetroSearchField extends StatelessWidget {
  const RetroSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.width = 170,
    this.hint = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final double width;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 24,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
          prefixIcon: const Icon(Icons.search, size: 15),
          prefixIconConstraints: const BoxConstraints(minWidth: 26),
          suffixIcon: ListenableBuilder(
            listenable: controller,
            builder: (_, __) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                    child: const Icon(Icons.cancel, size: 14, color: Color(0xFF9A9A9A)),
                  ),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 24),
          contentPadding: const EdgeInsets.symmetric(vertical: 5),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8C8C8C)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8C8C8C)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF5B8FD9), width: 2),
          ),
        ),
      ),
    );
  }
}

/// Album art for a track, or a classic gray "music note" placeholder.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({super.key, required this.track, this.size, this.radius = 0});

  final Track? track;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = track;
    Widget placeholder() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF2F2F2), Color(0xFFBDBDBD)],
            ),
          ),
          child: LayoutBuilder(
            builder: (_, c) => Icon(Icons.music_note,
                size: (c.maxWidth.isFinite ? c.maxWidth : 60) * 0.5,
                color: const Color(0xFF8F8F8F)),
          ),
        );
    if (t == null) return placeholder();
    return FutureBuilder<File?>(
      future: AppServices.I.artwork.forTrack(t),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return placeholder();
        final dpr = MediaQuery.devicePixelRatioOf(context);
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(
            f,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: size == null ? null : (size! * dpr).round(),
            errorBuilder: (_, __, ___) => placeholder(),
          ),
        );
      },
    );
  }
}

/// Simple text-entry dialog.
Future<String?> promptText(BuildContext context,
    {required String title, String initial = '', String ok = 'OK'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: TextField(
        controller: c,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context,
    {required String title, required String message, String ok = 'OK'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

void showMessage(BuildContext context, String title, String message) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: SingleChildScrollView(child: SelectableText(message)),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}
