// ========== 图谱受控词表 ==========
// 关系类型与实体类型只允许受控取值，避免模型自由发挥导致画布语义混乱。
// 同时提供「模型自由文本 → 受控值」的归一化，以及名称规范化与去重键计算。

class GraphEntityTypes {
  const GraphEntityTypes._();

  static const String concept = '概念';
  static const String definition = '定义';
  static const String theorem = '定理';
  static const String formula = '公式';
  static const String method = '方法';
  static const String algorithm = '算法';
  static const String model = '模型';
  static const String property = '性质';
  static const String application = '应用';
  static const String term = '术语';
  static const String proposition = '命题';
  static const String structure = '结构';
  static const String other = '其他';

  static const List<String> all = <String>[
    concept,
    definition,
    theorem,
    formula,
    method,
    algorithm,
    model,
    property,
    application,
    term,
    proposition,
    structure,
    other,
  ];

  static const Map<String, String> _synonyms = <String, String>{
    '概念': concept,
    '知识点': concept,
    '名词': term,
    '术语': term,
    '定义': definition,
    '定理': theorem,
    '公式': formula,
    '方程': formula,
    '方法': method,
    '算法': algorithm,
    '模型': model,
    '性质': property,
    '应用': application,
    '命题': proposition,
    '结构': structure,
    'concept': concept,
    'definition': definition,
    'theorem': theorem,
    'formula': formula,
    'method': method,
    'algorithm': algorithm,
    'model': model,
    'property': property,
    'application': application,
    'term': term,
    'proposition': proposition,
    'structure': structure,
  };

  /// 归一化实体类型；无法识别时回退到「概念」。
  static String normalize(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return concept;
    for (final type in all) {
      if (text == type) return type;
    }
    final lower = text.toLowerCase();
    for (final entry in _synonyms.entries) {
      if (lower == entry.key.toLowerCase()) return entry.value;
    }
    for (final type in all) {
      if (text.contains(type)) return type;
    }
    return concept;
  }
}

/// 一条关系在画布上的渲染约定。
class GraphRelationSpec {
  const GraphRelationSpec({
    required this.type,
    required this.directed,
    required this.dashed,
  });

  final String type;
  final bool directed;
  final bool dashed;
}

class GraphRelationTypes {
  const GraphRelationTypes._();

  static const String prerequisite = '前置知识';
  static const String belongsTo = '属于';
  static const String contains = '包含';
  static const String appliedTo = '应用于';
  static const String related = '相关';
  static const String extends_ = '扩展';
  static const String dependsOn = '依赖于';

  static const List<GraphRelationSpec> specs = <GraphRelationSpec>[
    GraphRelationSpec(type: prerequisite, directed: true, dashed: false),
    GraphRelationSpec(type: dependsOn, directed: true, dashed: false),
    GraphRelationSpec(type: belongsTo, directed: true, dashed: false),
    GraphRelationSpec(type: contains, directed: true, dashed: false),
    GraphRelationSpec(type: appliedTo, directed: true, dashed: false),
    GraphRelationSpec(type: extends_, directed: true, dashed: true),
    GraphRelationSpec(type: related, directed: false, dashed: true),
  ];

  static const Map<String, String> _synonyms = <String, String>{
    '前置知识': prerequisite,
    '前置': prerequisite,
    '先修': prerequisite,
    'prerequisite': prerequisite,
    'requires': prerequisite,
    '属于': belongsTo,
    '归属': belongsTo,
    'belongs_to': belongsTo,
    'belongsto': belongsTo,
    'is_a': belongsTo,
    '包含': contains,
    '包括': contains,
    'contains': contains,
    'includes': contains,
    '应用于': appliedTo,
    '用于': appliedTo,
    '应用': appliedTo,
    'applied_to': appliedTo,
    'used_for': appliedTo,
    'uses': appliedTo,
    '相关': related,
    '关联': related,
    'related': related,
    'related_to': related,
    'see_also': related,
    '扩展': extends_,
    '延伸': extends_,
    'extends': extends_,
    '依赖于': dependsOn,
    '依赖': dependsOn,
    '取决于': dependsOn,
    'depends_on': dependsOn,
    'depends': dependsOn,
  };

  /// 归一化关系类型；无法识别时回退到「相关」。
  static String normalize(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return related;
    for (final spec in specs) {
      if (text == spec.type) return spec.type;
    }
    final lower = text.toLowerCase().replaceAll(' ', '_');
    final direct = _synonyms[lower];
    if (direct != null) return direct;
    for (final entry in _synonyms.entries) {
      if (text.contains(entry.key) || lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return related;
  }

  static GraphRelationSpec specFor(String type) {
    final normalized = normalize(type);
    return specs.firstWhere(
      (spec) => spec.type == normalized,
      orElse: () => specs.last,
    );
  }
}

class GraphNameNormalizer {
  const GraphNameNormalizer._();

  /// 参与去重时需要忽略的标点（不含数学/逻辑符号，避免误伤语义）。
  static const String _punctuation =
      '·・-_—–~～/\\|,，.。;；:：!！?？"“”\'‘’`´'
      '《》〈〉【】[]（）(){}<>＋＝';

  static final Set<int> _punctuationRunes = _punctuation.runes.toSet();

  static bool _isIgnorable(int rune) {
    if (rune <= 0x20) return true; // ASCII 控制符与空格
    if (rune == 0x3000) return true; // 全角空格
    return _punctuationRunes.contains(rune);
  }

  /// 规范化知识实体名称：统一大小写、去空白与常见标点，用于去重匹配。
  /// 保留语义字符（中英文、数字、数学符号），不做激进改写。
  static String normalize(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.trim().toLowerCase().runes) {
      if (_isIgnorable(rune)) continue;
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  /// 去重键：规范化名称 + 实体类型。
  /// 数学「函数」与编程「函数」若实体类型不同，则不会自动合并。
  static String canonicalKey(String name, String entityType) {
    final normalizedName = normalize(name);
    if (normalizedName.isEmpty) return '';
    return '$normalizedName|${GraphEntityTypes.normalize(entityType)}';
  }
}
