import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double height;

  const AppLogo({
    super.key,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/pdf/logos/CSSLogo.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}