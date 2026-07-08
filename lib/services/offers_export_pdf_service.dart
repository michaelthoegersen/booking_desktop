import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../platform/pdf_saver.dart';

/// Exports an overview of all offers ("Tilbud") for the active company as a
/// PDF, grouped into the periods (months) the jobs belong to. Each offer is
/// listed with full customer info + status, and consecutive jobs are
/// collapsed into a single date span (e.g. 05.02.2026 - 11.02.2026).
///
/// Follows the proven directory-export pattern in pdf_export_service.dart:
/// Roboto fonts via the safeFont wrapper (fixes web ByteData offset issues
/// and tofu characters). The offer content is emitted as a flat list of
/// top-level widgets (NOT one big Container) so MultiPage can break long
/// offers across pages instead of clipping them.
class OffersExportPdfService {
  static final _df = DateFormat('dd.MM.yyyy');
  static final _monthFmt = DateFormat('MMMM yyyy', 'nb_NO');
  static final _nf = NumberFormat('#,##0', 'nb_NO');

  static String _statusLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'invoiced':
        return 'Fakturert';
      case 'confirmed':
        return 'Bekreftet';
      case 'accepted':
      case 'accepted_by_client':
        return 'Godtatt';
      case 'inquiry':
        return 'Forespørsel';
      case 'quoted':
      case 'offer_sent':
        return 'Tilbud sendt';
      case 'draft':
        return 'Utkast';
      case 'manual':
        return 'Manuell';
      case 'declined':
      case 'rejected':
        return 'Avslått';
      case 'cancelled':
        return 'Avlyst';
      default:
        return raw ?? '';
    }
  }

  /// All individual jobs (date + location) from an offer payload, sorted.
  static List<({DateTime date, String location})> _jobs(
      Map<String, dynamic> payload) {
    final out = <({DateTime date, String location})>[];
    final rounds = payload['rounds'];
    if (rounds is List) {
      for (final r in rounds) {
        if (r is! Map) continue;
        final entries = r['entries'];
        if (entries is! List) continue;
        for (final e in entries) {
          if (e is! Map) continue;
          final d = DateTime.tryParse((e['date'] ?? '').toString());
          if (d == null) continue;
          out.add((
            date: d,
            location: (e['location'] as String? ?? '').trim(),
          ));
        }
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Collapse consecutive (same-day or next-day) jobs into runs. Each run
  /// keeps the first/last date plus every location visited (in order).
  static List<({DateTime start, DateTime end, List<String> locations})> _runs(
      List<({DateTime date, String location})> jobs) {
    final runs =
        <({DateTime start, DateTime end, List<String> locations})>[];
    if (jobs.isEmpty) return runs;
    var start = jobs.first.date;
    var end = jobs.first.date;
    var locs = <String>[jobs.first.location];
    for (var i = 1; i < jobs.length; i++) {
      final j = jobs[i];
      if (j.date.difference(end).inDays <= 1) {
        end = j.date;
        locs.add(j.location);
      } else {
        runs.add((start: start, end: end, locations: locs));
        start = j.date;
        end = j.date;
        locs = [j.location];
      }
    }
    runs.add((start: start, end: end, locations: locs));
    return runs;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _runDateText(
      ({DateTime start, DateTime end, List<String> locations}) r) {
    if (r.start == r.end) return _df.format(r.start);
    return '${_df.format(r.start)} - ${_df.format(r.end)}';
  }

  /// All places visited during the run, in order, with consecutive
  /// duplicates collapsed (a 2-day stay in the same city shows once).
  static String _runRouteText(
      ({DateTime start, DateTime end, List<String> locations}) r) {
    final out = <String>[];
    for (final loc in r.locations) {
      final l = loc.trim();
      if (l.isEmpty) continue;
      if (out.isEmpty || out.last != l) out.add(l);
    }
    return out.join(' - ');
  }

  /// [offers] are raw rows from the `offers` table. Each should include:
  /// production, company, contact, status, total_excl_vat, created_at and
  /// payload (JSON map or string with phone/email/rounds).
  static Future<void> exportOffers({
    required List<Map<String, dynamic>> offers,
    required String companyName,
  }) async {
    final pdf = pw.Document();

    ByteData safeFont(ByteData d) {
      final fresh = ByteData(d.lengthInBytes);
      fresh.buffer.asUint8List().setAll(
          0, d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
      return fresh;
    }

    final regular = pw.Font.ttf(
      safeFont(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    );
    final bold = pw.Font.ttf(
      safeFont(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
    );
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);

    // ── Normalise rows ──
    final parsed = <({
      String production,
      String company,
      String contact,
      String phone,
      String email,
      String status,
      double totalValue,
      List<({DateTime start, DateTime end, List<String> locations})> runs,
      DateTime? periodDate,
    })>[];

    for (final o in offers) {
      dynamic raw = o['payload'] ?? o['offer_json'];
      Map<String, dynamic> payload = {};
      if (raw is String && raw.isNotEmpty) {
        try {
          payload = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      } else if (raw is Map) {
        payload = Map<String, dynamic>.from(raw);
      }

      final jobs = _jobs(payload);
      final runs = _runs(jobs);
      // Top-level columns can be empty on older rows — fall back to payload,
      // then to the title, so production/company never render blank.
      String firstNonEmpty(List<String?> vals) {
        for (final v in vals) {
          final t = (v ?? '').trim();
          if (t.isNotEmpty) return t;
        }
        return '';
      }
      parsed.add((
        production: firstNonEmpty([
          o['production'] as String?,
          payload['production'] as String?,
          o['title'] as String?,
        ]),
        company: firstNonEmpty([
          o['company'] as String?,
          payload['company'] as String?,
        ]),
        contact: firstNonEmpty([
          o['contact'] as String?,
          payload['contact'] as String?,
        ]),
        phone: (payload['phone'] as String? ?? '').trim(),
        email: (payload['email'] as String? ?? '').trim(),
        status: _statusLabel(o['status'] as String?),
        totalValue: (o['total_excl_vat'] as num?)?.toDouble() ?? 0,
        runs: runs,
        periodDate: jobs.isNotEmpty ? jobs.first.date : null,
      ));
    }

    // ── Group by period (month of the offer's first job date) ──
    final byPeriod = <String, List<int>>{};
    for (var i = 0; i < parsed.length; i++) {
      final p = parsed[i].periodDate;
      final key = p != null
          ? '${p.year}-${p.month.toString().padLeft(2, '0')}'
          : 'zzzz';
      byPeriod.putIfAbsent(key, () => []).add(i);
    }
    final periodKeys = byPeriod.keys.toList()..sort();

    final generatedAt = _df.format(DateTime.now());

    pw.Widget infoChip(String label, String value) => pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                  text: '$label: ',
                  style: pw.TextStyle(font: bold, fontSize: 9)),
              pw.TextSpan(
                  text: value,
                  style: pw.TextStyle(font: regular, fontSize: 9)),
            ],
          ),
        );

    // Build the flat, break-safe widget list for one offer.
    List<pw.Widget> offerWidgets(({
      String production,
      String company,
      String contact,
      String phone,
      String email,
      String status,
      double totalValue,
      List<({DateTime start, DateTime end, List<String> locations})> runs,
      DateTime? periodDate,
    }) o) {
      final w = <pw.Widget>[];

      // Title row: production + company (left), status chip (right).
      w.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8, bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(children: [
                  pw.TextSpan(
                    text: o.production.isEmpty ? '(uten navn)' : o.production,
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                  if (o.company.isNotEmpty)
                    pw.TextSpan(
                      text: '  -  ${o.company}',
                      style: pw.TextStyle(font: regular, fontSize: 10),
                    ),
                ]),
              ),
            ),
            if (o.status.isNotEmpty)
              pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  // NB: keep this small. A huge radius (e.g. 999) on a tiny
                  // box generates a degenerate rounded-rect path that
                  // corrupts the PDF stream — PDFKit then renders the whole
                  // page grey/clipped.
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text(o.status,
                    style: pw.TextStyle(font: bold, fontSize: 8)),
              ),
          ],
        ),
      ));

      // Contact info line.
      final infoParts = <pw.Widget>[];
      if (o.contact.isNotEmpty) infoParts.add(infoChip('Kontakt', o.contact));
      if (o.phone.isNotEmpty) infoParts.add(infoChip('Tlf', o.phone));
      if (o.email.isNotEmpty) infoParts.add(infoChip('E-post', o.email));
      if (infoParts.isNotEmpty) {
        w.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Wrap(spacing: 14, runSpacing: 2, children: infoParts),
        ));
      }

      // Job runs (consecutive dates collapsed into spans).
      if (o.runs.isEmpty) {
        w.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
          child: pw.Text('(ingen datoer)',
              style: pw.TextStyle(
                  font: regular, fontSize: 9, color: PdfColors.grey600)),
        ));
      } else {
        for (final r in o.runs) {
          w.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 135,
                  child: pw.Text(_runDateText(r),
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                ),
                pw.Expanded(
                  child: pw.Text(_runRouteText(r),
                      style: pw.TextStyle(font: regular, fontSize: 9)),
                ),
              ],
            ),
          ));
        }
      }

      // Total for the offer.
      if (o.totalValue > 0) {
        w.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8, top: 2),
          child: pw.Text('Total eks. mva: ${_nf.format(o.totalValue.round())} kr',
              style: pw.TextStyle(font: bold, fontSize: 9)),
        ));
      }

      // Thin separator between offers.
      w.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Divider(thickness: 0.4, color: PdfColors.grey300, height: 1),
      ));
      return w;
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.all(28),
          // Explicit white background — without this, some viewers (macOS
          // Preview in particular) render the transparent page as grey.
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.only(bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey400),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(companyName,
                      style: pw.TextStyle(font: bold, fontSize: 14)),
                  pw.Text('Tilbudsoversikt',
                      style: pw.TextStyle(font: regular, fontSize: 10)),
                ],
              ),
              pw.Spacer(),
              pw.Text(
                  'Generert $generatedAt  ·  Side ${context.pageNumber}/${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        build: (context) {
          if (parsed.isEmpty) {
            return [
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 40),
                child: pw.Center(
                  child: pw.Text('Ingen tilbud funnet',
                      style: pw.TextStyle(font: regular, fontSize: 12)),
                ),
              ),
            ];
          }
          final widgets = <pw.Widget>[];
          for (final key in periodKeys) {
            final indices = byPeriod[key]!;
            final periodTitle = key == 'zzzz'
                ? 'Uten dato'
                : _capitalize(_monthFmt.format(DateTime(
                    int.parse(key.substring(0, 4)),
                    int.parse(key.substring(5, 7)),
                  )));
            double subtotal = 0;
            for (final i in indices) {
              subtotal += parsed[i].totalValue;
            }
            // Period header (kept together with its rule).
            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(top: 12, bottom: 2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(periodTitle,
                          style: pw.TextStyle(font: bold, fontSize: 15)),
                      pw.Spacer(),
                      pw.Text(
                          '${indices.length} tilbud'
                          '${subtotal > 0 ? '  ·  ${_nf.format(subtotal.round())} kr' : ''}',
                          style: pw.TextStyle(
                              font: regular,
                              fontSize: 9,
                              color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Divider(thickness: 0.8, color: PdfColors.grey500),
                ],
              ),
            ));
            for (final i in indices) {
              widgets.addAll(offerWidgets(parsed[i]));
            }
          }
          widgets.add(pw.SizedBox(height: 12));
          widgets.add(pw.Text('Totalt ${parsed.length} tilbud',
              style: pw.TextStyle(font: bold, fontSize: 11)));
          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();
    // Hand over the exact bytes. On web this downloads via a Blob (no browser
    // print-dialog re-render, which previously injected a grey page
    // background); on desktop it opens a native save dialog.
    await savePdf(bytes, 'Tilbudsoversikt.pdf');
  }
}
