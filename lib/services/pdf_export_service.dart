import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

class PdfExportService {

  static Future<void> exportCustomers({
    required List<Map<String,dynamic>> companies,
    required List<Map<String,dynamic>> contacts,
    required List<Map<String,dynamic>> productions,
  }) async {

    print("📄 ENTERPRISE+ PDF START");

    final pdf = pw.Document();

    // =====================================================
    // ✅ LOAD UNICODE FONTS
    // =====================================================

    final regularFontData =
        await rootBundle.load("assets/fonts/Roboto-Regular.ttf");

    final boldFontData =
        await rootBundle.load("assets/fonts/Roboto-Bold.ttf");

    final regular = pw.Font.ttf(regularFontData);
    final bold = pw.Font.ttf(boldFontData);

    final theme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
    );

    // =====================================================
    // ⚡ SUPER FAST LOOKUPS (O(1))
    // =====================================================

    final Map<dynamic, List<Map<String,dynamic>>> contactsByCompany = {};
    final Map<dynamic, List<Map<String,dynamic>>> productionsByCompany = {};

    for (final c in contacts) {
      contactsByCompany.putIfAbsent(c['company_id'], () => []);
      contactsByCompany[c['company_id']]!.add(c);
    }

    for (final p in productions) {
      productionsByCompany.putIfAbsent(p['company_id'], () => []);
      productionsByCompany[p['company_id']]!.add(p);
    }

    // =====================================================
    // 🔤 SORT A–Å
    // =====================================================

    companies.sort((a,b)=>
        (a['name'] ?? '').toString().toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));

    final Map<String,List<Map<String,dynamic>>> grouped = {};

    for(final c in companies){
      final name = (c['name'] ?? '').toString();
      final letter = name.isEmpty ? "#" : name[0].toUpperCase();

      grouped.putIfAbsent(letter, ()=>[]);
      grouped[letter]!.add(c);
    }

    final letters = grouped.keys.toList()..sort();

    // =====================================================
    // 🧾 BUILD PDF
    // =====================================================

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,

        // ================= HEADER =================
        header: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom:6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300),
              ),
            ),
            child: pw.Row(
              children: [

                pw.Text(
                  "TourFlow Company Directory",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),

                pw.Spacer(),

                pw.Text(
                  "Page ${context.pageNumber}/${context.pagesCount}",
                  style: const pw.TextStyle(fontSize:10),
                ),
              ],
            ),
          );
        },

        build: (context){

          final widgets = <pw.Widget>[];

          for(final letter in letters){

            // 🔤 LETTER TITLE
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(top:14,bottom:6),
                child: pw.Text(
                  letter,
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            );

            for(final company in grouped[letter]!){

              final companyContacts =
                  contactsByCompany[company['id']] ?? [];

              final companyProductions =
                  productionsByCompany[company['id']] ?? [];

              widgets.add(

                // =====================================================
                // 🧠 PRO TABLE STYLE COMPANY CARD
                // =====================================================

                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom:12),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(2),
                    border: pw.Border.all(
                      color: PdfColors.grey300,
                      width: 0.5,
                    ),
                  ),

                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [

                      // COMPANY NAME
                      pw.Text(
                        company['name'] ?? '',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),

                      pw.SizedBox(height:6),

                      // ================= CONTACT TABLE =================

                      if(companyContacts.isNotEmpty) ...[

                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical:2),
                          child: pw.Text(
                            "Contacts",
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize:10,
                            ),
                          ),
                        ),

                        pw.Table(
                          columnWidths: const {
                            0: pw.FlexColumnWidth(3),
                            1: pw.FlexColumnWidth(2),
                            2: pw.FlexColumnWidth(3),
                          },
                          children: companyContacts.map((c){
                            return pw.TableRow(
                              children: [

                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(2),
                                  child: pw.Text(
                                    c['name'] ?? '',
                                    style: const pw.TextStyle(fontSize:10),
                                  ),
                                ),

                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(2),
                                  child: pw.Text(
                                    c['phone'] ?? '',
                                    style: const pw.TextStyle(fontSize:10),
                                  ),
                                ),

                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(2),
                                  child: pw.Text(
                                    c['email'] ?? '',
                                    style: const pw.TextStyle(fontSize:10),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),

                        pw.SizedBox(height:6),
                      ],

                      // ================= PRODUCTIONS =================

                      if(companyProductions.isNotEmpty) ...[

                        pw.Text(
                          "Productions",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize:10,
                          ),
                        ),

                        pw.SizedBox(height:2),

                        pw.Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          children: companyProductions.map((p){

                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal:6,
                                vertical:2,
                              ),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.grey200,
                                borderRadius: pw.BorderRadius.circular(2),
                              ),
                              child: pw.Text(
                                p['name'] ?? '',
                                style: const pw.TextStyle(fontSize:9),
                              ),
                            );

                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
          }

          return widgets;
        },
      ),
    );

    // =====================================================
    // 💾 SAVE FILE
    // =====================================================

    final dir = await getApplicationDocumentsDirectory();

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File("${dir.path}/customers.pdf");

    await file.writeAsBytes(await pdf.save());

    print("✅ ENTERPRISE+ PDF SAVED: ${file.path}");

    // =====================================================
    // 🍏 MAC AUTO OPEN
    // =====================================================

    try {
      await Process.run('open', [file.path]);
    } catch (e) {
      print("❌ OPEN FAILED: $e");
    }
  }
}