import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pxt1/camera/image_input_service.dart';
import 'package:pxt1/ocr/local_ocr_client.dart';
import 'package:pxt1/ui/pages/guide_page.dart';

// Serve build/import_validation on localhost:8767 and use adb reverse tcp:8767 tcp:8767.
// Use a disposable device: flutter test uninstalls its application after the run.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixtureNames = [
    'simple.doc',
    'cjk.docx',
    'order.ppt',
    'order.pptx',
    'blank.docx',
    'bad.docx',
    'encrypted.doc',
    'long.docx',
    'sample.pdf',
  ];
  final report = <String, Object?>{};
  late Directory folder;
  setUpAll(() async {
    folder = await Directory(
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'import_validation_${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create();
    final client = HttpClient();
    try {
      for (final name in fixtureNames) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:8767/$name'),
        );
        final response = await request.close();
        expect(response.statusCode, 200, reason: 'Missing fixture $name');
        await response.pipe(File(p.join(folder.path, name)).openWrite());
      }
    } finally {
      client.close(force: true);
    }
  });
  tearDownAll(() async {
    binding.reportData = report;
    await File(
      p.join(folder.parent.path, 'document_import_device_results.json'),
    ).writeAsString(jsonEncode(report));
    // The uniquely named test directory contains only files created in this test.
    await folder.delete(recursive: true);
  });

  for (final name in ['simple.doc', 'cjk.docx', 'order.ppt', 'order.pptx']) {
    testWidgets('Android imports $name into readable text pages', (
      tester,
    ) async {
      final original = File(p.join(folder.path, name));
      final before = await original.readAsBytes();
      final pages = await const OfficePageRenderer().renderOffice(
        documentPath: original.path,
        outputDirectoryPath: folder.path,
        outputPrefix: 'render_${name.replaceAll('.', '_')}',
        maxPages: 80,
      );
      expect(pages, isNotEmpty);
      final recognized = <String>[];
      for (final page in pages) {
        final bytes = await File(page.savedPath).readAsBytes();
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final ocr = await LocalOcrClient().recognizeImage(
          imagePath: page.savedPath,
        );
        expect(ocr.cleanText.trim(), isNotEmpty);
        recognized.add(ocr.cleanText);
      }
      expect(await original.readAsBytes(), before);
      report[name] = {'pages': pages.length, 'text': recognized};
    });
  }

  for (final name in ['blank.docx', 'bad.docx', 'encrypted.doc', 'long.docx']) {
    testWidgets('Android rejects $name without leaving partial pages', (
      tester,
    ) async {
      final original = File(p.join(folder.path, name));
      final before = await original.readAsBytes();
      final prefix = 'failed_${name.replaceAll('.', '_')}';
      await expectLater(
        const OfficePageRenderer().renderOffice(
          documentPath: original.path,
          outputDirectoryPath: folder.path,
          outputPrefix: prefix,
          maxPages: name == 'long.docx' ? 1 : 80,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await original.readAsBytes(), before);
      expect(
        folder.listSync().where(
          (file) => p.basename(file.path).startsWith(prefix),
        ),
        isEmpty,
      );
      report[name] = 'rejected, original preserved, no partial pages';
    });
  }

  testWidgets('Android still renders PDF documents', (tester) async {
    final pages = await const PdfPageRenderer().renderPdf(
      pdfPath: p.join(folder.path, 'sample.pdf'),
      outputDirectoryPath: folder.path,
      outputPrefix: 'render_pdf',
      maxPages: 80,
      maxLongestSide: 1600,
      maxRenderedPixels: 2200000,
    );
    expect(pages, hasLength(1));
    expect(await File(pages.single.savedPath).length(), greaterThan(100));
    report['sample.pdf'] = 'rendered';
  });

  testWidgets('guide displays supplied background and login button on device', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GuidePage()));
    final image = tester.widget<Image>(find.byType(Image)).image as AssetImage;
    await precacheImage(image, tester.element(find.byType(GuidePage)));
    await tester.pumpAndSettle();
    expect(image.assetName, 'assets/images/1.png');
    expect(find.text('进入登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    report['guide'] = 'artwork decoded and button rendered';
  });
}
