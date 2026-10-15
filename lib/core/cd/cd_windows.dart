// Windows audio CD access through kernel32 DeviceIoControl (dart:ffi).
//
//   IOCTL_CDROM_READ_TOC   read the table of contents
//   IOCTL_CDROM_RAW_READ   read raw 2352-byte CD-DA sectors (16-bit LE stereo)
//   IOCTL_STORAGE_EJECT_MEDIA
//
// No admin rights or extra drivers are needed. Everything here is
// synchronous; call it from a background isolate.

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'cd_models.dart';

const int _genericRead = 0x80000000;
const int _fileShareRead = 0x1;
const int _fileShareWrite = 0x2;
const int _openExisting = 3;
const int _driveCdrom = 5;
const int _ioctlCdromReadToc = 0x00024000;
const int _ioctlCdromRawRead = 0x0002403E;
const int _ioctlStorageEjectMedia = 0x002D4808;
const int _cdda = 2; // TRACK_MODE_TYPE.CDDA

const int sectorBytes = 2352;
const int _maxSectorsPerRead = 20;

typedef _CreateFileC = IntPtr Function(
    Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr);
typedef _CreateFileD = int Function(
    Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);
typedef _IoctlC = Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32,
    Pointer<Void>, Uint32, Pointer<Uint32>, Pointer<Void>);
typedef _IoctlD = int Function(
    int, int, Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>, Pointer<Void>);

class _K32 {
  static final DynamicLibrary lib = DynamicLibrary.open('kernel32.dll');
  static final createFile =
      lib.lookupFunction<_CreateFileC, _CreateFileD>('CreateFileW');
  static final ioctl = lib.lookupFunction<_IoctlC, _IoctlD>('DeviceIoControl');
  static final closeHandle =
      lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  static final getLogicalDriveStrings = lib.lookupFunction<
      Uint32 Function(Uint32, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>)>('GetLogicalDriveStringsW');
  static final getDriveType = lib.lookupFunction<Uint32 Function(Pointer<Utf16>),
      int Function(Pointer<Utf16>)>('GetDriveTypeW');
}

/// Drive letters ("D", "E", ...) of all optical drives.
List<String> winListCdDrives() {
  final buf = calloc<Uint16>(1024);
  try {
    final n = _K32.getLogicalDriveStrings(1023, buf.cast<Utf16>());
    if (n <= 0) return [];
    final all = String.fromCharCodes(buf.asTypedList(n));
    final out = <String>[];
    for (final root in all.split('\u0000')) {
      if (root.isEmpty) continue;
      final p = root.toNativeUtf16();
      try {
        if (_K32.getDriveType(p) == _driveCdrom) out.add(root.substring(0, 1));
      } finally {
        malloc.free(p);
      }
    }
    return out;
  } finally {
    calloc.free(buf);
  }
}

int _open(String letter) {
  final path = '\\\\.\\$letter:'.toNativeUtf16();
  try {
    return _K32.createFile(path, _genericRead, _fileShareRead | _fileShareWrite,
        nullptr, _openExisting, 0, 0);
  } finally {
    malloc.free(path);
  }
}

bool _valid(int h) => h != -1 && h != 0;

/// Reads the TOC of the disc in [letter]; null if no (audio) disc.
CdDisc? winReadToc(String letter) {
  final h = _open(letter);
  if (!_valid(h)) return null;
  final buf = calloc<Uint8>(804);
  final ret = calloc<Uint32>();
  try {
    final ok = _K32.ioctl(h, _ioctlCdromReadToc, nullptr, 0, buf.cast<Void>(),
        804, ret, nullptr);
    if (ok == 0) return null;
    final b = Uint8List.fromList(buf.asTypedList(804));
    final first = b[2];
    final last = b[3];
    if (first == 0 || last < first || last > 99) return null;
    final entries = <(int number, int lba, bool audio)>[];
    for (var i = 0; i <= last - first + 1; i++) {
      final e = 4 + i * 8;
      final control = b[e + 1] & 0x0F;
      final number = b[e + 2];
      final lba = (b[e + 5] * 60 + b[e + 6]) * 75 + b[e + 7] - 150;
      entries.add((number, lba, (control & 0x04) == 0));
    }
    final leadout = entries.last.$2; // track 0xAA
    final tracks = <CdTocTrack>[];
    for (var i = 0; i < entries.length - 1; i++) {
      final (number, lba, audio) = entries[i];
      var end = entries[i + 1].$2;
      // An audio track followed by a data session ends 11400 sectors early.
      if (audio && i + 1 < entries.length - 1 && !entries[i + 1].$3) {
        end -= 11400;
      }
      tracks.add(CdTocTrack(
        number: number,
        startLba: lba,
        lengthSectors: (end - lba).clamp(0, 1 << 30),
        isAudio: audio,
      ));
    }
    if (!tracks.any((t) => t.isAudio)) return null;
    return CdDisc(
      drive: letter,
      label: 'Audio CD',
      firstTrack: first,
      lastTrack: last,
      leadoutLba: leadout,
      tracks: tracks,
    );
  } finally {
    calloc.free(buf);
    calloc.free(ret);
    _K32.closeHandle(h);
  }
}

/// All audio CDs currently inserted.
List<CdDisc> winScanDiscs() {
  final out = <CdDisc>[];
  for (final d in winListCdDrives()) {
    try {
      final disc = winReadToc(d);
      if (disc != null) out.add(disc);
    } catch (_) {}
  }
  return out;
}

bool winEject(String letter) {
  final h = _open(letter);
  if (!_valid(h)) return false;
  final ret = calloc<Uint32>();
  try {
    return _K32.ioctl(h, _ioctlStorageEjectMedia, nullptr, 0, nullptr, 0, ret,
            nullptr) !=
        0;
  } finally {
    calloc.free(ret);
    _K32.closeHandle(h);
  }
}

/// Reads raw CD-DA sectors.
class WinCdReader {
  WinCdReader._(this._h);

  final int _h;
  final Pointer<Uint8> _info = calloc<Uint8>(16);
  final Pointer<Uint8> _out = calloc<Uint8>(_maxSectorsPerRead * sectorBytes);
  final Pointer<Uint32> _ret = calloc<Uint32>();
  int errorSectors = 0;

  static WinCdReader? open(String letter) {
    final h = _open(letter);
    return _valid(h) ? WinCdReader._(h) : null;
  }

  bool _readRaw(int lba, int count) {
    _info.cast<Int64>().value = lba * 2048;
    Pointer<Uint32>.fromAddress(_info.address + 8).value = count;
    Pointer<Uint32>.fromAddress(_info.address + 12).value = _cdda;
    final ok = _K32.ioctl(_h, _ioctlCdromRawRead, _info.cast<Void>(), 16,
        _out.cast<Void>(), count * sectorBytes, _ret, nullptr);
    return ok != 0;
  }

  /// Reads [count] sectors starting at [lba]. Unreadable sectors are
  /// returned as silence (counted in [errorSectors]).
  Uint8List read(int lba, int count) {
    final result = Uint8List(count * sectorBytes);
    var done = 0;
    while (done < count) {
      final n = (count - done) > _maxSectorsPerRead
          ? _maxSectorsPerRead
          : count - done;
      var ok = false;
      for (var attempt = 0; attempt < 3 && !ok; attempt++) {
        ok = _readRaw(lba + done, n);
      }
      if (ok) {
        result.setRange(done * sectorBytes, (done + n) * sectorBytes,
            _out.asTypedList(n * sectorBytes));
      } else {
        // Fall back to single sectors so one scratch doesn't zero 20.
        for (var s = 0; s < n; s++) {
          var sok = false;
          for (var attempt = 0; attempt < 5 && !sok; attempt++) {
            sok = _readRaw(lba + done + s, 1);
          }
          if (sok) {
            result.setRange((done + s) * sectorBytes,
                (done + s + 1) * sectorBytes, _out.asTypedList(sectorBytes));
          } else {
            errorSectors++;
          }
        }
      }
      done += n;
    }
    return result;
  }

  void close() {
    calloc.free(_info);
    calloc.free(_out);
    calloc.free(_ret);
    _K32.closeHandle(_h);
  }
}

/// 44-byte WAV header for 44.1 kHz 16-bit stereo PCM.
Uint8List wavHeader(int dataBytes) {
  final b = ByteData(44);
  void tag(int o, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 2, Endian.little); // channels
  b.setUint32(24, 44100, Endian.little);
  b.setUint32(28, 44100 * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}
