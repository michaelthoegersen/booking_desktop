import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

Future<void> openPdfPlatform(Uint8List bytes, String filename) async {
  final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_');
  final name = safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf';
  final dir = await Directory.systemTemp.createTemp('tourflow_pdf');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await launchUrl(Uri.file(file.path));
}
