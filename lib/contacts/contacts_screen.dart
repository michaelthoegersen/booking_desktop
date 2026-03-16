import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/active_company.dart';
import '../ui/css_theme.dart';
import '../widgets/agora_meeting_view.dart';
import '../widgets/agora_meeting_stub.dart'
    if (dart.library.js_interop) '../widgets/agora_meeting_view_web.dart';
import 'direct_chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _contacts = [];

  String get _myId => _sb.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final companyId = activeCompanyNotifier.value?.id;
      if (companyId == null) {
        _contacts = [];
      } else {
        // SECURITY DEFINER-funksjon omgår RLS og returnerer alle felter
        final memberRows = await _sb.rpc(
          'get_company_member_profiles',
          params: {'p_company_id': companyId},
        );
        _contacts = List<Map<String, dynamic>>.from(memberRows as List)
          ..removeWhere((r) => r['id'].toString() == _myId);
      }
    } catch (e) {
      debugPrint('Contacts load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _startVideoCall(String calleeId, String calleeName) async {
    final myId = _myId;
    if (myId.isEmpty || myId == calleeId) return;

    final ids = [myId, calleeId]..sort();
    final channelName = 'call-${ids[0].substring(0, 8)}-${ids[1].substring(0, 8)}';

    final inserted = await _sb.from('video_calls').insert({
      'caller_id': myId,
      'callee_id': calleeId,
      'channel_name': channelName,
      'status': 'ringing',
    }).select('id').single();
    final callId = inserted['id'] as String?;

    final profile = await _sb
        .from('profiles')
        .select('name')
        .eq('id', myId)
        .maybeSingle();
    final myName = (profile?['name'] as String?) ?? 'Deltaker';

    // VoIP push for iOS (native call screen) + FCM for Android
    try {
      await _sb.functions.invoke('voip-push', body: {
        'callee_id': calleeId,
        'caller_name': myName,
        'channel_name': channelName,
        if (callId != null) 'call_id': callId,
      });
      await _sb.functions.invoke('send-push', body: {
        'user_id': calleeId,
        'title': 'Innkommende videosamtale',
        'body': '$myName ringer deg',
        'type': 'video_call',
        'channel_name': channelName,
        if (callId != null) 'call_id': callId,
      });
    } catch (e) {
      debugPrint('Video call push error: $e');
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 800,
            height: 600,
            child: kIsWeb
                ? AgoraMeetingViewWeb(
                    channelName: channelName,
                    displayName: myName,
                    onLeave: () => Navigator.of(ctx).pop(),
                  )
                : AgoraMeetingView(
                    channelName: channelName,
                    displayName: myName,
                    onLeave: () => Navigator.of(ctx).pop(),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kontakter',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Kollegaer i systemet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CssTheme.textMuted,
                ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _contacts.isEmpty
                    ? const Center(
                        child: Text(
                          'Ingen kontakter funnet',
                          style: TextStyle(color: CssTheme.textMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _contacts.length,
                        itemBuilder: (context, i) =>
                            _ContactCard(
                              contact: _contacts[i],
                              onUpdated: _load,
                              onVideoCall: _startVideoCall,
                            ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact card
// ---------------------------------------------------------------------------

class _ContactCard extends StatelessWidget {
  final Map<String, dynamic> contact;
  final VoidCallback onUpdated;
  final void Function(String id, String name) onVideoCall;

  const _ContactCard({
    required this.contact,
    required this.onUpdated,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final name = contact['name'] as String? ?? '';
    final phone = contact['phone'] as String? ?? '';
    final email = contact['email'] as String? ?? '';
    final avatarUrl = contact['avatar_url'] as String?;
    final peerId = contact['id'] as String;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CssTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CssTheme.outline),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            backgroundColor: Colors.black,
            radius: 22,
            backgroundImage:
                avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),

          // Name + phone + email
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _launchPhone(phone),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone_rounded,
                            size: 15, color: CssTheme.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          phone,
                          style: const TextStyle(
                            fontSize: 13,
                            color: CssTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  InkWell(
                    onTap: () => _launchEmail(email),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mail_outline_rounded,
                            size: 15, color: CssTheme.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 13,
                            color: CssTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Video call button
          IconButton(
            tooltip: 'Videosamtale',
            icon: Icon(Icons.videocam, size: 22, color: Colors.blue.shade700),
            onPressed: () => onVideoCall(peerId, name),
          ),

          // Edit button
          IconButton(
            tooltip: 'Rediger kontakt',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showEditDialog(context, peerId, name, phone, email),
          ),

          // Chat button
          IconButton(
            tooltip: 'Send melding',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DirectChatScreen(
                    peerId: peerId,
                    peerName: name,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String peerId,
    String name,
    String phone,
    String email,
  ) {
    final phoneCtrl = TextEditingController(text: phone);
    final emailCtrl = TextEditingController(text: email);

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(name),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Telefon',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-post',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Avbryt'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await Supabase.instance.client
                                .from('profiles')
                                .update({
                              'phone': phoneCtrl.text.trim(),
                              'email': emailCtrl.text.trim(),
                            }).eq('id', peerId);

                            if (ctx.mounted) Navigator.pop(ctx);
                            onUpdated();
                          } catch (e) {
                            setDialogState(() => saving = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Feil: $e')),
                              );
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Lagre'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _launchPhone(String phone) {
    launchUrl(Uri(scheme: 'tel', path: phone));
  }

  void _launchEmail(String email) {
    launchUrl(Uri(scheme: 'mailto', path: email));
  }
}
