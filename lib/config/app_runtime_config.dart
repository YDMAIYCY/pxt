class AppRuntimeConfig {
  const AppRuntimeConfig._();

  // OCR 本地服务配置：默认指向本机服务，可通过 --dart-define 覆盖。
  static const String ocrServiceBaseUrl = String.fromEnvironment(
    'OCR_SERVICE_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const String ocrServicePath = String.fromEnvironment(
    'OCR_SERVICE_PATH',
    defaultValue: '/ocr',
  );

  // MiniMax 配置：必须通过 --dart-define 注入 API Key。
  static const String minimaxApiKey = String.fromEnvironment('MINIMAX_API_KEY');
  static const String minimaxGroupId = String.fromEnvironment(
    'MINIMAX_GROUP_ID',
  );
  static const String minimaxBaseUrl = String.fromEnvironment(
    'MINIMAX_BASE_URL',
    defaultValue: 'https://api.minimax.io',
  );
  static const String minimaxChatPath = String.fromEnvironment(
    'MINIMAX_CHAT_PATH',
    defaultValue: '/v1/text/chatcompletion_v2',
  );
  static const String minimaxModel = String.fromEnvironment(
    'MINIMAX_MODEL',
    defaultValue: 'MiniMax-Text-01',
  );
  static const String minimaxApiMode = String.fromEnvironment(
    'MINIMAX_API_MODE',
    defaultValue: 'auto',
  );
  static const String minimaxTokenPlanBaseUrl = String.fromEnvironment(
    'MINIMAX_TOKEN_PLAN_BASE_URL',
    defaultValue: 'https://api.minimax.io/anthropic',
  );
  static const String minimaxTokenPlanPath = String.fromEnvironment(
    'MINIMAX_TOKEN_PLAN_PATH',
    defaultValue: '/v1/messages',
  );
  static const String minimaxTokenPlanModel = String.fromEnvironment(
    'MINIMAX_TOKEN_PLAN_MODEL',
    defaultValue: 'MiniMax-M2.7',
  );

  static const int requestTimeoutSeconds = int.fromEnvironment(
    'AI_REQUEST_TIMEOUT_SECONDS',
    defaultValue: 90,
  );
  static const int minimaxMaxCompletionTokens = int.fromEnvironment(
    'MINIMAX_MAX_COMPLETION_TOKENS',
    defaultValue: 4096,
  );

  static bool get hasMiniMaxApiKey => minimaxApiKey.trim().isNotEmpty;

  static Uri get ocrEndpoint => _buildUri(ocrServiceBaseUrl, ocrServicePath);

  static Uri get miniMaxChatEndpoint =>
      _buildUri(minimaxBaseUrl, minimaxChatPath);

  static Uri get miniMaxTokenPlanEndpoint =>
      _buildUri(minimaxTokenPlanBaseUrl, minimaxTokenPlanPath);

  static Uri _buildUri(String baseUrl, String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;

    return Uri.parse(normalizedBase).resolve(normalizedPath);
  }
}
