import 'package:flutter/material.dart';

import 'ui/app_shell.dart';
import 'community/cloud_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CloudBackend.instance.initialize();
  runApp(const PaixuetongApp());
}
