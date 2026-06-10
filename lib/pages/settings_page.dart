import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_branding.dart';
import '../models/profile_field.dart';
import '../services/branding_service.dart';
import '../services/profile_field_service.dart';

import '../localization/s.dart';
import '../localization/app_locale.dart';
import '../models/swe_settings.dart';
import '../services/km_se_updater.dart';
import '../services/email_service.dart';
import '../services/microsoft_oauth_service.dart';
import '../state/active_company.dart';
import '../state/settings_store.dart';
import '../pages/routes_admin_page.dart';
import '../utils/company_vehicles.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController dayPriceCtrl;
  late TextEditingController extraKmCtrl;
  late TextEditingController trailerDayCtrl;
  late TextEditingController trailerKmCtrl;
  late TextEditingController dDriveDayCtrl;
  late TextEditingController flightTicketCtrl;
  late TextEditingController bankAccountCtrl;
  late TextEditingController tollKmRateCtrl;

  // --- Complete pricing ---
  late TextEditingController creoFeeMinCtrl;
  late TextEditingController extraShowFeeCtrl;
  late TextEditingController markupPctCtrl;
  late TextEditingController inearPriceCtrl;
  late TextEditingController transportPerKmCtrl;

  // --- Swedish pricing model ---
  late TextEditingController sweTimlonCtrl;
  late TextEditingController sweTimmarCtrl;
  late TextEditingController sweArbGAvgCtrl;
  late TextEditingController sweTraktamenteCtrl;
  late TextEditingController sweChaufforMarginalCtrl;

  late TextEditingController sweKopPrisCtrl;
  late TextEditingController sweAvskrivningArCtrl;
  late TextEditingController sweRantaCtrl;
  late TextEditingController sweForsakringCtrl;
  late TextEditingController sweSkattCtrl;
  late TextEditingController sweParkeringCtrl;
  late TextEditingController sweKordagarCtrl;
  late TextEditingController sweFordonMarginalCtrl;

  late TextEditingController sweDieselprisCtrl;
  late TextEditingController sweDieselforbrukningCtrl;
  late TextEditingController sweDackCtrl;
  late TextEditingController sweOljaCtrl;
  late TextEditingController sweVerkstadCtrl;
  late TextEditingController sweOvrigtCtrl;
  late TextEditingController sweKmMarginalCtrl;

  late TextEditingController sweDdTimlonCtrl;
  late TextEditingController sweDdTimmarCtrl;
  late TextEditingController sweDdArbGAvgCtrl;
  late TextEditingController sweDdTraktamenteCtrl;
  late TextEditingController sweDdResorCtrl;
  late TextEditingController sweDdHotellCtrl;
  late TextEditingController sweDdMarginalCtrl;
  late TextEditingController sweDdKmGransCtrl;

  late TextEditingController sweTrailerCtrl;
  late TextEditingController sweUtlandstraktCtrl;

  // --- SMTP Email Account ---
  SmtpAccount? _smtpAccount;

  // --- Microsoft OAuth (delegated send via Graph) ---
  String? _msOauthEmail;
  bool _msOauthBusy = false;

  // --- Vehicles ---
  List<Map<String, dynamic>> _vehicleTypes = [];
  bool _vehiclesExpanded = false;

  // --- Vehicle categories (type dropdown in offers) ---
  List<Map<String, dynamic>> _vehicleCategories = [];
  bool _vehicleCategoriesExpanded = false;

  // --- Profile fields (members fill in via mobile app) ---
  List<ProfileField> _profileFields = [];
  bool _profileFieldsLoading = false;
  final Set<String> _expandedSections = {};

  // --- Branding ---
  CompanyBranding? _branding;
  late TextEditingController brandCompanyNameCtrl;
  late TextEditingController brandAddressCtrl;
  late TextEditingController brandContact1Ctrl;
  late TextEditingController brandContact2Ctrl;
  late TextEditingController brandSignatureCtrl;

  /// One controller per supported offer language. 'no' is the source,
  /// the others are manually maintained translations stored in
  /// company_branding.terms_translations.
  static const List<String> _termsLanguages = ['no', 'en', 'sv', 'de'];
  final Map<String, TextEditingController> brandTermsCtrls = {
    for (final l in _termsLanguages) l: TextEditingController(),
  };
  String _termsEditingLang = 'no';

  Future<void> _loadSmtpAccount() async {
    final companyId = activeCompanyNotifier.value?.id;
    final accounts = await EmailService.loadSmtpAccounts(companyId: companyId);
    if (mounted) setState(() => _smtpAccount = accounts.isNotEmpty ? accounts.first : null);
  }

  Future<void> _loadMicrosoftOAuth() async {
    final email = await MicrosoftOAuthService.getConnectedEmail();
    if (mounted) setState(() => _msOauthEmail = email);
  }

  Future<void> _connectMicrosoftOAuth() async {
    setState(() => _msOauthBusy = true);
    try {
      final ok = await MicrosoftOAuthService.connect();
      if (ok) await _loadMicrosoftOAuth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Microsoft-tilkobling feilet: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _msOauthBusy = false);
    }
  }

  Future<void> _disconnectMicrosoftOAuth() async {
    await MicrosoftOAuthService.disconnect();
    await _loadMicrosoftOAuth();
  }

  Future<void> _loadBranding() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    final b = await BrandingService.load(cid);
    if (!mounted) return;
    setState(() {
      _branding = b;
      brandCompanyNameCtrl.text = b?.companyName ?? '';
      brandAddressCtrl.text = b?.addressLine ?? '';
      brandContact1Ctrl.text = b?.contactLine1 ?? '';
      brandContact2Ctrl.text = b?.contactLine2 ?? '';
      brandSignatureCtrl.text = b?.signatureName ?? '';
      brandTermsCtrls['no']!.text = b?.termsText ?? '';
      for (final l in _termsLanguages) {
        if (l == 'no') continue;
        brandTermsCtrls[l]!.text = b?.termsTranslations[l] ?? '';
      }
    });
  }

  Future<void> _saveBranding() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;

    try {
      final translations = <String, String>{
        for (final l in _termsLanguages)
          if (l != 'no') l: brandTermsCtrls[l]!.text.trim(),
      }..removeWhere((_, v) => v.isEmpty);

      final updated = CompanyBranding(
        id: _branding?.id,
        companyId: cid,
        logoUrl: _branding?.logoUrl,
        companyName: brandCompanyNameCtrl.text.trim(),
        addressLine: brandAddressCtrl.text.trim(),
        contactLine1: brandContact1Ctrl.text.trim(),
        contactLine2: brandContact2Ctrl.text.trim(),
        signatureName: brandSignatureCtrl.text.trim(),
        termsText: brandTermsCtrls['no']!.text.trim(),
        termsTranslations: translations,
      );

      await BrandingService.save(updated);
      setState(() => _branding = updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('brandingSaved'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('error')}: $e')),
        );
      }
    }
  }

  Future<void> _loadVehicleTypes() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('vehicle_types')
          .select('*')
          .eq('company_id', cid)
          .eq('active', true)
          .order('sort_order');
      if (mounted) setState(() => _vehicleTypes = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Table might not exist yet
    }
  }

  Future<void> _loadVehicleCategories() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('vehicle_categories')
          .select('*')
          .eq('company_id', cid)
          .eq('active', true)
          .order('sort_order');
      if (mounted) setState(() => _vehicleCategories = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _uploadLogo() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    try {
      final file = result.files.single;
      final url = await BrandingService.uploadLogo(
        companyId: cid,
        bytes: file.bytes!,
        filename: file.name,
      );
      final updated = (_branding ?? CompanyBranding(companyId: cid)).copyWith(logoUrl: url);
      await BrandingService.save(updated);
      BrandingService.clearCache(cid);
      final refreshed = await BrandingService.load(cid);
      if (mounted) {
        setState(() => _branding = refreshed);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('logoUploaded'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${S.t('error')}: $e')),
        );
      }
    }
  }

  Future<void> _openSmtpDialog({SmtpAccount? existing}) async {
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final nameCtrl = TextEditingController(text: existing?.displayName ?? '');
    final hostCtrl = TextEditingController(text: existing?.smtpHost ?? 'smtp.office365.com');
    final portCtrl = TextEditingController(text: (existing?.smtpPort ?? 587).toString());
    final passCtrl = TextEditingController(text: existing?.password ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(existing != null ? S.t('editEmailAccount') : S.t('addEmailAccount')),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: emailCtrl, decoration: InputDecoration(labelText: S.t('emailAddress'))),
                  const SizedBox(height: 8),
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: S.t('displayName'))),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: hostCtrl, decoration: InputDecoration(labelText: S.t('smtpHost')))),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: TextField(controller: portCtrl, decoration: InputDecoration(labelText: S.t('port')), keyboardType: TextInputType.number)),
                  ]),
                  const SizedBox(height: 8),
                  TextField(controller: passCtrl, obscureText: true, decoration: InputDecoration(labelText: S.t('password'))),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.t('cancel'))),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (emailCtrl.text.trim().isEmpty || passCtrl.text.trim().isEmpty) return;
                        setLocal(() => saving = true);
                        try {
                          final sb = Supabase.instance.client;
                          final data = {
                            'user_id': sb.auth.currentUser!.id,
                            'company_id': activeCompanyNotifier.value?.id,
                            'email': emailCtrl.text.trim(),
                            'display_name': nameCtrl.text.trim(),
                            'smtp_host': hostCtrl.text.trim(),
                            'smtp_port': int.tryParse(portCtrl.text.trim()) ?? 587,
                            'password': passCtrl.text.trim(),
                            'is_default': true,
                          };
                          if (existing != null) {
                            await sb.from('smtp_accounts').update(data).eq('id', existing.id);
                          } else {
                            await sb.from('smtp_accounts').insert(data);
                          }
                          EmailService.clearSmtpCache();
                          Navigator.pop(ctx, true);
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('${S.t('error')}: $e'), backgroundColor: Colors.red),
                          );
                          setLocal(() => saving = false);
                        }
                      },
                child: Text(saving ? S.t('saving') : S.t('save')),
              ),
            ],
          ),
        );
      },
    );
    if (saved == true) await _loadSmtpAccount();
  }

  Future<void> _deleteSmtpAccount() async {
    if (_smtpAccount == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.t('removeEmailAccount')),
        content: const Text('Emails will fall back to the default sender (michael@nttas.com).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(S.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(S.t('remove'))),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.from('smtp_accounts').delete().eq('id', _smtpAccount!.id);
    EmailService.clearSmtpCache();
    if (mounted) setState(() => _smtpAccount = null);
  }

  Future<void> _openChangePasswordDialog() async {

  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) {

      bool loading = false;

      return StatefulBuilder(
        builder: (context, setLocalState) {

          return AlertDialog(
            title: Text(S.t('changePassword')),

            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: S.t('newPassword'),
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: S.t('confirmPassword'),
                    ),
                  ),
                ],
              ),
            ),

            actions: [

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(S.t('cancel')),
              ),

              FilledButton(
                onPressed: loading ? null : () async {

                  final p1 = passCtrl.text.trim();
                  final p2 = confirmCtrl.text.trim();

                  if (p1.isEmpty || p1 != p2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.t('passwordsDoNotMatch')),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  setLocalState(() => loading = true);

                  try {

                    await Supabase.instance.client.auth.updateUser(
                      UserAttributes(password: p1),
                    );

                    if (!mounted) return;

                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(S.t('passwordUpdated')),
                      ),
                    );

                  } catch (e) {

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${S.t('error')}: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }

                  setLocalState(() => loading = false);
                },
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(S.t('update')),
              ),
            ],
          );
        },
      );
    },
  );
}

  // =====================================================
  // INIT
  // =====================================================

  @override
  void initState() {
    super.initState();

    final s = SettingsStore.current;

    dayPriceCtrl =
        TextEditingController(text: s.dayPrice.toStringAsFixed(0));
    extraKmCtrl =
        TextEditingController(text: s.extraKmPrice.toStringAsFixed(0));
    trailerDayCtrl =
        TextEditingController(text: s.trailerDayPrice.toStringAsFixed(0));
    trailerKmCtrl =
        TextEditingController(text: s.trailerKmPrice.toStringAsFixed(0));
    dDriveDayCtrl =
        TextEditingController(text: s.dDriveDayPrice.toStringAsFixed(0));
    flightTicketCtrl =
        TextEditingController(text: s.flightTicketPrice.toStringAsFixed(0));

    bankAccountCtrl = TextEditingController(text: s.bankAccount);
    tollKmRateCtrl = TextEditingController(text: s.tollKmRate.toStringAsFixed(2));

    creoFeeMinCtrl = TextEditingController(text: s.creoFeeMinimum.toStringAsFixed(0));
    extraShowFeeCtrl = TextEditingController(text: s.extraShowFee.toStringAsFixed(0));
    markupPctCtrl = TextEditingController(text: (s.markupPct * 100).toStringAsFixed(0));
    inearPriceCtrl = TextEditingController(text: s.inearPrice.toStringAsFixed(0));
    transportPerKmCtrl = TextEditingController(text: s.transportPricePerKm.toStringAsFixed(2));

    final swe = s.sweSettings;
    sweTimlonCtrl = TextEditingController(text: swe.timlon.toStringAsFixed(0));
    sweTimmarCtrl = TextEditingController(text: swe.timmarPerDag.toStringAsFixed(0));
    sweArbGAvgCtrl = TextEditingController(text: (swe.arbGAvg * 100).toStringAsFixed(2));
    sweTraktamenteCtrl = TextEditingController(text: swe.traktamente.toStringAsFixed(0));
    sweChaufforMarginalCtrl = TextEditingController(text: (swe.chaufforMarginal * 100).toStringAsFixed(0));

    sweKopPrisCtrl = TextEditingController(text: swe.kopPris.toStringAsFixed(0));
    sweAvskrivningArCtrl = TextEditingController(text: swe.avskrivningAr.toStringAsFixed(0));
    sweRantaCtrl = TextEditingController(text: (swe.rantaPerAr * 100).toStringAsFixed(1));
    sweForsakringCtrl = TextEditingController(text: swe.forsakringPerAr.toStringAsFixed(0));
    sweSkattCtrl = TextEditingController(text: swe.skattPerAr.toStringAsFixed(0));
    sweParkeringCtrl = TextEditingController(text: swe.parkeringPerAr.toStringAsFixed(0));
    sweKordagarCtrl = TextEditingController(text: swe.kordagarPerAr.toStringAsFixed(0));
    sweFordonMarginalCtrl = TextEditingController(text: (swe.fordonMarginal * 100).toStringAsFixed(0));

    sweDieselprisCtrl = TextEditingController(text: swe.dieselprisPerLiter.toStringAsFixed(2));
    sweDieselforbrukningCtrl = TextEditingController(text: swe.dieselforbrukningPerMil.toStringAsFixed(2));
    sweDackCtrl = TextEditingController(text: swe.dackKostnadPerMil.toStringAsFixed(2));
    sweOljaCtrl = TextEditingController(text: swe.oljaKostnadPerMil.toStringAsFixed(2));
    sweVerkstadCtrl = TextEditingController(text: swe.verkstadKostnadPerMil.toStringAsFixed(2));
    sweOvrigtCtrl = TextEditingController(text: swe.ovrigtKostnadPerMil.toStringAsFixed(2));
    sweKmMarginalCtrl = TextEditingController(text: (swe.kmMarginal * 100).toStringAsFixed(0));

    sweDdTimlonCtrl = TextEditingController(text: swe.ddTimlon.toStringAsFixed(0));
    sweDdTimmarCtrl = TextEditingController(text: swe.ddTimmarPerDag.toStringAsFixed(0));
    sweDdArbGAvgCtrl = TextEditingController(text: (swe.ddArbGAvg * 100).toStringAsFixed(2));
    sweDdTraktamenteCtrl = TextEditingController(text: swe.ddTraktamente.toStringAsFixed(0));
    sweDdResorCtrl = TextEditingController(text: swe.ddResor.toStringAsFixed(0));
    sweDdHotellCtrl = TextEditingController(text: swe.ddHotell.toStringAsFixed(0));
    sweDdMarginalCtrl = TextEditingController(text: (swe.ddMarginal * 100).toStringAsFixed(0));
    sweDdKmGransCtrl = TextEditingController(text: swe.ddKmGrans.toStringAsFixed(0));

    sweTrailerCtrl = TextEditingController(text: swe.trailerhyraPerDygn.toStringAsFixed(0));
    sweUtlandstraktCtrl = TextEditingController(text: swe.utlandstraktamente.toStringAsFixed(0));

    _loadSmtpAccount();
    _loadMicrosoftOAuth();

    brandCompanyNameCtrl = TextEditingController();
    brandAddressCtrl = TextEditingController();
    brandContact1Ctrl = TextEditingController();
    brandContact2Ctrl = TextEditingController();
    brandSignatureCtrl = TextEditingController();
    _loadBranding();
    _loadVehicleTypes();
    _loadVehicleCategories();
    _loadProfileFields();
  }

  // =====================================================
  // PROFILE FIELDS
  // =====================================================

  Future<void> _loadProfileFields() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    setState(() => _profileFieldsLoading = true);
    final list = await ProfileFieldService.loadAll(cid);
    if (!mounted) return;
    setState(() {
      _profileFields = list;
      _profileFieldsLoading = false;
    });
  }

  List<ProfileField> get _sections =>
      _profileFields.where((f) => f.isSection).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<ProfileField> _childrenOf(String sectionId) =>
      _profileFields.where((f) => f.parentId == sectionId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Future<void> _addSection() async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    final title = await _promptText(
      title: 'Ny hovedbolk',
      label: 'Navn på bolk',
    );
    if (title == null || title.trim().isEmpty) return;

    final nextOrder = _sections.isEmpty
        ? 0
        : _sections.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    try {
      final created = await ProfileFieldService.insert(ProfileField(
        id: '',
        companyId: cid,
        parentId: null,
        title: title.trim(),
        type: ProfileFieldType.section,
        sortOrder: nextOrder,
      ));
      if (created != null && mounted) {
        setState(() {
          _profileFields.add(created);
          _expandedSections.add(created.id);
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

  Future<void> _addField(ProfileField section) async {
    final cid = activeCompanyNotifier.value?.id;
    if (cid == null) return;
    final result = await _showFieldDialog();
    if (result == null) return;

    final children = _childrenOf(section.id);
    final nextOrder = children.isEmpty
        ? 0
        : children.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    try {
      final created = await ProfileFieldService.insert(ProfileField(
        id: '',
        companyId: cid,
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

  Future<void> _editSection(ProfileField section) async {
    final newTitle = await _promptText(
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

  Future<void> _editField(ProfileField field) async {
    final result = await _showFieldDialog(initial: field);
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

  Future<void> _deleteField(ProfileField f) async {
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
            child: Text(S.t('cancel')),
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

  Future<String?> _promptText({
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
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(S.t('save')),
          ),
        ],
      ),
    );
  }

  Future<_FieldDialogResult?> _showFieldDialog({ProfileField? initial}) async {
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    final optionsCtrl = TextEditingController(
      text: (initial?.options ?? const <String>[]).join('\n'),
    );
    ProfileFieldType type = initial?.type == null ||
            initial!.type == ProfileFieldType.section
        ? ProfileFieldType.text
        : initial.type;
    bool required = initial?.required ?? false;

    return showDialog<_FieldDialogResult>(
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
                child: Text(S.t('cancel')),
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
                    _FieldDialogResult(
                      title: t,
                      type: type,
                      options: opts,
                      required: required,
                    ),
                  );
                },
                child: Text(S.t('save')),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    dayPriceCtrl.dispose();
    extraKmCtrl.dispose();
    trailerDayCtrl.dispose();
    trailerKmCtrl.dispose();
    dDriveDayCtrl.dispose();
    flightTicketCtrl.dispose();
    bankAccountCtrl.dispose();
    tollKmRateCtrl.dispose();
    creoFeeMinCtrl.dispose();
    extraShowFeeCtrl.dispose();
    markupPctCtrl.dispose();
    inearPriceCtrl.dispose();
    transportPerKmCtrl.dispose();

    sweTimlonCtrl.dispose();
    sweTimmarCtrl.dispose();
    sweArbGAvgCtrl.dispose();
    sweTraktamenteCtrl.dispose();
    sweChaufforMarginalCtrl.dispose();
    sweKopPrisCtrl.dispose();
    sweAvskrivningArCtrl.dispose();
    sweRantaCtrl.dispose();
    sweForsakringCtrl.dispose();
    sweSkattCtrl.dispose();
    sweParkeringCtrl.dispose();
    sweKordagarCtrl.dispose();
    sweFordonMarginalCtrl.dispose();
    sweDieselprisCtrl.dispose();
    sweDieselforbrukningCtrl.dispose();
    sweDackCtrl.dispose();
    sweOljaCtrl.dispose();
    sweVerkstadCtrl.dispose();
    sweOvrigtCtrl.dispose();
    sweKmMarginalCtrl.dispose();
    sweDdTimlonCtrl.dispose();
    sweDdTimmarCtrl.dispose();
    sweDdArbGAvgCtrl.dispose();
    sweDdTraktamenteCtrl.dispose();
    sweDdResorCtrl.dispose();
    sweDdHotellCtrl.dispose();
    sweDdMarginalCtrl.dispose();
    sweDdKmGransCtrl.dispose();
    sweTrailerCtrl.dispose();
    sweUtlandstraktCtrl.dispose();

    brandCompanyNameCtrl.dispose();
    brandAddressCtrl.dispose();
    brandContact1Ctrl.dispose();
    brandContact2Ctrl.dispose();
    brandSignatureCtrl.dispose();
    for (final c in brandTermsCtrls.values) {
      c.dispose();
    }

    super.dispose();
  }

  // =====================================================
  // HELPERS
  // =====================================================

  double _parseDouble(String s, double fallback) {
    final clean = s.replaceAll(" ", "").replaceAll(",", ".");
    return double.tryParse(clean) ?? fallback;
  }

  // =====================================================
  // ADD USER DIALOG
  // =====================================================

  Future<List<Map<String, dynamic>>> _loadCompanies() async {
    try {
      final res = await Supabase.instance.client
          .from('companies')
          .select('id, name')
          .order('name');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('Load companies error: $e');
      return [];
    }
  }

  Future<void> _openAddUserDialog() async {
    final emailCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedRole = 'driver';
    String? selectedCompanyId;
    List<Map<String, dynamic>> companies = [];

    // Load companies for management role selection
    companies = await _loadCompanies();

    // CSS company auto-set
    final cssCompanyId = activeCompanyNotifier.value?.id;

    if (!mounted) return;

    final outerContext = context;

    await showDialog(
      context: outerContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: Text(S.t('addUser')),

              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: S.t('name'),
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextField(
                      controller: emailCtrl,
                      decoration: InputDecoration(
                        labelText: S.t('email'),
                      ),
                    ),

                    const SizedBox(height: 10),

                    TextField(
                      controller: phoneCtrl,
                      decoration: InputDecoration(
                        labelText: S.t('phone'),
                      ),
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: S.t('role'),
                      ),
                      items: [
                        DropdownMenuItem(value: 'driver', child: Text(S.t('roleDriver'))),
                        DropdownMenuItem(value: 'admin', child: Text(S.t('roleAdmin'))),
                        DropdownMenuItem(
                            value: 'management', child: Text(S.t('roleManagement'))),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          selectedRole = v ?? 'driver';
                          if (selectedRole != 'management') {
                            selectedCompanyId = null;
                          }
                        });
                      },
                    ),

                    // Company dropdown — only shown for management role
                    if (selectedRole == 'management') ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCompanyId,
                        decoration: InputDecoration(
                          labelText: S.t('company'),
                          hintText: S.t('selectCompany'),
                        ),
                        items: companies
                            .map((c) => DropdownMenuItem<String>(
                                  value: c['id'] as String,
                                  child: Text(c['name'] as String? ?? ''),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedCompanyId = v),
                      ),
                    ],
                  ],
                ),
              ),

              actions: [

                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(S.t('cancel')),
                ),

                FilledButton(
                  onPressed: () async {

                    if (selectedRole == 'management' &&
                        selectedCompanyId == null) {
                      ScaffoldMessenger.of(dialogCtx).showSnackBar(
                        SnackBar(
                          content: Text(S.t('selectCompanyForManagement')),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // For driver/admin: bruk CSS company. For management: valgt company.
                    final companyForUser = selectedRole == 'management'
                        ? selectedCompanyId
                        : cssCompanyId;

                    final tempPassword = await _createProfileUser(
                      name: nameCtrl.text.trim(),
                      email: emailCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      role: selectedRole,
                      companyId: companyForUser,
                    );

                    if (!mounted) return;

                    Navigator.pop(dialogCtx);

                    if (tempPassword != null) {
                      await showDialog(
                        context: outerContext,
                        builder: (ctx) => AlertDialog(
                          title: Text(S.t('userCreated')),
                          content: SizedBox(
                            width: 420,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${S.t('sendLoginDetails')} ${nameCtrl.text.trim()}:'),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        "Email:     ${emailCtrl.text.trim()}",
                                        style: const TextStyle(fontFamily: 'monospace'),
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                        "Password:  $tempPassword",
                                        style: const TextStyle(fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  S.t('changePasswordAfterLogin'),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(S.t('ok')),
                            ),
                          ],
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(outerContext).showSnackBar(
                        SnackBar(content: Text(S.t('userCreated'))),
                      );
                    }
                  },
                  child: Text(S.t('create')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // CALL EDGE FUNCTION
  // =====================================================

  Future<String?> _createProfileUser({
    required String name,
    required String email,
    String phone = '',
    required String role,
    String? companyId,
  }) async {

    if (name.isEmpty || email.isEmpty) {
      debugPrint("❌ Name or email empty");
      return null;
    }

    try {

      final supabase = Supabase.instance.client;

      final body = {
        'name': name,
        'email': email,
        if (phone.isNotEmpty) 'phone': phone,
        'role': role.isEmpty ? 'user' : role,
        if (companyId != null) 'company_id': companyId,
      };

      debugPrint("Creating user: $body");

      final res = await supabase.functions.invoke(
        'create-user',
        body: body,
      );

      debugPrint("✅ Create user result: ${res.data}");

      final data = res.data as Map<String, dynamic>?;
      return data?['temp_password'] as String?;

    } catch (e, st) {
      debugPrint("❌ Create user error:");
      debugPrint(e.toString());
      debugPrint(st.toString());
      return null;
    }
  }

  // =====================================================
  // DROPBOX
  // =====================================================

  // =====================================================
  // =====================================================
  // POPULATE km_se
  // =====================================================

  Future<void> _runKmSeUpdater() async {
    final logs = <String>[];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            // Start the updater the first time the dialog opens
            if (logs.isEmpty) {
              logs.add('Starter...');
              KmSeUpdater.updateAll(
                onProgress: (msg) => setS(() => logs.add(msg)),
                onError:    (msg) => setS(() => logs.add(msg)),
              ).then((_) {
                setS(() => logs.add('— Lukk vinduet når du er ferdig —'));
              });
            }

            return AlertDialog(
              title: const Text('Oppdater km_se for alle ruter'),
              content: SizedBox(
                width: 560,
                height: 360,
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    logs.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(S.t('close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =====================================================
  // SAVE SETTINGS
  // =====================================================

  Future<void> _save() async {
    final current = SettingsStore.current;

    SettingsStore.current = current.copyWith(
      dayPrice: _parseDouble(dayPriceCtrl.text, current.dayPrice),
      extraKmPrice: _parseDouble(extraKmCtrl.text, current.extraKmPrice),
      trailerDayPrice:
          _parseDouble(trailerDayCtrl.text, current.trailerDayPrice),
      trailerKmPrice:
          _parseDouble(trailerKmCtrl.text, current.trailerKmPrice),
      dDriveDayPrice:
          _parseDouble(dDriveDayCtrl.text, current.dDriveDayPrice),
      flightTicketPrice:
          _parseDouble(flightTicketCtrl.text, current.flightTicketPrice),
      dropboxRootPath: current.dropboxRootPath,
      bankAccount: bankAccountCtrl.text.trim(),
      tollKmRate: _parseDouble(tollKmRateCtrl.text, current.tollKmRate),
      creoFeeMinimum: _parseDouble(creoFeeMinCtrl.text, current.creoFeeMinimum),
      extraShowFee: _parseDouble(extraShowFeeCtrl.text, current.extraShowFee),
      markupPct: _parseDouble(markupPctCtrl.text, current.markupPct * 100) / 100,
      inearPrice: _parseDouble(inearPriceCtrl.text, current.inearPrice),
      transportPricePerKm: _parseDouble(transportPerKmCtrl.text, current.transportPricePerKm),
      sweSettings: SweSettings(
        timlon: _parseDouble(sweTimlonCtrl.text, current.sweSettings.timlon),
        timmarPerDag: _parseDouble(sweTimmarCtrl.text, current.sweSettings.timmarPerDag),
        arbGAvg: _parseDouble(sweArbGAvgCtrl.text, current.sweSettings.arbGAvg * 100) / 100,
        traktamente: _parseDouble(sweTraktamenteCtrl.text, current.sweSettings.traktamente),
        chaufforMarginal: _parseDouble(sweChaufforMarginalCtrl.text, current.sweSettings.chaufforMarginal * 100) / 100,
        kopPris: _parseDouble(sweKopPrisCtrl.text, current.sweSettings.kopPris),
        avskrivningAr: _parseDouble(sweAvskrivningArCtrl.text, current.sweSettings.avskrivningAr),
        rantaPerAr: _parseDouble(sweRantaCtrl.text, current.sweSettings.rantaPerAr * 100) / 100,
        forsakringPerAr: _parseDouble(sweForsakringCtrl.text, current.sweSettings.forsakringPerAr),
        skattPerAr: _parseDouble(sweSkattCtrl.text, current.sweSettings.skattPerAr),
        parkeringPerAr: _parseDouble(sweParkeringCtrl.text, current.sweSettings.parkeringPerAr),
        kordagarPerAr: _parseDouble(sweKordagarCtrl.text, current.sweSettings.kordagarPerAr),
        fordonMarginal: _parseDouble(sweFordonMarginalCtrl.text, current.sweSettings.fordonMarginal * 100) / 100,
        dieselprisPerLiter: _parseDouble(sweDieselprisCtrl.text, current.sweSettings.dieselprisPerLiter),
        dieselforbrukningPerMil: _parseDouble(sweDieselforbrukningCtrl.text, current.sweSettings.dieselforbrukningPerMil),
        dackKostnadPerMil: _parseDouble(sweDackCtrl.text, current.sweSettings.dackKostnadPerMil),
        oljaKostnadPerMil: _parseDouble(sweOljaCtrl.text, current.sweSettings.oljaKostnadPerMil),
        verkstadKostnadPerMil: _parseDouble(sweVerkstadCtrl.text, current.sweSettings.verkstadKostnadPerMil),
        ovrigtKostnadPerMil: _parseDouble(sweOvrigtCtrl.text, current.sweSettings.ovrigtKostnadPerMil),
        kmMarginal: _parseDouble(sweKmMarginalCtrl.text, current.sweSettings.kmMarginal * 100) / 100,
        ddTimlon: _parseDouble(sweDdTimlonCtrl.text, current.sweSettings.ddTimlon),
        ddTimmarPerDag: _parseDouble(sweDdTimmarCtrl.text, current.sweSettings.ddTimmarPerDag),
        ddArbGAvg: _parseDouble(sweDdArbGAvgCtrl.text, current.sweSettings.ddArbGAvg * 100) / 100,
        ddTraktamente: _parseDouble(sweDdTraktamenteCtrl.text, current.sweSettings.ddTraktamente),
        ddResor: _parseDouble(sweDdResorCtrl.text, current.sweSettings.ddResor),
        ddHotell: _parseDouble(sweDdHotellCtrl.text, current.sweSettings.ddHotell),
        ddMarginal: _parseDouble(sweDdMarginalCtrl.text, current.sweSettings.ddMarginal * 100) / 100,
        ddKmGrans: _parseDouble(sweDdKmGransCtrl.text, current.sweSettings.ddKmGrans),
        trailerhyraPerDygn: _parseDouble(sweTrailerCtrl.text, current.sweSettings.trailerhyraPerDygn),
        utlandstraktamente: _parseDouble(sweUtlandstraktCtrl.text, current.sweSettings.utlandstraktamente),
      ),
    );

    await SettingsStore.save();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.t('settingsSaved'))),
    );

    setState(() {});
  }

  // =====================================================
  // FIELD
  // =====================================================

  Widget _field(
    String label,
    TextEditingController ctrl,
    String suffix,
  ) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
      ),
    );
  }

  Widget _sweField(String label, TextEditingController ctrl, String suffix,
      {double width = 200}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
        ),
      ),
    );
  }

  // =====================================================
  // SWEDISH SETTINGS SECTION
  // =====================================================

  Widget _buildSweSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final swe = SettingsStore.current.sweSettings;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          S.t('swedishPricingModel'),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          "${S.t('vehicle')} ${swe.fordonDagpris.toStringAsFixed(0)} + "
          "${S.t('driver')} ${swe.chaufforDagpris.toStringAsFixed(0)} + "
          "${swe.milpris.toStringAsFixed(0)} SEK/10km  •  "
          "DD ${swe.ddDagpris.toStringAsFixed(0)} when >${swe.ddKmGrans.toStringAsFixed(0)} km",
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        children: [
          const SizedBox(height: 8),

          // --- DRIVER ---
          Text(S.t('driver'),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField(S.t('hourlyRate'), sweTimlonCtrl, "SEK/h"),
            _sweField(S.t('hoursPerDay'), sweTimmarCtrl, "h"),
            _sweField(S.t('employerTax'), sweArbGAvgCtrl, "%"),
            _sweField(S.t('allowance'), sweTraktamenteCtrl, "SEK/day"),
            _sweField(S.t('margin'), sweChaufforMarginalCtrl, "%"),
          ]),
          const SizedBox(height: 16),

          // --- VEHICLE ---
          Text(S.t('vehicle'),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField(S.t('purchasePrice'), sweKopPrisCtrl, "SEK", width: 220),
            _sweField(S.t('depreciation'), sweAvskrivningArCtrl, "years"),
            _sweField(S.t('interest'), sweRantaCtrl, "%/year"),
            _sweField(S.t('insurance'), sweForsakringCtrl, "SEK/year", width: 220),
            _sweField(S.t('tax'), sweSkattCtrl, "SEK/year", width: 220),
            _sweField(S.t('parking'), sweParkeringCtrl, "SEK/year", width: 220),
            _sweField(S.t('drivingDays'), sweKordagarCtrl, "days/year"),
            _sweField(S.t('margin'), sweFordonMarginalCtrl, "%"),
          ]),
          const SizedBox(height: 16),

          // --- KM PRICE ---
          Text(S.t('kmPriceVariable'),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField(S.t('dieselPrice'), sweDieselprisCtrl, "SEK/l"),
            _sweField(S.t('consumption'), sweDieselforbrukningCtrl, "l/10km"),
            _sweField(S.t('tires'), sweDackCtrl, "SEK/10km"),
            _sweField(S.t('oil'), sweOljaCtrl, "SEK/10km"),
            _sweField(S.t('workshop'), sweVerkstadCtrl, "SEK/10km"),
            _sweField(S.t('other'), sweOvrigtCtrl, "SEK/10km"),
            _sweField(S.t('margin'), sweKmMarginalCtrl, "%"),
          ]),
          const SizedBox(height: 16),

          // --- DD ---
          Text(S.t('doubleDriver'),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField(S.t('hourlyRate'), sweDdTimlonCtrl, "SEK/h"),
            _sweField(S.t('hoursPerDay'), sweDdTimmarCtrl, "h"),
            _sweField(S.t('employerTax'), sweDdArbGAvgCtrl, "%"),
            _sweField(S.t('allowance'), sweDdTraktamenteCtrl, "SEK"),
            _sweField(S.t('travel'), sweDdResorCtrl, "SEK"),
            _sweField(S.t('hotel'), sweDdHotellCtrl, "SEK"),
            _sweField(S.t('margin'), sweDdMarginalCtrl, "%"),
            _sweField(S.t('kmThreshold'), sweDdKmGransCtrl, "km"),
          ]),
          const SizedBox(height: 16),

          // --- OTHER ---
          Text(S.t('other'),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _sweField(S.t('trailerHire'), sweTrailerCtrl, "SEK/day", width: 220),
            _sweField(S.t('internationalAllowance'), sweUtlandstraktCtrl, "SEK/unit", width: 260),
          ]),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 4,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.t('settings'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                indicatorColor: cs.primary,
                tabs: [
                  Tab(text: S.t('tabGeneral')),
                  Tab(text: S.t('tabIntegrations')),
                  Tab(text: S.t('tabPricing')),
                  Tab(text: S.t('tabAdmin')),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildGeneralTab(cs),
                    _buildIntegrationsTab(cs),
                    _buildPricingTab(cs),
                    _buildAdminTab(cs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // TAB: GENERAL
  // =====================================================
  Widget _buildGeneralTab(ColorScheme cs) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ---------------- LANGUAGE ----------------

            Text(
              S.t('language'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            ValueListenableBuilder<Locale>(
              valueListenable: appLocale,
              builder: (context, locale, _) {
                return DropdownButton<String>(
                  value: appLocale.lang,
                  items: supportedLangs
                      .map((code) => DropdownMenuItem<String>(
                            value: code,
                            child: Text(langName(code)),
                          ))
                      .toList(),
                  onChanged: (code) {
                    if (code != null) {
                      appLocale.setLang(code);
                    }
                  },
                );
              },
            ),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- BRANDING ----------------
            Text(
              S.t('branding'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              S.t('brandingDesc'),
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 14),

            // Logo preview + upload
            Row(
              children: [
                if (_branding?.logoUrl != null && _branding!.logoUrl!.isNotEmpty)
                  Container(
                    width: 120,
                    height: 60,
                    margin: const EdgeInsets.only(right: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: Image.network(
                        _branding!.logoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _uploadLogo,
                  icon: const Icon(Icons.upload, size: 18),
                  label: Text(S.t('uploadLogo')),
                ),
                if (_branding?.logoUrl != null && _branding!.logoUrl!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final cid = activeCompanyNotifier.value?.id;
                      if (cid == null) return;
                      final b = CompanyBranding(
                        id: _branding!.id,
                        companyId: cid,
                        logoUrl: null,
                        companyName: _branding!.companyName,
                        addressLine: _branding!.addressLine,
                        contactLine1: _branding!.contactLine1,
                        contactLine2: _branding!.contactLine2,
                        signatureName: _branding!.signatureName,
                        termsText: _branding!.termsText,
                      );
                      await BrandingService.save(b);
                      BrandingService.clearCache(cid);
                      setState(() => _branding = b);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(S.t('logoRemoved'))),
                        );
                      }
                    },
                    child: Text(S.t('removeLogo')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Text fields
            TextField(
              controller: brandCompanyNameCtrl,
              decoration: InputDecoration(labelText: S.t('companyNameLabel')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: brandAddressCtrl,
              decoration: InputDecoration(labelText: S.t('addressLineLabel')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: brandContact1Ctrl,
              decoration: InputDecoration(labelText: S.t('contactLine1Label')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: brandContact2Ctrl,
              decoration: InputDecoration(labelText: S.t('contactLine2Label')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: brandSignatureCtrl,
              decoration: InputDecoration(labelText: S.t('signatureNameLabel')),
            ),
            const SizedBox(height: 14),

            // Terms
            Text(
              S.t('termsAndConditions'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              S.t('termsHint'),
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'no', label: Text('🇳🇴 NO')),
                ButtonSegment(value: 'en', label: Text('🇬🇧 EN')),
                ButtonSegment(value: 'sv', label: Text('🇸🇪 SV')),
                ButtonSegment(value: 'de', label: Text('🇩🇪 DE')),
              ],
              selected: {_termsEditingLang},
              onSelectionChanged: (selected) {
                setState(() => _termsEditingLang = selected.first);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('terms_$_termsEditingLang'),
              controller: brandTermsCtrls[_termsEditingLang]!,
              maxLines: 10,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: S.t('termsAndConditions'),
              ),
            ),
            const SizedBox(height: 12),

            FilledButton(
              onPressed: _saveBranding,
              child: Text(S.t('save')),
            ),

            const SizedBox(height: 24),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- KJØRETØY ----------------
            InkWell(
              onTap: () => setState(() => _vehiclesExpanded = !_vehiclesExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(
                    _vehiclesExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Kjøretøy (${_vehicleTypes.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (_vehiclesExpanded)
                    FilledButton.icon(
                      onPressed: _showAddVehicleDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Legg til kjøretøy'),
                    ),
                ],
              ),
            ),
            if (_vehiclesExpanded) ...[
              const SizedBox(height: 12),
              if (_vehicleTypes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    'Ingen kjøretøy lagt til ennå. Hardkodede verdier brukes som fallback.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                ...(_vehicleTypes.map((v) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surface,
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
                                  v['name'] as String? ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                if ((v['description'] as String? ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    v['description'] as String,
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (v['is_conference'] == true)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Konferanse',
                                  style: TextStyle(fontSize: 11, color: Colors.orange)),
                            ),
                          TextButton(
                            onPressed: () => _showEditVehicleDialog(v),
                            child: const Text('Rediger'),
                          ),
                          TextButton(
                            onPressed: () => _deleteVehicle(v),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Slett'),
                          ),
                        ],
                      ),
                    ))),
            ],

            const SizedBox(height: 24),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- KJØRETØYTYPER (for dropdown i tilbud) ----------------
            InkWell(
              onTap: () => setState(() => _vehicleCategoriesExpanded = !_vehicleCategoriesExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(
                    _vehicleCategoriesExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Kjøretøytyper (${_vehicleCategories.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (_vehicleCategoriesExpanded)
                    FilledButton.icon(
                      onPressed: _showAddVehicleCategoryDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Legg til type'),
                    ),
                ],
              ),
            ),
            if (_vehicleCategoriesExpanded) ...[
              const SizedBox(height: 4),
              Text(
                'Disse dukker opp i "Kjøretøytype"-dropdown i tilbud.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (_vehicleCategories.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    'Ingen typer lagt til. Standard-verdier brukes.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                ...(_vehicleCategories.map((c) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Text(
                            c['name'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _showEditVehicleCategoryDialog(c),
                            child: const Text('Rediger'),
                          ),
                          TextButton(
                            onPressed: () => _deleteVehicleCategory(c),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Slett'),
                          ),
                        ],
                      ),
                    ))),
            ],
          ],
        ),
      );
  }

  // ── Vehicle dialogs ──────────────────────────────────────────────────

  Future<void> _showAddVehicleDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isConference = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Legg til kjøretøy'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Navn (f.eks. CSS_1034)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Type (f.eks. 16-sleeper)'),
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: isConference,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Konferanse / spesialtype'),
                  onChanged: (v) => setDlgState(() => isConference = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  final cid = activeCompanyNotifier.value?.id;
                  await Supabase.instance.client.from('vehicle_types').insert({
                    'company_id': cid,
                    'name': nameCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'is_conference': isConference,
                    'sort_order': _vehicleTypes.length,
                    'active': true,
                  });
                  clearVehicleConfigCache();
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadVehicleTypes();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Legg til'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditVehicleDialog(Map<String, dynamic> vehicle) async {
    final nameCtrl = TextEditingController(text: vehicle['name'] as String? ?? '');
    final descCtrl = TextEditingController(text: vehicle['description'] as String? ?? '');
    bool isConference = vehicle['is_conference'] == true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Rediger kjøretøy'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Navn')),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Type')),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: isConference,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Konferanse / spesialtype'),
                  onChanged: (v) => setDlgState(() => isConference = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () async {
                try {
                  await Supabase.instance.client.from('vehicle_types').update({
                    'name': nameCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'is_conference': isConference,
                  }).eq('id', vehicle['id'] as String);
                  clearVehicleConfigCache();
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadVehicleTypes();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Lagre'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteVehicle(Map<String, dynamic> vehicle) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett kjøretøy'),
        content: Text('Vil du slette "${vehicle['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
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
      await Supabase.instance.client.from('vehicle_types').update({'active': false}).eq('id', vehicle['id'] as String);
      clearVehicleConfigCache();
      await _loadVehicleTypes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Vehicle category dialogs ─────────────────────────────────────────

  Future<void> _showAddVehicleCategoryDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legg til kjøretøytype'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Navn (f.eks. 16-sleeper, Lastebil)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                final cid = activeCompanyNotifier.value?.id;
                await Supabase.instance.client.from('vehicle_categories').insert({
                  'company_id': cid,
                  'name': nameCtrl.text.trim(),
                  'sort_order': _vehicleCategories.length,
                  'active': true,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadVehicleCategories();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
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

  Future<void> _showEditVehicleCategoryDialog(Map<String, dynamic> cat) async {
    final nameCtrl = TextEditingController(text: cat['name'] as String? ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rediger kjøretøytype'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Navn'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () async {
              try {
                await Supabase.instance.client.from('vehicle_categories').update({
                  'name': nameCtrl.text.trim(),
                }).eq('id', cat['id'] as String);
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadVehicleCategories();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
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

  Future<void> _deleteVehicleCategory(Map<String, dynamic> cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slett kjøretøytype'),
        content: Text('Vil du slette "${cat['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
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
      await Supabase.instance.client.from('vehicle_categories').update({'active': false}).eq('id', cat['id'] as String);
      await _loadVehicleCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Feil: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // =====================================================
  // TAB: EMAIL & INTEGRATIONS
  // =====================================================
  Widget _buildIntegrationsTab(ColorScheme cs) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

            // ---------------- EMAIL ACCOUNT ----------------

            Text(
              S.t('emailAccount'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 6),

            Text(
              S.t('emailAccountDesc'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),

            const SizedBox(height: 10),

            if (_smtpAccount != null) ...[
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _smtpAccount!.email,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (_smtpAccount!.displayName.isNotEmpty)
                          Text(
                            '${_smtpAccount!.displayName} · ${_smtpAccount!.smtpHost}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _openSmtpDialog(existing: _smtpAccount),
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(S.t('edit')),
                  ),
                  TextButton.icon(
                    onPressed: _deleteSmtpAccount,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(S.t('remove')),
                  ),
                ],
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () => _openSmtpDialog(),
                icon: const Icon(Icons.add),
                label: Text(S.t('addEmailAccount')),
              ),
            ],

            const SizedBox(height: 28),

            // ---------------- MICROSOFT OAUTH ----------------
            Text(
              'Microsoft-konto (OAuth)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Hvis din Microsoft-tenant har deaktivert SMTP AUTH (vanlig for '
              'Office 365), koble til med OAuth for å sende via Microsoft Graph.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            if (_msOauthEmail != null) ...[
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _msOauthEmail!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _msOauthBusy ? null : _disconnectMicrosoftOAuth,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('Koble fra'),
                  ),
                ],
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _msOauthBusy ? null : _connectMicrosoftOAuth,
                icon: _msOauthBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Koble til Microsoft'),
              ),
            ],
          ],
        ),
      );
  }

  // =====================================================
  // TAB: PRICING
  // =====================================================
  Widget _buildPricingTab(ColorScheme cs) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

            // ---------------- BANK ACCOUNT ----------------

            Text(
              S.t('invoice'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: 360,
              child: TextField(
                controller: bankAccountCtrl,
                decoration: InputDecoration(
                  labelText: S.t('bankAccountNumber'),
                  hintText: "e.g. 9710.05.12345",
                  prefixIcon: Icon(Icons.account_balance),
                ),
              ),
            ),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- COMPLETE PRICING ----------------

            Text(
              S.t('completePricing'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                SizedBox(width: 170, child: _field(S.t('creoFeeMinimum'), creoFeeMinCtrl, "NOK")),
                SizedBox(width: 170, child: _field(S.t('extraShowFee'), extraShowFeeCtrl, "NOK")),
                SizedBox(width: 170, child: _field(S.t('markup'), markupPctCtrl, "%")),
                SizedBox(width: 170, child: _field(S.t('inEarPrice'), inearPriceCtrl, "NOK")),
                SizedBox(width: 170, child: _field(S.t('transportKmPrice'), transportPerKmCtrl, "NOK/km")),
              ],
            ),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- SWEDISH PRICING MODEL ----------------

            _buildSweSection(context),

            const SizedBox(height: 18),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 18),

            // ---------------- PRICES (Norwegian model) ----------------

            Text(
              S.t('norwegianPricingModel'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [

                SizedBox(
                  width: 240,
                  child: _field(S.t('dayPrice'), dayPriceCtrl, "NOK"),
                ),

                SizedBox(
                  width: 240,
                  child: _field(S.t('extraKmPrice'), extraKmCtrl, "NOK/km"),
                ),

                // Truck: the trailer day price is repurposed as the per-day
                // Mellomlagring (intermediate storage) rate; the km field is
                // hidden. Bus keeps both trailer fields.
                if (getVehicleConfig().label.toLowerCase() == 'lastebil')
                  SizedBox(
                    width: 240,
                    child:
                        _field('Mellomlagring (per dag)', trailerDayCtrl, "NOK/day"),
                  )
                else ...[
                  SizedBox(
                    width: 240,
                    child: _field(S.t('trailerDayPrice'), trailerDayCtrl, "NOK/day"),
                  ),
                  SizedBox(
                    width: 240,
                    child: _field(S.t('trailerKmPrice'), trailerKmCtrl, "NOK/km"),
                  ),
                ],

                SizedBox(
                  width: 240,
                  child: _field(S.t('dDriveDayPrice'), dDriveDayCtrl, "NOK/day"),
                ),

                SizedBox(
                  width: 240,
                  child: _field(S.t('flightTicketPrice'), flightTicketCtrl, "NOK"),
                ),

                SizedBox(
                  width: 240,
                  child: _field(S.t('tollKmRate'), tollKmRateCtrl, "NOK/km"),
                ),
              ],
            ),

            const SizedBox(height: 18),

            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(S.t('save')),
            ),
          ],
        ),
      );
  }

  // =====================================================
  // TAB: ADMIN
  // =====================================================
  Widget _buildAdminTab(ColorScheme cs) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RoutesAdminPage(),
                ),
              );
            },
            icon: const Icon(Icons.route),
            label: Text(S.t('manageRoutes')),
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _runKmSeUpdater,
            icon: const Icon(Icons.map_outlined),
            label: Text(S.t('updateKmSweden')),
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _openAddUserDialog,
            icon: const Icon(Icons.person_add),
            label: Text(S.t('addUser')),
          ),

          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _openChangePasswordDialog,
            icon: const Icon(Icons.lock_reset),
            label: Text(S.t('changePassword')),
          ),

          const SizedBox(height: 24),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 18),

          _buildProfileFieldsSection(cs),
        ],
      ),
    );
  }

  // =====================================================
  // PROFILE FIELDS UI
  // =====================================================
  Widget _buildProfileFieldsSection(ColorScheme cs) {
    final sections = _sections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Profilfelt',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _addSection,
              icon: const Icon(Icons.add),
              label: const Text('Ny hovedbolk'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Definer hva medlemmene skal fylle ut i profilen sin (i mobilappen).',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 12),
        if (_profileFieldsLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (sections.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Ingen bolker definert ennå.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          )
        else
          ...sections.map((s) => _buildSectionCard(s, cs)),
      ],
    );
  }

  Widget _buildSectionCard(ProfileField section, ColorScheme cs) {
    final children = _childrenOf(section.id);
    final expanded = _expandedSections.contains(section.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
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
                _expandedSections.remove(section.id);
              } else {
                _expandedSections.add(section.id);
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
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Endre',
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _editSection(section),
                  ),
                  IconButton(
                    tooltip: 'Slett',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _deleteField(section),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Ingen underbolker.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              )
            else
              ...children.map((c) => _buildFieldRow(c, cs)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: OutlinedButton.icon(
                onPressed: () => _addField(section),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Legg til underbolk'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldRow(ProfileField f, ColorScheme cs) {
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
            onPressed: () => _editField(f),
          ),
          IconButton(
            tooltip: 'Slett',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _deleteField(f),
          ),
        ],
      ),
    );
  }
}

class _FieldDialogResult {
  final String title;
  final ProfileFieldType type;
  final List<String> options;
  final bool required;

  _FieldDialogResult({
    required this.title,
    required this.type,
    required this.options,
    required this.required,
  });
}
