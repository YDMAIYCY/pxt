// Offline selection fixtures; these do not establish provider API access.
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/feishu/feishu_selection.dart';

void main() {
  FeishuResource node(
    String id,
    String kind, {
    String? parent,
    String account = 'tenant:user',
  }) => FeishuResource({
    'key': '$kind:$id',
    'id': id,
    'kind': kind,
    'name': id,
    'account_id': account,
    'parent_key': parent,
    'has_children': kind == 'folder',
  });
  test(
    'folder selection covers unloaded descendants and allows exclusions',
    () {
      final state = FeishuSelection();
      state.add([node('root', 'folder')]);
      state.toggle('folder:root', true);
      state.add([
        node('nested', 'folder', parent: 'folder:root'),
        node('doc', 'docx', parent: 'folder:nested'),
      ]);
      expect(state.selected('docx:doc'), isTrue);
      state.toggle('docx:doc', false);
      expect(state.state('folder:root'), isNull);
      expect(state.state('folder:nested'), isNull);
      expect(state.selected('docx:doc'), isFalse);
      expect(state.roots.single['excluded'], ['docx:doc']);
      expect(state.roots.single['include_future'], isFalse);
      state.dispose();
    },
  );
  test('reinclude one child inside an excluded folder keeps a single root', () {
    final state = FeishuSelection()
      ..add([
        node('root', 'folder'),
        node('nested', 'folder', parent: 'folder:root'),
        node('doc', 'docx', parent: 'folder:nested'),
        node('other', 'docx', parent: 'folder:nested'),
      ]);
    state.toggle('folder:root', true);
    state.toggle('folder:nested', false);
    state.toggle('docx:doc', true);
    expect(state.rules, hasLength(1));
    expect(state.selected('docx:doc'), isTrue);
    expect(state.selected('docx:other'), isFalse);
    expect(state.roots.single['included'], ['docx:doc']);
    state.dispose();
  });
  test('selection cannot mix accounts and clears on disconnect', () {
    final state = FeishuSelection()..add([node('root', 'folder')]);
    expect(
      () => state.add([node('other', 'docx', account: 'tenant:other')]),
      throwsStateError,
    );
    state.clear();
    state.add([node('other', 'docx', account: 'tenant:other')]);
    expect(state.accountId, 'tenant:other');
    state.dispose();
  });
}
