import 'package:flutter/foundation.dart';

class FeishuResource {
  FeishuResource(this.data) {
    accessible = data['accessible'] != false;
    error = data['error'] as String?;
  }
  final Map<String, dynamic> data;
  String get key => data['key'] as String;
  String get id => data['id'] as String;
  String get kind => data['kind'] as String;
  String get name => data['name'] as String;
  String get accountId => data['account_id'] as String;
  String? get parentKey => data['parent_key'] as String?;
  String get spaceId => data['space_id'] as String? ?? '';
  bool get hasChildren => data['has_children'] == true;
  bool get selectable => {'folder', 'wiki', 'docx'}.contains(kind);
  String loadState = 'unloaded';
  String? error, pageToken;
  bool accessible = true, expanded = false, hasMore = false;
  final List<String> children = [];
}

class FeishuSelectionRule {
  FeishuSelectionRule(this.resource, {this.includeDescendants = true});
  final FeishuResource resource;
  final bool includeDescendants;
  bool includeFuture = false;
  final Set<String> excluded = {};
  final Set<String> included = {};
  Map<String, dynamic> toJson() => {
    'kind': resource.kind,
    'id': resource.id,
    'space_id': resource.spaceId,
    'excluded': excluded.toList(),
    'included': included.toList(),
    'include_descendants': includeDescendants,
    'include_future': includeFuture,
  };
}

class FeishuSelection extends ChangeNotifier {
  final Map<String, FeishuResource> nodes = {};
  final Map<String, FeishuSelectionRule> rules = {};
  String? accountId;

  void clear() {
    nodes.clear();
    rules.clear();
    accountId = null;
    notifyListeners();
  }

  void add(List<FeishuResource> resources) {
    for (final resource in resources) {
      if (accountId != null && accountId != resource.accountId) {
        throw StateError('不能混合不同飞书账号的资料，请重新选择');
      }
      accountId = resource.accountId;
      final old = nodes[resource.key];
      if (old == null) nodes[resource.key] = resource;
    }
    notifyListeners();
  }

  Iterable<String> ancestors(String key) sync* {
    final seen = <String>{};
    String? current = nodes[key]?.parentKey;
    while (current != null && seen.add(current)) {
      yield current;
      current = nodes[current]?.parentKey;
    }
  }

  bool selected(String key) {
    if (rules.containsKey(key)) return true;
    for (final ancestor in ancestors(key)) {
      final rule = rules[ancestor];
      if (rule == null || !rule.includeDescendants) continue;
      for (final candidate in [
        key,
        ...ancestors(key).takeWhile((a) => a != ancestor),
      ]) {
        if (rule.included.contains(candidate)) return true;
        if (rule.excluded.contains(candidate)) return false;
      }
      return true;
    }
    return false;
  }

  bool? state(String key) {
    if (selected(key)) {
      return rules.values.any(
            (rule) =>
                rule.resource.key == key && rule.excluded.isNotEmpty ||
                rule.excluded.any((e) => ancestors(e).contains(key)),
          )
          ? null
          : true;
    }
    if (nodes.values.any(
      (n) => ancestors(n.key).contains(key) && selected(n.key),
    )) {
      return null;
    }
    return false;
  }

  void toggle(String key, bool value) {
    final node = nodes[key]!;
    if (!node.selectable || !node.accessible) return;
    final parent = ancestors(key).where(rules.containsKey).firstOrNull;
    if (parent != null) {
      final rule = rules[parent]!;
      if (value) {
        rule.excluded.removeWhere(
          (e) => e == key || ancestors(e).contains(key),
        );
        rule.included.removeWhere((e) => ancestors(e).contains(key));
        if (!selected(key)) rule.included.add(key);
      } else {
        rule.included.removeWhere(
          (e) => e == key || ancestors(e).contains(key),
        );
        rule.excluded.add(key);
      }
    } else if (value) {
      rules[key] = FeishuSelectionRule(
        node,
        includeDescendants: node.kind != 'docx',
      );
    } else {
      rules.remove(key);
    }
    for (final descendant in rules.keys.toList()) {
      if (descendant != key && ancestors(descendant).contains(key)) {
        rules.remove(descendant);
      }
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> get roots =>
      rules.values.map((r) => r.toJson()).toList();
}
