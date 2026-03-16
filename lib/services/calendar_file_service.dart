import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class CalendarFileService {
  static final _sb = Supabase.instance.client;

  static Future<Map<String, dynamic>> uploadFile({
    required String samletdataId,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'application/octet-stream',
  }) async {
    final userId = _sb.auth.currentUser!.id;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final path = 'calendar/$userId/${timestamp}_$safeName';

    await _sb.storage.from('chat-attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );

    final url = _sb.storage.from('chat-attachments').getPublicUrl(path);

    // Determine file type
    final lower = fileName.toLowerCase();
    String fileType = 'file';
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      fileType = 'image';
    } else if (lower.endsWith('.pdf')) {
      fileType = 'pdf';
    }

    final res = await _sb.from('calendar_attachments').insert({
      'samletdata_id': samletdataId,
      'file_url': url,
      'file_name': fileName,
      'file_type': fileType,
    }).select().single();
    return res;
  }

  static Future<List<Map<String, dynamic>>> getFilesForIds(
      List<String> samletdataIds) async {
    if (samletdataIds.isEmpty) return [];
    final res = await _sb
        .from('calendar_attachments')
        .select()
        .inFilter('samletdata_id', samletdataIds)
        .order('created_at');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> deleteFile(String id) async {
    await _sb.from('calendar_attachments').delete().eq('id', id);
  }
}
