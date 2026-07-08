import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatAttachmentService {
  static final _sb = Supabase.instance.client;

  /// Upload a file to the chat-attachments bucket.
  /// Returns the public URL of the uploaded file.
  static Future<String> uploadFile({
    required Uint8List bytes,
    required String fileName,
    String contentType = 'application/octet-stream',
  }) async {
    final userId = _sb.auth.currentUser!.id;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = _sanitizeFileName(fileName);
    final path = '$userId/${timestamp}_$safeName';

    await _sb.storage.from('chat-attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return _sb.storage.from('chat-attachments').getPublicUrl(path);
  }

  /// Strip everything that isn't ASCII alphanumeric, dot, dash or underscore.
  /// Collapses runs of underscores and trims leading/trailing ones so we never
  /// produce keys Supabase Storage rejects (e.g. spaces, Norwegian å/ø/æ).
  static String _sanitizeFileName(String name) {
    String s = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^[_.]+|[_]+$'), '');
    if (s.isEmpty) s = 'file';
    return s;
  }
}
