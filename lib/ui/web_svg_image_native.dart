import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

Widget buildSvgImage({
  required String svgAsset,
  String? pngFallback,
  double? width,
  double? height,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: SvgPicture.asset(
      'assets/$svgAsset',
      fit: BoxFit.contain,
    ),
  );
}
