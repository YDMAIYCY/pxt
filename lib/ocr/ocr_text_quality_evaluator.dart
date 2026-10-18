enum OcrQualityLevel {
  high('high'),
  medium('medium'),
  low('low');

  const OcrQualityLevel(this.value);

  final String value;
}

enum OcrQualityReason {
  uiNoise('ui_noise'),
  ineffectiveCleaning('ineffective_cleaning'),
  tooShort('too_short'),
  tooManySymbols('too_many_symbols'),
  lowChineseRatio('low_chinese_ratio'),
  suspiciousStructure('suspicious_structure');

  const OcrQualityReason(this.value);

  final String value;
}

class OcrQualityResult {
  const OcrQualityResult({
    required this.score,
    required this.level,
    required this.reasons,
  });

  final int score;
  final OcrQualityLevel level;
  final List<OcrQualityReason> reasons;

  bool get isUsableForAutomation => level != OcrQualityLevel.low;

  List<String> get reasonValues =>
      reasons.map((reason) => reason.value).toList(growable: false);
}

class OcrTextQualityEvaluator {
  const OcrTextQualityEvaluator._();

  static final RegExp _timeLikePattern = RegExp(r'\b\d{1,2}:\d{2}\b');
  static final RegExp _chinesePattern = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _letterOrDigitPattern = RegExp(r'[A-Za-z0-9]');
  static final RegExp _symbolPattern = RegExp(
    r'''[^\sA-Za-z0-9\u4e00-\u9fff，。！？；：、（）《》【】“”‘’.,!?;:()\[\]<>+\-*/=]''',
  );

  static const List<String> _uiNoiseTokens = <String>[
    'YCY/pxt',
    'PageAgent',
    '视频生成',
    '更多',
    '素材',
    '绘图',
    '海报',
    '浏览器',
    '地址栏',
    'toolbar',
    'menu',
  ];

  static OcrQualityResult evaluate({
    required String rawText,
    required String cleanText,
  }) {
    final raw = _normalize(rawText);
    final clean = _normalize(cleanText);
    final text = clean.isNotEmpty ? clean : raw;
    final reasons = <OcrQualityReason>{};
    var score = 100;

    if (text.length < 20) {
      reasons.add(OcrQualityReason.tooShort);
      score -= 35;
    }

    final uiNoiseScore = _countUiNoiseSignals(text);
    if (uiNoiseScore >= 2) {
      reasons.add(OcrQualityReason.uiNoise);
      score -= 30;
    }

    final symbolRatio = _symbolRatio(text);
    if (symbolRatio > 0.18) {
      reasons.add(OcrQualityReason.tooManySymbols);
      score -= 20;
    }

    final chineseRatio = _chineseRatio(text);
    if (text.length >= 40 && chineseRatio < 0.18) {
      reasons.add(OcrQualityReason.lowChineseRatio);
      score -= 15;
    }

    if (_looksStructurallySuspicious(text)) {
      reasons.add(OcrQualityReason.suspiciousStructure);
      score -= 10;
    }

    if (raw.isNotEmpty &&
        clean.isNotEmpty &&
        raw == clean &&
        (reasons.contains(OcrQualityReason.uiNoise) ||
            reasons.contains(OcrQualityReason.tooManySymbols) ||
            reasons.contains(OcrQualityReason.suspiciousStructure))) {
      reasons.add(OcrQualityReason.ineffectiveCleaning);
      score -= 15;
    }

    if (reasons.contains(OcrQualityReason.uiNoise) &&
        reasons.contains(OcrQualityReason.ineffectiveCleaning)) {
      score = score > 45 ? 45 : score;
    }

    final clampedScore = score.clamp(0, 100).toInt();
    final level = _levelForScore(clampedScore, reasons);

    return OcrQualityResult(
      score: clampedScore,
      level: level,
      reasons: reasons.toList(growable: false),
    );
  }

  static OcrQualityLevel _levelForScore(
    int score,
    Set<OcrQualityReason> reasons,
  ) {
    if (score < 50 ||
        (reasons.contains(OcrQualityReason.uiNoise) &&
            reasons.contains(OcrQualityReason.ineffectiveCleaning))) {
      return OcrQualityLevel.low;
    }
    if (score < 75) {
      return OcrQualityLevel.medium;
    }
    return OcrQualityLevel.high;
  }

  static int _countUiNoiseSignals(String text) {
    var count = 0;
    final lower = text.toLowerCase();
    for (final token in _uiNoiseTokens) {
      if (lower.contains(token.toLowerCase())) {
        count++;
      }
    }
    if (_timeLikePattern.hasMatch(text)) {
      count++;
    }
    return count;
  }

  static bool _looksStructurallySuspicious(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length <= 2 && text.length > 80) {
      return true;
    }

    final veryShortLines = lines.where((line) => line.length <= 3).length;
    return lines.length >= 5 && veryShortLines >= lines.length / 2;
  }

  static double _symbolRatio(String text) {
    if (text.isEmpty) {
      return 0;
    }
    final symbolCount = _symbolPattern.allMatches(text).length;
    return symbolCount / text.length;
  }

  static double _chineseRatio(String text) {
    if (text.isEmpty) {
      return 0;
    }
    final chineseCount = _chinesePattern.allMatches(text).length;
    final letterOrDigitCount = _letterOrDigitPattern.allMatches(text).length;
    final contentCount = chineseCount + letterOrDigitCount;
    if (contentCount == 0) {
      return 0;
    }
    return chineseCount / contentCount;
  }

  static String _normalize(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }
}
