import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/css_theme.dart';

class MgmtSettingsPage extends StatefulWidget {
  const MgmtSettingsPage({super.key});

  @override
  State<MgmtSettingsPage> createState() => _MgmtSettingsPageState();
}

class _MgmtSettingsPageState extends State<MgmtSettingsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _company;
  String? _companyId;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      final profile = await _sb
          .from('profiles')
          .select('company_id')
          .eq('id', uid)
          .maybeSingle();
      _companyId = profile?['company_id'] as String?;

      if (_companyId != null) {
        final company = await _sb
            .from('companies')
            .select('*')
            .eq('id', _companyId!)
            .maybeSingle();
        _company = company;

        // Load other members in the same company
        final members = await _sb
            .from('profiles')
            .select('id, name, email, role')
            .eq('company_id', _companyId!);
        _members = List<Map<String, dynamic>>.from(members);
      }
    } catch (e) {
      debugPrint('MgmtSettings load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openInviteUserDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite User'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'User will be created with management role and linked to your company.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (emailCtrl.text.trim().isEmpty ||
                  nameCtrl.text.trim().isEmpty) {
                return;
              }
              try {
                await _sb.functions.invoke(
                  'create-user',
                  body: {
                    'name': nameCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'role': 'management',
                    'company_id': _companyId,
                  },
                );

                if (ctx.mounted) Navigator.pop(ctx);
                await _load();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User invited successfully')),
                  );
                }
              } catch (e) {
                debugPrint('Invite user error: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),

                  // Company info
                  Text(
                    'Company',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: _company == null
                        ? const Text(
                            'No company linked to your account.',
                            style: TextStyle(color: CssTheme.textMuted),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _company!['name'] as String? ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              if (_company!['email'] != null)
                                Text(
                                  _company!['email'] as String,
                                  style: const TextStyle(
                                      color: CssTheme.textMuted),
                                ),
                              if (_company!['phone'] != null)
                                Text(
                                  _company!['phone'] as String,
                                  style: const TextStyle(
                                      color: CssTheme.textMuted),
                                ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 24),

                  // Team members
                  Row(
                    children: [
                      Text(
                        'Team Members',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _openInviteUserDialog,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Invite user'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_members.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: const Text(
                        'No team members yet.',
                        style: TextStyle(color: CssTheme.textMuted),
                      ),
                    )
                  else
                    ...(_members.map((m) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.black,
                                child: Text(
                                  (m['name'] as String? ?? '?')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m['name'] as String? ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900),
                                    ),
                                    Text(
                                      m['email'] as String? ?? '',
                                      style: const TextStyle(
                                          color: CssTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m['role'] as String? ?? 'management',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))),

                  const SizedBox(height: 24),

                  // Change password
                  Text(
                    'Account',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openChangePasswordDialog,
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Change password'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          bool loading = false;
          return AlertDialog(
            title: const Text('Change Password'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New password'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm password'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        final p1 = passCtrl.text.trim();
                        final p2 = confirmCtrl.text.trim();
                        if (p1.isEmpty || p1 != p2) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Passwords do not match'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setS(() => loading = true);
                        try {
                          await _sb.auth
                              .updateUser(UserAttributes(password: p1));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Password updated')),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        setS(() => loading = false);
                      },
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }
}
