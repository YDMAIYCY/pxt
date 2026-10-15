// Platform interfaces are used only to isolate plugins without changing pubspec.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:file_picker/src/platform/file_picker_method_channel.dart';
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:image_picker_platform_interface/src/method_channel/method_channel_image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:pxt1/camera/document_input_contract.dart';
import 'package:pxt1/camera/image_input_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const imageChannel = MethodChannel('plugins.flutter.io/image_picker');
  const fileChannel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const pdfChannel = MethodChannel('pxt1/pdf_renderer');
  const officeChannel = MethodChannel('pxt1/office_renderer');

  late Directory temporaryDirectory;
  late Directory appDirectory;
  late FilePickerPlatform previousFilePicker;
  late ImagePickerPlatform previousImagePicker;
  late PathProviderPlatform previousPathProvider;
  late List<String> selectedImages;
  File? selectedDocument;
  late List<MethodCall> imageCalls;
  late List<MethodCall> fileCalls;
  late List<MethodCall> renderCalls;
  late bool rendererFails;
  late bool rendererReturnsNoPages;

  Future<List<Map<String, Object>>> render(MethodCall call) async {
    renderCalls.add(call);
    final arguments = Map<String, dynamic>.from(call.arguments as Map);
    final inputPath =
        (arguments['pdfPath'] ?? arguments['documentPath']) as String;
    expect(inputPath, isNot(selectedDocument!.path));
    expect(
      await File(inputPath).readAsBytes(),
      await selectedDocument!.readAsBytes(),
    );
    expect(
      arguments['outputDirectoryPath'],
      p.join(appDirectory.path, 'source_documents'),
    );
    expect(arguments['maxPages'], 80);
    if (rendererFails) {
      throw PlatformException(code: 'render_failed', message: 'Cannot render');
    }
    if (rendererReturnsNoPages) return [];

    final pages = <Map<String, Object>>[];
    for (final number in [1, 2]) {
      final page = File(
        p.join(
          arguments['outputDirectoryPath'] as String,
          '${arguments['outputPrefix']}_$number.png',
        ),
      );
      await page.writeAsBytes([number]);
      pages.add({'pageNumber': number, 'savedPath': page.path});
    }
    return pages;
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'document-input-',
    );
    appDirectory = Directory(p.join(temporaryDirectory.path, 'app'));
    previousFilePicker = FilePickerPlatform.instance;
    previousImagePicker = ImagePickerPlatform.instance;
    previousPathProvider = PathProviderPlatform.instance;
    FilePickerPlatform.instance = MethodChannelFilePicker();
    ImagePickerPlatform.instance = MethodChannelImagePicker();
    PathProviderPlatform.instance = MethodChannelPathProvider();
    selectedImages = [];
    selectedDocument = null;
    imageCalls = [];
    fileCalls = [];
    renderCalls = [];
    rendererFails = false;
    rendererReturnsNoPages = false;

    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, (
      call,
    ) async {
      expect(call.method, 'getApplicationDocumentsDirectory');
      return appDirectory.path;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(imageChannel, (
      call,
    ) async {
      imageCalls.add(call);
      expect(call.method, 'pickMultiImage');
      expect((call.arguments as Map)['imageQuality'], 92);
      return selectedImages;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(fileChannel, (
      call,
    ) async {
      fileCalls.add(call);
      final file = selectedDocument;
      return file == null
          ? null
          : [
              {
                'path': file.path,
                'name': p.basename(file.path),
                'size': await file.length(),
              },
            ];
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pdfChannel, render);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      officeChannel,
      render,
    );
  });

  tearDown(() async {
    for (final channel in [
      imageChannel,
      fileChannel,
      pathChannel,
      pdfChannel,
      officeChannel,
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
    FilePickerPlatform.instance = previousFilePicker;
    ImagePickerPlatform.instance = previousImagePicker;
    PathProviderPlatform.instance = previousPathProvider;
    await temporaryDirectory.delete(recursive: true);
  });

  group('Unified document input', () {
    for (final count in [1, 3]) {
      test(
        'gallery stores $count selected photos as an ordered batch',
        () async {
          for (var index = 0; index < count; index++) {
            final photo = File(
              p.join(temporaryDirectory.path, 'note-$index.jpg'),
            );
            await photo.writeAsBytes([index, 42]);
            selectedImages.add(photo.path);
          }

          final result = (await ImageInputService().pickAndStoreBatch(
            source: BatchDocumentInputSource.multiImage,
          ))!;

          expect(imageCalls, hasLength(1));
          expect(fileCalls, isEmpty);
          expect(renderCalls, isEmpty);
          expect(result.source, BatchDocumentInputSource.multiImage);
          expect(result.originalFilePath, isNull);
          expect(result.pages, hasLength(count));
          expect(
            result.pages.map((page) => page.savedPath).toSet(),
            hasLength(count),
          );
          if (count == 1) expect(result.title, 'note-0');
          for (var index = 0; index < count; index++) {
            final page = result.pages[index];
            expect(page.originalName, 'note-$index');
            expect(
              p.dirname(page.savedPath),
              p.join(appDirectory.path, 'source_documents'),
            );
            expect(page.savedPath, isNot(selectedImages[index]));
            expect(await File(page.savedPath).readAsBytes(), [index, 42]);
            expect(await File(selectedImages[index]).readAsBytes(), [
              index,
              42,
            ]);
          }
        },
      );
    }

    for (final extension in ['PDF', 'doc', 'docx', 'ppt', 'pptx']) {
      test(
        'document picker routes .$extension and preserves its original copy',
        () async {
          selectedDocument = await File(
            p.join(temporaryDirectory.path, 'lesson.$extension'),
          ).writeAsBytes([4, 5, 6]);

          final result = (await ImageInputService().pickAndStoreBatch(
            source: BatchDocumentInputSource.document,
          ))!;

          expect(fileCalls, hasLength(1));
          expect(fileCalls.single.method, 'custom');
          expect(
            fileCalls.single.arguments,
            containsPair('allowedExtensions', [
              'pdf',
              'doc',
              'docx',
              'ppt',
              'pptx',
            ]),
          );
          expect(
            fileCalls.single.arguments,
            containsPair('allowMultipleSelection', false),
          );
          expect(fileCalls.single.arguments, containsPair('withData', false));
          expect(imageCalls, isEmpty);
          expect(renderCalls, hasLength(1));
          final isPdf = extension == 'PDF';
          expect(
            renderCalls.single.method,
            isPdf ? 'renderPdf' : 'renderOffice',
          );
          expect(
            result.source,
            isPdf
                ? BatchDocumentInputSource.pdf
                : BatchDocumentInputSource.document,
          );
          expect(result.title, 'lesson');
          expect(result.originalFilePath, isNot(selectedDocument!.path));
          expect(
            p.dirname(result.originalFilePath!),
            p.join(appDirectory.path, 'source_documents'),
          );
          expect(await File(result.originalFilePath!).readAsBytes(), [4, 5, 6]);
          expect(await selectedDocument!.readAsBytes(), [4, 5, 6]);
          expect(result.pages.map((page) => page.originalName), [
            'lesson-1',
            'lesson-2',
          ]);
          for (var index = 0; index < result.pages.length; index++) {
            expect(await File(result.pages[index].savedPath).readAsBytes(), [
              index + 1,
            ]);
          }
        },
      );
    }

    test('legacy PDF picker restricts extensions to PDF', () async {
      expect(
        await ImageInputService().pickAndStoreBatch(
          source: BatchDocumentInputSource.pdf,
        ),
        isNull,
      );
      expect(fileCalls.single.method, 'custom');
      expect(
        fileCalls.single.arguments,
        containsPair('allowedExtensions', ['pdf']),
      );
      expect(renderCalls, isEmpty);
      expect(appDirectory.existsSync(), isFalse);
    });

    for (final source in [
      BatchDocumentInputSource.multiImage,
      BatchDocumentInputSource.document,
    ]) {
      test(
        '$source cancellation creates no stored files or rendered pages',
        () async {
          expect(
            await ImageInputService().pickAndStoreBatch(source: source),
            isNull,
          );
          expect(
            source == BatchDocumentInputSource.multiImage
                ? imageCalls
                : fileCalls,
            hasLength(1),
          );
          expect(renderCalls, isEmpty);
          expect(appDirectory.existsSync(), isFalse);
        },
      );
    }

    for (final extension in ['pdf', 'docx']) {
      for (final empty in [false, true]) {
        test(
          '.$extension ${empty ? 'empty render' : 'renderer failure'} removes copy and keeps selected original',
          () async {
            selectedDocument = await File(
              p.join(temporaryDirectory.path, 'lesson.$extension'),
            ).writeAsBytes([7, 8, 9]);
            rendererFails = !empty;
            rendererReturnsNoPages = empty;

            await expectLater(
              ImageInputService().pickAndStoreBatch(
                source: BatchDocumentInputSource.document,
              ),
              throwsA(isA<StateError>()),
            );

            expect(renderCalls, hasLength(1));
            expect(
              renderCalls.single.method,
              extension == 'pdf' ? 'renderPdf' : 'renderOffice',
            );
            expect(
              await Directory(
                p.join(appDirectory.path, 'source_documents'),
              ).list().toList(),
              isEmpty,
            );
            expect(await selectedDocument!.readAsBytes(), [7, 8, 9]);
          },
        );
      }
    }
  });
}
