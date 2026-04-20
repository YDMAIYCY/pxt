import 'package:flutter/material.dart';

import '../../common/app_assets.dart';
import 'login_page.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  static const routeName = '/guide';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.topCenter,
                child: Image.asset(
                  AppAssets.guideImage,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pushReplacementNamed(LoginPage.routeName);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF0C4A6E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  '进入登录',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
