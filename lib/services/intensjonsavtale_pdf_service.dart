import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// IntensjonsavtalePdfService
// Generates a contract / letter-of-intent PDF for a tenant company.
// All selskaps-spesifikke tekster (tittel, header-kontakt, avtaletekst,
// signatur-label, show-label) leses fra `companies.contract_config`, så
// hver tenant kan overstyre alt i Settings.
// ---------------------------------------------------------------------------

class _ContractTranslation {
  final String title;
  final String body;
  const _ContractTranslation({required this.title, required this.body});

  factory _ContractTranslation.fromJson(Map<String, dynamic>? m) {
    return _ContractTranslation(
      title: (m?['title'] as String?) ?? '',
      body:  (m?['body']  as String?) ?? '',
    );
  }
}

class _ContractConfig {
  final String headerContactName;
  final String headerPhone;
  final String headerEmail;
  final String signatureLabel;
  final String showLabel;

  /// Map from locale code (e.g. 'no', 'en', 'sv') to the title+body for
  /// that language. Companies only populate the languages they support.
  final Map<String, _ContractTranslation> translations;

  const _ContractConfig({
    required this.headerContactName,
    required this.headerPhone,
    required this.headerEmail,
    required this.signatureLabel,
    required this.showLabel,
    required this.translations,
  });

  factory _ContractConfig.fromJson(Map<String, dynamic>? m) {
    String pick(String key) {
      final v = m?[key];
      if (v is String) return v;
      return '';
    }
    final rawTrans = m?['translations'];
    final translations = <String, _ContractTranslation>{};
    if (rawTrans is Map) {
      rawTrans.forEach((k, v) {
        if (k is String && v is Map) {
          translations[k] = _ContractTranslation.fromJson(
            Map<String, dynamic>.from(v),
          );
        }
      });
    }
    return _ContractConfig(
      headerContactName: pick('header_contact_name'),
      headerPhone:       pick('header_phone'),
      headerEmail:       pick('header_email'),
      signatureLabel:    pick('signature_label'),
      showLabel:         pick('show_label'),
      translations:      translations,
    );
  }

  /// Returns the translation for [lang], falling back to the first
  /// available translation if that language isn't configured. When
  /// no translations exist at all, returns empty strings.
  _ContractTranslation translationFor(String lang) {
    final match = translations[lang];
    if (match != null) return match;
    if (translations.isNotEmpty) return translations.values.first;
    return const _ContractTranslation(title: '', body: '');
  }
}

class IntensjonsavtalePdfService {
  // --------------------------------------------------------------------------
  // AGREEMENT TEXT — template substitution
  // --------------------------------------------------------------------------

  static String _substitute(
    String template, {
    required String us,
    required String firma,
    required String kontaktperson,
    required String spillested,
  }) {
    return template
        .replaceAll('{us}', us)
        .replaceAll('{firma}', firma)
        .replaceAll('{kontaktperson}', kontaktperson)
        .replaceAll('{spillested}', spillested);
  }

  // --------------------------------------------------------------------------
  // PUBLIC ENTRY POINT
  // --------------------------------------------------------------------------

  /// Returns the main PDF bytes plus any rider PDF attachments.
  /// When [customerSignature] and [companySignature] are provided,
  /// the PDF includes digital signatures with names and dates.
  ///
  /// When [calcLines] and [calcTotal] are provided, the PDF uses those
  /// directly instead of recalculating from raw gig/show data.
  /// [dateEntries] overrides the single-date display for multi-date offers.
  static Future<({Uint8List mainPdf, List<({String filename, Uint8List bytes, bool autoInclude})> riders, String title, String companyName})> generate({
    required Map<String, dynamic> gig,
    required List<Map<String, dynamic>> shows,
    String? customerSignature,
    String? customerSignatureDate,
    String? companySignature,
    String? companySignatureDate,
    List<({String label, double amount})>? calcLines,
    double? calcTotal,
    List<
            ({
              String date,
              String venue,
              bool isRehearsal,
              List<String> shows,
              List<double> showPrices,
              String getIn,
              String rehearsalTime,
              String performance,
              String getOut,
            })>?
        dateEntries,
    bool markupOnAll = false,
    String lang = 'no',
  }) async {
    final isEn = lang == 'en';

    // ── Load tenant company + contract_config ─────────────────────────────
    _ContractConfig config = _ContractConfig.fromJson(null);
    Map<String, dynamic>? tenantCompany;
    String? brandingLogoUrl;
    final tenantCompanyId = gig['company_id'] as String?;
    if (tenantCompanyId != null) {
      try {
        final sb = Supabase.instance.client;
        tenantCompany = await sb
            .from('companies')
            .select('name, address, postal_code, city, country, contract_config')
            .eq('id', tenantCompanyId)
            .maybeSingle();
        config = _ContractConfig.fromJson(
          tenantCompany?['contract_config'] as Map<String, dynamic>?,
        );
        final branding = await sb
            .from('company_branding')
            .select('logo_url')
            .eq('company_id', tenantCompanyId)
            .maybeSingle();
        brandingLogoUrl = branding?['logo_url'] as String?;
      } catch (e) {
        debugPrint('Load contract_config error: $e');
      }
    }
    final tenantName = (tenantCompany?['name'] as String?) ?? '';

    // Pick translation for requested language (or first available fallback)
    final translation = config.translationFor(lang);
    // Localized labels
    final lblTitle = translation.title;
    final lblIssued = isEn ? 'Issued' : 'Utstedt';
    final lblVenueDate = isEn ? 'VENUE AND TIME' : 'SPILLESTED OG TIDSPUNKT';
    final lblVenue = isEn ? 'Venue' : 'Spillested';
    final lblDate = isEn ? 'Date' : 'Dato';
    final lblGetIn = isEn ? 'Get-in' : 'Get-in';
    final lblRehearsal = isEn ? 'Rehearsal' : 'Prøver';
    final lblFirstShow = isEn ? 'First performance' : 'Første opptreden';
    final lblGetOut = isEn ? 'Get-out' : 'Get-out';
    final lblCustomer = isEn ? 'CLIENT' : 'OPPDRAGSGIVER';
    final lblFirma = isEn ? 'Company' : 'Firma';
    final lblContact = isEn ? 'Contact' : 'Kontaktperson';
    final lblPhone = isEn ? 'Phone' : 'Telefon';
    final lblEmail = isEn ? 'Email' : 'E-post';
    final lblNotes = isEn ? 'NOTES' : 'MERKNADER';
    final pdf = pw.Document();

    // Helper: copy asset into a fresh buffer (web ByteData has offset issues)
    Future<Uint8List> loadAssetBytes(String path) async {
      final data = await rootBundle.load(path);
      return Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }

    // On web, custom TTF fonts cause DataView offset errors during rendering,
    // so fall back to built-in Helvetica.
    pw.Font regularFont;
    pw.Font boldFont;
    // Helvetica's built-in PDF font lacks general punctuation (em/en dashes),
    // so prefer the bundled Roboto TTFs which include these glyphs. Calibri
    // ships in the same folder as a fallback for native targets.
    Future<pw.Font> tryLoad(List<String> paths) async {
      for (final p in paths) {
        try {
          final bytes = await loadAssetBytes(p);
          return pw.Font.ttf(ByteData.view(bytes.buffer));
        } catch (_) {}
      }
      return pw.Font.helvetica();
    }

    regularFont = await tryLoad([
      'assets/fonts/Roboto-Regular.ttf',
      'assets/fonts/calibri.ttf',
    ]);
    boldFont = await tryLoad([
      'assets/fonts/Roboto-Bold.ttf',
      'assets/fonts/calibrib.ttf',
    ]);

    // Header logo: use branding.logo_url if uploaded, else fall back to the
    // Complete Drums white asset (only renders correctly on the black
    // header).
    pw.ImageProvider? logo;
    if (brandingLogoUrl != null && brandingLogoUrl.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(brandingLogoUrl));
        if (res.statusCode == 200) {
          logo = pw.MemoryImage(res.bodyBytes);
        }
      } catch (e) {
        debugPrint('Could not fetch branding logo: $e');
      }
    }
    if (logo == null && tenantName.toLowerCase().contains('complete')) {
      try {
        logo = pw.MemoryImage(
            await loadAssetBytes('assets/pdf/logos/CompleteDrumsWhite.png'));
      } catch (_) {
        debugPrint('Could not load PDF logo');
      }
    }

    // Separate black logo for rider attachments (white background).
    Uint8List? riderLogoBytes;
    if (tenantName.toLowerCase().contains('complete')) {
      try {
        riderLogoBytes =
            await loadAssetBytes('assets/pdf/logos/CompleteDrumsBlack.png');
      } catch (_) {
        // Black asset missing — riders render without a logo.
      }
    }

    final nok = NumberFormat('#,##0', isEn ? 'en_US' : 'nb_NO');

    // Extract gig fields
    final dateFrom = gig['date_from'] as String?;
    final dateTo = gig['date_to'] as String?;
    final venueName = gig['venue_name'] as String? ?? '';
    final city = gig['city'] as String? ?? '';
    final country = gig['country'] as String? ?? '';
    final firma = gig['customer_firma'] as String? ?? '';
    final custName = gig['customer_name'] as String? ?? '';
    final custPhone = gig['customer_phone'] as String? ?? '';
    final custEmail = gig['customer_email'] as String? ?? '';
    final performanceTime = gig['performance_time'] as String? ?? '';
    final getInTime = gig['get_in_time'] as String? ?? '';
    final rehearsalTime = gig['rehearsal_time'] as String? ?? '';
    final getOutTime = gig['get_out_time'] as String? ?? '';
    final notesForContract = gig['notes_for_contract'] as String? ?? '';
    final showDesc = gig['show_desc'] as String? ?? '';
    final hasTimes = getInTime.isNotEmpty || rehearsalTime.isNotEmpty || performanceTime.isNotEmpty || getOutTime.isNotEmpty;

    // Date formatting
    final df = DateFormat('dd.MM.yyyy');
    String dateLabel = '';
    if (dateEntries != null && dateEntries.isNotEmpty) {
      dateLabel = dateEntries.map((e) => e.date).join(', ');
    } else if (dateFrom != null) {
      final fromFmt = df.format(DateTime.parse(dateFrom));
      if (dateTo != null && dateTo != dateFrom) {
        dateLabel = '$fromFmt - ${df.format(DateTime.parse(dateTo))}';
      } else {
        dateLabel = fromFmt;
      }
    }

    // Time info — use performance_time (the "Tidspunkt" field from the offer)
    final timeLabel = performanceTime;

    // Use pre-calculated values if provided, otherwise fall back to legacy calc
    final bool useCalcLines = calcLines != null && calcTotal != null;
    double total;
    double markupFactor = 1.0;
    double showsTotal = 0;
    double inearWithMarkup = 0;
    double transportWithMarkup = 0;
    bool inearFromUs = false;
    double transportPrice = 0;

    if (!useCalcLines) {
      inearFromUs = gig['inear_from_us'] == true;
      final inearPrice = (gig['inear_price'] as num?)?.toDouble() ?? 0;
      transportPrice = (gig['transport_price'] as num?)?.toDouble() ?? 0;
      final extraPrice = (gig['extra_price'] as num?)?.toDouble() ?? 0;
      final showsRaw = shows.fold<double>(
          0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
      final basePrice = showsRaw + (inearFromUs ? inearPrice : 0) + transportPrice;
      total = basePrice + extraPrice;
      markupFactor = basePrice > 0 ? total / basePrice : 1.0;
      // All markup goes into show price; transport + inear stay raw
      final showsRawTotal = showsRaw > 0 ? showsRaw : 1;
      showsTotal = total - transportPrice - (inearFromUs ? inearPrice : 0);
      markupFactor = showsTotal / showsRawTotal;
      inearWithMarkup = inearPrice;
      transportWithMarkup = transportPrice;
    } else {
      total = calcTotal;
    }

    // Today's date
    final todayStr = df.format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) {
          return [
            // ── HEADER ──────────────────────────────────────────────────
            _buildHeader(
              boldFont, regularFont, logo,
              companyName: tenantName,
              contactName: config.headerContactName,
              addressLine: [
                tenantCompany?['address'] as String?,
                [
                  tenantCompany?['postal_code'] as String?,
                  tenantCompany?['city'] as String?,
                ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
              ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
              phone: config.headerPhone,
              email: config.headerEmail,
            ),
            pw.SizedBox(height: 20),

            // ── TITLE ───────────────────────────────────────────────────
            if (lblTitle.isNotEmpty) ...[
              pw.Center(
                child: pw.Text(
                  lblTitle,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 20,
                    letterSpacing: 2,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
            ],
            pw.Center(
              child: pw.Text(
                '$lblIssued: $todayStr',
                style: pw.TextStyle(font: regularFont, fontSize: 10,
                    color: PdfColors.grey600),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 12),

            // ── VENUE / DATES ────────────────────────────────────────────
            _buildSection(boldFont, regularFont, lblVenueDate, [
              if (dateEntries != null && dateEntries.length > 1) ...[
                for (int i = 0; i < dateEntries.length; i++) ...[
                  if (i > 0) pw.SizedBox(height: 6),
                  _labelValue(regularFont, boldFont, '$lblDate ${i + 1}',
                      '${dateEntries[i].date} - ${dateEntries[i].venue}'),
                  // Per-date times — only render lines that have a value
                  if (dateEntries[i].getIn.isNotEmpty)
                    _labelValue(regularFont, boldFont, lblGetIn,
                        dateEntries[i].getIn),
                  if (dateEntries[i].rehearsalTime.isNotEmpty)
                    _labelValue(regularFont, boldFont, lblRehearsal,
                        dateEntries[i].rehearsalTime),
                  if (dateEntries[i].performance.isNotEmpty)
                    _labelValue(regularFont, boldFont, lblFirstShow,
                        dateEntries[i].performance),
                  if (dateEntries[i].getOut.isNotEmpty)
                    _labelValue(regularFont, boldFont, lblGetOut,
                        dateEntries[i].getOut),
                ],
              ] else ...[
                _labelValue(regularFont, boldFont, lblVenue,
                    dateEntries != null && dateEntries.isNotEmpty
                        ? dateEntries.first.venue
                        : [venueName, city, country]
                            .where((s) => s.isNotEmpty)
                            .join(', ')),
                _labelValue(regularFont, boldFont, lblDate, dateLabel),
                if (hasTimes) ...[
                  if (getInTime.isNotEmpty)
                    _labelValue(regularFont, boldFont, lblGetIn, getInTime),
                  if (rehearsalTime.isNotEmpty)
                    _labelValue(
                        regularFont, boldFont, lblRehearsal, rehearsalTime),
                  if (performanceTime.isNotEmpty)
                    _labelValue(
                        regularFont, boldFont, lblFirstShow, performanceTime),
                  if (getOutTime.isNotEmpty)
                    _labelValue(regularFont, boldFont, lblGetOut, getOutTime),
                ],
              ],
            ]),
            pw.SizedBox(height: 12),

            // ── CUSTOMER ─────────────────────────────────────────────────
            _buildSection(boldFont, regularFont, lblCustomer, [
              if (firma.isNotEmpty)
                _labelValue(regularFont, boldFont, lblFirma, firma),
              if (custName.isNotEmpty)
                _labelValue(regularFont, boldFont, lblContact, custName),
              if (custPhone.isNotEmpty)
                _labelValue(regularFont, boldFont, lblPhone, custPhone),
              if (custEmail.isNotEmpty)
                _labelValue(regularFont, boldFont, lblEmail, custEmail),
            ]),
            pw.SizedBox(height: 12),

            // ── SHOWS TABLE / PRICE SUMMARY ──────────────────────────────
            if (useCalcLines) ...[
              // Show names as a simple list
              _buildShowsList(boldFont, regularFont, shows, lang: lang, showDesc: showDesc),
              pw.SizedBox(height: 12),
              // Price lines from calc card
              _buildCalcPriceSummary(boldFont, regularFont, nok,
                  lines: calcLines, total: calcTotal, lang: lang,
                  dateEntries: dateEntries,
                  markupOnAll: markupOnAll,
                  showLabel: config.showLabel.isNotEmpty
                      ? config.showLabel
                      : (tenantName.isNotEmpty ? tenantName : 'Show')),
            ] else ...[
              _buildShowsTable(boldFont, regularFont, shows, nok,
                  markupFactor: markupFactor, lang: lang, showDesc: showDesc),
              pw.SizedBox(height: 12),
              _buildPriceSummary(
                boldFont, regularFont, nok,
                shows: shows,
                showsTotal: showsTotal,
                inearFromUs: inearFromUs,
                inearPrice: inearWithMarkup,
                transportPrice: transportWithMarkup,
                total: total,
                lang: lang,
                showLabel: config.showLabel.isNotEmpty
                    ? config.showLabel
                    : (tenantName.isNotEmpty ? tenantName : 'Show'),
              ),
            ],
            pw.SizedBox(height: 16),

            // ── NOTES FOR CONTRACT ─────────────────────────────────────────
            if (notesForContract.isNotEmpty) ...[
              _buildSection(boldFont, regularFont, lblNotes, [
                pw.Text(notesForContract,
                    style: pw.TextStyle(font: regularFont, fontSize: 10)),
              ]),
              pw.SizedBox(height: 12),
            ],

            // ── SIGNATURES ────────────────────────────────────────────────
            _buildSignature(
              boldFont, regularFont, firma,
              customerSignature: customerSignature,
              customerSignatureDate: customerSignatureDate,
              companySignature: companySignature,
              companySignatureDate: companySignatureDate,
              tenantLabel: config.signatureLabel.isNotEmpty
                  ? config.signatureLabel
                  : (tenantName.isNotEmpty ? 'For $tenantName' : 'For'),
              tenantContactFallback: config.headerContactName,
              lang: lang,
            ),
            pw.SizedBox(height: 20),

            // ── AGREEMENT TEXT ────────────────────────────────────────────
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 10),
            if (translation.body.isNotEmpty)
              pw.Text(
                _substitute(
                  translation.body,
                  us: tenantName,
                  firma: firma,
                  kontaktperson: custName,
                  spillested: dateEntries != null && dateEntries.isNotEmpty
                      ? dateEntries.map((e) => e.venue).toSet().join(', ')
                      : [venueName, city].where((s) => s.isNotEmpty).join(' - '),
                ),
                style: pw.TextStyle(font: regularFont, fontSize: 8.5,
                    lineSpacing: 1.2),
              ),
          ];
        },
      ),
    );

    final mainPdfBytes = await pdf.save();

    // ── Collect rider PDFs from database ──────────────────────────────────
    final riderAttachments =
        <({String filename, Uint8List bytes, bool autoInclude})>[];

    try {
      final companyId = gig['company_id'] as String?;
      if (companyId != null) {
        final sb = Supabase.instance.client;
        // Select * so the query keeps working even if the optional text-rider
        // columns (body_text / quantity_source / quantity_fixed) haven't been
        // added yet by the migration.
        final riderRows = await sb
            .from('company_riders')
            .select('*')
            .eq('company_id', companyId)
            .eq('active', true)
            .order('sort_order');

        final showNames = shows
            .map((s) => (s['show_name'] as String? ?? '').toLowerCase())
            .toList();

        // Sum participant counts across all selected shows
        int sumOf(String key) => shows.fold<int>(
            0, (s, sh) => s + ((sh[key] as num?)?.toInt() ?? 0));
        final totalDrummers = sumOf('drummers');
        final totalDancers = sumOf('dancers');
        final totalOthers = sumOf('others');
        final showTotal = totalDrummers + totalDancers + totalOthers;

        int countFor(Map<String, dynamic> r) {
          final src = (r['quantity_source'] as String?) ?? '';
          switch (src) {
            case 'drummers':
              return totalDrummers;
            case 'dancers':
              return totalDancers;
            case 'others':
              return totalOthers;
            case 'show_total':
              return showTotal;
            case 'fixed':
              return (r['quantity_fixed'] as num?)?.toInt() ?? 1;
            default:
              return 1;
          }
        }

        // Return ALL active riders so the send dialog can offer them as
        // selectable attachments. Riders matching always_attach or show_match
        // get autoInclude=true so they are pre-checked.
        for (final r in (riderRows as List)) {
          final m = r as Map<String, dynamic>;
          final showMatch = m['show_match'] as String? ?? '';
          final alwaysAttach = m['always_attach'] == true;
          final bodyText = (m['body_text'] as String? ?? '').trim();
          final filePath = m['file_path'] as String?;
          final isTextRider = filePath == null || filePath.isEmpty;
          final rawName = m['name'] as String? ?? 'rider';

          // Skip riders that target a different language. Language-agnostic
          // riders (no NO/EN tag in the name) are always included.
          final riderLang = _detectRiderLang(rawName);
          if (riderLang.isNotEmpty && riderLang != lang) continue;

          // Strip the language tag from the visible name and resolve any
          // {antall} placeholders against the actual count.
          final cleanName = _stripLangTag(rawName);

          bool autoInclude = alwaysAttach;
          if (!autoInclude && showMatch.isNotEmpty) {
            autoInclude = showNames.any((s) => s.contains(showMatch));
          }

          final count = countFor(m);
          // Dynamic-quantity text riders disappear when count is 0
          if (isTextRider && count <= 0) continue;

          final substitutedName = _substituteRiderCount(cleanName, count);
          if (isTextRider) {
            if (bodyText.isEmpty) continue;
            try {
              final pdfBytes = await _buildTextRiderPdf(
                regularFont: regularFont,
                boldFont: boldFont,
                title: cleanName,
                bodyText: bodyText,
                quantity: count,
                logoBytes: riderLogoBytes,
              );
              riderAttachments.add((
                filename: '$substitutedName.pdf',
                bytes: pdfBytes,
                autoInclude: autoInclude,
              ));
            } catch (e) {
              debugPrint('Error building text rider: $e');
            }
          } else {
            try {
              final bytes = await sb.storage.from('riders').download(filePath);
              riderAttachments.add((
                filename: '$substitutedName.pdf',
                bytes: bytes,
                autoInclude: autoInclude,
              ));
            } catch (e) {
              debugPrint('Error downloading rider: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading riders: $e');
    }

    return (
      mainPdf: mainPdfBytes,
      riders: riderAttachments,
      title: lblTitle,
      companyName: tenantName,
    );
  }

  // --------------------------------------------------------------------------
  // HEADER
  // --------------------------------------------------------------------------

  static pw.Widget _buildHeader(
    pw.Font bold,
    pw.Font regular,
    pw.ImageProvider? logo, {
    required String companyName,
    required String contactName,
    required String addressLine,
    required String phone,
    required String email,
  }) {
    final line2 = [
      if (contactName.isNotEmpty) contactName,
      if (addressLine.isNotEmpty) addressLine,
    ].join('  ·  ');
    final line3 = [
      if (phone.isNotEmpty) phone,
      if (email.isNotEmpty) email,
    ].join('  ·  ');
    // Negative margin to counteract the 40px page margin on top/left/right
    return pw.Container(
      margin: const pw.EdgeInsets.only(left: -40, right: -40, top: -40),
      width: double.infinity,
      height: 80,
      color: PdfColors.black,
      child: pw.Stack(
        children: [
          // Logo left (if available)
          if (logo != null)
            pw.Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: pw.Center(
                child: pw.Image(
                  logo,
                  height: 65,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
          // Contact info right
          pw.Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (companyName.isNotEmpty)
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 10,
                      color: PdfColors.white,
                    ),
                  ),
                if (line2.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    line2,
                    style: pw.TextStyle(
                        font: regular, fontSize: 9, color: PdfColors.grey300),
                  ),
                ],
                if (line3.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    line3,
                    style: pw.TextStyle(
                        font: regular, fontSize: 9, color: PdfColors.grey300),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SECTION
  // --------------------------------------------------------------------------

  static pw.Widget _buildSection(
    pw.Font bold,
    pw.Font regular,
    String title,
    List<pw.Widget> children,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: bold,
            fontSize: 11,
            color: PdfColors.grey800,
            letterSpacing: 1,
          ),
        ),
        pw.SizedBox(height: 6),
        ...children,
      ],
    );
  }

  static pw.Widget _labelValue(
    pw.Font regular,
    pw.Font bold,
    String label,
    String value,
  ) {
    if (value.isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                  font: regular, fontSize: 10, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: bold, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SHOWS TABLE
  // --------------------------------------------------------------------------

  static pw.Widget _buildShowsTable(
    pw.Font bold,
    pw.Font regular,
    List<Map<String, dynamic>> shows,
    NumberFormat nok, {
    double markupFactor = 1.0,
    String lang = 'no',
    String showDesc = '',
  }) {
    final isEn = lang == 'en';
    final headerStyle = pw.TextStyle(
        font: bold, fontSize: 9.5, color: PdfColors.white);
    final boldCell = pw.TextStyle(font: bold, fontSize: 10);

    final headerBg = PdfColors.black;
    final rowBg = PdfColors.grey100;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          isEn ? 'SHOW OVERVIEW' : 'SHOW-OVERSIKT',
          style: pw.TextStyle(
            font: bold,
            fontSize: 11,
            color: PdfColors.grey800,
            letterSpacing: 1,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FixedColumnWidth(90),
          },
          children: [
            // Header row
            pw.TableRow(
              decoration: pw.BoxDecoration(color: headerBg),
              children: [
                _cell('Show', headerStyle, pw.Alignment.centerLeft),
                _cell(isEn ? 'Price' : 'Pris', headerStyle, pw.Alignment.centerRight),
              ],
            ),
            // Data rows
            ...shows.asMap().entries.map((entry) {
              final i = entry.key;
              final show = entry.value;
              final isEven = i % 2 == 0;
              final bg = isEven ? rowBg : PdfColors.white;
              final price = ((show['price'] as num?)?.toDouble() ?? 0) * markupFactor;
              final ekstra = show['ekstrainnslag'] as String? ?? '';
              final name = show['show_name'] as String? ?? '';
              final nameWithEkstra = ekstra.isNotEmpty
                  ? '$name\n$ekstra'
                  : name;
              // Build show name cell with optional italic description
              final showNameWidget = pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(nameWithEkstra, style: boldCell),
                    if (showDesc.isNotEmpty)
                      pw.Text(showDesc,
                          style: pw.TextStyle(
                            font: regular,
                            fontSize: 9,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          )),
                  ],
                ),
              );
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  showNameWidget,
                  _cell(_money(nok, price, isEn),
                      boldCell, pw.Alignment.centerRight),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(
      String text, pw.TextStyle style, pw.Alignment align) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: style),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SHOWS LIST (simple — used with calcLines mode)
  // --------------------------------------------------------------------------

  static pw.Widget _buildShowsList(
    pw.Font bold,
    pw.Font regular,
    List<Map<String, dynamic>> shows, {
    String lang = 'no',
    String showDesc = '',
  }) {
    final isEn = lang == 'en';
    if (showDesc.trim().isEmpty) return pw.SizedBox();
    return _buildSection(
        bold, regular, isEn ? 'SHOW OVERVIEW' : 'SHOW-OVERSIKT', [
      pw.Text(
        showDesc,
        style: pw.TextStyle(font: regular, fontSize: 10),
      ),
    ]);
  }

  static String _money(NumberFormat nok, double v, bool isEn) {
    return isEn ? 'NOK ${nok.format(v)}' : 'kr ${nok.format(v)}';
  }

  /// Detects the language tag in a rider name. Returns 'no', 'en' or ''
  /// (no tag / language-agnostic). Looks for whole-word "NO" or "EN".
  static String _detectRiderLang(String name) {
    final hasNo = RegExp(r'\bNO\b', caseSensitive: false).hasMatch(name);
    final hasEn = RegExp(r'\bEN\b', caseSensitive: false).hasMatch(name);
    if (hasNo && !hasEn) return 'no';
    if (hasEn && !hasNo) return 'en';
    return '';
  }

  /// Strips a "NO" or "EN" language tag from the rider name so it doesn't
  /// surface in the title or filename.
  static String _stripLangTag(String name) {
    final cleaned =
        name.replaceAll(RegExp(r'\b(NO|EN)\b', caseSensitive: false), '');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Substitute `{antall}` / `{count}` placeholders in rider body text.
  /// Supports basic arithmetic so `{antall*2}`, `{antall+1}`, `{antall-1}`,
  /// `{antall/2}` work too.
  static String _substituteRiderCount(String body, int quantity) {
    final re = RegExp(
      r'\{(?:antall|count)(?:\s*([*+\-/x×])\s*(\d+(?:[\.,]\d+)?))?\s*\}',
      caseSensitive: false,
    );
    return body.replaceAllMapped(re, (m) {
      final op = m.group(1);
      final raw = m.group(2);
      if (op == null || raw == null) return quantity.toString();
      final n = double.tryParse(raw.replaceAll(',', '.'));
      if (n == null) return quantity.toString();
      double result;
      switch (op) {
        case '*':
        case 'x':
        case '×':
          result = quantity * n;
          break;
        case '+':
          result = quantity + n;
          break;
        case '-':
          result = quantity - n;
          break;
        case '/':
          result = n == 0 ? 0 : quantity / n;
          break;
        default:
          return quantity.toString();
      }
      if (result == result.truncateToDouble()) return result.toInt().toString();
      return result.toStringAsFixed(1).replaceAll('.', ',');
    });
  }

  /// Build a small PDF document for a text-based rider that scales with the
  /// number of performers in the show. Layout mirrors the existing
  /// HOSPITALITY rider: centered logo, centered title between two horizontal
  /// rules, then the body text. Both title and body support `{antall}`
  /// placeholders.
  static Future<Uint8List> _buildTextRiderPdf({
    required pw.Font regularFont,
    required pw.Font boldFont,
    required String title,
    required String bodyText,
    required int quantity,
    Uint8List? logoBytes,
  }) async {
    final substitutedTitle = _substituteRiderCount(title, quantity);
    final substitutedBody = _substituteRiderCount(bodyText, quantity);
    final pdf = pw.Document();
    pw.MemoryImage? logo;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      try {
        logo = pw.MemoryImage(logoBytes);
      } catch (e) {
        debugPrint('Rider logo decode failed: $e');
      }
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(50, 40, 50, 40),
        build: (ctx) => [
          if (logo != null)
            pw.Center(
              child: pw.Container(
                height: 150,
                margin: const pw.EdgeInsets.only(bottom: 24),
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
            ),
          // Title row with horizontal rules on each side
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Container(height: 1, color: PdfColors.black),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 16),
                child: pw.Text(
                  substitutedTitle,
                  style: pw.TextStyle(font: regularFont, fontSize: 12),
                ),
              ),
              pw.Expanded(
                child: pw.Container(height: 1, color: PdfColors.black),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            substitutedBody,
            style: pw.TextStyle(font: regularFont, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // --------------------------------------------------------------------------
  // CALC PRICE SUMMARY (from calc card — used with calcLines mode)
  // --------------------------------------------------------------------------

  static pw.Widget _buildCalcPriceSummary(
    pw.Font bold,
    pw.Font regular,
    NumberFormat nok, {
    required List<({String label, double amount})> lines,
    required double total,
    required String showLabel,
    String lang = 'no',
    List<
            ({
              String date,
              String venue,
              bool isRehearsal,
              List<String> shows,
              List<double> showPrices,
              String getIn,
              String rehearsalTime,
              String performance,
              String getOut,
            })>?
        dateEntries,
    bool markupOnAll = false,
  }) {
    final isEn = lang == 'en';
    double performerFeesRaw = 0;
    double transportAmount = 0;
    double inearAmount = 0;
    double rehearsalAmount = 0;
    double markupAmount = 0;
    // Free-text Ekstrakostnader lines (any label that isn't one of the known
    // calc lines) — rendered at face value on equal footing with shows.
    final customExtras = <({String label, double amount})>[];
    for (final l in lines) {
      if (l.label == 'Utøverhyrer' || l.label == 'Performer fees') {
        performerFeesRaw = l.amount;
      } else if (l.label == 'CompleteKonto' || l.label == 'BookingHonorar') {
        markupAmount += l.amount;
      } else if (l.label == 'Transport') {
        transportAmount = l.amount;
      } else if (l.label == 'In-Ear') {
        inearAmount = l.amount;
      } else if (l.label == 'Prøver') {
        rehearsalAmount = l.amount;
      } else if (l.amount != 0) {
        customExtras.add((label: l.label, amount: l.amount));
      }
    }

    // Distribute markup. markupOnAll = true means markup applies ONLY to
    // performer/rehearsal fees; markupOnAll = false (default) means markup
    // applies to performer fees + transport + rehearsal (everything except
    // in-ear). See gig_offer_page.dart _recalc().
    final markupBase = markupOnAll
        ? (performerFeesRaw + rehearsalAmount)
        : (performerFeesRaw + transportAmount + rehearsalAmount);
    final markupPct = markupBase > 0 ? markupAmount / markupBase : 0.0;

    final performerFeesWithMarkup = performerFeesRaw * (1 + markupPct);
    final transportWithMarkup = markupOnAll
        ? transportAmount
        : transportAmount * (1 + markupPct);
    // rehearsalAmount with markup is shown as kr 0 per rehearsal date in the
    // per-date breakdown (consistent with current UX), so it's not a separate
    // visible line here.

    final entries = dateEntries ?? const [];
    final perfDates = entries.where((e) => !e.isRehearsal).toList();

    // Sum of raw show prices across all performance dates — used to spread
    // the per-show portion of performerFeesWithMarkup proportionally to each
    // show's raw price (so main shows weighted by creo×perf, extras by
    // extraShow×perf or custom price).
    double totalRawShowPrice = 0;
    for (final e in perfDates) {
      for (final p in e.showPrices) {
        totalRawShowPrice += p;
      }
    }
    // Fallback: when caller didn't supply per-show prices, fall back to an
    // even split across all shows (legacy behaviour).
    int totalShowsCount = 0;
    for (final e in perfDates) {
      totalShowsCount += e.shows.isNotEmpty ? e.shows.length : 1;
    }
    final pricePerShowEven =
        totalShowsCount > 0 ? performerFeesWithMarkup / totalShowsCount : 0.0;

    final extraLines = <({String label, double amount})>[
      if (inearAmount > 0)
        (label: isEn ? 'In-ear monitor' : 'In-ear monitoring', amount: inearAmount),
      if (transportWithMarkup > 0)
        (label: 'Transport', amount: transportWithMarkup),
      // Ekstrakostnader — face value, no markup.
      ...customExtras,
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            isEn ? 'PRICE SUMMARY' : 'PRISOPPSUMMERING',
            style: pw.TextStyle(
              font: bold,
              fontSize: 11,
              color: PdfColors.grey800,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 8),
          // Per-date breakdown — chronological dates, price after each one.
          // Performance dates show their share of the show total; rehearsal
          // dates show kr 0.
          if (entries.isNotEmpty) ...[
            ...entries.expand<pw.Widget>((e) {
              final rows = <pw.Widget>[];
              if (e.isRehearsal) {
                rows.add(pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${e.date} - ${isEn ? 'Rehearsal' : 'Prøve'}',
                          style: pw.TextStyle(font: regular, fontSize: 10),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(_money(nok, 0.0, isEn),
                          style: pw.TextStyle(font: bold, fontSize: 10)),
                    ],
                  ),
                ));
                return rows;
              }
              if (e.shows.isEmpty) {
                rows.add(pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(e.date,
                            style: pw.TextStyle(font: regular, fontSize: 10)),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(_money(nok, pricePerShowEven, isEn),
                          style: pw.TextStyle(font: bold, fontSize: 10)),
                    ],
                  ),
                ));
                return rows;
              }
              // Date header (no amount), then one row per show below it.
              rows.add(pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2, top: 2),
                child: pw.Text(
                  e.date,
                  style: pw.TextStyle(font: bold, fontSize: 10),
                ),
              ));
              // Rule: extras show their raw price (perf × extraShowFee or
              // custom), main show absorbs whatever is left of this date's
              // share of performerFeesWithMarkup. Main = highest raw price,
              // ties broken by lowest index.
              int mainIdx = 0;
              double mainRaw = -1;
              for (int i = 0; i < e.showPrices.length; i++) {
                if (e.showPrices[i] > mainRaw) {
                  mainRaw = e.showPrices[i];
                  mainIdx = i;
                }
              }
              double dateRawTotal = 0;
              for (final p in e.showPrices) {
                dateRawTotal += p;
              }
              final dateShareWithMarkup = totalRawShowPrice > 0
                  ? (dateRawTotal / totalRawShowPrice) * performerFeesWithMarkup
                  : 0.0;
              double extrasRawSum = 0;
              for (int i = 0; i < e.showPrices.length; i++) {
                if (i != mainIdx) extrasRawSum += e.showPrices[i];
              }
              final mainDisplay = dateShareWithMarkup - extrasRawSum;
              for (int i = 0; i < e.shows.length; i++) {
                final showName = e.shows[i];
                double showAmount;
                if (totalRawShowPrice <= 0 || i >= e.showPrices.length) {
                  showAmount = pricePerShowEven;
                } else if (i == mainIdx) {
                  showAmount = mainDisplay;
                } else {
                  showAmount = e.showPrices[i];
                }
                rows.add(pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3, left: 12),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(showName,
                            style: pw.TextStyle(font: regular, fontSize: 10)),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(_money(nok, showAmount, isEn),
                          style: pw.TextStyle(font: bold, fontSize: 10)),
                    ],
                  ),
                ));
              }
              return rows;
            }),
            if (extraLines.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
            ],
          ],
          ...extraLines.map((l) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(l.label,
                        style: pw.TextStyle(font: regular, fontSize: 10)),
                    pw.Text(_money(nok, l.amount, isEn),
                        style: pw.TextStyle(font: bold, fontSize: 10)),
                  ],
                ),
              )),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1, color: PdfColors.black),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL',
                  style: pw.TextStyle(font: bold, fontSize: 13)),
              pw.Text(_money(nok, total, isEn),
                  style: pw.TextStyle(font: bold, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // PRICE SUMMARY (legacy — used without calcLines)
  // --------------------------------------------------------------------------

  static pw.Widget _buildPriceSummary(
    pw.Font bold,
    pw.Font regular,
    NumberFormat nok, {
    required List<Map<String, dynamic>> shows,
    required double showsTotal,
    required bool inearFromUs,
    required double inearPrice,
    required double transportPrice,
    required double total,
    required String showLabel,
    String lang = 'no',
  }) {
    final isEn = lang == 'en';
    final effectiveShowLabel = shows.length == 1
        ? (shows.first['show_name'] as String? ?? showLabel)
        : showLabel;
    final rows = <_PriceLine>[
      _PriceLine(effectiveShowLabel, showsTotal),
      if (inearFromUs && inearPrice > 0)
        _PriceLine(isEn ? 'In-ear monitor' : 'In-ear monitoring', inearPrice),
      if (transportPrice > 0) _PriceLine('Transport', transportPrice),
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            isEn ? 'PRICE SUMMARY' : 'PRISOPPSUMMERING',
            style: pw.TextStyle(
              font: bold,
              fontSize: 11,
              color: PdfColors.grey800,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 8),
          ...rows.map((r) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(r.label,
                        style:
                            pw.TextStyle(font: regular, fontSize: 10)),
                    pw.Text(_money(nok, r.amount, isEn),
                        style: pw.TextStyle(font: bold, fontSize: 10)),
                  ],
                ),
              )),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1, color: PdfColors.black),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL',
                style: pw.TextStyle(font: bold, fontSize: 13),
              ),
              pw.Text(
                _money(nok, total, isEn),
                style: pw.TextStyle(font: bold, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // SIGNATURE BLOCK
  // --------------------------------------------------------------------------

  static pw.Widget _buildSignature(
    pw.Font bold,
    pw.Font regular,
    String customerFirma, {
    String? customerSignature,
    String? customerSignatureDate,
    String? companySignature,
    String? companySignatureDate,
    required String tenantLabel,
    required String tenantContactFallback,
    String lang = 'no',
  }) {
    final isEn = lang == 'en';
    final dateLbl = isEn ? 'Date' : 'Dato';
    final clientFallback = isEn ? 'Client' : 'Oppdragsgiver';
    final tenantFallbackLine = tenantContactFallback.isNotEmpty
        ? '$tenantContactFallback  ·  $dateLbl: _______________'
        : '$dateLbl: _______________';
    return pw.Row(
      children: [
        // Tenant side
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                tenantLabel,
                style: pw.TextStyle(font: bold, fontSize: 10),
              ),
              pw.SizedBox(height: 6),
              if (companySignature != null) ...[
                pw.Text(
                  companySignature,
                  style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.blue900),
                ),
                pw.SizedBox(height: 4),
              ] else
                pw.SizedBox(height: 24),
              pw.Container(
                height: 1,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black),
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                companySignature != null
                    ? '$companySignature  ·  $dateLbl: ${companySignatureDate ?? ''}'
                    : tenantFallbackLine,
                style: pw.TextStyle(
                    font: regular, fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 40),
        // Customer side
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'For ${customerFirma.isNotEmpty ? customerFirma : clientFallback}',
                style: pw.TextStyle(font: bold, fontSize: 10),
              ),
              pw.SizedBox(height: 6),
              if (customerSignature != null) ...[
                pw.Text(
                  customerSignature,
                  style: pw.TextStyle(font: bold, fontSize: 14, color: PdfColors.blue900),
                ),
                pw.SizedBox(height: 4),
              ] else
                pw.SizedBox(height: 24),
              pw.Container(
                height: 1,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black),
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                customerSignature != null
                    ? '$customerSignature  ·  $dateLbl: ${customerSignatureDate ?? ''}'
                    : (isEn
                        ? 'Name and title  ·  $dateLbl: _______________'
                        : 'Navn og tittel  ·  $dateLbl: _______________'),
                style: pw.TextStyle(
                    font: regular, fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// HELPERS
// ---------------------------------------------------------------------------

class _PriceLine {
  final String label;
  final double amount;
  const _PriceLine(this.label, this.amount);
}
