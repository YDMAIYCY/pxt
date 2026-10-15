import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class PcmFrame {
  PcmFrame(this.bytes, this.samples, this.activity);
  final Uint8List bytes;
  final Float32List samples;
  final double activity;
}

class Pcm16Decoder {
  int? _tail;
  bool get hasTail => _tail != null;

  PcmFrame decode(Uint8List chunk) {
    final bytes = Uint8List(chunk.length + (_tail == null ? 0 : 1));
    var offset = 0;
    if (_tail != null) bytes[offset++] = _tail!;
    bytes.setRange(offset, bytes.length, chunk);
    _tail = bytes.length.isOdd ? bytes.last : null;
    final aligned = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2 * 2);
    final data = ByteData.sublistView(aligned);
    final samples = Float32List(aligned.length ~/ 2);
    var energy = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final value = data.getInt16(i * 2, Endian.little) / 32768.0;
      samples[i] = value;
      energy += value * value;
    }
    final activity = samples.isEmpty
        ? 0.0
        : (math.sqrt(energy / samples.length) * 4).clamp(0.0, 1.0);
    return PcmFrame(aligned, samples, activity);
  }
}

/// Incremental PCM16 mono 16kHz WAV. A partial never looks like a saved answer.
class PcmWavWriter {
  PcmWavWriter._(this.path, this._file);
  final String path;
  final RandomAccessFile _file;
  int bytes = 0;
  int get durationMs => bytes * 1000 ~/ 32000;
  bool _closed = false;

  static Future<PcmWavWriter> create(String path) async {
    await File(path).parent.create(recursive: true);
    final file = await File('$path.partial').open(mode: FileMode.write);
    await file.writeFrom(Uint8List(44));
    return PcmWavWriter._(path, file);
  }

  Future<void> append(Uint8List data) async {
    await _file.writeFrom(data);
    bytes += data.length;
  }

  Future<void> finish() async {
    final header = ByteData(44);
    void tag(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    header.setUint32(4, bytes + 36, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    header.setUint32(40, bytes, Endian.little);
    await _file.setPosition(0);
    await _file.writeFrom(header.buffer.asUint8List());
    await _file.flush();
    await _file.close();
    _closed = true;
    await File('$path.partial').rename(path);
  }

  Future<void> discard() async {
    if (!_closed) {
      await _file.close();
      _closed = true;
    }
    final partial = File('$path.partial');
    if (await partial.exists()) await partial.delete();
  }
}
