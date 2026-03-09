import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

int _viewCounter = 0;

Widget buildSvgImage({
  required String svgAsset,
  String? pngFallback,
  double? width,
  double? height,
}) {
  final viewType = '__svg_img_${_viewCounter++}';
  // Flutter web serves assets at assets/assets/... in release builds
  final assetUrl = 'assets/assets/$svgAsset';

  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final img = web.document.createElement('img') as web.HTMLImageElement;
    img.src = assetUrl;
    img.style.width = '100%';
    img.style.height = '100%';
    img.style.objectFit = 'contain';
    return img;
  });

  return SizedBox(
    width: width,
    height: height ?? width,
    child: HtmlElementView(viewType: viewType),
  );
}
