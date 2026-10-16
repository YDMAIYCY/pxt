import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';

void main() {
  test('source document labels are readable Chinese', () {
    expect(
      SourceDocumentRecord(
        id: 1,
        userId: 7,
        sourceType: SourceDocumentSourceType.cameraCapture,
        imagePath: '/tmp/demo.png',
        title: 'demo',
        createdAt: DateTime(2026, 6, 18),
        ocrStatus: SourceDocumentOcrStatus.pending,
        aiDone: false,
      ).ocrStatusLabel,
      '\u5f85\u8bc6\u522b',
    );
    expect(
      SourceDocumentRecord(
        id: 1,
        userId: 7,
        sourceType: SourceDocumentSourceType.galleryImport,
        imagePath: '/tmp/demo.png',
        title: 'demo',
        createdAt: DateTime(2026, 6, 18),
        ocrStatus: SourceDocumentOcrStatus.success,
        aiDone: true,
      ).sourceTypeLabel,
      '\u76f8\u518c',
    );
  });

  test('document batch labels are readable Chinese', () {
    // \u591a\u56fe\u5bfc\u5165 is presented to users as \u76f8\u518c\u5bfc\u5165 (see import_entry_ui_test).
    expect(
      DocumentBatchSourceType.labelOf(DocumentBatchSourceType.multiImage),
      '\u76f8\u518c\u5bfc\u5165',
    );
    expect(
      DocumentBatchSourceType.labelOf(DocumentBatchSourceType.pdf),
      '\u6587\u6863\u5bfc\u5165',
    );
  });
}
