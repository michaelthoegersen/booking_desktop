import 'dart:typed_data';

import 'pdf_opener_io.dart' if (dart.library.html) 'pdf_opener_web.dart';

/// Opens a PDF for viewing.
///
/// Desktop/mobile: writes to a temp file and hands it to the OS viewer.
/// Web: wraps the bytes in a blob URL and opens it in a new tab
/// (`dart:io` is unavailable there — `Directory.systemTemp` throws
/// `Unsupported operation: _Namespace`).
Future<void> openPdf(Uint8List bytes, String filename) =>
    openPdfPlatform(bytes, filename);
