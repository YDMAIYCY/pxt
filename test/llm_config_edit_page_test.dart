import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/llm_model_catalog.dart';
import 'package:pxt1/ui/pages/llm_config_edit_page.dart';

class _FakeLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getForProvider(int userId, String provider) async =>
      null;
}

void main() {
  testWidgets('provider grid renders every preset without a range error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: LlmConfigEditPage(
          config: LlmProviderConfig.emptyForUser(1),
          repository: _FakeLlmConfigRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Regression: the accent-colour list was indexed by provider position, so
    // adding a provider past its length threw RangeError while building the grid.
    expect(tester.takeException(), isNull);

    for (final preset in LlmModelCatalog.providerPresets) {
      expect(
        find.byKey(ValueKey('provider_${preset.provider}')),
        findsOneWidget,
        reason: 'provider tile missing for ${preset.provider}',
      );
    }
  });
}
