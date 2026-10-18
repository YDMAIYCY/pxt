import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      initialRoute: GuidePage.routeName,
      routes: {
        GuidePage.routeName: (_) => const GuidePage(),
        LoginPage.routeName: (_) => const LoginPage(),
        HomePage.routeName: (_) => const HomePage(),
      },
    );
  }
}
