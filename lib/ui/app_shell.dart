import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'pages/guide_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';

class PaixuetongApp extends StatelessWidget {
  const PaixuetongApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拍学通',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: GuidePage.routeName,
      routes: {
        GuidePage.routeName: (_) => const GuidePage(),
        LoginPage.routeName: (_) => const LoginPage(),
        HomePage.routeName: (_) => const HomePage(),
      },
    );
  }
}
