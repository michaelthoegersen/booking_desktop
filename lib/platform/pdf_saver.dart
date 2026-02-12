import 'dart:typed_data';

import 'pdf_saver_io.dart'
    if (dart.library.html) 'pdf_saver_web.dart';

Future<String> savePdf(
  Uint8List bytes,
  String filename,
) async {
  return savePdfPlatform(bytes, filename);
}