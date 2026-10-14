import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'voice_backends.dart';

class OfflineModelFile {
  const OfflineModelFile(this.name, this.size, this.sha256, this.url);
  final String name;
  final int size;
  final String sha256;
  final String url;
}

const _modelBase =
    'https://huggingface.co/csukuangfj/'
    'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23/resolve/'
    '204ad334e2e683fd295359930cc16fc0432a23ac';

const chinese14mFiles = [
  OfflineModelFile(
    'encoder-epoch-99-avg-1.int8.onnx',
    21621684,
    '1c556ea57cec304e55ec4b72e52c1cc098bb01476ed7d90f3de939fe126487b1',
    '$_modelBase/encoder-epoch-99-avg-1.int8.onnx',
  ),
  OfflineModelFile(
    'decoder-epoch-99-avg-1.int8.onnx',
    1888682,
    '22f123bb8cba9b38974b3df18a3f45e7081f4985ebb2e075d9f21f618c468bbf',
    '$_modelBase/decoder-epoch-99-avg-1.int8.onnx',
  ),
  OfflineModelFile(
    'joiner-epoch-99-avg-1.int8.onnx',
    1795562,
    'a7cf9d82757bdcf786059454495a9ca95e4bd7347f72473fc08d794475c36169',
    '$_modelBase/joiner-epoch-99-avg-1.int8.onnx',
  ),
  OfflineModelFile(
    'tokens.txt',
    48697,
    '8b294db9045d6e5f94647f4c1eec1af4da143a75053c399611444b378ff966ac',
    '$_modelBase/tokens.txt',
  ),
];

/// Explicit downloads only. The controller must display progress and cancel.
class OfflineModelManager {
  OfflineModelManager({
    required Directory documentsDirectory,
    this.files = chinese14mFiles,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(minutes: 5),
  }) : root = Directory(p.join(documentsDirectory.path, 'interview_asr')),
       _clientFactory = clientFactory ?? http.Client.new {
    for (final file in files) {
      if (p.basename(file.name) != file.name || file.name == '..') {
        throw ArgumentError('模型文件名必须是目录内的普通文件名');
      }
    }
  }

  final Directory root;
  final List<OfflineModelFile> files;
  final http.Client Function() _clientFactory;
  final Duration timeout;
  final progress = ValueNotifier<double>(0);
  final downloading = ValueNotifier<bool>(false);
  Directory get directory => Directory(p.join(root.path, 'zh14m-int8-v1'));
  bool get ready => _ready;
  bool _ready = false;
  bool _disposed = false;
  Future<void>? _disposing;
  int _generation = 0;
  http.Client? _client;
  Future<void>? _pending;
  Completer<void>? _cancelled;

  Future<bool> inspect() async {
    if (_disposed) throw StateError('模型管理器已释放');
    final generation = _generation;
    final valid = await _valid(directory);
    _check(generation);
    _ready = valid;
    return _ready;
  }

  Future<bool> _valid(Directory dir) async {
    if (await FileSystemEntity.type(dir.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    for (final spec in files) {
      final file = File(p.join(dir.path, spec.name));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != spec.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              spec.sha256) {
        return false;
      }
    }
    return files.isNotEmpty;
  }

  Future<void> ensure({void Function(double)? onProgress}) {
    if (_disposed) throw StateError('模型管理器已释放');
    if (_pending != null) return _pending!;
    final generation = ++_generation;
    _cancelled = Completer<void>();
    final result = _download(generation, onProgress);
    _pending = result;
    // The returned future carries errors; the cleanup listener does not.
    unawaited(
      result.then(
        (_) => _pending = null,
        onError: (Object _) {
          _pending = null;
        },
      ),
    );
    return result;
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) throw const VoiceCancelled();
  }

  Future<T> _await<T>(Future<T> future) => Future.any([
    future,
    _cancelled!.future.then<T>((_) => throw const VoiceCancelled()),
  ]).timeout(timeout);

  Future<void> _download(
    int generation,
    void Function(double)? callback,
  ) async {
    await root.create(recursive: true);
    if (await inspect()) {
      _check(generation);
      progress.value = 1;
      callback?.call(1);
      return;
    }
    _check(generation);
    downloading.value = true;
    progress.value = 0;
    Directory? stage;
    http.Client? client;
    final total = files.fold<int>(0, (n, f) => n + f.size);
    var received = 0;
    try {
      callback?.call(0);
      stage = await root.createTemp('.partial-');
      _check(generation);
      client = _clientFactory();
      _client = client;
      for (final spec in files) {
        _check(generation);
        final response = await _await(
          client.send(http.Request('GET', Uri.parse(spec.url))),
        );
        if (response.statusCode != 200) {
          throw HttpException('模型下载 HTTP ${response.statusCode}');
        }
        final partial = File(p.join(stage.path, '${spec.name}.partial'));
        final output = await partial.open(mode: FileMode.write);
        final chunks = StreamIterator<List<int>>(response.stream);
        var fileBytes = 0;
        try {
          while (await _await(chunks.moveNext())) {
            _check(generation);
            fileBytes += chunks.current.length;
            if (fileBytes > spec.size) throw StateError('模型文件超出声明大小');
            await output.writeFrom(chunks.current);
            received += chunks.current.length;
            // Reserve 100% for verified, atomically installed files.
            progress.value = received / total * 0.99;
            callback?.call(progress.value);
          }
          await output.flush();
        } finally {
          if (generation != _generation) client.close();
          try {
            await chunks.cancel().timeout(timeout);
          } finally {
            await output.close();
          }
        }
        _check(generation);
        if (fileBytes != spec.size ||
            (await sha256.bind(partial.openRead()).first).toString() !=
                spec.sha256) {
          throw StateError('模型大小或 SHA-256 校验失败：${spec.name}');
        }
        await partial.rename(p.join(stage.path, spec.name));
      }
      _check(generation);
      // Only incomplete installations may be removed; a valid one is reused.
      if (await directory.exists()) {
        if (await _valid(directory)) {
          _check(generation);
          _ready = true;
          progress.value = 1;
          callback?.call(1);
          return;
        }
        await _deleteOwned(directory);
      }
      _check(generation);
      await stage.rename(directory.path);
      _check(generation);
      _ready = true;
      progress.value = 1;
      callback?.call(1);
    } finally {
      client?.close();
      _client = null;
      try {
        if (stage != null && await stage.exists()) await _deleteOwned(stage);
      } finally {
        downloading.value = false;
      }
    }
  }

  Future<void> _deleteOwned(Directory dir) async {
    final parent = p.normalize(p.absolute(root.path));
    final child = p.normalize(p.absolute(dir.path));
    if (!p.isWithin(parent, child) ||
        await FileSystemEntity.type(child, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw StateError('拒绝删除模型目录外的路径或符号链接');
    }
    await dir.delete(recursive: true);
  }

  Future<void> cancel() async {
    ++_generation;
    if (!(_cancelled?.isCompleted ?? true)) _cancelled!.complete();
    _client?.close();
    try {
      await _pending;
    } on VoiceCancelled {
      // Expected cancellation; incomplete files were removed by finally.
    } on Exception {
      // The original ensure caller receives the download error.
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await cancel();
    } finally {
      progress.dispose();
      downloading.dispose();
    }
  }
}
