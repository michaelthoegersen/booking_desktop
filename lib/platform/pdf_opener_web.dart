import 'dart:html' as html;
import 'dart:typed_data';

Future<void> openPdfPlatform(Uint8List bytes, String filename) async {
  final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_');
  final name = safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf';
  final blob = html.Blob(<dynamic>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final opened = html.window.open(url, '_blank');
  if (opened.closed ?? true) {
    // Popup blocked -> download instead so the user still gets the file.
    html.AnchorElement(href: url)
      ..setAttribute('download', name)
      ..click();
  }

  // Give the new tab time to fetch the blob before releasing it.
  Future<void>.delayed(const Duration(minutes: 1))
      .then((_) => html.Url.revokeObjectUrl(url));
}
