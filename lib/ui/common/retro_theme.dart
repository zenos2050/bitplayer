import 'package:flutter/material.dart';

/// Colors from the iTunes 4–7 era: brushed metal, a pale green LCD,
/// blue-gray source list and blue-striped song list.
class RetroColors {
  static const metalTop = Color(0xFFE9E9E9);
  static const metalMid = Color(0xFFD2D2D2);
  static const metalBottom = Color(0xFFB7B7B7);
  static const metalEdge = Color(0xFF7F7F7F);

  static const lcdTop = Color(0xFFF1F4DF);
  static const lcdBottom = Color(0xFFD3DABA);
  static const lcdBorder = Color(0xFF6F7558);
  static const lcdText = Color(0xFF1D1F16);
  static const lcdDim = Color(0xFF4D523C);

  static const sourceBg = Color(0xFFD5DCE6);
  static const sourceHeader = Color(0xFF5F6B7A);
  static const sourceSelTop = Color(0xFF6C9AD9);
  static const sourceSelBottom = Color(0xFF3B6BBF);

  static const rowAlt = Color(0xFFEDF3FE);
  static const rowSel = Color(0xFF3D80DF);
  static const rowSelInactive = Color(0xFFC9C9C9);
  static const grid = Color(0xFFD9D9D9);
  static const headerTop = Color(0xFFFBFBFB);
  static const headerBottom = Color(0xFFDCDCDC);
  static const headerBorder = Color(0xFFA6A6A6);
  static const text = Color(0xFF111111);
  static const textDim = Color(0xFF6B6B6B);

  static const aquaTop = Color(0xFFF8F8F8);
  static const aquaBottom = Color(0xFFBDBDBD);
  static const aquaRim = Color(0xFF6E6E6E);

  // Mobile (iPhone OS 1-3 "iPod" app)
  static const navTop = Color(0xFFB0BCCD);
  static const navMid = Color(0xFF8297B4);
  static const navBottom = Color(0xFF6D84A2);
  static const tabTop = Color(0xFF3C3C3C);
  static const tabBottom = Color(0xFF0E0E0E);
  static const pinstripeA = Color(0xFFC5CCD4);
  static const pinstripeB = Color(0xFFCBD2D8);
}

class RetroTheme {
  static ThemeData desktop() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: RetroColors.rowSel,
        brightness: Brightness.light,
      ),
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: Colors.white,
      fontFamily: _desktopFont,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: RetroColors.text,
        displayColor: RetroColors.text,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFFECECEC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 700),
        textStyle: TextStyle(fontSize: 11, color: Colors.black),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFC6),
          border: Border.fromBorderSide(BorderSide(color: Color(0xFF8F8F8F))),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(10),
        radius: const Radius.circular(5),
        thumbColor: WidgetStateProperty.all(const Color(0xFF9DA8B8)),
        trackColor: WidgetStateProperty.all(const Color(0xFFEDEDED)),
        trackVisibility: WidgetStateProperty.all(true),
      ),
    );
  }

  static ThemeData mobile() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: RetroColors.navBottom),
      scaffoldBackgroundColor: Colors.white,
    );
    return base.copyWith(
      dividerColor: const Color(0xFFD8D8D8),
      listTileTheme: const ListTileThemeData(
        dense: false,
        titleTextStyle: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: Colors.black),
        subtitleTextStyle: TextStyle(fontSize: 13, color: Color(0xFF808080)),
      ),
    );
  }

  static String? get _desktopFont => null; // platform default (Segoe UI / SF)
}

/// Standard vertical metal gradient.
const metalGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [RetroColors.metalTop, RetroColors.metalMid, RetroColors.metalBottom],
  stops: [0, 0.55, 1],
);
