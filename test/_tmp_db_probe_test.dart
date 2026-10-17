import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';

void main() {
  test('opening the shared database in a temp path completes', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('pxt-probe-');
    await databaseFactory.setDatabasesPath(dir.path);
    final db = await AppDatabase.instance.database.timeout(
      const Duration(seconds: 30),
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    // ignore: avoid_print
    print('PROBE tables=${tables.length}');
    expect(tables, isNotEmpty);
    await dir.delete(recursive: true);
  });
}
