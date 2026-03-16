import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generates a calendar overview PDF for selected buses and month range.
class CalendarPdfService {
  CalendarPdfService._();

  static Future<Uint8List> generate({
    required List<String> buses,
    required DateTime fromMonth,
    required DateTime toMonth,
    required Map<String, Map<DateTime, List<Map<String, dynamic>>>> data,
    required String companyName,
  }) async {
    // Fonts
    ByteData _safe(ByteData d) {
      final fresh = ByteData(d.lengthInBytes);
      fresh.buffer.asUint8List().setAll(
          0, d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
      return fresh;
    }

    final regular =
        pw.Font.ttf(_safe(await rootBundle.load('assets/fonts/calibri.ttf')));
    final bold =
        pw.Font.ttf(_safe(await rootBundle.load('assets/fonts/calibrib.ttf')));

    final doc = pw.Document();
    final monthFmt = DateFormat('MMMM yyyy');

    // Iterate months
    var current = DateTime(fromMonth.year, fromMonth.month, 1);
    final last = DateTime(toMonth.year, toMonth.month + 1, 0);

    while (!current.isAfter(last)) {
      final thisMonth = current; // capture for closure
      final monthEnd = DateTime(thisMonth.year, thisMonth.month + 1, 0);
      final daysInMonth = monthEnd.day;

      final days = List.generate(
        daysInMonth,
        (i) => DateTime.utc(thisMonth.year, thisMonth.month, i + 1),
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Title
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '$companyName — ${monthFmt.format(thisMonth)}',
                      style: pw.TextStyle(font: bold, fontSize: 14),
                    ),
                    pw.Text(
                      'Generated ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                      style: pw.TextStyle(
                          font: regular, fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Calendar grid
                pw.Expanded(
                  child: _buildMonthGrid(
                    buses: buses,
                    days: days,
                    data: data,
                    regular: regular,
                    bold: bold,
                  ),
                ),
              ],
            );
          },
        ),
      );

      current = DateTime(current.year, current.month + 1, 1);
    }

    return doc.save();
  }

  // ── Block building (same logic as calendar_page.dart) ────────

  /// Groups all rows for a bus into contiguous booking blocks.
  static List<_Block> _buildBlocks(
    Map<DateTime, List<Map<String, dynamic>>> busData,
    List<DateTime> days,
  ) {
    // 1. Flatten all rows
    final allRows = <Map<String, dynamic>>[];
    for (final entry in busData.entries) {
      allRows.addAll(entry.value);
    }

    // 2. Group by draft_id:round_index
    final Map<String, List<Map<String, dynamic>>> rounds = {};
    for (final r in allRows) {
      final draftId = r['draft_id']?.toString() ?? '';
      final roundIndex = r['round_index']?.toString() ?? '0';
      final key = '$draftId:$roundIndex';
      rounds.putIfAbsent(key, () => []);
      rounds[key]!.add(r);
    }

    // 3. Build chunks: consecutive days within each round
    final blocks = <_Block>[];
    final gridStart = days.first;
    final gridEnd = days.last;

    for (final round in rounds.values) {
      final sorted = [...round]
        ..sort((a, b) {
          final da = _parseDay(a['dato']);
          final db = _parseDay(b['dato']);
          return da.compareTo(db);
        });

      List<Map<String, dynamic>> current = [];

      for (final row in sorted) {
        final date = _parseDay(row['dato']);

        if (current.isEmpty) {
          current.add(row);
          continue;
        }

        final prev = _parseDay(current.last['dato']);
        final expectedNext = DateTime.utc(prev.year, prev.month, prev.day + 1);
        final isNextDay = date.year == expectedNext.year &&
            date.month == expectedNext.month &&
            date.day == expectedNext.day;

        if (isNextDay) {
          current.add(row);
        } else {
          blocks.add(_Block.from(current, gridStart, gridEnd));
          current = [row];
        }
      }
      if (current.isNotEmpty) {
        blocks.add(_Block.from(current, gridStart, gridEnd));
      }
    }

    // Sort by visible start day index
    blocks.sort((a, b) => a.startIndex.compareTo(b.startIndex));
    return blocks;
  }

  static DateTime _parseDay(dynamic v) {
    final s = v.toString();
    final d = DateTime.parse(s);
    return DateTime.utc(d.year, d.month, d.day);
  }

  // ── Grid rendering ───────────────────────────────────────────

  static pw.Widget _buildMonthGrid({
    required List<String> buses,
    required List<DateTime> days,
    required Map<String, Map<DateTime, List<Map<String, dynamic>>>> data,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const busColWidth = 70.0;
    const rowHeight = 18.0;

    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints!.maxWidth;
        final gridWidth = totalWidth - busColWidth;
        final dayW = gridWidth / days.length;

        final rows = <pw.Widget>[];

        // ── Header row ──
        rows.add(
          pw.Row(
            children: [
              pw.SizedBox(
                width: busColWidth,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(2),
                  child: pw.Text('Bus', style: pw.TextStyle(font: bold, fontSize: 6)),
                ),
              ),
              ...days.map((d) {
                final isWeekend = d.weekday >= 6;
                return pw.SizedBox(
                  width: dayW,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(1),
                    decoration: pw.BoxDecoration(
                      color: isWeekend ? PdfColors.grey200 : null,
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          dayNames[d.weekday - 1],
                          style: pw.TextStyle(font: regular, fontSize: 4, color: PdfColors.grey600),
                        ),
                        pw.Text(
                          '${d.day}',
                          style: pw.TextStyle(font: bold, fontSize: 5),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );

        // ── Bus rows ──
        for (final bus in buses) {
          final busData = data[bus] ?? {};
          final blocks = _buildBlocks(busData, days);

          // Build the day cells using a stack-like approach via Row
          final dayCells = <pw.Widget>[];
          int i = 0;

          while (i < days.length) {
            // Find a block that covers this day
            _Block? activeBlock;
            for (final b in blocks) {
              if (i >= b.startIndex && i <= b.endIndex) {
                activeBlock = b;
                break;
              }
            }

            if (activeBlock == null) {
              // Empty cell
              final isWeekend = days[i].weekday >= 6;
              dayCells.add(
                pw.SizedBox(
                  width: dayW,
                  height: rowHeight,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      color: isWeekend ? PdfColors.grey100 : null,
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
                    ),
                  ),
                ),
              );
              i++;
            } else if (i == activeBlock.startIndex) {
              // Start of a block — render the full merged cell
              final span = activeBlock.endIndex - activeBlock.startIndex + 1;
              final blockWidth = dayW * span;

              dayCells.add(
                pw.SizedBox(
                  width: blockWidth,
                  height: rowHeight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: pw.BoxDecoration(
                      color: activeBlock.color,
                      border: pw.Border.all(color: PdfColors.grey400, width: 0.3),
                      borderRadius: pw.BorderRadius.circular(1),
                    ),
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(
                      activeBlock.label,
                      style: pw.TextStyle(font: regular, fontSize: 5.5),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                ),
              );
              i += span;
            } else {
              // We're in the middle of a block but didn't hit startIndex
              // (shouldn't happen with sorted blocks, but be safe)
              i++;
            }
          }

          rows.add(
            pw.Row(
              children: [
                pw.SizedBox(
                  width: busColWidth,
                  height: rowHeight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
                    ),
                    child: pw.Text(
                      _formatBusName(bus),
                      style: pw.TextStyle(font: bold, fontSize: 5.5),
                      maxLines: 1,
                    ),
                  ),
                ),
                ...dayCells,
              ],
            ),
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }

  static String _formatBusName(String raw) {
    if (raw == 'WAITING_LIST') return 'Waiting List';
    return raw.replaceAll('CSS_', 'CSS ');
  }

}

// ── Helper class for a contiguous booking block ────────────────

class _Block {
  final String label;
  final String status;
  final int startIndex; // day index within the month grid
  final int endIndex;
  final PdfColor color;

  _Block({
    required this.label,
    required this.status,
    required this.startIndex,
    required this.endIndex,
    required this.color,
  });

  factory _Block.from(
    List<Map<String, dynamic>> rows,
    DateTime gridStart,
    DateTime gridEnd,
  ) {
    final first = rows.first;
    final production = first['produksjon']?.toString() ?? '';
    final status = (first['status']?.toString() ?? '').toLowerCase();
    final isBlock = production == '[BLOCK]' || production.isEmpty;
    final isManual = first['manual_block'] == true;
    final kjoretoy = (first['kjoretoy'] as String?) ?? '';
    final hasTrailer = kjoretoy.contains('+ trailer');

    final chunkStart = CalendarPdfService._parseDay(rows.first['dato']);
    final chunkEnd = CalendarPdfService._parseDay(rows.last['dato']);

    // Clamp to grid
    final visStart = chunkStart.isBefore(gridStart) ? gridStart : chunkStart;
    final visEnd = chunkEnd.isAfter(gridEnd) ? gridEnd : chunkEnd;

    final startIdx = visStart.difference(gridStart).inDays;
    final endIdx = visEnd.difference(gridStart).inDays;

    PdfColor bgColor;
    switch (status) {
      case 'confirmed':
        bgColor = const PdfColor.fromInt(0xFFA5D6A7); // green300
      case 'invoiced':
        bgColor = const PdfColor.fromInt(0xFF90CAF9); // blue200
      case 'inquiry':
        bgColor = const PdfColor.fromInt(0xFFFFCC80); // orange200
      case 'draft':
        bgColor = const PdfColor.fromInt(0xFFCE93D8); // purple200
      default:
        bgColor = isBlock
            ? const PdfColor.fromInt(0xFFE0E0E0) // grey
            : const PdfColor.fromInt(0xFFE0E0E0);
    }

    return _Block(
      label: isManual
          ? (isBlock ? (first['note']?.toString() ?? 'X') : production)
          : (isBlock ? 'X' : '$production${hasTrailer ? ' +trailer' : ''}'),
      status: status,
      startIndex: startIdx,
      endIndex: endIdx,
      color: bgColor,
    );
  }
}
