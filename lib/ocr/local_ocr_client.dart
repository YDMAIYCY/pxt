import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

import '../config/app_runtime_config.dart';
import 'models/ocr_result.dart';
import 'ocr_text_cleaner.dart';

class LocalOcrException implements Exception {
  const LocalOcrException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmptyOcrResultException extends LocalOcrException {
  const EmptyOcrResultException(super.message);
}

// ========== OCR 客户端 ==========
// Android/iOS 优先使用端侧 OCR；其余平台走 HTTP OCR 服务。

class LocalOcrClient {
  LocalOcrClient({http.Client? httpClient, Uri? endpoint, Duration? timeout})
    : _httpClient = httpClient ?? http.Client(),
      _endpoint = endpoint ?? AppRuntimeConfig.ocrEndpoint,
      _timeout =
          timeout ?? Duration(seconds: AppRuntimeConfig.requestTimeoutSeconds);

  final http.Client _httpClient;
  final Uri _endpoint;
  final Duration _timeout;

  Future<OcrResult> recognizeImage({
    required String imagePath,
    String language = 'zh-CN',
  }) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw const LocalOcrException('原始图片不存在，无法执行 OCR');
    }

    if (_shouldUseOnDeviceOcr()) {
      return _recognizeOnDevice(imagePath: imagePath, language: language);
    }

    return _recognizeByHttp(imagePath: imagePath, language: language);
  }

  bool _shouldUseOnDeviceOcr() {
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<OcrResult> _recognizeOnDevice({
    required String imagePath,
    required String language,
  }) async {
    final script = _mapLanguageToScript(language);
    final recognizer = TextRecognizer(script: script);

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(inputImage);
      final rawText = recognizedText.text.trim();
      final cleanText = OcrTextCleaner.clean(rawText);

      if (rawText.isEmpty && cleanText.isEmpty) {
        throw const EmptyOcrResultException('OCR 未识别到可用文本，请重试');
      }

      return OcrResult(
        rawText: rawText,
        cleanText: cleanText,
        language: language,
      );
    } catch (error) {
      if (error is LocalOcrException) {
        rethrow;
      }

      final message = error.toString().trim();
      throw LocalOcrException(
        message.isEmpty ? '手机端本地 OCR 失败，请重试' : '手机端本地 OCR 失败：$message',
      );
    } finally {
      await recognizer.close();
    }
  }

  TextRecognitionScript _mapLanguageToScript(String language) {
    final normalized = language.trim().toLowerCase();

    if (normalized.startsWith('zh')) {
      return TextRecognitionScript.chinese;
    }
    if (normalized.startsWith('ja')) {
      return TextRecognitionScript.japanese;
    }
    if (normalized.startsWith('ko')) {
      return TextRecognitionScript.korean;
    }

    return TextRecognitionScript.latin;
  }

  Future<OcrResult> _recognizeByHttp({
    required String imagePath,
    required String language,
  }) async {
    final request = http.MultipartRequest('POST', _endpoint)
      ..fields['language'] = language
      ..files.add(await http.MultipartFile.fromPath('image', imagePath));

    try {
      final streamedResponse = await _httpClient
          .send(request)
          .timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LocalOcrException('OCR 服务调用失败（HTTP ${response.statusCode}）');
      }

      return _parseResponseBody(response.body, fallbackLanguage: language);
    } on SocketException {
      throw LocalOcrException(_buildConnectionErrorMessage());
    } on TimeoutException {
      throw const LocalOcrException('OCR 服务响应超时，请稍后重试');
    } on FormatException {
      throw const LocalOcrException('OCR 服务返回了无法解析的数据');
    }
  }

  String _buildConnectionErrorMessage() {
    final host = _endpoint.host.toLowerCase();
    final endpointText = _endpoint.toString();

    if (host == '127.0.0.1' || host == 'localhost') {
      final port = _endpoint.hasPort
          ? _endpoint.port
          : (_endpoint.scheme == 'https' ? 443 : 80);

      return '无法连接本地 OCR 服务（$endpointText）。如果是真机调试，127.0.0.1 指向手机自身。Android 请先执行 adb reverse tcp:$port tcp:$port，或把 OCR_SERVICE_BASE_URL 改为电脑局域网 IP。';
    }

    return '无法连接本地 OCR 服务（$endpointText），请确认 OCR 服务已启动且手机可访问该地址。';
  }

  OcrResult _parseResponseBody(
    String body, {
    required String fallbackLanguage,
  }) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      throw const EmptyOcrResultException('OCR 返回为空，请重试或更换图片');
    }

    try {
      final decoded = jsonDecode(trimmedBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON root is not an object');
      }

      final rawText = _readString(decoded, const [
        'raw_text',
        'text',
        'result',
        'content',
      ]);
      final cleanFromResponse = _readString(decoded, const [
        'clean_text',
        'clean',
      ]);
      final language = _readString(decoded, const ['language']);
      final cleanText = cleanFromResponse.isNotEmpty
          ? cleanFromResponse
          : OcrTextCleaner.clean(rawText);

      if (rawText.trim().isEmpty && cleanText.trim().isEmpty) {
        throw const EmptyOcrResultException('OCR 未识别到可用文本，请重试');
      }

      return OcrResult(
        rawText: rawText,
        cleanText: cleanText,
        language: language.isEmpty ? fallbackLanguage : language,
      );
    } on FormatException {
      final cleanText = OcrTextCleaner.clean(trimmedBody);
      if (cleanText.isEmpty) {
        throw const EmptyOcrResultException('OCR 返回为空，请重试或更换图片');
      }

      return OcrResult(
        rawText: trimmedBody,
        cleanText: cleanText,
        language: fallbackLanguage,
      );
    }
  }

  String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final text = _valueToString(value);
      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  String _valueToString(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value.trim();
    }
    if (value is List) {
      for (final item in value) {
        final text = _valueToString(item);
        if (text.isNotEmpty) {
          return text;
        }
      }
      return '';
    }
    if (value is Map) {
      for (final mapValue in value.values) {
        final text = _valueToString(mapValue);
        if (text.isNotEmpty) {
          return text;
        }
      }
      return '';
    }

    return value.toString().trim();
  }
}
