import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ---------------------------------------------------------------------------
// IntensjonsavtalePdfService
// Generates an "Intensjonsavtale" (intention agreement) PDF for Complete Drums.
// ---------------------------------------------------------------------------

class IntensjonsavtalePdfService {
  // --------------------------------------------------------------------------
  // AGREEMENT TEXT (from Excel template)
  // --------------------------------------------------------------------------

  static String _agreementText({
    required String firma,
    required String kontaktperson,
    required String spillested,
    required String tidsrom,
  }) => '''Dette er en intensjonsavtale mellom Complete Drums og $firma v/ $kontaktperson, og forutsettes godkjent før Complete holder av dato eller begynner noen som helst form for forberedelser.

Dersom intensjonsavtalen ikke er kansellert av noen parter senest 61 dager før oppdragsdato, blir den bindende for begge parter.

Det er kun oppdragsdatoen(e) nedenfor som holdes av. Dersom det er behov for prøver etc. må dette opplyses om og beregnes inn i denne avtalen før den godkjennes.

Begge parter, både Complete og $firma, kan avlyse bookingen tidligere enn 60 dager før oppdraget skulle finne sted, uten videre følger.

Dersom $firma avlyser bookingen senere enn 60 dager før oppdraget skulle funnet sted, faktureres 50% av honoraret i oppreisning.

Dersom $firma avlyser bookingen innen 30 dager før oppdraget skulle funnet sted, plikter $firma å betale ut honoraret i sin helhet.

Dersom Complete avlyser innenfor 60 dager før oppdraget skulle funnet sted, plikter Complete å være behjelpelig med å få på plass en tilfredsstillende erstatning.

Dersom intensjonsavtalen godkjennes innenfor fristen på 60 dager, har Complete uansett 7 dager på seg til å kartlegge tilgjengeligheten, før bindingen blir gjeldende. Hører du ingenting, har vi en avtale.

Vedlagt ligger raider(e) - Det som står om sceneareale må leses nøye.

OBS! Complete har omgående behov for bekreftet Getin-tid, prøvetid og tid for opptreden, samt en planskisse med inntegninger og mål av sal, scene, scenetilkomster, bord, stoler, passasjer i salen og dører.
NB! Alle opptredener registreres til Tono og $firma vil bli fakturert direkte av de.

Spillested: $spillested
Tidsrom vi holder av: $tidsrom''';

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
  static Future<({Uint8List mainPdf, List<({String filename, Uint8List bytes})> riders})> generate({
    required Map<String, dynamic> gig,
    required List<Map<String, dynamic>> shows,
    String? customerSignature,
    String? customerSignatureDate,
    String? companySignature,
    String? companySignatureDate,
    List<({String label, double amount})>? calcLines,
    double? calcTotal,
    List<({String date, String venue})>? dateEntries,
  }) async {
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
    if (kIsWeb) {
      regularFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    } else {
      try {
        regularFont = pw.Font.ttf(ByteData.view(
            (await loadAssetBytes('assets/fonts/Calibri.ttf')).buffer));
        boldFont = pw.Font.ttf(ByteData.view(
            (await loadAssetBytes('assets/fonts/CalibriBold.ttf')).buffer));
      } catch (_) {
        regularFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }
    }

    pw.ImageProvider? logo;
    try {
      logo = pw.MemoryImage(
          await loadAssetBytes('assets/pdf/logos/CompleteDrumsWhite.png'));
    } catch (_) {
      debugPrint('Could not load PDF logo');
    }

    final nok = NumberFormat('#,##0', 'nb_NO');

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
    final notesForContract = gig['notes_for_contract'] as String? ?? '';

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
      showsTotal = showsRaw * markupFactor;
      inearWithMarkup = inearPrice * markupFactor;
      transportWithMarkup = transportPrice * markupFactor;
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
            if (logo != null)
              _buildHeader(boldFont, regularFont, logo),
            pw.SizedBox(height: 20),

            // ── TITLE ───────────────────────────────────────────────────
            pw.Center(
              child: pw.Text(
                'INTENSJONSAVTALE',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 20,
                  letterSpacing: 2,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Utstedt: $todayStr',
                style: pw.TextStyle(font: regularFont, fontSize: 10,
                    color: PdfColors.grey600),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 12),

            // ── VENUE / DATES ────────────────────────────────────────────
            _buildSection(boldFont, regularFont, 'SPILLESTED OG TIDSPUNKT', [
              if (dateEntries != null && dateEntries.length > 1) ...[
                for (int i = 0; i < dateEntries.length; i++)
                  _labelValue(regularFont, boldFont, 'Dato ${i + 1}',
                      '${dateEntries[i].date} - ${dateEntries[i].venue}'),
              ] else ...[
                _labelValue(regularFont, boldFont, 'Spillested',
                    dateEntries != null && dateEntries.isNotEmpty
                        ? dateEntries.first.venue
                        : [venueName, city, country]
                            .where((s) => s.isNotEmpty)
                            .join(', ')),
                _labelValue(regularFont, boldFont, 'Dato', dateLabel),
              ],
              if (timeLabel.isNotEmpty)
                _labelValue(regularFont, boldFont, 'Tider', timeLabel),
            ]),
            pw.SizedBox(height: 12),

            // ── CUSTOMER ─────────────────────────────────────────────────
            _buildSection(boldFont, regularFont, 'OPPDRAGSGIVER', [
              if (firma.isNotEmpty)
                _labelValue(regularFont, boldFont, 'Firma', firma),
              if (custName.isNotEmpty)
                _labelValue(regularFont, boldFont, 'Kontaktperson', custName),
              if (custPhone.isNotEmpty)
                _labelValue(regularFont, boldFont, 'Telefon', custPhone),
              if (custEmail.isNotEmpty)
                _labelValue(regularFont, boldFont, 'E-post', custEmail),
            ]),
            pw.SizedBox(height: 12),

            // ── SHOWS TABLE / PRICE SUMMARY ──────────────────────────────
            if (useCalcLines) ...[
              // Show names as a simple list
              _buildShowsList(boldFont, regularFont, shows),
              pw.SizedBox(height: 12),
              // Price lines from calc card
              _buildCalcPriceSummary(boldFont, regularFont, nok,
                  lines: calcLines, total: calcTotal),
            ] else ...[
              _buildShowsTable(boldFont, regularFont, shows, nok,
                  markupFactor: markupFactor),
              pw.SizedBox(height: 12),
              _buildPriceSummary(
                boldFont, regularFont, nok,
                shows: shows,
                showsTotal: showsTotal,
                inearFromUs: inearFromUs,
                inearPrice: inearWithMarkup,
                transportPrice: transportWithMarkup,
                total: total,
              ),
            ],
            pw.SizedBox(height: 16),

            // ── NOTES FOR CONTRACT ─────────────────────────────────────────
            if (notesForContract.isNotEmpty) ...[
              _buildSection(boldFont, regularFont, 'MERKNADER', [
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
            ),
            pw.SizedBox(height: 20),

            // ── AGREEMENT TEXT ────────────────────────────────────────────
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 10),
            pw.Text(
              _agreementText(
                firma: firma,
                kontaktperson: custName,
                spillested: dateEntries != null && dateEntries.isNotEmpty
                    ? dateEntries.map((e) => e.venue).toSet().join(', ')
                    : [venueName, city].where((s) => s.isNotEmpty).join(' - '),
                tidsrom: '$dateLabel${performanceTime.isNotEmpty ? ' kl $performanceTime' : ''}',
              ),
              style: pw.TextStyle(font: regularFont, fontSize: 8.5,
                  lineSpacing: 1.2),
            ),
          ];
        },
      ),
    );

    final mainPdfBytes = await pdf.save();

    // ── Collect rider PDFs as separate attachments ─────────────────────────
    final riderAttachments = <({String filename, Uint8List bytes})>[];

    if (!kIsWeb) {
      final riderBase =
          '/Users/michaelthogersen/Dropbox/Complete Dokumenter/4-Riders';
      const riderMap = <String, String>{
        'taikwho': 'TaikWho Rider 2026/TaikWho Teknisk Rider 2026.pdf',
        'completeshow':
            'CompleteShow Rider 2025/CompleteShow Teknisk Rider 2026.pdf',
        'londonshow':
            'LondonShow Rider 2025/LondonShow Teknisk Rider 2025.pdf',
      };
      const hospitalityFile = 'HOSPITALITY.pdf';

      // Match show names to riders
      final addedPaths = <String>{};
      for (final show in shows) {
        final name = (show['show_name'] as String? ?? '').toLowerCase();
        for (final entry in riderMap.entries) {
          if (name.contains(entry.key)) {
            addedPaths.add('$riderBase/${entry.value}');
          }
        }
      }
      // Always add hospitality
      addedPaths.add('$riderBase/$hospitalityFile');

      for (final path in addedPaths) {
        try {
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            // Use just the filename, not the full path
            final filename = path.split('/').last;
            riderAttachments.add((filename: filename, bytes: bytes));
          } else {
            debugPrint('Rider not found: $path');
          }
        } catch (e) {
          debugPrint('Error reading rider $path: $e');
        }
      }
    }

    return (mainPdf: mainPdfBytes, riders: riderAttachments);
  }

  // --------------------------------------------------------------------------
  // HEADER
  // --------------------------------------------------------------------------

  static pw.Widget _buildHeader(
      pw.Font bold, pw.Font regular, pw.ImageProvider logo) {
    // Negative margin to counteract the 40px page margin on top/left/right
    return pw.Container(
      margin: const pw.EdgeInsets.only(left: -40, right: -40, top: -40),
      width: double.infinity,
      height: 80,
      color: PdfColors.black,
      child: pw.Stack(
        children: [
          // Logo left
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
                pw.Text(
                  'Complete Drums',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 10,
                    color: PdfColors.white,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Stian Skog  ·  Holteveien 18C, 1410 Kolbotn',
                  style: pw.TextStyle(
                      font: regular, fontSize: 9, color: PdfColors.grey300),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  '+47 480 24 259  ·  stian@completedrums.no',
                  style: pw.TextStyle(
                      font: regular, fontSize: 9, color: PdfColors.grey300),
                ),
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
  }) {
    final headerStyle = pw.TextStyle(
        font: bold, fontSize: 9.5, color: PdfColors.white);
    final boldCell = pw.TextStyle(font: bold, fontSize: 10);

    final headerBg = PdfColors.black;
    final rowBg = PdfColors.grey100;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SHOW-OVERSIKT',
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
                _cell('Pris', headerStyle, pw.Alignment.centerRight),
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
              final label = ekstra.isNotEmpty
                  ? '${show['show_name'] ?? ''}\n$ekstra'
                  : show['show_name'] as String? ?? '';
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _cell(label, boldCell, pw.Alignment.centerLeft),
                  _cell('kr ${nok.format(price)}',
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
    List<Map<String, dynamic>> shows,
  ) {
    final showNames = shows
        .map((s) {
          final name = s['show_name'] as String? ?? '';
          final ekstra = s['ekstrainnslag'] as String? ?? '';
          return ekstra.isNotEmpty ? '$name ($ekstra)' : name;
        })
        .where((n) => n.isNotEmpty)
        .toList();
    if (showNames.isEmpty) return pw.SizedBox();
    return _buildSection(bold, regular, 'SHOW-OVERSIKT', [
      pw.Text(
        showNames.join(', '),
        style: pw.TextStyle(font: regular, fontSize: 10),
      ),
    ]);
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
  }) {
    // Merge CompleteKonto + BookingHonorar into Utøverhyrer
    double ckAmount = 0;
    double bhAmount = 0;
    for (final l in lines) {
      if (l.label == 'CompleteKonto') ckAmount = l.amount;
      if (l.label == 'BookingHonorar') bhAmount = l.amount;
    }
    final displayLines = lines
        .map((l) {
          if (l.label == 'Utøverhyrer') {
            return (label: l.label, amount: l.amount + ckAmount + bhAmount);
          }
          return l;
        })
        .where((l) =>
            l.amount > 0 &&
            l.label != 'CompleteKonto' &&
            l.label != 'BookingHonorar')
        .toList();

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
            'PRISOPPSUMMERING',
            style: pw.TextStyle(
              font: bold,
              fontSize: 11,
              color: PdfColors.grey800,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 8),
          ...displayLines.map((l) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(l.label,
                        style: pw.TextStyle(font: regular, fontSize: 10)),
                    pw.Text('kr ${nok.format(l.amount)}',
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
              pw.Text('kr ${nok.format(total)}',
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
  }) {
    final showLabel = shows.length == 1
        ? (shows.first['show_name'] as String? ?? 'Show')
        : 'Sum shows';
    final rows = <_PriceLine>[
      _PriceLine(showLabel, showsTotal),
      if (inearFromUs && inearPrice > 0)
        _PriceLine('In-ear monitor', inearPrice),
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
            'PRISOPPSUMMERING',
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
                    pw.Text('kr ${nok.format(r.amount)}',
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
                'kr ${nok.format(total)}',
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
  }) {
    return pw.Row(
      children: [
        // Complete Drums side
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'For Complete Drums',
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
                    ? '$companySignature  ·  Dato: ${companySignatureDate ?? ''}'
                    : 'Stian Skog  ·  Dato: _______________',
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
                'For ${customerFirma.isNotEmpty ? customerFirma : 'Oppdragsgiver'}',
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
                    ? '$customerSignature  ·  Dato: ${customerSignatureDate ?? ''}'
                    : 'Navn og tittel  ·  Dato: _______________',
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
