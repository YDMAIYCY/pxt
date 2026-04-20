import 'package:flutter/material.dart';

import 'pages/guide_page.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';

class PaixuetongApp extends StatelessWidget {
  const PaixuetongApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0C4A6E);
    const secondary = Color(0xFFEA580C);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: '拍学通',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        textTheme: Typography.material2021(platform: TargetPlatform.android)
            .black
            .apply(
              bodyColor: const Color(0xFF0B1324),
              displayColor: const Color(0xFF0B1324),
            ),
      ),
      initialRoute: GuidePage.routeName,
      routes: {
        GuidePage.routeName: (_) => const GuidePage(),
        LoginPage.routeName: (_) => const LoginPage(),
        HomePage.routeName: (_) => const HomePage(),
      },
    );
  }
}
