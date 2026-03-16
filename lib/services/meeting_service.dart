import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MeetingService {
  static final _sb = Supabase.instance.client;

  // ---------------------------------------------------------------
  // MEETINGS CRUD
  // ---------------------------------------------------------------

  static Future<Map<String, dynamic>> createMeeting({
    required String companyId,
    required String title,
    required String date,
    String? startTime,
    String? endTime,
    String? address,
    String? postalCode,
    String? city,
    String? comment,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    final res = await _sb.from('meetings').insert({
      'company_id': companyId,
      'title': title,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      'address': address,
      'postal_code': postalCode,
      'city': city,
      'comment': comment,
      'status': 'draft',
      'created_by': uid,
    }).select().single();
    return res;
  }

  static Future<void> updateMeeting({
    required String meetingId,
    required Map<String, dynamic> fields,
  }) async {
    fields['updated_at'] = DateTime.now().toIso8601String();
    await _sb.from('meetings').update(fields).eq('id', meetingId);
  }

  static Future<void> deleteMeeting(String meetingId) async {
    await _sb.from('meetings').delete().eq('id', meetingId);
  }

  static Future<List<Map<String, dynamic>>> listMeetings(String companyId) async {
    final res = await _sb
        .from('meetings')
        .select('*, meeting_participants(user_id, rsvp_status)')
        .eq('company_id', companyId)
        .order('date', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>> getMeeting(String meetingId) async {
    final res = await _sb
        .from('meetings')
        .select('*, meeting_participants(id, user_id, rsvp_status), meeting_agenda_items(*, meeting_agenda_files(*))')
        .eq('id', meetingId)
        .single();
    return res;
  }

  static Future<void> updateStatus(String meetingId, String status) async {
    await _sb.from('meetings').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', meetingId);
  }

  // ---------------------------------------------------------------
  // PARTICIPANTS
  // ---------------------------------------------------------------

  static Future<void> addParticipant(String meetingId, String userId) async {
    await _sb.from('meeting_participants').upsert({
      'meeting_id': meetingId,
      'user_id': userId,
      'rsvp_status': 'pending',
    }, onConflict: 'meeting_id,user_id');
  }

  static Future<void> removeParticipant(String meetingId, String userId) async {
    await _sb
        .from('meeting_participants')
        .delete()
        .eq('meeting_id', meetingId)
        .eq('user_id', userId);
  }

  static Future<void> setParticipants(String meetingId, List<String> userIds) async {
    // Delete existing
    await _sb.from('meeting_participants').delete().eq('meeting_id', meetingId);
    // Insert new
    if (userIds.isNotEmpty) {
      await _sb.from('meeting_participants').insert(
        userIds.map((uid) => <String, dynamic>{
            'meeting_id': meetingId,
            'user_id': uid,
            'rsvp_status': 'pending',
        }).toList(),
      );
    }
  }

  // ---------------------------------------------------------------
  // AGENDA ITEMS
  // ---------------------------------------------------------------

  static Future<Map<String, dynamic>> addAgendaItem({
    required String meetingId,
    required String title,
    String itemType = 'none',
    String? description,
    String? assignedTo,
    int sortOrder = 0,
  }) async {
    final res = await _sb.from('meeting_agenda_items').insert({
      'meeting_id': meetingId,
      'title': title,
      'item_type': itemType,
      'description': description,
      'assigned_to': assignedTo,
      'sort_order': sortOrder,
    }).select().single();
    return res;
  }

  static Future<void> updateAgendaItem(String itemId, Map<String, dynamic> fields) async {
    await _sb.from('meeting_agenda_items').update(fields).eq('id', itemId);
  }

  static Future<void> deleteAgendaItem(String itemId) async {
    await _sb.from('meeting_agenda_items').delete().eq('id', itemId);
  }

  static Future<void> reorderAgendaItems(List<String> itemIds) async {
    for (int i = 0; i < itemIds.length; i++) {
      await _sb.from('meeting_agenda_items').update({'sort_order': i}).eq('id', itemIds[i]);
    }
  }

  static Future<void> updateAgendaNotes(String itemId, String notes) async {
    await _sb.from('meeting_agenda_items').update({'notes': notes}).eq('id', itemId);
  }

  // ---------------------------------------------------------------
  // AGENDA FILES
  // ---------------------------------------------------------------

  static Future<Map<String, dynamic>> uploadAgendaFile({
    required String agendaItemId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final path = '$agendaItemId/${timestamp}_$safeName';

    await _sb.storage.from('meeting-attachments').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );

    final publicUrl = _sb.storage.from('meeting-attachments').getPublicUrl(path);

    final res = await _sb.from('meeting_agenda_files').insert({
      'agenda_item_id': agendaItemId,
      'file_url': publicUrl,
      'file_name': fileName,
      'file_size': bytes.length,
      'content_type': contentType,
      'uploaded_by': uid,
    }).select().single();

    return res;
  }

  static Future<void> deleteAgendaFile(String fileId) async {
    await _sb.from('meeting_agenda_files').delete().eq('id', fileId);
  }

  // ---------------------------------------------------------------
  // AGENDA TEMPLATES
  // ---------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> listTemplates(String companyId) async {
    final res = await _sb
        .from('meeting_agenda_templates')
        .select()
        .eq('company_id', companyId)
        .order('title');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> saveTemplate({
    required String companyId,
    required String title,
    required String itemType,
    String? description,
  }) async {
    await _sb.from('meeting_agenda_templates').insert({
      'company_id': companyId,
      'title': title,
      'item_type': itemType,
      'description': description,
    });
  }

  static Future<void> deleteTemplate(String templateId) async {
    await _sb.from('meeting_agenda_templates').delete().eq('id', templateId);
  }

  // ---------------------------------------------------------------
  // COMPANY MEMBERS
  // ---------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getCompanyMembers(String companyId) async {
    final res = await _sb
        .from('profiles')
        .select('id, name, role, section, email')
        .eq('company_id', companyId)
        .order('name');
    return List<Map<String, dynamic>>.from(res);
  }

  // ---------------------------------------------------------------
  // RSVP URL
  // ---------------------------------------------------------------

  static String rsvpUrl({
    required String meetingId,
    required String userId,
    required String response,
  }) {
    return 'https://tourflow-60890.web.app/rsvp.html'
        '?meeting_id=$meetingId&user_id=$userId&response=$response';
  }
}
