import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:flutter/gestures.dart';

import '../services/offer_storage_service.dart';
import '../services/notification_service.dart';
import '../services/email_service.dart';
import '../utils/bus_utils.dart';

// ============================================================
// HELPERS
// ============================================================
extension _NullIfEmpty on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

DateTime parseUtcDay(String s) {
  final d = DateTime.parse(s);
  return DateTime.utc(d.year, d.month, d.day);
}
String formatBusName(String raw) => fmtBus(raw);
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

  // ============================================================
  // WAITING LIST STATE
  // ============================================================
  List<Map<String, dynamic>> _waitingList = [];
  bool _wlExpanded = true;

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
    _loadWaitingList();

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

    _loadWaitingList();
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

    _loadWaitingList();
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

          // =========================
          // WAITING LIST
          // =========================
          const Divider(height: 1),

          const SizedBox(height: 4),

          _buildWaitingListPanel(),
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

    final kjoretoy = (first['kjoretoy'] as String?) ?? '';
    final hasTrailer = kjoretoy.contains('+ trailer');

    final noDriver = !isManual &&
        ((first['sjafor'] as String?)?.trim() ?? '').isEmpty;

    const dDriveThreshold = 600.0;
    final noDDrive = !isManual && chunk.any((r) {
      final km = double.tryParse(
              ((r['km'] as String?)?.trim() ?? '')) ??
          0.0;
      final excepted = (r['no_ddrive'] as bool?) ?? false;
      final dDrive = ((r['d_drive'] as String?)?.trim() ?? '');
      return km >= dDriveThreshold && !excepted && dDrive.isEmpty;
    });

    result.add(
      BookingSegment(
        title: isManual
            ? (first['note'] ?? 'Blocked')
            : ((first['produksjon'] ?? '') + (hasTrailer ? ' +trailer' : '')),
        span: visibleCount,
        bus: bus,
        from: chunkStart,
        to: chunkEnd,
        status: isManual ? 'manual' : first['status'],
        width: dayWidth,
        draftId: first['draft_id'].toString(),
        noDriver: noDriver,
        noDDrive: noDDrive,
        driver: (first['sjafor'] as String?)?.trim().nullIfEmpty,
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

  
  // ============================================================
  // WAITING LIST — LOAD
  // ============================================================

  Future<void> _loadWaitingList() async {
    // Show only entries that overlap with the currently visible period.
    final DateTime periodStart;
    final DateTime periodEnd;
    if (isMonthView) {
      periodStart = DateTime(monthStart.year, monthStart.month, 1);
      periodEnd   = DateTime(monthStart.year, monthStart.month + 1, 0);
    } else {
      periodStart = weekStart;
      periodEnd   = weekStart.add(const Duration(days: 6));
    }
    final psStr = fmtDb(periodStart);
    final peStr = fmtDb(periodEnd);

    // Overlap: date_from <= periodEnd AND date_to >= periodStart
    // Also include entries with null dates (manually added without dates).
    final res = await supabase
        .from('waiting_list')
        .select()
        .or('date_from.is.null,date_from.lte.$peStr')
        .or('date_to.is.null,date_to.gte.$psStr')
        .order('date_from', ascending: true, nullsFirst: true);

    if (mounted) {
      setState(() {
        _waitingList = List<Map<String, dynamic>>.from(res);
      });
    }
  }

  // ============================================================
  // WAITING LIST — DIALOGS
  // ============================================================

  Future<void> _openAddWaitingListDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _WaitingListAddDialog(),
    );
    if (added == true && mounted) _loadWaitingList();
  }

  Future<void> _openAssignToBusDialog(Map<String, dynamic> item) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _WaitingListAssignDialog(item: item, buses: buses),
    );
    if (done == true && mounted) {
      _loadWaitingList();
      isMonthView ? loadMonth() : loadWeek();
    }
  }

  Future<void> _deleteWaitingListItem(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    final draftId = item['draft_id']?.toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove from waiting list?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (ok == true) {
      await supabase.from('waiting_list').delete().eq('id', id);
      // Also remove any WAITING_LIST samletdata rows for this draft
      if (draftId != null && draftId.isNotEmpty) {
        await supabase
            .from('samletdata')
            .delete()
            .eq('draft_id', draftId)
            .eq('kilde', 'WAITING_LIST');
      }
      if (mounted) _loadWaitingList();
    }
  }

  // ============================================================
  // WAITING LIST — PANEL UI
  // ============================================================

  Widget _buildWaitingListPanel() {
    final cs = Theme.of(context).colorScheme;
    final screenH = MediaQuery.of(context).size.height;
    // Scale expanded height with screen: 22% of height, clamped 120–240 px.
    final expandedHeight = (screenH * 0.22).clamp(120.0, 240.0);
    final panelHeight = _wlExpanded ? expandedHeight : 48.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: panelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── HEADER ──────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _wlExpanded = !_wlExpanded),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [

                  Icon(
                    _wlExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),

                  const SizedBox(width: 8),

                  Text(
                    "Waiting List",
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),

                  if (_waitingList.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        "${_waitingList.length}",
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: "Refresh waiting list",
                    onPressed: _loadWaitingList,
                  ),
                ],
              ),
            ),
          ),

          // ── LIST ─────────────────────────────────────────────
          if (_wlExpanded)
            Expanded(
              child: _waitingList.isEmpty
                  ? Center(
                      child: Text(
                        "No jobs in waiting list",
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _waitingList.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final item = _waitingList[i];
                        final fromStr = item['date_from'] != null
                            ? DateFormat("dd.MM.yy")
                                .format(DateTime.parse(item['date_from']))
                            : "—";
                        final toStr = item['date_to'] != null
                            ? DateFormat("dd.MM.yy")
                                .format(DateTime.parse(item['date_to']))
                            : "—";
                        final notes = (item['notes'] ?? '').toString().trim();

                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.hourglass_top_outlined,
                            color: Colors.orange,
                          ),
                          title: Text(
                            item['production'] ?? "—",
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              if ((item['company'] ?? '').toString().isNotEmpty)
                                item['company'],
                              "$fromStr – $toStr",
                              if (notes.isNotEmpty) notes,
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openAssignToBusDialog(item),
                                icon: const Icon(Icons.directions_bus,
                                    size: 16),
                                label: const Text("Assign to bus"),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                color: cs.error,
                                tooltip: "Remove from waiting list",
                                onPressed: () => _deleteWaitingListItem(item),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

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
  final bool noDriver;
  final bool noDDrive;
  final String? driver;

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
    this.noDriver = false,
    this.noDDrive = false,
    this.driver,
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
            value: 'Draft',
            child: Row(
              children: [
                _StatusDot(color: Colors.purple),
                SizedBox(width: 8),
                Text('Draft'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'Inquiry',
            child: Row(
              children: [
                _StatusDot(color: Colors.orange),
                SizedBox(width: 8),
                Text('Inquiry'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'Confirmed',
            child: Row(
              children: [
                _StatusDot(color: Colors.green),
                SizedBox(width: 8),
                Text('Confirmed'),
              ],
            ),
          ),

          PopupMenuItem(
            value: 'Invoiced',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (driver != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '· $driver',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (noDriver || noDDrive) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 11,
                  color: Colors.white70,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    [
                      if (noDriver) 'No driver',
                      if (noDDrive) 'No D.Drive',
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
        .eq('produksjon', widget.production.replaceAll(' +trailer', ''))
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

  // Strip display-only suffix added in buildSegments()
  final produksjon = widget.production.replaceAll(' +trailer', '');

  final res = await supabase
      .from('samletdata')
      .select()
      .eq('produksjon', produksjon)
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

    final oldStatus = (rows.first['status'] as String? ?? '').trim();
    final newStatus = statusCtrl.text.trim();

    final rowIds = rows.map((r) => r['id'].toString()).toList();

    await supabase
        .from('samletdata')
        .update({
          'sjafor': newSjafor,
          'status': newStatus,
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
    // 3.5️⃣ FERRY BOOKING EMAIL — ved overgang til Confirmed
    // =====================================================

    if (oldStatus != 'Confirmed' && newStatus == 'Confirmed') {
      try {
        final draft = await OfferStorageService.loadDraft(draftId);
        debugPrint('FERRY EMAIL (calendar edit): '
            'ferryPerLeg=${draft.rounds.map((r) => r.ferryPerLeg).toList()}');
        await EmailService.sendFerryBookingEmail(offer: draft);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ferry booking email sent ✅')),
          );
        }
      } catch (e) {
        debugPrint('Ferry email error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ferry email failed: $e'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
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
            : rows.isEmpty
                ? const Center(child: Text("No calendar data found."))
                : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  children: [

                    _field("Driver", sjaforCtrl),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: sjaforCtrl,
                      builder: (_, value, __) {
                        if (value.text.trim().isNotEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 16, color: Colors.orange.shade700),
                              const SizedBox(width: 4),
                              Text(
                                "No driver allocated",
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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

                              // ── City (sted) for this day ──
                              Builder(builder: (context) {
                                final sted =
                                    (rows[activeIndex]['sted'] as String?)
                                            ?.trim() ??
                                        '';
                                if (sted.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    sted,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),

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


                    _dDriveField(),
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
                    child: Text(fmtBus(b)),
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


  Widget _dDriveField() {
    if (rows.isEmpty || activeIndex >= rows.length) {
      return const SizedBox.shrink();
    }
    final row = rows[activeIndex];
    final kmStr = (row['km'] as String?)?.trim() ?? '';
    final kmVal = double.tryParse(kmStr) ?? 0.0;
    final excepted = (row['no_ddrive'] as bool?) ?? false;
    // Only show field on actual D.Drive days
    if (kmVal < 600.0 || excepted) return const SizedBox.shrink();
    final id = row['id'].toString();
    final ctrl = dDriveCtrls[id];
    if (ctrl == null) return _dayField("D.Drive", dDriveCtrls);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _dayField("D.Drive", dDriveCtrls),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: ctrl,
          builder: (_, value, __) {
            if (value.text.trim().isNotEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    "No driver allocated",
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
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

    // 2. Ferry booking email — fires when setting to Confirmed
    if (widget.newStatus == 'Confirmed') {
      try {
        final draft = await OfferStorageService.loadDraft(widget.draftId);
        await EmailService.sendFerryBookingEmail(offer: draft);
      } catch (e) {
        debugPrint('Ferry email error: $e');
      }
    }

    // 3. Also update the offer draft so the bus change persists
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
                      "${fmt(b.from)} – ${fmt(b.to)} (${fmtBus(widget.targetBus)})",
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
                      child: Text(fmtBus(b)),
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

// ============================================================
// WAITING LIST — ADD DIALOG
// ============================================================

class _WaitingListAddDialog extends StatefulWidget {
  const _WaitingListAddDialog();

  @override
  State<_WaitingListAddDialog> createState() => _WaitingListAddDialogState();
}

class _WaitingListAddDialogState extends State<_WaitingListAddDialog> {
  final _sb = Supabase.instance.client;

  final _productionCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime? _from;
  DateTime? _to;
  bool _saving = false;

  @override
  void dispose() {
    _productionCtrl.dispose();
    _companyCtrl.dispose();
    _contactCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: _from ?? DateTime.now(),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: _to ?? _from ?? DateTime.now(),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _save() async {
    if (_productionCtrl.text.trim().isEmpty) return;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _sb.from('waiting_list').insert({
        'production': _productionCtrl.text.trim(),
        'company': _companyCtrl.text.trim().isEmpty
            ? null
            : _companyCtrl.text.trim(),
        'contact': _contactCtrl.text.trim().isEmpty
            ? null
            : _contactCtrl.text.trim(),
        'date_from': _from != null ? fmtDb(_from!) : null,
        'date_to': _to != null ? fmtDb(_to!) : null,
        'notes': _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add to waiting list"),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // Production
              TextField(
                controller: _productionCtrl,
                decoration: const InputDecoration(
                  labelText: "Production *",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              // Company
              TextField(
                controller: _companyCtrl,
                decoration: const InputDecoration(
                  labelText: "Company",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              // Contact
              TextField(
                controller: _contactCtrl,
                decoration: const InputDecoration(
                  labelText: "Contact",
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 12),

              // Date from
              TextField(
                readOnly: true,
                onTap: _pickFrom,
                decoration: InputDecoration(
                  labelText: "Date from",
                  border: const OutlineInputBorder(),
                  hintText: _from == null
                      ? 'Pick date'
                      : DateFormat('dd.MM.yyyy').format(_from!),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
              ),

              const SizedBox(height: 12),

              // Date to
              TextField(
                readOnly: true,
                onTap: _pickTo,
                decoration: InputDecoration(
                  labelText: "Date to",
                  border: const OutlineInputBorder(),
                  hintText: _to == null
                      ? 'Pick date'
                      : DateFormat('dd.MM.yyyy').format(_to!),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
              ),

              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "Notes",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Add"),
        ),
      ],
    );
  }
}

// ============================================================
// WAITING LIST — ASSIGN TO BUS DIALOG
// ============================================================

class _WaitingListAssignDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final List<String> buses;

  const _WaitingListAssignDialog({
    required this.item,
    required this.buses,
  });

  @override
  State<_WaitingListAssignDialog> createState() =>
      _WaitingListAssignDialogState();
}

class _WaitingListAssignDialogState
    extends State<_WaitingListAssignDialog> {
  final _sb = Supabase.instance.client;

  String? _bus;
  DateTime? _from;
  DateTime? _to;
  String _status = 'Inquiry';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.item['date_from'] != null) {
      _from = DateTime.parse(widget.item['date_from']);
    }
    if (widget.item['date_to'] != null) {
      _to = DateTime.parse(widget.item['date_to']);
    }
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: _from ?? DateTime.now(),
    );
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: _to ?? _from ?? DateTime.now(),
    );
    if (d != null) setState(() => _to = d);
  }

  Future<void> _assign() async {
    if (_bus == null || _from == null || _to == null) return;
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final draftIdForRows = widget.item['draft_id']?.toString() ?? '';
      final roundIdxForRows = widget.item['round_index'];

      if (draftIdForRows.isNotEmpty) {
        // ── Draft-backed entry: update existing WAITING_LIST rows in samletdata
        //    This preserves sted, km, kjoretoy, pris, no_ddrive etc.
        var query = _sb
            .from('samletdata')
            .update({'kilde': _bus, 'status': _status})
            .eq('draft_id', draftIdForRows)
            .eq('kilde', 'WAITING_LIST');
        if (roundIdxForRows != null) {
          final ri = roundIdxForRows is int
              ? roundIdxForRows
              : (roundIdxForRows as num).toInt();
          query = query.eq('round_index', ri);
        }
        await query;
      } else {
        // ── Manual waiting-list entry (no draft): create new blank rows
        final rows = <Map<String, dynamic>>[];
        DateTime d = normalize(_from!);
        final end = normalize(_to!);
        while (!d.isAfter(end)) {
          rows.add({
            'dato': fmtDb(d),
            'kilde': _bus,
            'produksjon': widget.item['production'] ?? '',
            'contact': widget.item['contact'] ?? '',
            'status': _status,
            'manual_block': false,
          });
          d = d.add(const Duration(days: 1));
        }
        await _sb.from('samletdata').insert(rows);
      }

      // Remove from waiting list
      await _sb.from('waiting_list').delete().eq('id', widget.item['id']);

      // Update the offer draft: replace the waiting list slot with the assigned bus
      final draftId = widget.item['draft_id']?.toString();
      if (draftId != null && draftId.isNotEmpty) {
        final roundIdx = widget.item['round_index'];
        final slotIdx  = widget.item['slot_index'];
        // Coerce to int defensively — Supabase may return num
        final ri = roundIdx is int ? roundIdx : (roundIdx as num?)?.toInt() ?? 0;
        final si = slotIdx  is int ? slotIdx  : (slotIdx  as num?)?.toInt() ?? 0;
        try {
          final draft = await OfferStorageService.loadDraft(draftId);
          if (ri < draft.rounds.length) {
            final round = draft.rounds[ri];
            // Extend list if needed (defensive)
            while (round.busSlots.length <= si) {
              round.busSlots.add(null);
            }
            round.busSlots[si] = _bus!;
            await OfferStorageService.saveDraft(id: draftId, offer: draft);
          }
        } catch (e) {
          debugPrint('⚠️ Could not update draft busSlots: $e');
        }
      }

      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Assign "${widget.item['production'] ?? ''}" to bus',
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // Bus
            DropdownButtonFormField<String>(
              value: _bus,
              decoration: const InputDecoration(
                labelText: "Bus *",
                border: OutlineInputBorder(),
              ),
              items: widget.buses
                  .map((b) => DropdownMenuItem(
                        value: b,
                        child: Text(fmtBus(b)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _bus = v),
            ),

            const SizedBox(height: 12),

            // Status
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                labelText: "Status",
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Inquiry', child: Text("Inquiry")),
                DropdownMenuItem(value: 'Confirmed', child: Text("Confirmed")),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'Inquiry'),
            ),

            const SizedBox(height: 12),

            // Date from
            TextField(
              readOnly: true,
              onTap: _pickFrom,
              decoration: InputDecoration(
                labelText: "From *",
                border: const OutlineInputBorder(),
                hintText: _from == null
                    ? 'Pick date'
                    : DateFormat('dd.MM.yyyy').format(_from!),
                suffixIcon: const Icon(Icons.calendar_today, size: 16),
              ),
            ),

            const SizedBox(height: 12),

            // Date to
            TextField(
              readOnly: true,
              onTap: _pickTo,
              decoration: InputDecoration(
                labelText: "To *",
                border: const OutlineInputBorder(),
                hintText: _to == null
                    ? 'Pick date'
                    : DateFormat('dd.MM.yyyy').format(_to!),
                suffixIcon: const Icon(Icons.calendar_today, size: 16),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: (_saving || _bus == null || _from == null || _to == null)
              ? null
              : _assign,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Assign"),
        ),
      ],
    );
  }
}