import 'dart:async';

/// Keep provider/native exception details out of the product interface.
String interviewFailure(Object error, {String fallback = '操作失败，请重试'}) {
  final text = error.toString();
  if (text.contains('429')) return 'AI 服务繁忙，请稍后重试';
  if (text.contains('401') || text.contains('403')) return '请检查 AI 模型配置';
  if (text.contains('权限') || text.toLowerCase().contains('permission')) {
    return '请允许麦克风权限';
  }
  if (text.contains('语音') &&
      (text.contains('未安装') || text.contains('未找到'))) {
    return '未找到可用的中文语音，请到系统设置 → 文字转语音输出 选择中文引擎';
  }
  if (text.contains('配置') && text.contains('模型')) return '请先在“我的”中配置 AI 模型';
  if ((text.contains('没有') || text.contains('暂无')) &&
      (text.contains('资料') || text.contains('片段'))) {
    return '所选资料暂无可用内容，请先完成文字识别';
  }
  if (text.contains('仅生成')) return '资料不足，请减少题量或重新选择';
  if (text.contains('删除') || text.contains('不属于') || text.contains('移出')) {
    return '资料已变更，请重新选择面试范围';
  }
  if (error is TimeoutException) return '响应超时，请重试';
  return fallback;
}
