import 'dart:convert';

String docxMarkdown(String encoded) {
  final blocks = (jsonDecode(encoded) as List).cast<Map<String, dynamic>>();
  final byId = {for (final block in blocks) block['block_id'] as String: block};
  final visited = <String>{};
  String element(Map value) {
    if (value['text_run'] is Map) {
      final run = value['text_run'] as Map;
      var content = '${run['content'] ?? ''}';
      final style = run['text_element_style'] as Map? ?? {};
      final url = (style['link'] as Map?)?['url'];
      if (url != null) content = '[$content]($url)';
      if (style['bold'] == true) content = '**$content**';
      if (style['italic'] == true) content = '*$content*';
      if (style['inline_code'] == true) content = '`$content`';
      return content;
    }
    if (value['equation'] is Map) {
      return ' `${value['equation']['content'] ?? ''}` ';
    }
    if (value['mention_user'] is Map) {
      return '@${value['mention_user']['name'] ?? '用户引用'}';
    }
    if (value['mention_doc'] is Map) {
      return '[文档引用：${value['mention_doc']['title'] ?? value['mention_doc']['token'] ?? ''}]';
    }
    return '[暂不支持的文本元素]';
  }

  String text(Map? part) =>
      ((part?['elements'] as List?) ?? []).map((e) => element(e as Map)).join();
  String render(String id, int depth) {
    if (!visited.add(id)) return '';
    final block = byId[id];
    if (block == null) return '\n> [缺少内容块]\n';
    final type = block['block_type'];
    final children = (block['children'] as List?)?.cast<String>() ?? [];
    String childrenText() =>
        children.map((child) => render(child, depth + 1)).join();
    if (type == 1 ||
        type == 34 ||
        type == 35 ||
        type == 26 ||
        type == 27 ||
        type == 32) {
      return childrenText();
    }
    if (type == 31 && block['table'] is Map) {
      final table = block['table'] as Map;
      final properties = table['property'] as Map? ?? {};
      final columns = properties['column_size'] as int? ?? 0;
      final cells = (table['cells'] as List?)?.cast<String>() ?? children;
      if (columns > 0 && cells.length % columns == 0 && cells.isNotEmpty) {
        final values = cells
            .map(
              (cell) => render(
                cell,
                depth + 1,
              ).trim().replaceAll('|', r'\|').replaceAll('\n', '<br>'),
            )
            .toList();
        final lines = <String>[];
        for (var i = 0; i < values.length; i += columns) {
          lines.add('| ${values.sublist(i, i + columns).join(' | ')} |');
          if (i == 0) {
            lines.add('| ${List.filled(columns, '---').join(' | ')} |');
          }
        }
        return '\n${lines.join('\n')}\n\n';
      }
      return '\n> [表格结构暂不能完整展示，可查看飞书原文]\n${childrenText()}';
    }
    if (type == 2) return '${text(block['text'] as Map?)}\n\n${childrenText()}';
    if (type is int && type >= 3 && type <= 11) {
      return '${List.filled((type - 2).clamp(1, 6), '#').join()} ${text(block['heading${type - 2}'] as Map?)}\n\n${childrenText()}';
    }
    if (type == 12 || type == 13 || type == 17) {
      final part =
          block[type == 12
                  ? 'bullet'
                  : type == 13
                  ? 'ordered'
                  : 'todo']
              as Map?;
      final prefix = type == 12
          ? '-'
          : type == 13
          ? '1.'
          : (part?['style'] as Map?)?['done'] == true
          ? '- [x]'
          : '- [ ]';
      return '${'  ' * depth}$prefix ${text(part)}\n${childrenText()}';
    }
    if (type == 14) {
      final content = text(block['code'] as Map?);
      final fence = content.contains('```') ? '````' : '```';
      return '\n$fence\n$content\n$fence\n\n';
    }
    if (type == 15) {
      return '> ${text(block['quote'] as Map?)}\n\n${childrenText()}';
    }
    if (type == 22) return '\n---\n';
    final label =
        {
          20: '嵌入内容',
          21: '画板',
          23: '附件',
          24: '嵌入内容',
          25: '分栏',
          28: '图片',
          29: '第三方组件',
          30: '电子表格',
          33: '视图',
          43: '白板',
        }[type] ??
        '内容块（类型 $type）';
    return '\n> [$label 暂不支持完整展示，原始结构已保存]\n\n${childrenText()}';
  }

  final roots = blocks
      .where((b) => b['parent_id'] == null || !byId.containsKey(b['parent_id']))
      .map((b) => b['block_id'] as String)
      .toList();
  final output = roots.map((root) => render(root, 0)).join();
  final remaining = blocks
      .where((b) => !visited.contains(b['block_id']))
      .map((b) => render(b['block_id'] as String, 0))
      .join();
  return output + remaining;
}
