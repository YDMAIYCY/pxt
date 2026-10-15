// ========== 图片输入来源 ==========
// 统一描述第七阶段支持的两种图片输入方式：拍照与相册。

enum ImageInputSource { camera, gallery }

enum BatchDocumentInputSource { multiImage, pdf, document }

// ========== 输入结果模型 ==========
// 承载图片选取后写入应用私有目录的结果，供后续入库流程使用。

class StoredImageSelection {
  const StoredImageSelection({
    required this.savedPath,
    required this.originalName,
    required this.inputSource,
  });

  final String savedPath;
  final String originalName;
  final ImageInputSource inputSource;
}

class StoredDocumentPage {
  const StoredDocumentPage({
    required this.savedPath,
    required this.originalName,
  });

  final String savedPath;
  final String originalName;
}

class StoredBatchSelection {
  const StoredBatchSelection({
    required this.source,
    required this.title,
    required this.originalFilePath,
    required this.pages,
  });

  final BatchDocumentInputSource source;
  final String title;
  final String? originalFilePath;
  final List<StoredDocumentPage> pages;
}

// ========== 图片输入接口 ==========
// 抽象图片选择与本地落盘能力，方便流程层解耦平台插件并提升可测试性。

abstract class ImageInputPort {
  Future<StoredImageSelection?> pickAndStoreImage({
    required ImageInputSource source,
  });
}

abstract class BatchDocumentInputPort {
  Future<StoredBatchSelection?> pickAndStoreBatch({
    required BatchDocumentInputSource source,
  });
}
