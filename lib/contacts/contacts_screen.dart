import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/css_theme.dart';
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
      // Get current user's company_id
      final myProfile = await _sb
          .from('profiles')
          .select('company_id')
          .eq('id', _myId)
          .maybeSingle();
      final companyId = myProfile?['company_id'];

      if (companyId == null) {
        _contacts = [];
      } else {
        final res = await _sb
            .from('profiles')
            .select('id, name, phone, email, avatar_url')
            .eq('company_id', companyId)
            .order('name');
        final all = List<Map<String, dynamic>>.from(res);
        all.removeWhere((p) => p['id'] == _myId);
        _contacts = all;
      }
    } catch (e) {
      debugPrint('Contacts load error: $e');
    }
    if (mounted) setState(() => _loading = false);
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

  const _ContactCard({required this.contact, required this.onUpdated});

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

          // Edit button
          IconButton(
            tooltip: 'Rediger kontakt',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showEditDialog(context, peerId, name, phone, email),
          ),

          // Delete button
          IconButton(
            tooltip: 'Fjern kontakt',
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: () => _confirmDelete(context, peerId, name),
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
    final nameCtrl = TextEditingController(text: name);
    final phoneCtrl = TextEditingController(text: phone);
    final emailCtrl = TextEditingController(text: email);

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Rediger kontakt'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Navn',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                              'name': nameCtrl.text.trim(),
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

  void _confirmDelete(BuildContext context, String peerId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern kontakt'),
        content: Text('Er du sikker på at du vil fjerne $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                // Remove from company_members first
                await Supabase.instance.client
                    .from('company_members')
                    .delete()
                    .eq('user_id', peerId);
                // Clear company_id from profile
                await Supabase.instance.client
                    .from('profiles')
                    .update({'company_id': null})
                    .eq('id', peerId);
                onUpdated();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Feil: $e')),
                  );
                }
              }
            },
            child: const Text('Fjern'),
          ),
        ],
      ),
    );
  }

  void _launchPhone(String phone) {
    launchUrl(Uri(scheme: 'tel', path: phone));
  }

  void _launchEmail(String email) {
    launchUrl(Uri(scheme: 'mailto', path: email));
  }
}
