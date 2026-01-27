import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../supabase_clients.dart';

// ------------------------------------------------------------
// CALENDAR PAGE
// ------------------------------------------------------------
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // Drivers-prosjektet
  final supabase = supabaseDrivers;

  DateTime weekStart = _startOfWeek(DateTime.now());

  bool loading = false;
  String? error;

  /// bus -> date -> rows
  Map<String, Map<DateTime, List<Map<String, dynamic>>>> data = {};

  /// Riktige busser
  final buses = [
    "CSS_1034",
    "CSS_1023",
    "CSS_1008",
  ];

  // --------------------------------------------------
  // INIT
  // --------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadWeek();
  }

  // --------------------------------------------------
  // LOAD WEEK
  // --------------------------------------------------
  Future<void> _loadWeek() async {
    setState(() {
      loading = true;
      error = null;
    });

    final start = weekStart;
    final end = start.add(const Duration(days: 6));

    try {
      debugPrint("📅 LOADING $start → $end");

      final res = await supabase
          .from('samletdata')
          .select('dato, produksjon, kilde')
          .gte('dato', _fmtDb(start))
          .lte('dato', _fmtDb(end));

      final rows = List<Map<String, dynamic>>.from(res as List);

      final map =
          <String, Map<DateTime, List<Map<String, dynamic>>>>{};

      for (final r in rows) {
        final bus = r['kilde']?.toString().trim();
        final dateStr = r['dato']?.toString();

        if (bus == null || bus.isEmpty) continue;
        if (dateStr == null) continue;

        final parsed = DateTime.parse(dateStr);

        final date = DateTime(
          parsed.year,
          parsed.month,
          parsed.day,
        );

        map.putIfAbsent(bus, () => {});
        map[bus]!.putIfAbsent(date, () => []);
        map[bus]![date]!.add(r);
      }

      setState(() {
        data = map;
      });
    } catch (e, st) {
      debugPrint("❌ ERROR: $e");
      debugPrint(st.toString());

      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() => loading = false);
    }
  }

  // --------------------------------------------------
  // WEEK NAV
  // --------------------------------------------------
  void _prevWeek() {
    setState(() {
      weekStart = weekStart.subtract(const Duration(days: 7));
    });

    _loadWeek();
  }

  void _nextWeek() {
    setState(() {
      weekStart = weekStart.add(const Duration(days: 7));
    });

    _loadWeek();
  }

  // --------------------------------------------------
  // UI
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final days =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER
          Row(
            children: [
              const Text(
                "Calendar",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),

              IconButton(
                onPressed: _prevWeek,
                icon: const Icon(Icons.chevron_left),
              ),

              Text(
                "${_fmt(days.first)} - ${_fmt(days.last)}",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),

              IconButton(
                onPressed: _nextWeek,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // CONTENT
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? _ErrorBox(error!)
                      : _buildGrid(days),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // GRID
  // --------------------------------------------------
  Widget _buildGrid(List<DateTime> days) {
    return Column(
      children: [
        _buildHeaderRow(days),

        for (final bus in buses)
          _buildTimelineRow(bus, days),
      ],
    );
  }

  // --------------------------------------------------
  // HEADER ROW
  // --------------------------------------------------
  Widget _buildHeaderRow(List<DateTime> days) {
    return Container(
      color: const Color(0xFFF7F7F7),
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 140),

          for (final d in days)
            Expanded(
              child: Center(
                child: Text(
                  DateFormat("EEE\ndd.MM").format(d),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // TIMELINE ROW
  // --------------------------------------------------
  Widget _buildTimelineRow(String bus, List<DateTime> days) {
    final segments = _buildSegments(bus, days);

    return Container(
      height: 70,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.black12),
        ),
      ),
      child: Row(
        children: [
          _BusCell(bus),

          Expanded(
            child: Row(
              children: segments,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------
  // BUILD SEGMENTS (FINAL FIX)
  // --------------------------------------------------
  List<Widget> _buildSegments(String bus, List<DateTime> days) {
    final result = <Widget>[];

    int i = 0;

    while (i < days.length) {
      final date = _normalize(days[i]);

      final items = data[bus]?[date] ?? [];

      // TOM DAG
      if (items.isEmpty) {
        result.add(const Expanded(child: SizedBox()));
        i++;
        continue;
      }

      final prod =
          items.first['produksjon']?.toString().trim() ?? '';

      // TOM PRODUKSJON = TOM DAG
      if (prod.isEmpty) {
        result.add(const Expanded(child: SizedBox()));
        i++;
        continue;
      }

      // FINN SPAN
      int span = 1;

      for (int j = i + 1; j < days.length; j++) {
        final d = _normalize(days[j]);

        final next = data[bus]?[d];

        if (next == null || next.isEmpty) break;

        final nextProd =
            next.first['produksjon']?.toString().trim() ?? '';

        if (nextProd != prod) break;

        span++;
      }

      result.add(
        _BookingSegment(
          title: prod,
          span: span,
        ),
      );

      i += span;
    }

    return result;
  }

  DateTime _normalize(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }
}

// --------------------------------------------------
// SEGMENTS
// --------------------------------------------------

class _BookingSegment extends StatelessWidget {
  final String title;
  final int span;

  const _BookingSegment({
    required this.title,
    required this.span,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: span,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// BUS CELL
// --------------------------------------------------
class _BusCell extends StatelessWidget {
  final String bus;

  const _BusCell(this.bus);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFFF7F7F7),
      child: Text(
        bus,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

// --------------------------------------------------
// ERROR
// --------------------------------------------------
class _ErrorBox extends StatelessWidget {
  final String error;

  const _ErrorBox(this.error);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// --------------------------------------------------
// HELPERS
// --------------------------------------------------

DateTime _startOfWeek(DateTime d) {
  final diff = d.weekday - DateTime.monday;
  return DateTime(d.year, d.month, d.day - diff);
}

String _fmt(DateTime d) {
  return DateFormat("dd.MM.yyyy").format(d);
}

String _fmtDb(DateTime d) {
  return DateFormat("yyyy-MM-dd").format(d);
}