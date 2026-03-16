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
    final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final path = '$userId/${timestamp}_$safeName';

    await _sb.storage.from('chat-attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    return _sb.storage.from('chat-attachments').getPublicUrl(path);
  }
}
