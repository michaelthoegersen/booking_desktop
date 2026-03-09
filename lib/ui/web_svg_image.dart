import 'package:flutter/material.dart';

import 'web_svg_image_web.dart' if (dart.library.io) 'web_svg_image_native.dart';

/// Displays an SVG asset.
/// On web: renders via native HTML <img> (always pixel-perfect).
/// On desktop: falls back to Image.asset with the PNG version.
class WebSvgImage extends StatelessWidget {
  final String svgAsset;
  final String? pngFallback;
  final double? width;
  final double? height;

  const WebSvgImage({
    super.key,
    required this.svgAsset,
    this.pngFallback,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return buildSvgImage(
      svgAsset: svgAsset,
      pngFallback: pngFallback,
      width: width,
      height: height,
    );
  }
}
