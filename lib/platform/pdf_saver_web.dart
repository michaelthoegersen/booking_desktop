import 'dart:typed_data';
import 'dart:html' as html;

Future<String> savePdfPlatform(
  Uint8List bytes,
  String filename,
) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..click();

  html.Url.revokeObjectUrl(url);

  return filename;
}