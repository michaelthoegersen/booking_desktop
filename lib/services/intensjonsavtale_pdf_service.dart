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

  static const String _agreementText = '''
AVTALEVILKÅR

1. Bindende bekreftelse
Intensjonsavtalen er bindende fra datoen den er signert. Oppdragsgiver forplikter seg til å bekrefte eller avbestille oppdraget senest 61 dager før avreisedato. Etter 61 dager regnes avtalen som bindende og fakturerbar i henhold til punkt 2.

2. Kansellering
Ved kansellering 61–31 dager før oppdraget faktureres 50 % av avtalt honorar.
Ved kansellering 30 dager eller mindre før oppdraget faktureres 100 % av avtalt honorar.
Dersom oppdragsgiver avbestiller oppdraget mer enn 30 dager før arrangementet og Complete Drums bekrefter at de ikke er i stand til å fylle den ledige plassen, forbeholder Complete Drums seg retten til å fakturere fullt honorar.

3. Tilgjengelighetssjekk
Complete Drums har 7 dager fra mottak av signert intensjonsavtale til å bekrefte tilgjengelighet for de aktuelle datoene.

4. Teknisk rider
Oppdragsgiver er ansvarlig for å sørge for at teknisk rider fra Complete Drums er oppfylt til enhver tid. Avvik fra riderkrav skal avklares skriftlig senest 14 dager før arrangementet.

5. Sceneareal
Oppdragsgiver sørger for tilstrekkelig sceneareal i henhold til de spesifikasjoner som er avtalt. Planskisse over scene leveres av Complete Drums ved bekreftelse.

6. Get-in og prøvetid
Oppdragsgiver sørger for tilgang til scenen for rigging og lydsjekk/prøver iht. den avtalte timeplan. Get-in til scene og prøvetid er obligatorisk og er inkludert i timeplan.

7. Betaling
Faktura sendes etter gjennomført arrangement med 14 dagers betalingsfrist, med mindre annet er skriftlig avtalt.

8. Gyldighet
Denne intensjonsavtalen er gyldig i 14 dager fra utstedelsesdato. Dersom den ikke er signert og returnert innen fristen, bortfaller tilbudet.
''';

  // --------------------------------------------------------------------------
  // PUBLIC ENTRY POINT
  // --------------------------------------------------------------------------

  static Future<Uint8List> generate({
    required Map<String, dynamic> gig,
    required List<Map<String, dynamic>> shows,
  }) async {
    final pdf = pw.Document();

    // Load fonts
    pw.Font regularFont;
    pw.Font boldFont;
    try {
      regularFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/Calibri.ttf'));
      boldFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/CalibriBold.ttf'));
    } catch (_) {
      // Fallback to built-in fonts
      regularFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    // Load logo
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/pdf/logos/CompleteDrumsWhite.png'))
          .buffer.asUint8List(),
    );

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
    final getInTime = gig['get_in_time'] as String? ?? '';
    final getOutTime = gig['get_out_time'] as String? ?? '';
    final performanceTime = gig['performance_time'] as String? ?? '';
    final inearFromUs = gig['inear_from_us'] == true;
    final inearPrice = (gig['inear_price'] as num?)?.toDouble() ?? 0;
    final transportPrice = (gig['transport_price'] as num?)?.toDouble() ?? 0;
    final extraDesc = gig['extra_desc'] as String? ?? '';
    final extraPrice = (gig['extra_price'] as num?)?.toDouble() ?? 0;
    final notesForContract = gig['notes_for_contract'] as String? ?? '';

    // Date formatting
    final df = DateFormat('dd.MM.yyyy');
    String dateLabel = '';
    if (dateFrom != null) {
      final fromFmt = df.format(DateTime.parse(dateFrom));
      if (dateTo != null && dateTo != dateFrom) {
        dateLabel = '$fromFmt – ${df.format(DateTime.parse(dateTo))}';
      } else {
        dateLabel = fromFmt;
      }
    }

    // Time info
    String timeLabel = '';
    if (getInTime.isNotEmpty) timeLabel += 'Get-in: $getInTime';
    if (performanceTime.isNotEmpty) {
      if (timeLabel.isNotEmpty) timeLabel += '  |  ';
      timeLabel += 'Opptreden: $performanceTime';
    }
    if (getOutTime.isNotEmpty) {
      if (timeLabel.isNotEmpty) timeLabel += '  |  ';
      timeLabel += 'Get-out: $getOutTime';
    }

    // Price calculations
    final showsTotal = shows.fold<double>(
        0, (s, sh) => s + ((sh['price'] as num?)?.toDouble() ?? 0));
    final total = showsTotal +
        (inearFromUs ? inearPrice : 0) +
        transportPrice +
        extraPrice;

    // Today's date
    final todayStr = df.format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) {
          return [
            // ── HEADER ──────────────────────────────────────────────────
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
              _labelValue(regularFont, boldFont, 'Spillested',
                  [venueName, city, country]
                      .where((s) => s.isNotEmpty)
                      .join(', ')),
              _labelValue(regularFont, boldFont, 'Dato', dateLabel),
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

            // ── SHOWS TABLE ───────────────────────────────────────────────
            _buildShowsTable(boldFont, regularFont, shows, nok),
            pw.SizedBox(height: 12),

            // ── PRICE SUMMARY ─────────────────────────────────────────────
            _buildPriceSummary(
              boldFont,
              regularFont,
              nok,
              shows: shows,
              showsTotal: showsTotal,
              inearFromUs: inearFromUs,
              inearPrice: inearPrice,
              transportPrice: transportPrice,
              extraDesc: extraDesc,
              extraPrice: extraPrice,
              total: total,
            ),
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
            _buildSignature(boldFont, regularFont, firma),
            pw.SizedBox(height: 20),

            // ── AGREEMENT TEXT ────────────────────────────────────────────
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 10),
            pw.Text(
              _agreementText,
              style: pw.TextStyle(font: regularFont, fontSize: 8.5,
                  lineSpacing: 1.2),
            ),
          ];
        },
      ),
    );

    return pdf.save();
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
    NumberFormat nok,
  ) {
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
              final price = (show['price'] as num?)?.toDouble() ?? 0;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _cell(show['show_name'] as String? ?? '',
                      boldCell, pw.Alignment.centerLeft),
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
  // PRICE SUMMARY
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
    required String extraDesc,
    required double extraPrice,
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
      if (extraPrice > 0)
        _PriceLine(extraDesc.isNotEmpty ? extraDesc : 'Ekstra', extraPrice),
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
      pw.Font bold, pw.Font regular, String customerFirma) {
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
              pw.SizedBox(height: 30),
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
                'Stian Skog  ·  Dato: _______________',
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
              pw.SizedBox(height: 30),
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
                'Navn og tittel  ·  Dato: _______________',
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
