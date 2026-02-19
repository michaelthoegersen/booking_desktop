import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:flutter/gestures.dart';

import '../services/offer_storage_service.dart';
import '../services/notification_service.dart';

// ============================================================
// HELPERS
// ============================================================
DateTime parseUtcDay(String s) {
  final d = DateTime.parse(s);
  return DateTime.utc(d.year, d.month, d.day);
}
String formatBusName(String raw) {
  return raw.replaceAll("_", " ");
}
DateTime startOfWeek(DateTime d) {
  final diff = d.weekday - DateTime.monday;
  return DateTime(d.year, d.month, d.day - diff);
}

DateTime normalize(DateTime d) {
  return DateTime(d.year, d.month, d.day);
}

String fmt(DateTime d) {
  return DateFormat("dd.MM.yyyy").format(d);
}

String fmtDb(DateTime d) {
  return DateFormat("yyyy-MM-dd").format(d);
}

final Map<String, String> busTypes = {
  "CSS_1034": "12–18 bunks\n12 + Star room",
  "CSS_1023": "12–14 sleeper",
  "CSS_1008": "12 sleeper",
  "YCR 682": "16-sleeper",
  "ESW 337": "14-sleeper",
  "WYN 802": "14-sleeper",
  "RLC 29G": "16-sleeper",
  "Rental 1 (Hasse)": "16-sleeper",
  "Rental 2 (Rickard)": "16-sleeper",
};
// ============================================================
// DRAG DATA
// ============================================================

class DragBookingData {
  final String production;
  final String fromBus;
  final DateTime from;
  final DateTime to;
  final String draftId; // 👈 NY

  DragBookingData({
    required this.production,
    required this.fromBus,
    required this.from,
    required this.to,
    required this.draftId,
  });
}

// ============================================================
// STATUS COLORS
// ============================================================

Color statusColor(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'manual':
      return Colors.blueGrey.shade400;

    case 'draft':
      return Colors.purple.shade300;

    case 'inquiry':
      return Colors.orange.shade300;

    case 'confirmed':
      return Colors.green.shade400;

    case 'invoiced':   // ⭐ NY
      return Colors.blue.shade400;

    default:
      return Colors.grey.shade300;
  }
}

class CalendarCard extends StatelessWidget {
  final Widget child;

  const CalendarCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),

        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),

      child: child,
    );
  }
}
// ============================================================
// CALENDAR PAGE
// ============================================================

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}


class _CalendarPageState extends State<CalendarPage> {

  final ScrollController _hScrollCtrl = ScrollController();
  final ScrollController _leftVScrollCtrl = ScrollController();
  final ScrollController _rightVScrollCtrl = ScrollController();
  bool _vScrollSyncing = false;

  final supabase = Supabase.instance.client;

  late final StreamSubscription<AuthState> _authSub;

  static const double dayWidth = 90;
  static const double busWidth = 140;

  late DateTime weekStart;
  late DateTime monthStart;

  bool isMonthView = false;

  bool loading = false;
  String? error;

  Map<String, Map<DateTime, List<Map<String, dynamic>>>> data = {};

  final buses = [
    "CSS_1034",
    "CSS_1023",
    "CSS_1008",
    "YCR 682",
    "ESW 337",
    "WYN 802",
    "RLC 29G",
    "Rental 1 (Hasse)",
    "Rental 2 (Rickard)",
  ];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    weekStart = startOfWeek(DateTime.now());
    monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);

    // 👉 Start i måned-visning
    isMonthView = true;
    loadMonth();

    // ✅ Synk vertikal scroll mellom buss-kolonne og kalender-kolonne
    _leftVScrollCtrl.addListener(_syncLeftToRight);
    _rightVScrollCtrl.addListener(_syncRightToLeft);

    // ✅ Lytt på auth-endringer
    _authSub = supabase.auth.onAuthStateChange.listen((data) {

      final event = data.event;

      if (event == AuthChangeEvent.signedOut) {
        if (mounted) {
          context.go('/login');
        }
      }
    });
  }

  void _syncLeftToRight() {
    if (_vScrollSyncing) return;
    _vScrollSyncing = true;
    if (_rightVScrollCtrl.hasClients) {
      _rightVScrollCtrl.jumpTo(_leftVScrollCtrl.offset);
    }
    _vScrollSyncing = false;
  }

  void _syncRightToLeft() {
    if (_vScrollSyncing) return;
    _vScrollSyncing = true;
    if (_leftVScrollCtrl.hasClients) {
      _leftVScrollCtrl.jumpTo(_rightVScrollCtrl.offset);
    }
    _vScrollSyncing = false;
  }

  @override
  void dispose() {
    _authSub.cancel();
    _hScrollCtrl.dispose();
    _leftVScrollCtrl.removeListener(_syncLeftToRight);
    _rightVScrollCtrl.removeListener(_syncRightToLeft);
    _leftVScrollCtrl.dispose();
    _rightVScrollCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> loadWeek() async {

    setState(() {
      loading = true;
      error = null;
    });

    final start = weekStart.subtract(const Duration(days: 7));
    final end = weekStart.add(const Duration(days: 14));

    await loadRange(start, end);
  }


  Future<void> loadMonth() async {

  setState(() {
    loading = true;
    error = null;
  });

  // ⭐⭐⭐ VIKTIG FIX ⭐⭐⭐
  final start = DateTime(monthStart.year, monthStart.month, 1)
      .subtract(const Duration(days: 40));

  final end = DateTime(monthStart.year, monthStart.month + 1, 0)
      .add(const Duration(days: 40));

  await loadRange(start, end);
}


  Future<void> loadRange(DateTime start, DateTime end) async {

    // ✅ Lagre scroll-posisjon før reload
    final oldOffset = _hScrollCtrl.hasClients
        ? _hScrollCtrl.offset
        : 0.0;

    try {

      final res = await supabase
          .from('samletdata')
          .select()
          .gte('dato', fmtDb(start))
          .lte('dato', fmtDb(end));

      final rows = List<Map<String, dynamic>>.from(res);

      final map = <String, Map<DateTime, List<Map<String, dynamic>>>>{};

      for (final r in rows) {

        final bus = r['kilde']?.toString();
        final dateStr = r['dato'];

        if (bus == null || dateStr == null) continue;

        final parsed = DateTime.parse(dateStr).toUtc();
final date = DateTime.utc(parsed.year, parsed.month, parsed.day);

        map.putIfAbsent(bus, () => {});
        map[bus]!.putIfAbsent(date, () => []);
        map[bus]![date]!.add(r);
      }

      if (!mounted) return;

      setState(() {
        data = map;
      });

      // ✅ Restore scroll etter rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hScrollCtrl.hasClients) {
          _hScrollCtrl.jumpTo(oldOffset);
        }
      });

    } catch (e) {

      if (mounted) {
        setState(() {
          error = e.toString();
        });
      }

    } finally {

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

    // ============================================================
  // NAVIGATION
  // ============================================================

  void prev() {

    if (isMonthView) {

      monthStart = DateTime(
        monthStart.year,
        monthStart.month - 1,
        1,
      );

      loadMonth();

    } else {

      weekStart = weekStart.subtract(const Duration(days: 7));
      loadWeek();
    }

    setState(() {});
  }


  void next() {

    if (isMonthView) {

      monthStart = DateTime(
        monthStart.year,
        monthStart.month + 1,
        1,
      );

      loadMonth();

    } else {

      weekStart = weekStart.add(const Duration(days: 7));
      loadWeek();
    }

    setState(() {});
  } 



  // ============================================================
// BUILD
// ============================================================

@override
Widget build(BuildContext context) {

  final days = isMonthView
      ? List.generate(
          DateTime(monthStart.year, monthStart.month + 1, 0).day,
          (i) => DateTime(
            monthStart.year,
            monthStart.month,
            i + 1,
          ),
        )
      : List.generate(
          7,
          (i) => weekStart.add(Duration(days: i)),
        );

  final cs = Theme.of(context).colorScheme;

  return Padding(
    padding: const EdgeInsets.all(16),

    child: Container(
      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),

        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          // =========================
          // HEADER
          // =========================
          buildHeader(days),

          const SizedBox(height: 16),

          const Divider(height: 1),

          const SizedBox(height: 12),

          // =========================
          // CONTENT
          // =========================
          Expanded(
            child: buildContent(days),
          ),
        ],
      ),
    ),
  );
}
    // ============================================================
  // HEADER
  // ============================================================

  Widget buildHeader(List<DateTime> days) {
  final title = isMonthView
      ? DateFormat("MMMM yyyy").format(monthStart)
      : "${fmt(days.first)} – ${fmt(days.last)}";

  return Row(
    children: [

      Text(
        "Calendar",
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),

      const SizedBox(width: 16),

      Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.grey,
        ),
      ),

      const Spacer(),

// ➕ ADD BLOCK
FilledButton.icon(
  onPressed: _openManualBlockDialog,
  icon: const Icon(Icons.add),
  label: const Text("Block"),
),

const SizedBox(width: 12),

IconButton(
  icon: const Icon(Icons.chevron_left),
  onPressed: prev,
),

      IconButton(
        icon: const Icon(Icons.chevron_right),
        onPressed: next,
      ),

      const SizedBox(width: 12),

const SizedBox(width: 8),

      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text("Week"),
          ),
          ButtonSegment(
            value: true,
            label: Text("Month"),
          ),
        ],

        selected: {isMonthView},

        onSelectionChanged: (v) {
          final val = v.first;

          setState(() {
            isMonthView = val;
          });

          val ? loadMonth() : loadWeek();
        },
      ),
    ],
  );
}



  // ============================================================
  // CONTENT
  // ============================================================

  Widget buildContent(List<DateTime> days) {

  if (loading) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  if (error != null) {
    return Center(
      child: Text(
        error!,
        style: const TextStyle(color: Colors.red),
      ),
    );
  }

  return buildGrid(days);
}
    // ============================================================
  // GRID
  // ============================================================

  // ============================================================
// GRID (STICKY BUS COLUMN)
// ============================================================

// ============================================================
// GRID (FIXED BUS + SCROLLABLE DAYS — NO OVERFLOW)
// ============================================================

// ============================================================
// GRID (STICKY BUS + STICKY HEADER)
// ============================================================

Widget buildGrid(List<DateTime> days) {
  final scrollWidth = dayWidth * days.length;

  return Row(
    children: [

      // =====================================================
      // LEFT: BUS COLUMN (FIXED)
      // =====================================================
      SizedBox(
        width: busWidth + 16,
        child: Column(
          children: [

            // Header spacer (same height as date row)
            const SizedBox(height: 56),

            // Bus list
            Expanded(
              child: ListView.builder(
                controller: _leftVScrollCtrl,
                itemCount: buses.length,
                itemBuilder: (_, i) {
                  return _buildBusOnlyRow(buses[i]);
                },
              ),
            ),
          ],
        ),
      ),

      // =====================================================
      // RIGHT: SCROLLABLE AREA
      // =====================================================
      Expanded(
        child: ClipRect(
          child: Scrollbar(
            controller: _hScrollCtrl,
            thumbVisibility: true,

            // 🔥 WEB SCROLL FIX START
            child: Listener(
              onPointerSignal: (event) {

                // 🌐 Web trackpad scroll → horisontal
                if (event is PointerScrollEvent) {
                  final newOffset =
                      _hScrollCtrl.offset + event.scrollDelta.dy;

                  _hScrollCtrl.jumpTo(
                    newOffset.clamp(
                      0,
                      _hScrollCtrl.position.maxScrollExtent,
                    ),
                  );
                }
              },
              // 🔥 WEB SCROLL FIX END

              child: SingleChildScrollView(
                controller: _hScrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),

                child: SizedBox(
                  width: scrollWidth,
                  child: CustomScrollView(
                    controller: _rightVScrollCtrl,
                    slivers: [

                      // ===================================
                      // STICKY DATE HEADER
                      // ===================================
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _CalendarHeaderDelegate(
                          height: 56,
                          child: SizedBox(
                            width: scrollWidth,
                            child: buildHeaderRow(days),
                          ),
                        ),
                      ),

                      // ===================================
                      // BODY ROWS
                      // ===================================
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildCalendarOnlyRow(
                              buses[index],
                              days,
                            );
                          },
                          childCount: buses.length,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
// ============================================================
// BUS COLUMN ROW (FIXED)
// ============================================================

Widget _buildBusOnlyRow(String bus) {

  return SizedBox(
    height: 72,

    child: Align(
      alignment: Alignment.centerLeft,

      child: BusCell(
        bus,
        busTypes: busTypes,
      ),
    ),
  );
}
// ============================================================
// CALENDAR ROW (SCROLLING)
// ============================================================

Widget _buildCalendarOnlyRow(
  String bus,
  List<DateTime> days,
) {
  final segments = buildSegments(bus, days);

  return DragTarget<DragBookingData>(

    // =====================================================
    // 🚫 IKKE TILLAT DROP PÅ OPPTATTE DATOER
    // =====================================================
    onWillAccept: (drag) {
      if (drag == null) return false;

      // Samme buss → ikke lov
      if (drag.fromBus == bus) return false;

      // Sjekk om hele perioden er ledig
      DateTime d = normalize(drag.from);
      final end = normalize(drag.to);

      while (!d.isAfter(end)) {
        final items = data[bus]?[d];

        // Finnes det noe denne dagen → stopp
        if (items != null && items.isNotEmpty) {
          return false;
        }

        d = d.add(const Duration(days: 1));
      }

      return true; // Alt ledig → OK
    },

    // =====================================================
// ✅ VED DROP
// =====================================================
onAccept: (data) async {

  if (!mounted) return;

  // ============================
  // 1️⃣ VIS DIALOG FØRST
  // ============================
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => StatusDatePickerDialog(
      draftId: data.draftId,
      newStatus: '',
      targetBus: bus,
      fromBus: data.fromBus,
    ),
  );

  if (changed != true) return;

  // ============================
  // 3️⃣ RELOAD
  // ============================
  await loadRange(
    isMonthView
        ? DateTime(monthStart.year, monthStart.month, 1)
        : weekStart.subtract(const Duration(days: 7)),
    isMonthView
        ? DateTime(monthStart.year, monthStart.month + 1, 0)
        : weekStart.add(const Duration(days: 14)),
  );
},

    // =====================================================
    // 🎨 UI
    // =====================================================
    builder: (context, candidate, rejected) {

      final highlight = candidate.isNotEmpty;

      return Container(
        height: 72,

        decoration: BoxDecoration(
          color: highlight
              ? Colors.blue.withOpacity(0.08)
              : null,

          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade200,
            ),
          ),
        ),

        child: Row(
          children: [

            SizedBox(
              width: dayWidth * days.length,
              child: Row(children: segments),
            ),
          ],
        ),
      );
    },
  );
}



  // ============================================================
  // HEADER ROW
  // ============================================================

  // ============================================================
// HEADER ROW (SYNC WIDTH)
// ============================================================

Widget buildHeaderRow(List<DateTime> days) {

  return Container(
    height: 56,

    decoration: BoxDecoration(
      color: Colors.grey.shade50,

      border: Border(
        bottom: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
    ),

    child: Row(
      children: [

        for (final d in days)

          SizedBox(
            width: dayWidth,

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,

              children: [

                Text(
                  DateFormat("EEE").format(d),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 2),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),

                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),

                  child: Text(
                    DateFormat("dd").format(d),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
  // ============================================================
// ROW
// ============================================================

Widget buildRow(String bus, List<DateTime> days) {

  final segments = buildSegments(bus, days);

  return DragTarget<DragBookingData>(

    onWillAccept: (data) {
      return data != null && data.fromBus != bus;
    },

    onAccept: (data) async {

      await supabase
          .from('samletdata')
          .update({'kilde': bus})
          .eq('produksjon', data.production)
          .eq('kilde', data.fromBus)
          .gte('dato', fmtDb(data.from))
          .lte('dato', fmtDb(data.to));

      // Reload correct range
      await loadRange(
        isMonthView
            ? DateTime(monthStart.year, monthStart.month, 1)
            : weekStart.subtract(const Duration(days: 7)),
        isMonthView
            ? DateTime(monthStart.year, monthStart.month + 1, 0)
            : weekStart.add(const Duration(days: 14)),
      );

      if (mounted) {
        setState(() {});
      }
    },

    builder: (context, candidate, rejected) {

      final highlight = candidate.isNotEmpty;

      return Container(
        height: 72,

        decoration: BoxDecoration(
          color: highlight
              ? Colors.blue.withOpacity(0.08)
              : null,

          border: Border(
            bottom: BorderSide(
            color: Colors.grey.shade200,
  ),
),        ),

        child: Row(
          children: [

            BusCell(
            bus,
            busTypes: busTypes,
),

            SizedBox(
              width: dayWidth * days.length,
              child: Row(children: segments),
            ),
          ],
        ),
      );
    },
  );
}



  // ============================================================
// SEGMENTS (FULL PERIOD FIXED)
// ============================================================

List<Widget> buildSegments(
  String bus,
  List<DateTime> days,
) {
  final result = <Widget>[];

  // =====================================================
  // 1️⃣ FLAT LIST
  // =====================================================

  final entries = data[bus]?.entries.toList() ?? [];
  final allRows = <Map<String, dynamic>>[];

  for (final e in entries) {
    for (final r in e.value) {
      allRows.add(r);
    }
  }

  // =====================================================
  // 2️⃣ GROUP PER ROUND
  // =====================================================

  final Map<String, List<Map<String, dynamic>>> rounds = {};

  for (final r in allRows) {
    final draftId = r['draft_id']?.toString() ?? '';
    final roundIndex = r['round_index']?.toString() ?? '0';
    final key = "$draftId:$roundIndex";

    rounds.putIfAbsent(key, () => []);
    rounds[key]!.add(r);
  }

  // =====================================================
  // 3️⃣ BUILD CHUNKS (DST SAFE)
  // =====================================================

  final List<List<Map<String, dynamic>>> chunks = [];

  for (final round in rounds.values) {

    final sorted = [...round]
      ..sort((a, b) {
        final da = parseUtcDay(a['dato']);
        final db = parseUtcDay(b['dato']);
        return da.compareTo(db);
      });

    List<Map<String, dynamic>> current = [];

    for (final row in sorted) {

      final date = parseUtcDay(row['dato']);

      if (current.isEmpty) {
        current.add(row);
        continue;
      }

      final prev = parseUtcDay(current.last['dato']);

      // ⭐ DST SAFE CHECK (IKKE difference().inDays!)
      final expectedNext =
          DateTime.utc(prev.year, prev.month, prev.day + 1);

      final isNextDay =
          date.year == expectedNext.year &&
          date.month == expectedNext.month &&
          date.day == expectedNext.day;

      if (isNextDay) {
        current.add(row);
      } else {
        chunks.add(current);
        current = [row];
      }
    }

    if (current.isNotEmpty) {
      chunks.add(current);
    }
  }

  // =====================================================
  // 4️⃣ SORTER CHUNKS PÅ STARTDATO (DST SAFE)
  // =====================================================

  chunks.sort((a, b) {
    final da = parseUtcDay(a.first['dato']);
    final db = parseUtcDay(b.first['dato']);
    return da.compareTo(db);
  });

  // =====================================================
  // 5️⃣ BUILD UI
  // =====================================================

  int i = 0;

  while (i < days.length) {

    final day =
        DateTime.utc(days[i].year, days[i].month, days[i].day);

    List<Map<String, dynamic>>? chunk;

    for (final c in chunks) {

      final start = parseUtcDay(c.first['dato']);
      final end   = parseUtcDay(c.last['dato']);

      if (!day.isBefore(start) && !day.isAfter(end)) {
        chunk = c;
        break;
      }
    }

    if (chunk == null) {
      result.add(const SizedBox(width: dayWidth));
      i++;
      continue;
    }

    final chunkStart = parseUtcDay(chunk.first['dato']);
    final chunkEnd   = parseUtcDay(chunk.last['dato']);

    final gridStart =
        DateTime.utc(days.first.year, days.first.month, days.first.day);
    final gridEnd =
        DateTime.utc(days.last.year, days.last.month, days.last.day);

    final visibleStart =
        chunkStart.isBefore(gridStart) ? gridStart : chunkStart;

    final visibleEnd =
        chunkEnd.isAfter(gridEnd) ? gridEnd : chunkEnd;

    final visibleCount =
        visibleEnd.difference(visibleStart).inDays + 1;

    if (visibleCount <= 0) {
      i++;
      continue;
    }

    final first = chunk.first;
    final isManual = first['manual_block'] == true;

    result.add(
      BookingSegment(
        title: isManual
            ? (first['note'] ?? 'Blocked')
            : (first['produksjon'] ?? ''),
        span: visibleCount,
        bus: bus,
        from: chunkStart,
        to: chunkEnd,
        status: isManual ? 'manual' : first['status'],
        width: dayWidth,
        draftId: first['draft_id'].toString(),
      ),
    );

    i += visibleCount;
  }

  return result;
}
  // ============================================================
  // UPDATE STATUS
  // ============================================================

  
  // ============================================================
  // STATUS MENU
  // ============================================================

  
  Future<void> _openManualBlockDialog() async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _ManualBlockDialog(
      buses: buses,
    ),
  );

  if (changed == true && mounted) {
    isMonthView ? loadMonth() : loadWeek();
  }
}
  }

  class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
// ============================================================
// SEGMENT BODY
// ============================================================

class BookingSegment extends StatelessWidget {

  final String title;
  final int span;
  final String bus;
  final DateTime from;
  final DateTime to;
  final String? status;
  final double width;
  final String draftId;

  const BookingSegment({
    super.key,
    required this.title,
    required this.span,
    required this.bus,
    required this.from,
    required this.to,
    this.status,
    required this.width,
    required this.draftId,
  });

  // ============================================================
  // BODY (CLICK + DOUBLE CLICK)
  // ============================================================

  Widget _buildBody(BuildContext context) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,

    // =====================================================
    // ⭐ DOBBELTKLIKK (GAMMEL FUNKSJON TILBAKE)
    // =====================================================
    onDoubleTap: () async {

  final parent =
      context.findAncestorStateOfType<_CalendarPageState>();

  if (parent == null) return;

  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => EditCalendarDialog(
      production: title,
      bus: bus,
      from: from,
      to: to,
    ),
  );

  if (changed == true) {
    parent.isMonthView
        ? parent.loadMonth()
        : parent.loadWeek();
  }
},

    // =====================================================
    // ⭐ HØYREKLIKK (STATUS MENU – DIN NYE)
    // =====================================================
    onSecondaryTapDown: (details) async {
      final result = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          details.globalPosition.dx,
          details.globalPosition.dy,
          details.globalPosition.dx,
          details.globalPosition.dy,
        ),
        items: const [

          PopupMenuItem(
            value: 'draft',
            child: Row(
              children: [
                _StatusDot(color: Colors.purple),
                SizedBox(width: 8),
                Text('Draft'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'inquiry',
            child: Row(
              children: [
                _StatusDot(color: Colors.orange),
                SizedBox(width: 8),
                Text('Inquiry'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'confirmed',
            child: Row(
              children: [
                _StatusDot(color: Colors.green),
                SizedBox(width: 8),
                Text('Confirmed'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'invoiced',
            child: Row(
              children: [
                _StatusDot(color: Colors.blue),
                SizedBox(width: 8),
                Text('Invoiced'),
              ],
            ),
          ),
        ],
      );

      if (result == null) return;

      final parent =
          context.findAncestorStateOfType<_CalendarPageState>();

      if (parent == null) return;

      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => StatusDatePickerDialog(
          draftId: draftId,
          newStatus: result,
          targetBus: bus,
        ),
      );

      if (changed == true) {
        parent.isMonthView
            ? parent.loadMonth()
            : parent.loadWeek();
      }
    },

    // =====================================================
    // UI
    // =====================================================
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: statusColor(status),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ),
  );
}

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width * span,
      child: Draggable<DragBookingData>(
        data: DragBookingData(
          production: title,
          fromBus: bus,
          from: from,
          to: to,
          draftId: draftId,
        ),
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: width * span,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: statusColor(status).withOpacity(0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(title),
          ),
        ),
        child: _buildBody(context),
      ),
    );
  }
}
// ============================================================
// BUS CELL
// ============================================================

class BusCell extends StatelessWidget {
  final String bus;
  final Map<String, String> busTypes;

  const BusCell(
    this.bus, {
    super.key,
    required this.busTypes,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final prettyBus = formatBusName(bus);
    final type = busTypes[bus] ?? '';

    return Container(
  width: 140,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

  decoration: BoxDecoration(
    color: Colors.grey.shade50,
    borderRadius: BorderRadius.circular(8),
  ),

  margin: const EdgeInsets.symmetric(horizontal: 6),

  alignment: Alignment.centerLeft,

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          // BUS NAME
          Text(
            prettyBus,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),

          // BUS TYPE (small text)
          if (type.isNotEmpty)
            Text(
              type,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}



// ============================================================
// EDIT DIALOG
// ============================================================

class EditCalendarDialog extends StatefulWidget {

  final String production;
  final String bus;
  final DateTime from;
  final DateTime to;

  const EditCalendarDialog({
    super.key,
    required this.production,
    required this.bus,
    required this.from,
    required this.to,
  });

  @override
  State<EditCalendarDialog> createState() =>
      _EditCalendarDialogState();
}



// ============================================================
// EDIT DIALOG STATE
// ============================================================

class _EditCalendarDialogState extends State<EditCalendarDialog> {

  final supabase = Supabase.instance.client;


  final sjaforCtrl = TextEditingController();
  final statusCtrl = TextEditingController();

  final contactNameCtrl = TextEditingController();
  final contactEmailCtrl = TextEditingController();
  final contactPhoneCtrl = TextEditingController();


  final Map<String, TextEditingController> dDriveCtrls = {};
  final Map<String, TextEditingController> itinCtrls = {};
  final Map<String, TextEditingController> venueCtrls = {};
  final Map<String, TextEditingController> addrCtrls = {};
  final Map<String, TextEditingController> commentCtrls = {};


  final List<Map<String, dynamic>> rows = [];


  bool loading = true;
  bool saving = false;

  int activeIndex = 0;


Future<void> copyToBus(String targetBus) async {

  for (final r in rows) {

    final sourceId = r['id'].toString();
    final date = fmtDb(DateTime.parse(r['dato']));

    final target = await supabase
        .from('samletdata')
        .select('id')
        .eq('produksjon', widget.production) // ⭐ FIX
        .eq('kilde', targetBus)
        .eq('dato', date)
        .maybeSingle();

    if (target == null) {
      print("❌ NO TARGET ROW $targetBus $date");
      continue;
    }

    final targetId = target['id'].toString();

    print("✅ COPY $date → $targetBus");

    await supabase
        .from('samletdata')
        .update({
          'd_drive': dDriveCtrls[sourceId]?.text.trim() ?? '',
          'getin': itinCtrls[sourceId]?.text.trim() ?? '',
          'venue': venueCtrls[sourceId]?.text.trim() ?? '',
          'adresse': addrCtrls[sourceId]?.text.trim() ?? '',
          'kommentarer': commentCtrls[sourceId]?.text.trim() ?? '',
          'contact_name': contactNameCtrl.text.trim(),
          'contact_email': contactEmailCtrl.text.trim(),
          'contact_phone': contactPhoneCtrl.text.trim(),
        })
        .eq('id', targetId);
  }
}
  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    load();
  }



  // ============================================================
  // LOAD
  // ============================================================

  // ============================================================
// LOAD
// ============================================================

Future<void> load() async {

  final res = await supabase
      .from('samletdata')
      .select()
      .eq('produksjon', widget.production)
      .eq('kilde', widget.bus)
      .gte('dato', fmtDb(widget.from))
      .lte('dato', fmtDb(widget.to))

      // ✅ KRITISK: alltid eldste → nyeste
      .order('dato', ascending: true);


  final list = List<Map<String, dynamic>>.from(res);


  if (list.isEmpty) {

    setState(() {
      loading = false;
    });

    return;
  }


  sjaforCtrl.text = list.first['sjafor'] ?? '';
  statusCtrl.text = list.first['status'] ?? '';
  contactNameCtrl.text = list.first['contact_name'] ?? '';
  contactEmailCtrl.text = list.first['contact_email'] ?? '';
  contactPhoneCtrl.text = list.first['contact_phone'] ?? '';


  rows.clear(); // 👈 sikkerhet
  rows.addAll(list);


  for (final r in list) {

    final id = r['id'].toString();


    dDriveCtrls[id] =
        TextEditingController(text: r['d_drive'] ?? '');

    itinCtrls[id] =
        TextEditingController(text: r['getin'] ?? '');

    venueCtrls[id] =
        TextEditingController(text: r['venue'] ?? '');

    addrCtrls[id] =
        TextEditingController(text: r['adresse'] ?? '');

    commentCtrls[id] =
        TextEditingController(text: r['kommentarer'] ?? '');
  }


  if (mounted) {
    setState(() {
      loading = false;
      activeIndex = 0; // ✅ start alltid på dag 1
    });
  }
}



  // ============================================================
  // SAVE
  // ============================================================

  Future<void> save() async {
  if (saving) return;

  setState(() {
    saving = true;
  });

  try {
    // =====================================================
    // 0️⃣ HENT DRAFT ID (JOBB-ID)
    // =====================================================

    final draftId = rows.first['draft_id']?.toString();

    if (draftId == null || draftId.isEmpty) {
      throw Exception("Missing draft_id – cannot save");
    }

    // =====================================================
    // 1️⃣ GAMMEL SJÅFØR — fra allerede lastede rader
    // =====================================================

    final oldSjafor = (rows.first['sjafor'] as String?)?.trim();
    final newSjafor = sjaforCtrl.text.trim();

    // =====================================================
    // 2️⃣ OPPDATER FELLES FELT — kun denne hendelsen
    // =====================================================

    final rowIds = rows.map((r) => r['id'].toString()).toList();

    await supabase
        .from('samletdata')
        .update({
          'sjafor': newSjafor,
          'status': statusCtrl.text.trim(),
          'contact_name': contactNameCtrl.text.trim(),
          'contact_email': contactEmailCtrl.text.trim(),
          'contact_phone': contactPhoneCtrl.text.trim(),
        })
        .inFilter('id', rowIds);

    // =====================================================
    // 3️⃣ OPPDATER PER-DAG FELTER (UENDRET LOGIKK)
    // =====================================================

    for (final r in rows) {
      final id = r['id'].toString();

      await supabase
          .from('samletdata')
          .update({
            'd_drive': dDriveCtrls[id]?.text.trim() ?? '',
            'getin': itinCtrls[id]?.text.trim() ?? '',
            'venue': venueCtrls[id]?.text.trim() ?? '',
            'adresse': addrCtrls[id]?.text.trim() ?? '',
            'kommentarer': commentCtrls[id]?.text.trim() ?? '',
          })
          .eq('id', id);
    }

    // =====================================================
    // 4️⃣ SEND PUSH – VED TILDELING OG ENDRING AV SJÅFØR
    // =====================================================

    final driverChanged =
        newSjafor.isNotEmpty && newSjafor != (oldSjafor ?? '');

    if (driverChanged) {
      final isFirstAssignment = oldSjafor == null || oldSjafor.isEmpty;
      await NotificationService.sendToDriver(
        driverName: newSjafor,
        title: 'Booking: ${widget.production}',
        body: isFirstAssignment
            ? 'You have been assigned as driver for this tour.'
            : 'Your driver assignment has been updated.',
        draftId: draftId,
      );
    }

    // =====================================================
    // 5️⃣ FERDIG
    // =====================================================

    if (!mounted) return;
    Navigator.pop(context, true);

  } catch (e) {
    rethrow;
  } finally {
    if (mounted) {
      setState(() {
        saving = false;
      });
    }
  }
}



  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {

    sjaforCtrl.dispose();
    statusCtrl.dispose();
    contactNameCtrl.dispose();
    contactEmailCtrl.dispose();
    contactPhoneCtrl.dispose();


    for (final m in [

      dDriveCtrls,
      itinCtrls,
      venueCtrls,
      addrCtrls,
      commentCtrls,
    ]) {

      for (final c in m.values) {
        c.dispose();
      }
    }

    super.dispose();
  }



  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {

    return AlertDialog(

      title: Text(
        "Edit ${widget.production}\n"
        "${fmt(widget.from)} - ${fmt(widget.to)}",
      ),


      content: SizedBox(
        width: 520,

        child: loading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  children: [

                    _field("Driver", sjaforCtrl),
                    _field("Status", statusCtrl),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // ── Contact person ──────────────────────
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Contact person",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _field("Name", contactNameCtrl),
                    _field("Email", contactEmailCtrl),
                    _field("Phone", contactPhoneCtrl),

                    const SizedBox(height: 8),
                    const Divider(),


                    Row(
                      children: [

                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: activeIndex > 0
                              ? () {
                                  setState(() {
                                    activeIndex--;
                                  });
                                }
                              : null,
                        ),


                        Expanded(
                          child: Column(
                            children: [

                              Text(
                                DateFormat("dd.MM.yyyy").format(
                                  DateTime.parse(
                                    rows[activeIndex]['dato'],
                                  ),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),


                              Text(
                                "Day ${activeIndex + 1} of ${rows.length}",
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),


                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed:
                              activeIndex < rows.length - 1
                                  ? () {
                                      setState(() {
                                        activeIndex++;
                                      });
                                    }
                                  : null,
                        ),
                      ],
                    ),


                    const SizedBox(height: 16),


                    _dayField("D.Drive", dDriveCtrls),
                    _multiDayField("Itinerary", itinCtrls),
                    _dayField("Venue", venueCtrls),
                    _dayField("Address", addrCtrls),
                    _multiDayField("Comment", commentCtrls),
                  ],
                ),
              ),
      ),


      actions: [

  OutlinedButton.icon(
    icon: const Icon(Icons.copy),
    label: const Text("Copy to"),
    onPressed: () async {

      final buses = [
        "CSS_1034",
        "CSS_1023",
        "CSS_1008",
        "YCR 682",
        "ESW 337",
        "WYN 802",
        "RLC 29G",
        "Rental 1 (Hasse)",
        "Rental 2 (Rickard)",
      ];

      final target = await showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text("Copy to bus"),
          children: buses
              .where((b) => b != widget.bus) // ikke samme buss
              .map((b) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, b),
                    child: Text(b),
                  ))
              .toList(),
        ),
      );

      if (target == null) return;

      await copyToBus(target);
    },
  ),

  TextButton(
    onPressed: saving ? null : () => Navigator.pop(context),
    child: const Text("Cancel"),
  ),

  FilledButton(
    onPressed: saving ? null : save,
    child: saving
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Text("Save"),
  ),
]
    );
  }



  // ============================================================
  // HELPERS
  // ============================================================

  Widget _field(String label, TextEditingController c) {

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),

      child: TextField(
        controller: c,

        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
      ),
    );
  }


  Widget _dayField(
    String label,
    Map<String, TextEditingController> map,
  ) {

    final id = rows[activeIndex]['id'].toString();


    return Padding(
      padding: const EdgeInsets.only(bottom: 10),

      child: TextField(
        controller: map[id],

        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }


  Widget _multiDayField(
    String label,
    Map<String, TextEditingController> map,
  ) {

    final id = rows[activeIndex]['id'].toString();


    return Padding(
      padding: const EdgeInsets.only(bottom: 12),

      child: TextField(
        controller: map[id],

        maxLines: null,
        minLines: 3,

        keyboardType: TextInputType.multiline,

        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
// ============================================================
// STICKY HEADER DELEGATE
// ============================================================

class _CalendarHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _CalendarHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_CalendarHeaderDelegate oldDelegate) {
    return height != oldDelegate.height ||
        child != oldDelegate.child;
  }
}
// ============================================================
// ROUND BLOCK (STATUS DIALOG)
// ============================================================

class _RoundBlock {
  final String bus;
  DateTime from;
  DateTime to;
  final List<String> ids;
  final Set<int> roundIndices;

  _RoundBlock({
    required this.bus,
    required this.from,
    required this.to,
    required this.ids,
    Set<int>? roundIndices,
  }) : roundIndices = roundIndices ?? {};
}
  class StatusDatePickerDialog extends StatefulWidget {

  final String draftId;
  final String newStatus;
  final String targetBus;
  final String fromBus;

  const StatusDatePickerDialog({
    super.key,
    required this.draftId,
    required this.newStatus,
    required this.targetBus,
    this.fromBus = '',
  });

  @override
  State<StatusDatePickerDialog> createState() =>
      _StatusDatePickerDialogState();
}

class _StatusDatePickerDialogState
    extends State<StatusDatePickerDialog> {

  final sb = Supabase.instance.client;

  bool loading = true;

  final Map<String, bool> selected = {};
  final List<_RoundBlock> blocks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _load() async {
    final res = await sb
        .from('samletdata')
        .select('id, dato, status, kilde, round_index')
        .eq('draft_id', widget.draftId)
        .order('dato');

    final list = List<Map<String, dynamic>>.from(res);

    if (list.isEmpty) {
      if (mounted) {
        setState(() => loading = false);
      }
      return;
    }

    list.sort(
      (a, b) => DateTime.parse(a['dato'])
          .compareTo(DateTime.parse(b['dato'])),
    );

    _RoundBlock? current;

    for (final r in list) {
      final date = parseUtcDay(r['dato']);
      final bus = r['kilde'].toString();
      final id = r['id'].toString();
      final roundIndex = (r['round_index'] as int?) ?? 0;

      if (current == null) {
        current = _RoundBlock(
          bus: bus,
          from: date,
          to: date,
          ids: [id],
          roundIndices: {roundIndex},
        );
        continue;
      }

      final isSameBus = bus == current.bus;
      final next = DateTime.utc(
        current.to.year,
        current.to.month,
        current.to.day + 1,
      );

      final isNextDay =
          date.year == next.year &&
          date.month == next.month &&
          date.day == next.day;

      if (isSameBus && isNextDay) {
        current.to = date;
        current.ids.add(id);
        current.roundIndices.add(roundIndex);
      } else {
        blocks.add(current);

        current = _RoundBlock(
          bus: bus,
          from: date,
          to: date,
          ids: [id],
          roundIndices: {roundIndex},
        );
      }
    }

    if (current != null) {
      blocks.add(current);
    }

    // Default: alle valgt
    for (final b in blocks) {
      selected[b.hashCode.toString()] = true;
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  // ============================================================
  // APPLY STATUS
  // ============================================================

  Future<void> _apply() async {
    // 1. Update samletdata rows
    for (final b in blocks) {
      final key = b.hashCode.toString();
      if (selected[key] != true) continue;

      final ids = b.ids.join(',');
      await sb
          .from('samletdata')
          .update({
            if (widget.newStatus.isNotEmpty) 'status': widget.newStatus,
            'kilde': widget.targetBus,
          })
          .filter('id', 'in', '($ids)');
    }

    // 2. Also update the offer draft so the bus change persists
    if (widget.fromBus.isNotEmpty) {
      final Set<int> affectedRounds = {};
      for (final b in blocks) {
        if (selected[b.hashCode.toString()] == true) {
          affectedRounds.addAll(b.roundIndices);
        }
      }

      if (affectedRounds.isNotEmpty) {
        try {
          final draft = await OfferStorageService.loadDraft(widget.draftId);
          for (final roundIndex in affectedRounds) {
            if (roundIndex >= draft.rounds.length) continue;
            final round = draft.rounds[roundIndex];
            for (int i = 0; i < round.busSlots.length; i++) {
              if (round.busSlots[i] == widget.fromBus) {
                round.busSlots[i] = widget.targetBus;
              }
            }
            if (round.bus == widget.fromBus) {
              round.bus = widget.targetBus;
            }
          }
          await OfferStorageService.saveDraft(
            id: widget.draftId,
            offer: draft,
          );
        } catch (e) {
          debugPrint('Failed to update draft bus assignment: $e');
        }
      }
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select dates"),

      content: SizedBox(
        width: 420,
        child: loading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : ListView(
                shrinkWrap: true,
                children: blocks.map((b) {
                  final key = b.hashCode.toString();

                  return CheckboxListTile(
                    value: selected[key] ?? false,

                    title: Text(
                      "${fmt(b.from)} – ${fmt(b.to)} (${widget.targetBus})",
                    ),

                    onChanged: (v) {
                      setState(() {
                        selected[key] = v ?? false;
                      });
                    },
                  );
                }).toList(),
              ),
      ),

      actions: [

        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),

        FilledButton(
          onPressed: _apply,
          child: const Text("Apply"),
        ),
      ],
    );
  }
}
class _ManualBlockDialog extends StatefulWidget {
  final List<String> buses;

  final String? initialBus;
  final DateTime? initialFrom;
  final DateTime? initialTo;
  final String? initialNote;

  const _ManualBlockDialog({
    super.key,
    required this.buses,
    this.initialBus,
    this.initialFrom,
    this.initialTo,
    this.initialNote,
  });

  @override
  State<_ManualBlockDialog> createState() =>
      _ManualBlockDialogState();
}

class _ManualBlockDialogState
    extends State<_ManualBlockDialog> {

  final sb = Supabase.instance.client;

  String? bus;
  DateTime? from;
  DateTime? to;

  late bool isEdit;

  final noteCtrl = TextEditingController();

  bool saving = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    isEdit = widget.initialFrom != null;

    bus = widget.initialBus;
    from = widget.initialFrom;
    to = widget.initialTo;

    noteCtrl.text = widget.initialNote ?? '';
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    noteCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // DATE PICKERS
  // ============================================================

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: from ?? DateTime.now(),
    );

    if (d != null) {
      setState(() => from = d);
    }
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: to ?? from ?? DateTime.now(),
    );

    if (d != null) {
      setState(() => to = d);
    }
  }

  // ============================================================
  // DELETE (ONLY FOR EDIT)
  // ============================================================

  Future<void> _delete() async {
    if (!isEdit) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete block?"),
        content: const Text(
          "This will permanently remove this manual block.\n\nAre you sure?",
        ),
        actions: [

          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),

          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await sb
        .from('samletdata')
        .delete()
        .eq('manual_block', true)
        .eq('kilde', widget.initialBus!)
        .gte('dato', fmtDb(widget.initialFrom!))
        .lte('dato', fmtDb(widget.initialTo!));

    if (!mounted) return;

    Navigator.pop(context, true);
  }

  // ============================================================
  // SAVE (ADD + EDIT)
  // ============================================================

  Future<void> _save() async {
    if (saving) return;

    if (bus == null || from == null || to == null) return;

    setState(() => saving = true);

    try {

      // =====================================
      // DELETE OLD (ONLY IF EDITING)
      // =====================================
      if (isEdit) {
        await sb
            .from('samletdata')
            .delete()
            .eq('manual_block', true)
            .eq('kilde', widget.initialBus!)
            .gte('dato', fmtDb(widget.initialFrom!))
            .lte('dato', fmtDb(widget.initialTo!));
      }

      // =====================================
      // INSERT NEW
      // =====================================
      final rows = <Map<String, dynamic>>[];

      DateTime d = normalize(from!);
      final end = normalize(to!);

      while (!d.isAfter(end)) {
        rows.add({
          'dato': fmtDb(d),
          'kilde': bus,
          'produksjon': '[BLOCK]',
          'manual_block': true,
          'note': noteCtrl.text.trim(),
          'status': 'manual',
        });

        d = d.add(const Duration(days: 1));
      }

      await sb.from('samletdata').insert(rows);

      if (!mounted) return;

      Navigator.pop(context, true);

    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? "Edit block" : "Add block"),

      content: SizedBox(
        width: 420,

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [

            // ================= BUS =================
            DropdownButtonFormField<String>(
              value: bus,

              decoration: const InputDecoration(
                labelText: "Bus",
                border: OutlineInputBorder(),
              ),

              items: widget.buses
                  .map(
                    (b) => DropdownMenuItem(
                      value: b,
                      child: Text(b),
                    ),
                  )
                  .toList(),

              onChanged: (v) => setState(() => bus = v),
            ),

            const SizedBox(height: 12),

            // ================= FROM =================
            TextField(
              readOnly: true,
              onTap: _pickFrom,

              decoration: InputDecoration(
                labelText: "From",
                border: const OutlineInputBorder(),
                hintText: from == null
                    ? ''
                    : DateFormat('dd.MM.yyyy').format(from!),
              ),
            ),

            const SizedBox(height: 12),

            // ================= TO =================
            TextField(
              readOnly: true,
              onTap: _pickTo,

              decoration: InputDecoration(
                labelText: "To",
                border: const OutlineInputBorder(),
                hintText: to == null
                    ? ''
                    : DateFormat('dd.MM.yyyy').format(to!),
              ),
            ),

            const SizedBox(height: 12),

            // ================= NOTE =================
            TextField(
              controller: noteCtrl,
              maxLines: 2,

              decoration: const InputDecoration(
                labelText: "Note",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),

      actions: [

        // DELETE (ONLY WHEN EDITING)
        if (isEdit)
          TextButton.icon(
            onPressed: saving ? null : _delete,
            icon: const Icon(Icons.delete, color: Colors.red),
            label: const Text(
              "Delete",
              style: TextStyle(color: Colors.red),
            ),
          ),

        if (isEdit) const Spacer(),

        // CANCEL
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),

        // SAVE
        FilledButton(
          onPressed: saving ? null : _save,

          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Save"),
        ),
      ],
    );
  }
}