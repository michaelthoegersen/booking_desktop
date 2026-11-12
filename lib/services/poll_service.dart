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
  ///
  /// [isGuest] gir stemmen til følget til den som er logget inn. Nøkkelen i
  /// basen er (poll_id, user_id, is_guest), så en bruker som tar med +1 kan
  /// ha én stemme for seg selv og én for følget -- men fortsatt bare én av
  /// hver.
  static Future<void> vote(
    String pollId,
    String optionId, {
    bool isGuest = false,
  }) async {
    await _sb.from('chat_poll_votes').upsert({
      'poll_id': pollId,
      'option_id': optionId,
      'user_id': _sb.auth.currentUser!.id,
      'is_guest': isGuest,
    }, onConflict: 'poll_id,user_id,is_guest');
  }

  /// Remove own vote from a poll. [isGuest] fjerner følgets stemme i stedet.
  static Future<void> removeVote(String pollId, {bool isGuest = false}) async {
    await _sb
        .from('chat_poll_votes')
        .delete()
        .eq('poll_id', pollId)
        .eq('user_id', _sb.auth.currentUser!.id)
        .eq('is_guest', isGuest);
  }

  /// Fjern alle +1-stemmene mine i avstemmingene som hører til en gig.
  ///
  /// Kalles når noen huker av "Tar med +1" igjen. Uten dette ville følgets
  /// stemme ligge igjen og telle med, og hodetellingen i aktiviteten ville
  /// vist en person som ikke kommer. Avstemmingene har ingen gig-kolonne --
  /// koblingen er meldingen de ligger i.
  static Future<void> removeGuestVotesForGig(String gigId) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    final msgs = await _sb
        .from('gig_messages')
        .select('attachment_url')
        .eq('gig_id', gigId)
        .eq('message_type', 'poll');

    final pollIds = msgs
        .map((m) => m['attachment_url'] as String?)
        .whereType<String>()
        .toList();
    if (pollIds.isEmpty) return;

    await _sb
        .from('chat_poll_votes')
        .delete()
        .inFilter('poll_id', pollIds)
        .eq('user_id', uid)
        .eq('is_guest', true);
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
        .select('option_id, user_id, is_guest')
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
