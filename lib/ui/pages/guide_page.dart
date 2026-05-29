import 'package:flutter/material.dart';

import '../../common/app_assets.dart';
import '../theme/app_theme.dart';
import 'login_page.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  static const routeName = '/guide';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  Navigator.of(context)
                      .pushReplacementNamed(LoginPage.routeName);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.button),
                  ),
                ),
                child: const Text(
                  '进入登录',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
