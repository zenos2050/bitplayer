import 'dart:io';

/// Small platform helpers.
class Plat {
  static bool get isWindows => Platform.isWindows;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isLinux => Platform.isLinux;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isIOS => Platform.isIOS;
  static bool get isDesktop => isWindows || isMacOS || isLinux;
  static bool get isMobile => isAndroid || isIOS;

  /// CD playback/ripping is only offered on the desktop apps.
  static bool get supportsCd => isWindows || isMacOS;

  static String get fileManagerName =>
      isWindows ? 'File Explorer' : (isMacOS ? 'Finder' : 'file manager');

  /// Opens the OS file manager with [path] selected.
  static Future<void> revealInFileManager(String path) async {
    try {
      if (isWindows) {
        await Process.start('explorer.exe', ['/select,', path]);
      } else if (isMacOS) {
        await Process.start('open', ['-R', path]);
      } else if (isLinux) {
        await Process.start('xdg-open', [File(path).parent.path]);
      }
    } catch (_) {}
  }

  /// Moves files to the Recycle Bin / Trash (plain delete on mobile).
  /// Returns the paths that are gone afterwards.
  static Future<List<String>> trashFiles(List<String> paths) async {
    if (paths.isEmpty) return [];
    try {
      if (isWindows) {
        final cmds = paths
            .map((p) => "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile("
                "'${p.replaceAll("'", "''")}','OnlyErrorDialogs','SendToRecycleBin')")
            .join('; ');
        await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Add-Type -AssemblyName Microsoft.VisualBasic; $cmds',
        ]);
      } else if (isMacOS) {
        for (final p in paths) {
          final esc = p.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
          await Process.run('osascript', [
            '-e',
            'tell application "Finder" to delete POSIX file "$esc"',
          ]);
        }
      } else {
        for (final p in paths) {
          try {
            await File(p).delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return paths.where((p) => !File(p).existsSync()).toList();
  }

  static Future<void> openFolder(String path) async {
    try {
      if (isWindows) {
        await Process.start('explorer.exe', [path]);
      } else if (isMacOS) {
        await Process.start('open', [path]);
      } else if (isLinux) {
        await Process.start('xdg-open', [path]);
      }
    } catch (_) {}
  }
}
