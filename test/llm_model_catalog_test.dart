import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/llm_model_catalog.dart';

void main() {
  test('zhipu preset is registered and resolvable', () {
    final preset = LlmModelCatalog.providerPresets.firstWhere(
      (p) => p.provider == LlmProvider.zhipu,
    );
    expect(preset.label, '智谱 GLM');
    expect(preset.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
    expect(preset.models, isNotEmpty);
    // Free trial packs are scoped to specific models; the default selection must
    // be one a trial account can actually call, or the first test returns 429.
    expect(preset.models.first.id, 'glm-5.3-flash');

    // Resolvable by provider key, by alias, and by host.
    expect(
      LlmModelCatalog.presetFor(provider: 'zhipu', baseUrl: '')?.provider,
      LlmProvider.zhipu,
    );
    expect(
      LlmModelCatalog.presetFor(provider: 'glm', baseUrl: '')?.provider,
      LlmProvider.zhipu,
    );
    // Host matching only runs when the provider key is unknown: a registered
    // key (including 'custom') short-circuits it. This is pre-existing behavior.
    expect(
      LlmModelCatalog.presetFor(
        provider: 'custom',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      )?.provider,
      LlmProvider.custom,
    );
    expect(
      LlmModelCatalog.presetFor(
        provider: 'some_unknown_provider',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      )?.provider,
      LlmProvider.zhipu,
    );

    // Alias normalisation.
    expect(LlmProvider.normalize('zhipuai'), LlmProvider.zhipu);
    expect(LlmProvider.normalize('bigmodel'), LlmProvider.zhipu);
    expect(LlmProvider.normalize('GLM'), LlmProvider.zhipu);
  });

  test('zhipu config builds an OpenAI-compatible endpoint', () {
    final config = LlmProviderConfig.emptyForUser(1).copyWith(
      provider: LlmProvider.zhipu,
      apiMode: LlmApiMode.openAiCompatible,
      apiKey: 'test-key',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      model: 'glm-4-flash',
    );
    expect(config.effectiveApiMode, LlmApiMode.openAiCompatible);
    expect(config.usesOpenAiCompatible, isTrue);
    expect(config.usesTokenPlan, isFalse);
    expect(config.isConfigured, isTrue);
    expect(
      config.effectiveEndpoint.toString(),
      'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    );
  });
}
