import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile_field.dart';
import '../../services/email_service.dart';
import '../../services/profile_field_service.dart';
import '../../state/active_company.dart';
import '../../state/role_labels.dart';
import '../inventory/show_equipment_dialog.dart';

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

  /// Members who asked for a new password from the login screen.
  List<Map<String, dynamic>> _resetRequests = [];
  List<Map<String, dynamic>> _showTypes = [];
  List<Map<String, dynamic>> _riders = [];
  bool _showTours = true;
  bool _showBusRequests = true;
  bool _membersExpanded = false;
  bool _showTypesExpanded = false;
  bool _rolesExpanded = false;

  // Role label controllers (per-company overrides for the 3 crew slots)
  final _role1Ctrl = TextEditingController();
  final _role2Ctrl = TextEditingController();
  final _role3Ctrl = TextEditingController();
  bool _rolesSaving = false;

  // Contract config controllers
  bool _contractExpanded = false;
  final _ctrContactCtrl = TextEditingController();
  final _ctrPhoneCtrl = TextEditingController();
  final _ctrEmailCtrl = TextEditingController();
  final _ctrSigLabelCtrl = TextEditingController();
  final _ctrShowLabelCtrl = TextEditingController();

  // Per-language title + body, keyed by locale code.
  final Map<String, ({String title, String body})> _contractTranslations = {};
  // Currently-selected language in the editor.
  String _ctrEditingLang = 'no';
  final _ctrTitleCtrl = TextEditingController();
  final _ctrBodyCtrl = TextEditingController();
  bool _contractSaving = false;

  // Supported languages for contract translations
  static const List<({String code, String label})> _kContractLangs = [
    (code: 'no', label: 'Norsk'),
    (code: 'en', label: 'English'),
    (code: 'sv', label: 'Svenska'),
    (code: 'da', label: 'Dansk'),
    (code: 'de', label: 'Deutsch'),
    (code: 'fr', label: 'Français'),
    (code: 'es', label: 'Español'),
  ];
  bool _ridersExpanded = false;
  bool _pricingExpanded = false;

  // Pricing defaults (per company)
  late final _creoCtrl = TextEditingController();
  late final _extraShowCtrl = TextEditingController();
  late final _markupCtrl = TextEditingController();
  late final _inearCtrl = TextEditingController();
  late final _krKmCtrl = TextEditingController();
  late final _hyreDayRateCtrl = TextEditingController();
  late final _hyreInclKmCtrl = TextEditingController();
  late final _hyreExtraKmRateCtrl = TextEditingController();

  // SMTP accounts
  List<SmtpAccount> _smtpAccounts = [];
  bool _smtpExpanded = false;

  // Tripletex
  final _ttConsumerCtrl = TextEditingController();
  final _ttEmployeeCtrl = TextEditingController();
  bool _ttSaving = false;

  // Tab index for grouped settings UI
  int _tabIndex = 0;

  // Profile fields (members fill in via mobile app)
  List<ProfileField> _profileFields = [];
  bool _profileFieldsExpanded = false;
  final Set<String> _expandedProfileSections = {};

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
    _role1Ctrl.dispose();
    _role2Ctrl.dispose();
    _role3Ctrl.dispose();
    _ctrContactCtrl.dispose();
    _ctrPhoneCtrl.dispose();
    _ctrEmailCtrl.dispose();
    _ctrSigLabelCtrl.dispose();
    _ctrShowLabelCtrl.dispose();
    _ctrTitleCtrl.dispose();
    _ctrBodyCtrl.dispose();
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
        _ttConsumerCtrl.text =
            company?['tripletex_consumer_token'] as String? ?? '';
        _ttEmployeeCtrl.text =
            company?['tripletex_employee_token'] as String? ?? '';
        final labels = RoleLabels.fromJson(
          company?['role_labels'] as Map<String, dynamic>?,
        );
        _role1Ctrl.text = labels.role1;
        _role2Ctrl.text = labels.role2;
        _role3Ctrl.text = labels.role3;

        // Contract config
        final ctr = company?['contract_config'] as Map<String, dynamic>? ?? {};
        _ctrContactCtrl.text = (ctr['header_contact_name'] as String?) ?? '';
        _ctrPhoneCtrl.text = (ctr['header_phone'] as String?) ?? '';
        _ctrEmailCtrl.text = (ctr['header_email'] as String?) ?? '';
        _ctrSigLabelCtrl.text = (ctr['signature_label'] as String?) ?? '';
        _ctrShowLabelCtrl.text = (ctr['show_label'] as String?) ?? '';

        _contractTranslations.clear();
        final rawTrans = ctr['translations'];
        if (rawTrans is Map) {
          rawTrans.forEach((k, v) {
            if (k is String && v is Map) {
              _contractTranslations[k] = (
                title: (v['title'] as String?) ?? '',
                body: (v['body'] as String?) ?? '',
              );
            }
          });
        }
        // Ensure at least the default language slot exists for editing
        if (!_contractTranslations.containsKey(_ctrEditingLang)) {
          _contractTranslations[_ctrEditingLang] = (title: '', body: '');
        }
        final cur = _contractTranslations[_ctrEditingLang]!;
        _ctrTitleCtrl.text = cur.title;
        _ctrBodyCtrl.text = cur.body;

        _emitFlags();

        // Load other members in the same company
        final members = await _sb
            .from('profiles')
            .select('id, name, email, role, section')
            .eq('company_id', _companyId!);
        _members = List<Map<String, dynamic>>.from(members);

        try {
          final reqs = await _sb
              .from('password_reset_requests')
              .select('id, email, user_id, requested_at')
              .eq('company_id', _companyId!)
              .eq('status', 'pending')
              .order('requested_at', ascending: false);
          _resetRequests = List<Map<String, dynamic>>.from(reqs);
        } catch (e) {
          debugPrint('Load reset requests: $e');
        }

        final types = await _sb
            .from('show_types')
            .select('*')
            .eq('company_id', _companyId!)
            .eq('active', true)
            .order('sort_order');
        _showTypes = List<Map<String, dynamic>>.from(types);

        try {
          final riders = await _sb
              .from('company_riders')
              .select('*')
              .eq('company_id', _companyId!)
              .eq('active', true)
              .order('sort_order');
          _riders = List<Map<String, dynamic>>.from(riders);
        } catch (_) {}

        _smtpAccounts =
            await EmailService.loadSmtpAccounts(companyId: _companyId);

        _profileFields = await ProfileFieldService.loadAll(_companyId!);

        // Load pricing defaults
        final pd = company?['pricing_defaults'] as Map<String, dynamic>? ?? {};
        _creoCtrl.text = (pd['creo_fee_minimum'] ?? 5500).toString();
        _extraShowCtrl.text = (pd['extra_show_fee'] ?? 1500).toString();
        _markupCtrl.text =
            (((pd['markup_pct'] ?? 0.25) as num) * 100).toString();
        _inearCtrl.text = (pd['inear_price'] ?? 7000).toString();
        _krKmCtrl.text = (pd['transport_price_per_km'] ?? 3.50).toString();
        _hyreDayRateCtrl.text = (pd['hyre_day_rate'] ?? 399).toString();
        _hyreInclKmCtrl.text = (pd['hyre_included_km'] ?? 150).toString();
        _hyreExtraKmRateCtrl.text =
            (pd['hyre_extra_km_rate'] ?? 3.50).toString();
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
      await _sb.from('companies').update({column: value}).eq('id', _companyId!);
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

  Future<void> _dismissResetRequest(Map<String, dynamic> req) async {
    try {
      await _sb.from('password_reset_requests').update({
        'status': 'dismissed',
        'handled_at': DateTime.now().toUtc().toIso8601String(),
        'handled_by': _sb.auth.currentUser?.id,
      }).eq('id', req['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  /// Set a new password for a locked-out member and close the request.
  /// The password is shown once so it can be passed on — the app has no way to
  /// email it.
  /// Set a new password for a member. [req] is the pending request row when
  /// this came from the "Ber om nytt passord" list; it is null when an admin
  /// resets a password directly from the member list, which is the case when
  /// someone is locked out and cannot reach the login screen to ask.
  Future<void> _setPasswordFor(
    Map<String, dynamic>? req, {
    String? memberId,
    String? memberEmail,
  }) async {
    final userId = (req?['user_id'] as String?) ?? memberId;
    final label = (req?['email'] as String?) ?? memberEmail ?? '';
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fant ikke brukeren.')),
      );
      return;
    }

    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sett nytt passord'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nytt passord',
                helperText: 'Minst 8 tegn. Gi det videre til medlemmet.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Sett passord'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (pw == null || pw.isEmpty || !mounted) return;
    if (pw.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passordet må være minst 8 tegn.')),
      );
      return;
    }

    try {
      final res = await _sb.functions.invoke(
        'reset-password',
        body: {'user_id': userId, 'password': pw},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }

      if (req != null) {
        await _sb.from('password_reset_requests').update({
          'status': 'handled',
          'handled_at': DateTime.now().toUtc().toIso8601String(),
          'handled_by': _sb.auth.currentUser?.id,
        }).eq('id', req['id']);
      }

      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Passord satt for $label. Gi det videre.'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditMemberDialog(
    String memberId,
    String name,
    String email,
    String role,
    String? section,
  ) {
    final nameCtrl = TextEditingController(text: name);
    final emailCtrl = TextEditingController(text: email);
    final phoneCtrl = TextEditingController();
    const validRoles = {
      'admin',
      'gruppeleder_skarp',
      'gruppeleder_bass',
      'bruker'
    };
    String selectedRole = validRoles.contains(role) ? role : 'admin';
    String? selectedSection = section;
    // Økonomiansvarlig is a flag rather than a role, so an admin keeps admin.
    // Loaded alongside phone below and applied through setDialogState.
    bool isFinance = false;
    void Function(void Function())? applyLoaded;

    // Load phone separately
    _sb
        .from('profiles')
        .select('phone, is_finance')
        .eq('id', memberId)
        .maybeSingle()
        .then(
      (res) {
        phoneCtrl.text = (res?['phone'] ?? '').toString();
        isFinance = res?['is_finance'] == true;
        applyLoaded?.call(() {});
      },
    );

    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Lets the async profile load above refresh the checkbox once the
            // is_finance value arrives.
            applyLoaded = setDialogState;
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
                            value: 'gruppeleder_skarp',
                            child: Text('Gruppeleder Skarp')),
                        DropdownMenuItem(
                            value: 'gruppeleder_bass',
                            child: Text('Gruppeleder Bass')),
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
                        DropdownMenuItem(
                            value: null, child: Text('Ingen seksjon')),
                        DropdownMenuItem(value: 'skarp', child: Text('Skarp')),
                        DropdownMenuItem(value: 'bass', child: Text('Bass')),
                      ],
                      onChanged: (v) {
                        setDialogState(() => selectedSection = v);
                      },
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      value: isFinance,
                      onChanged: (v) =>
                          setDialogState(() => isFinance = v ?? false),
                      title: const Text('Økonomiansvarlig'),
                      subtitle: const Text(
                        'Får varsel når et tilbud meldes klart for fakturering, '
                        'og er den eneste som kan låse det opp igjen.',
                        style: TextStyle(fontSize: 11),
                      ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ],
                ),
              ),
              // Puts "Sett nytt passord" on the left and Avbryt/Lagre on the
              // right. A Spacer cannot do this: actions sit in an OverflowBar,
              // which is not a Flex, so the Spacer blew the dialog up to fill
              // the screen.
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                // Reset without waiting for a request — someone locked out of
                // an old app version cannot reach "Glemt passord?" at all.
                TextButton.icon(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _setPasswordFor(
                            null,
                            memberId: memberId,
                            memberEmail: emailCtrl.text.trim().isNotEmpty
                                ? emailCtrl.text.trim()
                                : name,
                          );
                        },
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('Sett nytt passord'),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                                  'is_finance': isFinance,
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
                    .update({'company_id': null}).eq('id', memberId);
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
                        value: 'gruppeleder_skarp',
                        child: Text('Gruppeleder Skarp')),
                    DropdownMenuItem(
                        value: 'gruppeleder_bass',
                        child: Text('Gruppeleder Bass')),
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
                      const SnackBar(content: Text('Bruker invitert')),
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

  /// Persist the currently-edited language to the in-memory translations
  /// map. Call before switching languages or saving.
  void _stashCurrentTranslation() {
    _contractTranslations[_ctrEditingLang] = (
      title: _ctrTitleCtrl.text,
      body: _ctrBodyCtrl.text,
    );
  }

  void _switchContractLang(String code) {
    _stashCurrentTranslation();
    final next = _contractTranslations[code] ?? (title: '', body: '');
    setState(() {
      _ctrEditingLang = code;
      _ctrTitleCtrl.text = next.title;
      _ctrBodyCtrl.text = next.body;
    });
  }

  Future<void> _saveContractConfig() async {
    if (_companyId == null) return;
    _stashCurrentTranslation();
    setState(() => _contractSaving = true);
    try {
      // Only include languages with at least title or body content.
      final translationsMap = <String, Map<String, String>>{};
      _contractTranslations.forEach((code, t) {
        if (t.title.trim().isNotEmpty || t.body.trim().isNotEmpty) {
          translationsMap[code] = {
            'title': t.title.trim(),
            'body': t.body,
          };
        }
      });
      final payload = {
        'header_contact_name': _ctrContactCtrl.text.trim(),
        'header_phone': _ctrPhoneCtrl.text.trim(),
        'header_email': _ctrEmailCtrl.text.trim(),
        'signature_label': _ctrSigLabelCtrl.text.trim(),
        'show_label': _ctrShowLabelCtrl.text.trim(),
        'translations': translationsMap,
      };
      await _sb
          .from('companies')
          .update({'contract_config': payload}).eq('id', _companyId!);
      _company?['contract_config'] = payload;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kontrakt-innstillinger lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _contractSaving = false);
    }
  }

  Future<void> _saveRoleLabels() async {
    if (_companyId == null) return;
    final r1 = _role1Ctrl.text.trim();
    final r2 = _role2Ctrl.text.trim();
    final r3 = _role3Ctrl.text.trim();
    if (r1.isEmpty || r2.isEmpty || r3.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alle tre etiketter må fylles ut')),
      );
      return;
    }
    setState(() => _rolesSaving = true);
    try {
      final labels = {'role1': r1, 'role2': r2, 'role3': r3};
      await _sb
          .from('companies')
          .update({'role_labels': labels}).eq('id', _companyId!);
      _company?['role_labels'] = labels;
      await roleLabelsNotifier.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Roller lagret')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _rolesSaving = false);
    }
  }

  Future<void> _savePricingDefault(String key, String value,
      {bool isPct = false, bool isDecimal = false}) async {
    if (_companyId == null) return;
    try {
      final current =
          _company?['pricing_defaults'] as Map<String, dynamic>? ?? {};
      double? numVal;
      if (isPct) {
        numVal = (double.tryParse(value) ?? 0) / 100;
      } else if (isDecimal) {
        numVal = double.tryParse(value.replaceAll(',', '.'));
      } else {
        numVal = double.tryParse(value);
      }
      if (numVal == null) return;
      current[key] = numVal;
      await _sb
          .from('companies')
          .update({'pricing_defaults': current}).eq('id', _companyId!);
      _company?['pricing_defaults'] = current;
    } catch (e) {
      debugPrint('Save pricing default error: $e');
    }
  }

  Widget _pricingField(String label, TextEditingController ctrl, String key,
      {bool isPct = false, bool isDecimal = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                suffixText: isPct ? '%' : null,
              ),
              onSubmitted: (v) async {
                await _savePricingDefault(key, v,
                    isPct: isPct, isDecimal: isDecimal);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Lagret'),
                        duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Innstillinger',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Generelt')),
                      ButtonSegment(value: 1, label: Text('Booking & priser')),
                      ButtonSegment(value: 2, label: Text('Integrasjoner')),
                      ButtonSegment(value: 3, label: Text('Profilfelt')),
                    ],
                    selected: {_tabIndex},
                    onSelectionChanged: (s) =>
                        setState(() => _tabIndex = s.first),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_tabIndex == 0) ...[
                          // Company info
                          Text(
                            'Selskap',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
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
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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

                          // Members locked out of the app. Shown above the member list
                          // because it is the one thing here that needs acting on.
                          if (_resetRequests.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        Colors.orange.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.lock_reset,
                                          size: 18, color: Colors.orange),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Ber om nytt passord (${_resetRequests.length})',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.orange),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ..._resetRequests.map((r) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      r['email'] as String? ??
                                                          '',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                  if (r['requested_at'] != null)
                                                    Text(
                                                      DateFormat(
                                                              'dd.MM.yyyy HH:mm')
                                                          .format(DateTime.parse(
                                                                  r['requested_at']
                                                                      .toString())
                                                              .toLocal()),
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: cs
                                                              .onSurfaceVariant),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _dismissResetRequest(r),
                                              child: const Text('Avvis'),
                                            ),
                                            const SizedBox(width: 4),
                                            FilledButton(
                                              onPressed: () =>
                                                  _setPasswordFor(r),
                                              child: const Text(
                                                  'Sett nytt passord'),
                                            ),
                                          ],
                                        ),
                                      )),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Team members
                          InkWell(
                            onTap: () => setState(
                                () => _membersExpanded = !_membersExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                  _membersExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
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
                                final memberRole =
                                    m['role'] as String? ?? 'bruker';
                                final memberSection = m['section'] as String?;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(14),
                                    border:
                                        Border.all(color: cs.outlineVariant),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.black,
                                        child: Text(
                                          memberName.isNotEmpty
                                              ? memberName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                          final isBass =
                                              memberSection == 'bass';
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isBass
                                                  ? Colors.teal.shade50
                                                  : Colors.purple.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(999),
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
                                            borderRadius:
                                                BorderRadius.circular(999),
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
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 20),
                                        onPressed: () => _showEditMemberDialog(
                                          memberId,
                                          memberName,
                                          memberEmail,
                                          memberRole,
                                          memberSection,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Fjern',
                                        icon: const Icon(Icons.delete_outline,
                                            size: 20, color: Colors.red),
                                        onPressed: () => _confirmRemoveMember(
                                          memberId,
                                          memberName,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              })),
                          ], // end _membersExpanded

                          const SizedBox(height: 24),

                          // Roles (labels for the 3 crew slots)
                          InkWell(
                            onTap: () => setState(
                                () => _rolesExpanded = !_rolesExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                  _rolesExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 22,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Roller',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                          if (_rolesExpanded) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Navngi de tre crew-kategoriene som brukes i show-typer, '
                              'gigs og tilbud. F.eks. "Musikere", "Teknikere", "Andre".',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _role1Ctrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Rolle 1',
                                      hintText: 'Trommeslagere',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _role2Ctrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Rolle 2',
                                      hintText: 'Dansere',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _role3Ctrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Rolle 3',
                                      hintText: 'Andre',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed:
                                    _rolesSaving ? null : _saveRoleLabels,
                                icon: _rolesSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.save),
                                label: const Text('Lagre roller'),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ], // end Generelt (part 1)

                        if (_tabIndex == 1) ...[
                          // Contract config
                          InkWell(
                            onTap: () => setState(
                                () => _contractExpanded = !_contractExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                  _contractExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 22,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Kontrakt',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                          if (_contractExpanded) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Tilpass kontraktens tittel, header-info, avtaletekst og '
                              'signatur-etikett for dette selskapet. I avtaleteksten '
                              'kan du bruke {us}, {firma}, {kontaktperson} og '
                              '{spillested} som flettefelt.',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Header (vises øverst i kontrakten — selskapsnavn og adresse hentes fra selskapets info)',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _ctrContactCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Kontaktperson',
                                prefixIcon: Icon(Icons.person),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _ctrPhoneCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Telefon',
                                      prefixIcon: Icon(Icons.phone),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _ctrEmailCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'E-post',
                                      prefixIcon: Icon(Icons.email),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // ── Per-language title + body ───────────────────────
                            Row(
                              children: [
                                Text(
                                  'Tittel og avtaletekst',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: cs.onSurface,
                                      fontSize: 14),
                                ),
                                const Spacer(),
                                Text('Språk:',
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 12)),
                                const SizedBox(width: 8),
                                DropdownButton<String>(
                                  value: _ctrEditingLang,
                                  onChanged: (v) {
                                    if (v != null) _switchContractLang(v);
                                  },
                                  items: _kContractLangs.map((l) {
                                    final hasContent =
                                        _contractTranslations[l.code] != null &&
                                            ((_contractTranslations[l.code]!
                                                    .title
                                                    .isNotEmpty) ||
                                                (_contractTranslations[l.code]!
                                                    .body
                                                    .isNotEmpty));
                                    return DropdownMenuItem(
                                      value: l.code,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(l.label),
                                          if (hasContent) ...[
                                            const SizedBox(width: 6),
                                            Icon(Icons.check_circle,
                                                size: 14,
                                                color: Colors.green.shade600),
                                          ],
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'La feltene stå tomme for språk du ikke vil støtte. '
                              'Flettefelt: {us} {firma} {kontaktperson} {spillested}',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _ctrTitleCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Tittel',
                                hintText:
                                    'F.eks. KONTRAKT / CONTRACT / KONTRAKT',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _ctrBodyCtrl,
                              maxLines: 10,
                              decoration: const InputDecoration(
                                labelText: 'Avtaletekst',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _ctrSigLabelCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Signatur-etikett',
                                      hintText: 'F.eks. For Complete Drums',
                                      helperText: 'Tom = "For <selskapsnavn>"',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _ctrShowLabelCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Show-etikett i prisliste',
                                      hintText: 'F.eks. Completeshow',
                                      helperText: 'Tom = selskapsnavn',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _contractSaving
                                    ? null
                                    : _saveContractConfig,
                                icon: _contractSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.save),
                                label:
                                    const Text('Lagre kontrakt-innstillinger'),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Show Types
                          InkWell(
                            onTap: () => setState(
                                () => _showTypesExpanded = !_showTypesExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                  _showTypesExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
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
                                      border:
                                          Border.all(color: cs.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                st['name'] as String? ?? '',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900),
                                              ),
                                              const SizedBox(height: 4),
                                              ValueListenableBuilder<
                                                  RoleLabels>(
                                                valueListenable:
                                                    roleLabelsNotifier,
                                                builder: (_, labels, __) {
                                                  final drummers =
                                                      (st['drummers'] as num?)
                                                              ?.toInt() ??
                                                          0;
                                                  final dancers =
                                                      (st['dancers'] as num?)
                                                              ?.toInt() ??
                                                          0;
                                                  final others =
                                                      (st['others'] as num?)
                                                              ?.toInt() ??
                                                          0;
                                                  final isCustom =
                                                      st['price_is_custom'] ==
                                                          true;
                                                  final creo = double.tryParse(
                                                          _creoCtrl.text) ??
                                                      5500;
                                                  final autoPrice = (drummers +
                                                          dancers +
                                                          others) *
                                                      creo;
                                                  final display = isCustom
                                                      ? '${_formatPrice(st['price'])} kr'
                                                      : 'auto · ${_formatPrice(autoPrice)} kr';
                                                  return Text(
                                                    '$drummers ${labels.role1.toLowerCase()} · '
                                                    '$dancers ${labels.role2.toLowerCase()} · '
                                                    '$others ${labels.role3.toLowerCase()}  ·  '
                                                    '$display',
                                                    style: TextStyle(
                                                        color:
                                                            cs.onSurfaceVariant,
                                                        fontStyle: isCustom
                                                            ? FontStyle.normal
                                                            : FontStyle.italic),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () =>
                                              showFixedShowEquipmentDialog(
                                            context,
                                            showTypeId: st['id'] as String,
                                            showName:
                                                st['name'] as String? ?? '',
                                          ),
                                          icon: const Icon(
                                              Icons.inventory_2_outlined,
                                              size: 16),
                                          label: const Text('Utstyr'),
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

                          const SizedBox(height: 24),

                          // Riders (PDF-vedlegg for avtaler)
                          InkWell(
                            onTap: () => setState(
                                () => _ridersExpanded = !_ridersExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                  _ridersExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 22,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Riders / vedlegg (${_riders.length})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const Spacer(),
                                if (_ridersExpanded) ...[
                                  OutlinedButton.icon(
                                    onPressed: _addTextRider,
                                    icon:
                                        const Icon(Icons.text_snippet_outlined),
                                    label: const Text('Ny tekst-rider'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: _uploadRider,
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Last opp PDF'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_ridersExpanded) ...[
                            const SizedBox(height: 4),
                            Text(
                              'PDFer eller tekst-ridere som kan vedlegges intensjonsavtaler. Tekst-ridere genererer en PDF dynamisk basert på antall i showet.',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
                            if (_riders.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cs.outlineVariant),
                                ),
                                child: Text(
                                  'Ingen riders lastet opp ennå.',
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                              )
                            else
                              ...(_riders.map((r) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(14),
                                      border:
                                          Border.all(color: cs.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          (r['file_path'] as String? ?? '')
                                                  .isEmpty
                                              ? Icons.text_snippet_outlined
                                              : Icons.picture_as_pdf,
                                          size: 20,
                                          color:
                                              (r['file_path'] as String? ?? '')
                                                      .isEmpty
                                                  ? Colors.blueGrey
                                                  : Colors.red,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r['name'] as String? ?? '',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900),
                                              ),
                                              if ((r['show_match'] as String? ??
                                                      '')
                                                  .isNotEmpty)
                                                Text(
                                                  'Auto-vedlegg ved show: ${r['show_match']}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          cs.onSurfaceVariant),
                                                ),
                                              if ((r['quantity_source']
                                                          as String? ??
                                                      '')
                                                  .isNotEmpty)
                                                Text(
                                                  'Antall: ${_riderQuantityLabel(r)}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          cs.onSurfaceVariant),
                                                ),
                                              if (r['always_attach'] == true)
                                                const Text(
                                                  'Alltid vedlagt',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.green),
                                                ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => _editRider(r),
                                          child: const Text('Rediger'),
                                        ),
                                        TextButton(
                                          onPressed: () => _deleteRider(r),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.red),
                                          child: const Text('Slett'),
                                        ),
                                      ],
                                    ),
                                  ))),
                          ], // end _ridersExpanded

                          const SizedBox(height: 24),

                          // Pricing defaults
                          InkWell(
                            onTap: () => setState(
                                () => _pricingExpanded = !_pricingExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                    _pricingExpanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 22),
                                const SizedBox(width: 4),
                                Text(
                                  'Prisparametre (standardverdier)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                          if (_pricingExpanded) ...[
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
                                      'Disse verdiene brukes som standard i nye tilbud. De kan overstyres per tilbud.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 12),
                                  _pricingField('CREO-honorar per utøver',
                                      _creoCtrl, 'creo_fee_minimum'),
                                  _pricingField('Tillegg per ekstrashow',
                                      _extraShowCtrl, 'extra_show_fee'),
                                  _pricingField(
                                      'Påslag %', _markupCtrl, 'markup_pct',
                                      isPct: true),
                                  _pricingField(
                                      'In-ear pris', _inearCtrl, 'inear_price'),
                                  _pricingField('Transport kr/km', _krKmCtrl,
                                      'transport_price_per_km',
                                      isDecimal: true),
                                  const Divider(height: 16),
                                  Text('Hyre varebil',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: cs.onSurfaceVariant)),
                                  const SizedBox(height: 8),
                                  _pricingField('Dagspris', _hyreDayRateCtrl,
                                      'hyre_day_rate'),
                                  _pricingField('Inkl. km/dag', _hyreInclKmCtrl,
                                      'hyre_included_km'),
                                  _pricingField(
                                      'Extra kr/km',
                                      _hyreExtraKmRateCtrl,
                                      'hyre_extra_km_rate',
                                      isDecimal: true),
                                ],
                              ),
                            ),
                          ],
                        ], // end Booking & priser

                        if (_tabIndex == 0) ...[
                          if (Supabase
                                  .instance.client.auth.currentUser?.email ==
                              'michael@nttas.com') ...[
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    title: const Text('Turnéer'),
                                    subtitle:
                                        const Text('Vis turnéer i sidemenyen'),
                                    value: _showTours,
                                    onChanged: (v) =>
                                        _toggleFlag('show_tours', v),
                                  ),
                                  SwitchListTile(
                                    title: const Text('Bussforespørsler'),
                                    subtitle: const Text(
                                        'Vis bussforespørsler på dashboardet'),
                                    value: _showBusRequests,
                                    onChanged: (v) => _toggleFlag(
                                        'show_bus_requests_mgmt', v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ], // end Generelt (part 2: Funksjoner)

                        if (_tabIndex == 2) ...[
                          if (Supabase
                                  .instance.client.auth.currentUser?.email ==
                              'michael@nttas.com') ...[
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
                                    style:
                                        TextStyle(color: cs.onSurfaceVariant),
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
                                    onPressed:
                                        _ttSaving ? null : _saveTripletexTokens,
                                    icon: _ttSaving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white),
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
                            onTap: () =>
                                setState(() => _smtpExpanded = !_smtpExpanded),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                Icon(
                                  _smtpExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
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
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant),
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
                                      border:
                                          Border.all(color: cs.outlineVariant),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.email_outlined,
                                            size: 22,
                                            color: cs.onSurfaceVariant),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                account.email,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900),
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
                                            margin:
                                                const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.green
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
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
                                              size: 18,
                                              color: cs.onSurfaceVariant),
                                          onPressed: () =>
                                              _deleteSmtpAccount(account),
                                        ),
                                      ],
                                    ),
                                  ))),
                          ],
                        ], // end Integrasjoner

                        if (_tabIndex == 3) ...[
                          // Profile fields
                          _buildProfileFieldsSection(cs),
                        ], // end Profilfelt

                        if (_tabIndex == 0) ...[
                          const SizedBox(height: 24),

                          // Change password
                          Text(
                            'Konto',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _openChangePasswordDialog,
                            icon: const Icon(Icons.lock_reset),
                            label: const Text('Endre passord'),
                          ),
                        ], // end Generelt (part 3: Konto)
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // =====================================================
  // PROFILE FIELDS
  // =====================================================

  List<ProfileField> get _profileSections =>
      _profileFields.where((f) => f.isSection).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<ProfileField> _profileChildrenOf(String sectionId) =>
      _profileFields.where((f) => f.parentId == sectionId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Widget _buildProfileFieldsSection(ColorScheme cs) {
    final sections = _profileSections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _profileFieldsExpanded = !_profileFieldsExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Icon(
                _profileFieldsExpanded ? Icons.expand_less : Icons.expand_more,
                size: 22,
              ),
              const SizedBox(width: 4),
              Text(
                'Profilfelt (${sections.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (_profileFieldsExpanded)
                FilledButton.icon(
                  onPressed: _addProfileSection,
                  icon: const Icon(Icons.add),
                  label: const Text('Ny hovedbolk'),
                ),
            ],
          ),
        ),
        if (_profileFieldsExpanded) ...[
          const SizedBox(height: 4),
          Text(
            'Definer hva medlemmene skal fylle ut i profilen sin (i mobilappen).',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 12),
          if (sections.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                'Ingen bolker definert ennå.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...sections.map((s) => _buildProfileSectionCard(s, cs)),
        ],
      ],
    );
  }

  Widget _buildProfileSectionCard(ProfileField section, ColorScheme cs) {
    final children = _profileChildrenOf(section.id);
    final expanded = _expandedProfileSections.contains(section.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              if (expanded) {
                _expandedProfileSections.remove(section.id);
              } else {
                _expandedProfileSections.add(section.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${children.length} felt',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  IconButton(
                    tooltip: 'Endre',
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _editProfileSection(section),
                  ),
                  IconButton(
                    tooltip: 'Slett',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteProfileField(section),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            if (children.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Ingen underbolker.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              )
            else
              ...children.map((c) => _buildProfileFieldRow(c, cs)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: OutlinedButton.icon(
                onPressed: () => _addProfileField(section),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Legg til underbolk'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileFieldRow(ProfileField f, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title),
                const SizedBox(height: 2),
                Text(
                  f.type.label + (f.required ? ' • påkrevd' : ''),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Endre',
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _editProfileField(f),
          ),
          IconButton(
            tooltip: 'Slett',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _deleteProfileField(f),
          ),
        ],
      ),
    );
  }

  Future<void> _addProfileSection() async {
    if (_companyId == null) return;
    final title = await _promptProfileText(
      title: 'Ny hovedbolk',
      label: 'Navn på bolk',
    );
    if (title == null || title.trim().isEmpty) return;

    final sections = _profileSections;
    final nextOrder = sections.isEmpty
        ? 0
        : sections.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    try {
      final created = await ProfileFieldService.insert(ProfileField(
        id: '',
        companyId: _companyId!,
        parentId: null,
        title: title.trim(),
        type: ProfileFieldType.section,
        sortOrder: nextOrder,
      ));
      if (created != null && mounted) {
        setState(() {
          _profileFields.add(created);
          _expandedProfileSections.add(created.id);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Klarte ikke å legge til bolk: $e')),
        );
      }
    }
  }

  Future<void> _addProfileField(ProfileField section) async {
    if (_companyId == null) return;
    final result = await _showProfileFieldDialog();
    if (result == null) return;

    final children = _profileChildrenOf(section.id);
    final nextOrder = children.isEmpty
        ? 0
        : children.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    try {
      final created = await ProfileFieldService.insert(ProfileField(
        id: '',
        companyId: _companyId!,
        parentId: section.id,
        title: result.title,
        type: result.type,
        options: result.options,
        required: result.required,
        sortOrder: nextOrder,
      ));
      if (created != null && mounted) {
        setState(() => _profileFields.add(created));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Klarte ikke å legge til felt: $e')),
        );
      }
    }
  }

  Future<void> _editProfileSection(ProfileField section) async {
    final newTitle = await _promptProfileText(
      title: 'Endre bolk',
      label: 'Navn på bolk',
      initial: section.title,
    );
    if (newTitle == null || newTitle.trim().isEmpty) return;
    final updated = ProfileField(
      id: section.id,
      companyId: section.companyId,
      parentId: null,
      title: newTitle.trim(),
      type: ProfileFieldType.section,
      sortOrder: section.sortOrder,
    );
    try {
      await ProfileFieldService.update(updated);
      if (mounted) {
        setState(() {
          final idx = _profileFields.indexWhere((f) => f.id == section.id);
          if (idx >= 0) _profileFields[idx] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  Future<void> _editProfileField(ProfileField field) async {
    final result = await _showProfileFieldDialog(initial: field);
    if (result == null) return;
    final updated = ProfileField(
      id: field.id,
      companyId: field.companyId,
      parentId: field.parentId,
      title: result.title,
      type: result.type,
      options: result.options,
      required: result.required,
      sortOrder: field.sortOrder,
    );
    try {
      await ProfileFieldService.update(updated);
      if (mounted) {
        setState(() {
          final idx = _profileFields.indexWhere((f) => f.id == field.id);
          if (idx >= 0) _profileFields[idx] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  Future<void> _deleteProfileField(ProfileField f) async {
    final isSection = f.isSection;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSection ? 'Slett bolk' : 'Slett felt'),
        content: Text(isSection
            ? 'Vil du slette bolken "${f.title}" og alle underbolker?'
            : 'Vil du slette feltet "${f.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ProfileFieldService.delete(f.id);
      if (mounted) {
        setState(() {
          _profileFields.removeWhere(
            (x) => x.id == f.id || x.parentId == f.id,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  Future<String?> _promptProfileText({
    required String title,
    required String label,
    String initial = '',
  }) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Lagre'),
          ),
        ],
      ),
    );
  }

  Future<_MgmtFieldDialogResult?> _showProfileFieldDialog(
      {ProfileField? initial}) async {
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    final optionsCtrl = TextEditingController(
      text: (initial?.options ?? const <String>[]).join('\n'),
    );
    ProfileFieldType type =
        initial?.type == null || initial!.type == ProfileFieldType.section
            ? ProfileFieldType.text
            : initial.type;
    bool required = initial?.required ?? false;

    return showDialog<_MgmtFieldDialogResult>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(initial == null ? 'Nytt felt' : 'Endre felt'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Tittel'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ProfileFieldType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Felt-type'),
                    items: ProfileFieldType.values
                        .where((t) => t != ProfileFieldType.section)
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => type = v);
                    },
                  ),
                  if (type == ProfileFieldType.dropdown) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: optionsCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Valg (én per linje)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: required,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Påkrevd'),
                    onChanged: (v) => setLocal(() => required = v ?? false),
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
                onPressed: () {
                  final t = titleCtrl.text.trim();
                  if (t.isEmpty) return;
                  final opts = type == ProfileFieldType.dropdown
                      ? optionsCtrl.text
                          .split('\n')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList()
                      : <String>[];
                  Navigator.pop(
                    ctx,
                    _MgmtFieldDialogResult(
                      title: t,
                      type: type,
                      options: opts,
                      required: required,
                    ),
                  );
                },
                child: const Text('Lagre'),
              ),
            ],
          ),
        );
      },
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
    final priceCtrl = TextEditingController();
    final labels = roleLabelsNotifier.value;

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
                      decoration: InputDecoration(labelText: labels.role1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dancersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: labels.role2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: othersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: labels.role3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pris (kr)',
                  helperText: 'Tom = auto (utøvere × CREO-honorar)',
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
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                final priceVal = double.tryParse(priceCtrl.text.trim()) ?? 0;
                final isCustom = priceVal > 0;
                await _sb.from('show_types').insert({
                  'company_id': _companyId,
                  'name': nameCtrl.text.trim(),
                  'drummers': int.tryParse(drummersCtrl.text) ?? 0,
                  'dancers': int.tryParse(dancersCtrl.text) ?? 0,
                  'others': int.tryParse(othersCtrl.text) ?? 0,
                  'price': isCustom ? priceVal : 0,
                  'price_is_custom': isCustom,
                  'sort_order': _showTypes.length,
                  'active': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Feil: $e'), backgroundColor: Colors.red),
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
    final priceCtrl = TextEditingController(
      text: showType['price_is_custom'] == true
          ? _formatPrice(showType['price'])
          : '',
    );
    final labels = roleLabelsNotifier.value;

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
                      decoration: InputDecoration(labelText: labels.role1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dancersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: labels.role2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: othersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: labels.role3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Pris (kr)',
                  helperText: 'Tom = auto (utøvere × CREO-honorar)',
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
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                final priceVal = double.tryParse(priceCtrl.text.trim()) ?? 0;
                final isCustom = priceVal > 0;
                await _sb.from('show_types').update({
                  'name': nameCtrl.text.trim(),
                  'drummers': int.tryParse(drummersCtrl.text) ?? 0,
                  'dancers': int.tryParse(dancersCtrl.text) ?? 0,
                  'others': int.tryParse(othersCtrl.text) ?? 0,
                  'price': isCustom ? priceVal : 0,
                  'price_is_custom': isCustom,
                }).eq('id', showType['id']);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Feil: $e'), backgroundColor: Colors.red),
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
        content:
            Text('Er du sikker på at du vil slette "${showType['name']}"?'),
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
          .update({'active': false}).eq('id', showType['id']);
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

  /// Test SMTP credentials by connecting and authenticating via raw socket.
  static Future<void> _testSmtpCredentials({
    required String host,
    required int port,
    required String username,
    required String password,
    required bool useSsl,
  }) async {
    // Reuse EmailService's internal SMTP connection for testing
    final conn = SmtpConnection();
    await conn.connect(host, port, useSsl: useSsl);
    try {
      await conn.readResponse();
      var resp = await conn.sendCmd('EHLO tourflow.app');
      if (!useSsl && resp.contains('STARTTLS')) {
        await conn.sendCmd('STARTTLS');
        await conn.upgradeToTls(host);
        resp = await conn.sendCmd('EHLO tourflow.app');
      }
      await conn.sendCmd('AUTH LOGIN');
      await conn.sendCmd(base64Encode(utf8.encode(username)));
      final authResp = await conn.sendCmd(base64Encode(utf8.encode(password)));
      if (!authResp.startsWith('235')) {
        throw Exception('Authentication failed: $authResp');
      }
      try {
        await conn.sendCmd('QUIT');
      } catch (_) {}
    } finally {
      conn.close();
    }
  }

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
                            Icon(Icons.check_circle,
                                color: Colors.green, size: 18),
                            SizedBox(width: 8),
                            Text('Tilkobling vellykket!',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600)),
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
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(testError!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 12)),
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
                            await _testSmtpCredentials(
                              host: hostCtrl.text.trim(),
                              port: port,
                              username: emailCtrl.text.trim(),
                              password: passwordCtrl.text,
                              useSsl: port == 465,
                            );
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
                  onPressed: saving ? null : () => Navigator.pop(ctx, true),
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
      _smtpAccounts =
          await EmailService.loadSmtpAccounts(companyId: _companyId);
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
      _smtpAccounts =
          await EmailService.loadSmtpAccounts(companyId: _companyId);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e')),
        );
      }
    }
  }

  // ── Rider methods ──────────────────────────────────────────────────────

  String _riderQuantityLabel(Map<String, dynamic> r) {
    final src = (r['quantity_source'] as String?) ?? '';
    switch (src) {
      case 'drummers':
        return 'antall trommer i show';
      case 'dancers':
        return 'antall dansere i show';
      case 'others':
        return 'antall andre i show';
      case 'show_total':
        return 'totalt antall utøvere';
      case 'fixed':
        final n = r['quantity_fixed'] as int? ?? 1;
        return 'fast: $n';
      default:
        return '–';
    }
  }

  Future<void> _addTextRider() async {
    final nameCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final matchCtrl = TextEditingController();
    final fixedCtrl = TextEditingController(text: '1');
    bool alwaysAttach = false;
    String quantitySource = 'show_total';

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Ny tekst-rider'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Navn (f.eks. Trommerider)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: bodyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tekst',
                      hintText: 'Innholdet som rendres til PDF…',
                      alignLabelWithHint: true,
                    ),
                    minLines: 6,
                    maxLines: 14,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bruk {antall} for å sette inn antallet, '
                    '{antall*2}, {antall+1}, {antall-1}, {antall/2} for enkel matte.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: quantitySource,
                          decoration: const InputDecoration(
                              labelText: 'Antall basert på'),
                          items: const [
                            DropdownMenuItem(
                                value: 'drummers', child: Text('Trommer')),
                            DropdownMenuItem(
                                value: 'dancers', child: Text('Dansere')),
                            DropdownMenuItem(
                                value: 'others', child: Text('Andre')),
                            DropdownMenuItem(
                                value: 'show_total',
                                child: Text('Totalt antall utøvere')),
                            DropdownMenuItem(
                                value: 'fixed', child: Text('Fast antall')),
                          ],
                          onChanged: (v) =>
                              setSt(() => quantitySource = v ?? 'show_total'),
                        ),
                      ),
                      if (quantitySource == 'fixed') ...[
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: fixedCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Antall'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: matchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Auto-vedlegg ved show (valgfritt)',
                      hintText: 'f.eks. completeshow',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: alwaysAttach,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Alltid vedlagt'),
                    onChanged: (v) => setSt(() => alwaysAttach = v ?? false),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Logo hentes automatisk fra firmaets branding (samme som intensjonsavtalen).',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lagre')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    try {
      await _sb.from('company_riders').insert({
        'company_id': _companyId,
        'name': nameCtrl.text.trim(),
        'body_text': bodyCtrl.text,
        'show_match': matchCtrl.text.trim().isEmpty
            ? null
            : matchCtrl.text.trim().toLowerCase(),
        'always_attach': alwaysAttach,
        'quantity_source': quantitySource,
        'quantity_fixed': int.tryParse(fixedCtrl.text.trim()) ?? 1,
        'sort_order': _riders.length,
        'active': true,
      });

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tekst-rider lagret'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadRider() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final nameCtrl =
        TextEditingController(text: file.name.replaceAll('.pdf', ''));
    final matchCtrl = TextEditingController();
    bool alwaysAttach = false;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Legg til rider'),
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
                  controller: matchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Auto-vedlegg ved show (valgfritt)',
                    hintText: 'f.eks. completeshow',
                  ),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: alwaysAttach,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Alltid vedlagt'),
                  onChanged: (v) => setSt(() => alwaysAttach = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Last opp')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      // Upload to storage
      final storagePath =
          '$_companyId/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      await _sb.storage.from('riders').uploadBinary(
            storagePath,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'application/pdf', upsert: true),
          );

      // Insert DB row
      await _sb.from('company_riders').insert({
        'company_id': _companyId,
        'name': nameCtrl.text.trim(),
        'file_path': storagePath,
        'file_size': bytes.length,
        'show_match': matchCtrl.text.trim().isEmpty
            ? null
            : matchCtrl.text.trim().toLowerCase(),
        'always_attach': alwaysAttach,
        'sort_order': _riders.length,
        'active': true,
      });

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Rider lastet opp'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editRider(Map<String, dynamic> rider) async {
    final isTextRider = (rider['file_path'] as String? ?? '').isEmpty;
    final nameCtrl =
        TextEditingController(text: rider['name'] as String? ?? '');
    final bodyCtrl =
        TextEditingController(text: rider['body_text'] as String? ?? '');
    final matchCtrl =
        TextEditingController(text: rider['show_match'] as String? ?? '');
    final fixedCtrl = TextEditingController(
        text: (rider['quantity_fixed'] as num?)?.toInt().toString() ?? '1');
    bool alwaysAttach = rider['always_attach'] == true;
    String quantitySource =
        (rider['quantity_source'] as String?) ?? 'show_total';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(isTextRider ? 'Rediger tekst-rider' : 'Rediger rider'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Navn'),
                  ),
                  if (isTextRider) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: bodyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tekst',
                        alignLabelWithHint: true,
                      ),
                      minLines: 6,
                      maxLines: 14,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bruk {antall} for å sette inn antallet, '
                      '{antall*2}, {antall+1}, {antall-1}, {antall/2} for enkel matte. '
                      'Virker også i navn/filnavn.',
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: quantitySource,
                            decoration: const InputDecoration(
                                labelText: 'Antall basert på'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'drummers', child: Text('Trommer')),
                              DropdownMenuItem(
                                  value: 'dancers', child: Text('Dansere')),
                              DropdownMenuItem(
                                  value: 'others', child: Text('Andre')),
                              DropdownMenuItem(
                                  value: 'show_total',
                                  child: Text('Totalt antall utøvere')),
                              DropdownMenuItem(
                                  value: 'fixed', child: Text('Fast antall')),
                            ],
                            onChanged: (v) =>
                                setSt(() => quantitySource = v ?? 'show_total'),
                          ),
                        ),
                        if (quantitySource == 'fixed') ...[
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: fixedCtrl,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Antall'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: matchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Auto-vedlegg ved show (valgfritt)',
                      hintText: 'f.eks. completeshow',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: alwaysAttach,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Alltid vedlagt'),
                    onChanged: (v) => setSt(() => alwaysAttach = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lagre')),
          ],
        ),
      ),
    );

    if (saved != true) return;

    try {
      final update = <String, dynamic>{
        'name': nameCtrl.text.trim(),
        'show_match': matchCtrl.text.trim().isEmpty
            ? null
            : matchCtrl.text.trim().toLowerCase(),
        'always_attach': alwaysAttach,
      };
      if (isTextRider) {
        update['body_text'] = bodyCtrl.text;
        update['quantity_source'] = quantitySource;
        update['quantity_fixed'] = int.tryParse(fixedCtrl.text.trim()) ?? 1;
      }
      await _sb
          .from('company_riders')
          .update(update)
          .eq('id', rider['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteRider(Map<String, dynamic> rider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett rider'),
        content: Text('Vil du slette "${rider['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Slett'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb
          .from('company_riders')
          .update({'active': false}).eq('id', rider['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _MgmtFieldDialogResult {
  final String title;
  final ProfileFieldType type;
  final List<String> options;
  final bool required;

  _MgmtFieldDialogResult({
    required this.title,
    required this.type,
    required this.options,
    required this.required,
  });
}
