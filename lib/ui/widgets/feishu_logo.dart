import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Feishu mark from the official Open Platform favicon asset.
class FeishuLogo extends StatelessWidget {
  const FeishuLogo({this.size = 28, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '飞书',
    image: true,
    child: SvgPicture.asset(
      'assets/icons/feishu_logo.svg',
      width: size,
      height: size,
    ),
  );
}
