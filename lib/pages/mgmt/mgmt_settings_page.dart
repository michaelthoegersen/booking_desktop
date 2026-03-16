import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart' as smtp;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/email_service.dart';
import '../../state/active_company.dart';

/// Notifier so the sidebar can react to feature-flag changes without restart.
final companyFlagsNotifier = ValueNotifier<Map<String, bool>>({});

class MgmtSettingsPage extends StatefulWidget {
  const MgmtSettingsPage({super.key});

  @override
  State<MgmtSettingsPage> createState() => _MgmtSettingsPageState();
}

class _MgmtSettingsPageState extends State<MgmtSettingsPage> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _company;
  String? get _companyId => activeCompanyNotifier.value?.id;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _showTypes = [];
  bool _showTours = true;
  bool _showBusRequests = true;
  bool _membersExpanded = false;
  bool _showTypesExpanded = false;

  // SMTP accounts
  List<SmtpAccount> _smtpAccounts = [];
  bool _smtpExpanded = false;

  // Tripletex
  final _ttConsumerCtrl = TextEditingController();
  final _ttEmployeeCtrl = TextEditingController();
  bool _ttSaving = false;

  @override
  void initState() {
    super.initState();
    activeCompanyNotifier.addListener(_onCompanyChanged);
    _load();
  }

  @override
  void dispose() {
    activeCompanyNotifier.removeListener(_onCompanyChanged);
    _ttConsumerCtrl.dispose();
    _ttEmployeeCtrl.dispose();
    super.dispose();
  }

  void _onCompanyChanged() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_companyId != null) {
        final company = await _sb
            .from('companies')
            .select('*')
            .eq('id', _companyId!)
            .maybeSingle();
        _company = company;
        _showTours = company?['show_tours'] != false;
        _showBusRequests = company?['show_bus_requests_mgmt'] != false;
        _ttConsumerCtrl.text = company?['tripletex_consumer_token'] as String? ?? '';
        _ttEmployeeCtrl.text = company?['tripletex_employee_token'] as String? ?? '';
        _emitFlags();

        // Load other members in the same company
        final members = await _sb
            .from('profiles')
            .select('id, name, email, role, section')
            .eq('company_id', _companyId!);
        _members = List<Map<String, dynamic>>.from(members);

        final types = await _sb
            .from('show_types')
            .select('*')
            .eq('company_id', _companyId!)
            .eq('active', true)
            .order('sort_order');
        _showTypes = List<Map<String, dynamic>>.from(types);

        _smtpAccounts = await EmailService.loadSmtpAccounts();
      }
    } catch (e) {
      debugPrint('MgmtSettings load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _emitFlags() {
    companyFlagsNotifier.value = {
      'show_tours': _showTours,
      'show_bus_requests_mgmt': _showBusRequests,
    };
  }

  Future<void> _toggleFlag(String column, bool value) async {
    if (_companyId == null) return;
    try {
      await _sb
          .from('companies')
          .update({column: value})
          .eq('id', _companyId!);
      setState(() {
        if (column == 'show_tours') _showTours = value;
        if (column == 'show_bus_requests_mgmt') _showBusRequests = value;
      });
      _emitFlags();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditMemberDialog(
    String memberId, String name, String email, String role, String? section,
  ) {
    final nameCtrl = TextEditingController(text: name);
    final emailCtrl = TextEditingController(text: email);
    final phoneCtrl = TextEditingController();
    const validRoles = {'admin', 'gruppeleder_skarp', 'gruppeleder_bass', 'bruker'};
    String selectedRole = validRoles.contains(role) ? role : 'admin';
    String? selectedSection = section;

    // Load phone separately
    _sb.from('profiles').select('phone').eq('id', memberId).maybeSingle().then(
      (res) {
        phoneCtrl.text = (res?['phone'] ?? '').toString();
      },
    );

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Rediger medlem'),
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
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-post',
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
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Rolle',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                        DropdownMenuItem(
                            value: 'gruppeleder_skarp', child: Text('Gruppeleder Skarp')),
                        DropdownMenuItem(
                            value: 'gruppeleder_bass', child: Text('Gruppeleder Bass')),
                        DropdownMenuItem(
                            value: 'bruker', child: Text('Bruker')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedRole = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedSection,
                      decoration: const InputDecoration(
                        labelText: 'Seksjon',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Ingen seksjon')),
                        DropdownMenuItem(value: 'skarp', child: Text('Skarp')),
                        DropdownMenuItem(value: 'bass', child: Text('Bass')),
                      ],
                      onChanged: (v) {
                        setDialogState(() => selectedSection = v);
                      },
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
                            await _sb.from('profiles').update({
                              'name': nameCtrl.text.trim(),
                              'email': emailCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                              'role': selectedRole,
                              'section': selectedSection,
                            }).eq('id', memberId);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
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
                            strokeWidth: 2, color: Colors.white),
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

  void _confirmRemoveMember(String memberId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fjern medlem'),
        content: Text('Er du sikker på at du vil fjerne $name fra teamet?'),
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
                await _sb
                    .from('company_members')
                    .delete()
                    .eq('user_id', memberId);
                await _sb
                    .from('profiles')
                    .update({'company_id': null})
                    .eq('id', memberId);
                _load();
              } catch (e) {
                if (mounted) {
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

  Future<void> _openInviteUserDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedRole = 'bruker';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Inviter bruker'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Navn'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'E-post'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Rolle'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                        value: 'gruppeleder_skarp', child: Text('Gruppeleder Skarp')),
                    DropdownMenuItem(
                        value: 'gruppeleder_bass', child: Text('Gruppeleder Bass')),
                    DropdownMenuItem(value: 'bruker', child: Text('Bruker')),
                  ],
                  onChanged: (v) {
                    if (v != null) setS(() => selectedRole = v);
                  },
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
                          'Brukeren opprettes med passord: Complete2026',
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
              child: const Text('Avbryt'),
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
                      'role': selectedRole,
                      'company_id': _companyId,
                    },
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Bruker invitert')),
                    );
                  }
                } catch (e) {
                  debugPrint('Invite user error: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Feil: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Inviter'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveTripletexTokens() async {
    if (_companyId == null) return;
    setState(() => _ttSaving = true);
    try {
      await _sb.from('companies').update({
        'tripletex_consumer_token': _ttConsumerCtrl.text.trim().isEmpty
            ? null
            : _ttConsumerCtrl.text.trim(),
        'tripletex_employee_token': _ttEmployeeCtrl.text.trim().isEmpty
            ? null
            : _ttEmployeeCtrl.text.trim(),
      }).eq('id', _companyId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tripletex-tokens lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _ttSaving = false);
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
                    'Innstillinger',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),

                  // Company info
                  Text(
                    'Selskap',
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
                        ? Text(
                            'Ingen selskap koblet til kontoen din.',
                            style: TextStyle(color: cs.onSurfaceVariant),
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
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant),
                                ),
                              if (_company!['phone'] != null)
                                Text(
                                  _company!['phone'] as String,
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant),
                                ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 24),

                  // Team members
                  InkWell(
                    onTap: () => setState(() => _membersExpanded = !_membersExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(
                          _membersExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Teammedlemmer (${_members.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        if (_membersExpanded)
                          FilledButton.icon(
                            onPressed: _openInviteUserDialog,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Inviter bruker'),
                          ),
                      ],
                    ),
                  ),
                  if (_membersExpanded) ...[
                  const SizedBox(height: 12),
                  if (_members.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'Ingen teammedlemmer ennå.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    ...(_members.map((m) {
                      final memberId = m['id'] as String;
                      final memberName = m['name'] as String? ?? '';
                      final memberEmail = m['email'] as String? ?? '';
                      final memberRole = m['role'] as String? ?? 'bruker';
                      final memberSection = m['section'] as String?;

                      return Container(
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
                                  memberName.isNotEmpty
                                      ? memberName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      memberName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900),
                                    ),
                                    Text(
                                      memberEmail,
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              if (memberSection != null)
                                Builder(builder: (_) {
                                  final isBass = memberSection == 'bass';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isBass
                                          ? Colors.teal.shade50
                                          : Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isBass ? 'Bass' : 'Skarp',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isBass
                                            ? Colors.teal.shade700
                                            : Colors.purple.shade700,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                }),
                              if (memberSection != null)
                                const SizedBox(width: 6),
                              Builder(builder: (_) {
                                final Color bg;
                                final Color fg;
                                switch (memberRole) {
                                  case 'admin':
                                    bg = Colors.red.shade50;
                                    fg = Colors.red.shade700;
                                  case 'gruppeleder_skarp':
                                  case 'gruppeleder_bass':
                                    bg = Colors.orange.shade50;
                                    fg = Colors.orange.shade700;
                                  default:
                                    bg = Colors.blue.shade50;
                                    fg = Colors.blue.shade700;
                                }
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    memberRole,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: fg,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Rediger',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: () => _showEditMemberDialog(
                                  memberId, memberName, memberEmail, memberRole, memberSection,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fjern',
                                icon: const Icon(Icons.delete_outline,
                                    size: 20, color: Colors.red),
                                onPressed: () => _confirmRemoveMember(
                                  memberId, memberName,
                                ),
                              ),
                            ],
                          ),
                        );
                    })),
                  ], // end _membersExpanded

                  const SizedBox(height: 24),

                  // Show Types
                  InkWell(
                    onTap: () => setState(() => _showTypesExpanded = !_showTypesExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(
                          _showTypesExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Show-typer (${_showTypes.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        if (_showTypesExpanded)
                          FilledButton.icon(
                            onPressed: _showAddShowTypeDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Legg til show-type'),
                          ),
                      ],
                    ),
                  ),
                  if (_showTypesExpanded) ...[
                  const SizedBox(height: 12),
                  if (_showTypes.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'Ingen show-typer ennå.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    ...(_showTypes.map((st) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      st['name'] as String? ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${st['drummers'] ?? 0} trommeslagere · '
                                      '${st['dancers'] ?? 0} dansere · '
                                      '${st['others'] ?? 0} andre  ·  '
                                      '${_formatPrice(st['price'])} kr',
                                      style: TextStyle(
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _showEditShowTypeDialog(st),
                                child: const Text('Rediger'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _showDeleteShowTypeDialog(st),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.red),
                                child: const Text('Slett'),
                              ),
                            ],
                          ),
                        ))),
                  ], // end _showTypesExpanded

                  if (Supabase.instance.client.auth.currentUser?.email == 'michael@nttas.com') ...[
                  const SizedBox(height: 24),

                  // Features
                  Text(
                    'Funksjoner',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Turnéer'),
                          subtitle: const Text('Vis turnéer i sidemenyen'),
                          value: _showTours,
                          onChanged: (v) => _toggleFlag('show_tours', v),
                        ),
                        SwitchListTile(
                          title: const Text('Bussforespørsler'),
                          subtitle:
                              const Text('Vis bussforespørsler på dashboardet'),
                          value: _showBusRequests,
                          onChanged: (v) =>
                              _toggleFlag('show_bus_requests_mgmt', v),
                        ),
                      ],
                    ),
                  ),
                  ],

                  if (Supabase.instance.client.auth.currentUser?.email == 'michael@nttas.com') ...[
                  const SizedBox(height: 24),

                  // Tripletex integration
                  Text(
                    'Tripletex-integrasjon',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Koble til Tripletex for fakturering og leverandørfakturaer.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _ttConsumerCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Consumer Token',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _ttEmployeeCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Employee Token',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _ttSaving ? null : _saveTripletexTokens,
                          icon: _ttSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save, size: 18),
                          label: const Text('Lagre tokens'),
                        ),
                      ],
                    ),
                  ),
                  ],

                  const SizedBox(height: 24),

                  // SMTP e-post
                  InkWell(
                    onTap: () => setState(() => _smtpExpanded = !_smtpExpanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(
                          _smtpExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 22,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'E-postkonto${_smtpAccounts.isNotEmpty ? ' (${_smtpAccounts.length})' : ''}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        if (_smtpExpanded)
                          FilledButton.icon(
                            onPressed: _showAddSmtpDialog,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Legg til'),
                          ),
                      ],
                    ),
                  ),
                  if (_smtpExpanded) ...[
                    const SizedBox(height: 8),
                    Text(
                      'E-postkonto brukes til å sende tilbud, avtaler og fakturaer. Uten konto brukes standard Microsoft-avsender.',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    if (_smtpAccounts.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          'Ingen e-postkonto konfigurert.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    else
                      ...(_smtpAccounts.map((account) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.email_outlined,
                                    size: 22, color: cs.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        account.email,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                      Text(
                                        '${account.smtpHost}:${account.smtpPort}'
                                        '${account.displayName.isNotEmpty ? '  ·  ${account.displayName}' : ''}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                if (account.isDefault)
                                  Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Standard',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.green),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Slett',
                                  icon: Icon(Icons.delete_outline,
                                      size: 18, color: cs.onSurfaceVariant),
                                  onPressed: () => _deleteSmtpAccount(account),
                                ),
                              ],
                            ),
                          ))),
                  ],

                  const SizedBox(height: 24),

                  // Change password
                  Text(
                    'Konto',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openChangePasswordDialog,
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Endre passord'),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0';
    final d = double.tryParse(price.toString()) ?? 0;
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }

  Future<void> _showAddShowTypeDialog() async {
    final nameCtrl = TextEditingController();
    final drummersCtrl = TextEditingController(text: '0');
    final dancersCtrl = TextEditingController(text: '0');
    final othersCtrl = TextEditingController(text: '0');
    final priceCtrl = TextEditingController(text: '0');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legg til show-type'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Navn'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: drummersCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Trommeslagere'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dancersCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Dansere'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: othersCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Andre'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pris (kr)'),
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
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await _sb.from('show_types').insert({
                  'company_id': _companyId,
                  'name': nameCtrl.text.trim(),
                  'drummers': int.tryParse(drummersCtrl.text) ?? 0,
                  'dancers': int.tryParse(dancersCtrl.text) ?? 0,
                  'others': int.tryParse(othersCtrl.text) ?? 0,
                  'price': double.tryParse(priceCtrl.text) ?? 0,
                  'sort_order': _showTypes.length,
                  'active': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Feil: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Legg til'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditShowTypeDialog(Map<String, dynamic> showType) async {
    final nameCtrl =
        TextEditingController(text: showType['name'] as String? ?? '');
    final drummersCtrl =
        TextEditingController(text: '${showType['drummers'] ?? 0}');
    final dancersCtrl =
        TextEditingController(text: '${showType['dancers'] ?? 0}');
    final othersCtrl =
        TextEditingController(text: '${showType['others'] ?? 0}');
    final priceCtrl =
        TextEditingController(text: _formatPrice(showType['price']));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger show-type'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Navn'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: drummersCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Trommeslagere'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dancersCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Dansere'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: othersCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Andre'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pris (kr)'),
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
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await _sb
                    .from('show_types')
                    .update({
                      'name': nameCtrl.text.trim(),
                      'drummers': int.tryParse(drummersCtrl.text) ?? 0,
                      'dancers': int.tryParse(dancersCtrl.text) ?? 0,
                      'others': int.tryParse(othersCtrl.text) ?? 0,
                      'price': double.tryParse(priceCtrl.text) ?? 0,
                    })
                    .eq('id', showType['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Feil: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteShowTypeDialog(Map<String, dynamic> showType) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett show-type'),
        content: Text(
            'Er du sikker på at du vil slette "${showType['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _sb
          .from('show_types')
          .update({'active': false})
          .eq('id', showType['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
            title: const Text('Endre passord'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Nytt passord'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Bekreft passord'),
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
                onPressed: loading
                    ? null
                    : () async {
                        final p1 = passCtrl.text.trim();
                        final p2 = confirmCtrl.text.trim();
                        if (p1.isEmpty || p1 != p2) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Passordene stemmer ikke overens'),
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
                                  content: Text('Passord oppdatert')),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Feil: $e'),
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
                    : const Text('Oppdater'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------
  // SMTP account management
  // --------------------------------------------------

  Future<void> _showAddSmtpDialog() async {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final hostCtrl = TextEditingController(text: 'smtp.domeneshop.no');
    final portCtrl = TextEditingController(text: '587');
    final displayNameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool saving = false;
        bool testOk = false;
        String? testError;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Legg til e-postkonto'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-postadresse',
                        hintText: 'f.eks. economy@completedrums.no',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Passord',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: displayNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Visningsnavn (valgfritt)',
                        hintText: 'f.eks. Complete Drums',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: hostCtrl,
                            decoration: const InputDecoration(
                              labelText: 'SMTP-server',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: portCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    if (testOk) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green, size: 18),
                            SizedBox(width: 8),
                            Text('Tilkobling vellykket!',
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    if (testError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(testError!,
                                  style: const TextStyle(color: Colors.red, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Avbryt'),
                ),
                OutlinedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() {
                            saving = true;
                            testOk = false;
                            testError = null;
                          });
                          try {
                            final port = int.tryParse(portCtrl.text) ?? 587;
                            final server = smtp.SmtpServer(
                              hostCtrl.text.trim(),
                              port: port,
                              username: emailCtrl.text.trim(),
                              password: passwordCtrl.text,
                              ssl: port == 465,
                              ignoreBadCertificate: true,
                              allowInsecure: true,
                            );
                            await mailer.checkCredentials(server);
                            setDialogState(() {
                              testOk = true;
                              saving = false;
                            });
                          } catch (e) {
                            setDialogState(() {
                              testError = e.toString();
                              saving = false;
                            });
                          }
                        },
                  child: const Text('Test tilkobling'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: const Text('Lagre'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    if (emailCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) return;

    try {
      final isFirst = _smtpAccounts.isEmpty;
      await _sb.from('smtp_accounts').insert({
        'user_id': _sb.auth.currentUser!.id,
        'company_id': _companyId,
        'email': emailCtrl.text.trim(),
        'display_name': displayNameCtrl.text.trim(),
        'smtp_host': hostCtrl.text.trim(),
        'smtp_port': int.tryParse(portCtrl.text) ?? 587,
        'password': passwordCtrl.text,
        'is_default': isFirst,
      });
      EmailService.clearSmtpCache();
      _smtpAccounts = await EmailService.loadSmtpAccounts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  Future<void> _deleteSmtpAccount(SmtpAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett e-postkonto?'),
        content: Text('Fjern ${account.email} fra listen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _sb.from('smtp_accounts').delete().eq('id', account.id);
      EmailService.clearSmtpCache();
      _smtpAccounts = await EmailService.loadSmtpAccounts();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }
}
