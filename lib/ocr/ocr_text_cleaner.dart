class OcrTextCleaner {
  const OcrTextCleaner._();

  static final RegExp _timeOnlyLine = RegExp(r'^\d{1,2}[:：]\d{2}$');
  static final RegExp _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _browserOrPathNoise = RegExp(
    r'(https?://|www\.|/Users/|C:\\|D:\\|\.com|\.cn|localhost|127\.0\.0\.1)',
    caseSensitive: false,
  );

  static String clean(String source) {
    final normalized = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u3000', ' ')
        .replaceAll('\t', ' ');

    final compacted = normalized
        .split('\n')
        .map(_cleanLine)
        .where((line) => line.isNotEmpty && !_isUiNoiseLine(line))
        .join('\n');

    return compacted.replaceAll(RegExp(r'[ ]{2,}'), ' ').trim();
  }

  static String _cleanLine(String line) {
    return line
        .replaceAll(RegExp(r'[|｜]{2,}'), '|')
        .replaceAll(RegExp(r'[·•]{3,}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isUiNoiseLine(String line) {
    final normalized = line.trim();
    if (normalized.isEmpty) return true;
    if (_timeOnlyLine.hasMatch(normalized)) return true;
    if (normalized.length >= 3 && !_letterOrNumber.hasMatch(normalized)) {
      return true;
    }
    if (_browserOrPathNoise.hasMatch(normalized)) return true;

    final lower = normalized.toLowerCase();
    const noiseTokens = [
      'pageagent',
      'ycy/pxt',
      '视频生成',
      '素材',
      '绘图',
      '更多',
      '返回',
      '分享',
      '复制',
      '保存',
      '取消',
      '完成',
      '搜索',
      '电量',
      'wifi',
      'wi-fi',
    ];

    final hitCount = noiseTokens.where((token) => lower.contains(token)).length;
    if (hitCount >= 2) return true;
    if (hitCount == 1 && normalized.length <= 24) return true;
    return false;
  }
}
