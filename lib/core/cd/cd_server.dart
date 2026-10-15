// Windows CD playback: a tiny loopback HTTP server, running in its own
// isolate, that serves each CD track as a seekable WAV stream read straight
// from the drive. libmpv plays http:// URLs with range requests, so seeking
// works just like a file.
//
//   GET http://127.0.0.1:<port>/cd/<letter>/<startLba>/<sectors>.wav

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'cd_windows.dart';

class CdStreamServer {
  static int? _port;
  static Future<int>? _starting;

  /// Starts the server isolate once and returns its port.
  static Future<int> ensureStarted() {
    if (_port != null) return Future.value(_port);
    return _starting ??= () async {
      final rp = ReceivePort();
      await Isolate.spawn(_serverMain, rp.sendPort, debugName: 'cd-stream');
      final port = await rp.first as int;
      _port = port;
      return port;
    }();
  }

  static String trackUrl(int port, String letter, int startLba, int sectors) =>
      'http://127.0.0.1:$port/cd/$letter/$startLba/$sectors.wav';
}

Future<void> _serverMain(SendPort sp) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  sp.send(server.port);
  // Requests are handled concurrently: the player may open a new connection
  // for a seek before the previous one has been torn down.
  server.listen((req) {
    _handle(req).catchError((Object _) async {
      try {
        await req.response.close();
      } catch (_) {}
    });
  });
}

Future<void> _handle(HttpRequest req) async {
  final seg = req.uri.pathSegments;
  final res = req.response;
  if (seg.length != 4 || seg[0] != 'cd') {
    res.statusCode = HttpStatus.notFound;
    await res.close();
    return;
  }
  final letter = seg[1];
  final start = int.tryParse(seg[2]) ?? 0;
  final sectors = int.tryParse(seg[3].replaceAll('.wav', '')) ?? 0;
  final dataBytes = sectors * sectorBytes;
  final total = 44 + dataBytes;

  var from = 0;
  var to = total - 1;
  final range = req.headers.value(HttpHeaders.rangeHeader);
  if (range != null) {
    final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
    if (m != null) {
      if (m.group(1)!.isNotEmpty) from = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty) to = int.parse(m.group(2)!);
      if (m.group(1)!.isEmpty && m.group(2)!.isNotEmpty) {
        from = total - int.parse(m.group(2)!);
        to = total - 1;
      }
    }
    if (from >= total || from > to) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await res.close();
      return;
    }
    if (to >= total) to = total - 1;
    res.statusCode = HttpStatus.partialContent;
    res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $from-$to/$total');
  }
  res.headers.contentType = ContentType('audio', 'wav');
  res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  res.contentLength = to - from + 1;
  res.bufferOutput = false;

  if (req.method == 'HEAD') {
    await res.close();
    return;
  }

  final reader = WinCdReader.open(letter);
  if (reader == null) {
    res.statusCode = HttpStatus.serviceUnavailable;
    await res.close();
    return;
  }
  var gone = false;
  res.done.then((_) {}, onError: (Object _) => gone = true);
  try {
    var pos = from;
    if (pos < 44) {
      final h = wavHeader(dataBytes);
      final end = to < 43 ? to : 43;
      res.add(h.sublist(pos, end + 1));
      pos = end + 1;
    }
    const chunkSectors = 20;
    while (pos <= to && !gone) {
      final dataPos = pos - 44;
      final sector = dataPos ~/ sectorBytes;
      final offsetInSector = dataPos % sectorBytes;
      final remainingSectors = sectors - sector;
      if (remainingSectors <= 0) break;
      final n = remainingSectors < chunkSectors ? remainingSectors : chunkSectors;
      final Uint8List data = reader.read(start + sector, n);
      final available = data.length - offsetInSector;
      final want = to - pos + 1;
      final take = want < available ? want : available;
      res.add(Uint8List.sublistView(data, offsetInSector, offsetInSector + take));
      pos += take;
      await res.flush(); // throws if the player hung up (seek / stop)
    }
    await res.close();
  } finally {
    reader.close();
  }
}
