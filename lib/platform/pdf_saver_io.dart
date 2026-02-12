import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

Future<String> savePdfPlatform(
  Uint8List bytes,
  String filename,
) async {
  final filePath = await FilePicker.platform.saveFile(
    dialogTitle: "Save PDF offer",
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: ["pdf"],
    lockParentWindow: true,
  );

  if (filePath == null) {
    throw Exception("Save cancelled.");
  }

  var finalPath = filePath;

  if (!finalPath.toLowerCase().endsWith(".pdf")) {
    finalPath += ".pdf";
  }

  final file = File(finalPath);
  await file.writeAsBytes(bytes, flush: true);

  return finalPath;
}