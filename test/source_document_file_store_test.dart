import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/common/source_document_file_store.dart';

void main() {
  group('Source document file store', () {
    late Directory tempDirectory;
    late Directory managedDirectory;
    late Directory outsideDirectory;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync(
        'source-document-file-store',
      );
      managedDirectory = Directory('${tempDirectory.path}\\source_documents')
        ..createSync(recursive: true);
      outsideDirectory = Directory('${tempDirectory.path}\\outside')
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('deletes only files inside the managed source_documents folder',
        () async {
      final managedFile = File('${managedDirectory.path}\\page.png');
      final outsideFile = File('${outsideDirectory.path}\\keep.png');
      await managedFile.writeAsBytes(<int>[1]);
      await outsideFile.writeAsBytes(<int>[2]);

      final store = SourceDocumentFileStore(
        managedDirectoryPath: managedDirectory.path,
      );

      await store.deleteAllIfManaged([
        managedFile.path,
        outsideFile.path,
        managedFile.path,
        '',
        null,
      ]);

      expect(managedFile.existsSync(), isFalse);
      expect(outsideFile.existsSync(), isTrue);
    });
  });
}
