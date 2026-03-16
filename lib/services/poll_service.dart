import 'package:supabase_flutter/supabase_flutter.dart';

class PollService {
  static final _sb = Supabase.instance.client;

  /// Create a poll with options. Returns the poll ID.
  static Future<String> createPoll({
    required String question,
    required List<String> options,
  }) async {
    final res = await _sb.from('chat_polls').insert({
      'question': question,
      'created_by': _sb.auth.currentUser!.id,
    }).select('id').single();

    final pollId = res['id'] as String;

    await _sb.from('chat_poll_options').insert(
      options
          .asMap()
          .entries
          .map((e) => {
                'poll_id': pollId,
                'label': e.value,
                'position': e.key,
              })
          .toList(),
    );

    return pollId;
  }

  /// Vote on a poll option. Replaces any previous vote (UNIQUE constraint).
  static Future<void> vote(String pollId, String optionId) async {
    await _sb.from('chat_poll_votes').upsert({
      'poll_id': pollId,
      'option_id': optionId,
      'user_id': _sb.auth.currentUser!.id,
    }, onConflict: 'poll_id,user_id');
  }

  /// Remove own vote from a poll.
  static Future<void> removeVote(String pollId) async {
    await _sb
        .from('chat_poll_votes')
        .delete()
        .eq('poll_id', pollId)
        .eq('user_id', _sb.auth.currentUser!.id);
  }

  /// Fetch poll with options.
  static Future<Map<String, dynamic>> getPoll(String pollId) async {
    final poll =
        await _sb.from('chat_polls').select().eq('id', pollId).single();

    final options = await _sb
        .from('chat_poll_options')
        .select()
        .eq('poll_id', pollId)
        .order('position');

    final votes = await _sb
        .from('chat_poll_votes')
        .select('option_id, user_id')
        .eq('poll_id', pollId);

    return {
      ...poll,
      'options': List<Map<String, dynamic>>.from(options),
      'votes': List<Map<String, dynamic>>.from(votes),
    };
  }

  /// Realtime stream of votes for a poll.
  static Stream<List<Map<String, dynamic>>> streamVotes(String pollId) {
    return _sb
        .from('chat_poll_votes')
        .stream(primaryKey: ['id']).map((rows) => rows
            .where((r) => r['poll_id'] == pollId)
            .toList());
  }

  /// Close a poll (only creator can do this via RLS).
  static Future<void> closePoll(String pollId) async {
    await _sb
        .from('chat_polls')
        .update({'is_closed': true}).eq('id', pollId);
  }
}
