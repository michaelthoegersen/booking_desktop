import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


// ============================================================
// HELPERS
// ============================================================

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


// ============================================================
// DRAG DATA
// ============================================================

class DragBookingData {
  final String production;
  final String fromBus;
  final DateTime from;
  final DateTime to;

  DragBookingData({
    required this.production,
    required this.fromBus,
    required this.from,
    required this.to,
  });
}
// ============================================================
// STATUS COLORS
// ============================================================

Color statusColor(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'draft':
      return Colors.purple.shade300;
    case 'inquiry':
      return Colors.orange.shade300;
    case 'confirmed':
      return Colors.green.shade400;
    default:
      return Colors.grey.shade300;
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

  final supabase = Supabase.instance.client;

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
  ];


  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    weekStart = startOfWeek(DateTime.now());
    monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);

    loadWeek();
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

    final start = DateTime(monthStart.year, monthStart.month, 1);
    final end = DateTime(monthStart.year, monthStart.month + 1, 0);

    await loadRange(start, end);
  }


  Future<void> loadRange(DateTime start, DateTime end) async {

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

        final date = normalize(DateTime.parse(dateStr));

        map.putIfAbsent(bus, () => {});
        map[bus]!.putIfAbsent(date, () => []);
        map[bus]![date]!.add(r);
      }

      if (mounted) {
        setState(() {
          data = map;
        });
      }

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

    return Padding(
      padding: const EdgeInsets.all(16),

      child: Column(
        children: [

          buildHeader(days),

          const SizedBox(height: 12),

          buildContent(days),
        ],
      ),
    );
  }
    // ============================================================
  // HEADER
  // ============================================================

  Widget buildHeader(List<DateTime> days) {

    final title = isMonthView
        ? DateFormat("MMMM yyyy").format(monthStart)
        : "${fmt(days.first)} - ${fmt(days.last)}";

    return Row(
      children: [

        const Text(
          "Calendar",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),

        const Spacer(),

        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: prev,
        ),

        Text(title),

        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: next,
        ),

        const SizedBox(width: 16),

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
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (error != null) {
      return Expanded(
        child: Center(
          child: Text(
            error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return buildGrid(days);
  }
    // ============================================================
  // GRID
  // ============================================================

  Widget buildGrid(List<DateTime> days) {

    final width = busWidth + dayWidth * days.length;

    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,

        child: SizedBox(
          width: width,

          child: Column(
            children: [

              buildHeaderRow(days),

              Expanded(
                child: ListView(
                  children: [
                    for (final bus in buses)
                      buildRow(bus, days),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  // ============================================================
  // HEADER ROW
  // ============================================================

  Widget buildHeaderRow(List<DateTime> days) {

    return Container(
      height: 48,

      decoration: BoxDecoration(
        color: Colors.grey.shade100,

        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),

      child: Row(
        children: [

          const SizedBox(width: busWidth),

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
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  Text(
                    DateFormat("dd.MM").format(d),
                    style: const TextStyle(fontSize: 12),
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
        height: 64,

        decoration: BoxDecoration(
          color: highlight
              ? Colors.blue.withOpacity(0.08)
              : null,

          border: Border(
            bottom: BorderSide(
              color: Colors.grey.shade300,
            ),
          ),
        ),

        child: Row(
          children: [

            BusCell(bus),

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

  int i = 0;

  while (i < days.length) {
    final day = normalize(days[i]);

    final items = data[bus]?[day] ?? [];

    if (items.isEmpty) {
      result.add(
        SizedBox(width: dayWidth),
      );
      i++;
      continue;
    }

    final prod = items.first['produksjon']?.toString() ?? '';

    if (prod.isEmpty) {
      result.add(
        SizedBox(width: dayWidth),
      );
      i++;
      continue;
    }

    // =====================================
    // FIND FULL RANGE IN DATA (BACK + FORTH)
    // =====================================

    DateTime start = day;
    DateTime end = day;

    // Backwards
    DateTime prev = start.subtract(const Duration(days: 1));

    while (true) {
      final prevItems = data[bus]?[prev];

      if (prevItems == null ||
          prevItems.isEmpty ||
          prevItems.first['produksjon'] != prod) {
        break;
      }

      start = prev;
      prev = prev.subtract(const Duration(days: 1));
    }

    // Forwards
    DateTime next = end.add(const Duration(days: 1));

    while (true) {
      final nextItems = data[bus]?[next];

      if (nextItems == null ||
          nextItems.isEmpty ||
          nextItems.first['produksjon'] != prod) {
        break;
      }

      end = next;
      next = next.add(const Duration(days: 1));
    }

    // =====================================
    // CALCULATE ONLY VISIBLE SPAN
    // =====================================

    int span = 0;

    DateTime cursor = start;

    while (!cursor.isAfter(end)) {
      if (days.any((d) => normalize(d) == cursor)) {
        span++;
      }

      cursor = cursor.add(const Duration(days: 1));
    }

    // =====================================
    // ADD SEGMENT
    // =====================================

    result.add(
      BookingSegment(
        title: prod,
        span: span,
        bus: bus,
        from: start,
        to: end,
        status: items.first['status'],
        width: dayWidth,
      ),
    );

    i += span;
  }

  return result;
}
  } // <-- SLUTT på _CalendarPageState



// ============================================================
// BOOKING SEGMENT
// ============================================================

class BookingSegment extends StatelessWidget {

  final String title;
  final int span;
  final String bus;
  final DateTime from;
  final DateTime to;
  final String? status;
  final double width;

  const BookingSegment({
    super.key,
    required this.title,
    required this.span,
    required this.bus,
    required this.from,
    required this.to,
    this.status,
    required this.width,
  });



  // ============================================================
  // UPDATE STATUS
  // ============================================================

  Future<void> _updateStatus(
    BuildContext context,
    String newStatus,
  ) async {

    final sb = Supabase.instance.client;

    await sb
        .from('samletdata')
        .update({'status': newStatus})
        .eq('produksjon', title)
        .eq('kilde', bus)
        .gte('dato', fmtDb(from))
        .lte('dato', fmtDb(to));


    if (context.mounted) {

      final parent =
          context.findAncestorStateOfType<_CalendarPageState>();

      parent?.loadWeek();
    }
  }



  // ============================================================
  // STATUS MENU
  // ============================================================

  Future<void> _showStatusMenu(
    BuildContext context,
    TapDownDetails details,
  ) async {

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;


    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        details.globalPosition.dx,
        details.globalPosition.dy,
        1,
        1,
      ),
      Offset.zero & overlay.size,
    );


    final selected = await showMenu<String>(

      context: context,
      position: position,

      items: const [

        PopupMenuItem(
          value: 'draft',
          child: Text("Draft"),
        ),

        PopupMenuItem(
          value: 'inquiry',
          child: Text("Inquiry"),
        ),

        PopupMenuItem(
          value: 'confirmed',
          child: Text("Confirmed"),
        ),
      ],
    );


    if (selected != null) {
      await _updateStatus(context, selected);
    }
  }
// ============================================================
// SEGMENT BODY
// ============================================================

Widget _buildBody(BuildContext context) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,

    onDoubleTap: () async {
      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => EditCalendarDialog(
          production: title,
          bus: bus,
          from: from,
          to: to,
        ),
      );

      if (changed == true && context.mounted) {
        final parent =
            context.findAncestorStateOfType<_CalendarPageState>();

        parent?.loadWeek();
      }
    },

    onSecondaryTapDown: (d) {
      _showStatusMenu(context, d);
    },

    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(6),

      decoration: BoxDecoration(
        color: statusColor(status),
        borderRadius: BorderRadius.circular(6),
      ),

      child: Text(
        title,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

// ============================================================
// BUILD (DRAGGABLE + EXPANDED)
// ============================================================

@override
Widget build(BuildContext context) {
  return Expanded(
    flex: span,

    child: Draggable<DragBookingData>(
      data: DragBookingData(
        production: title,
        fromBus: bus,
        from: from,
        to: to,
      ),

      affinity: Axis.vertical,

      // =========================
      // Preview while dragging
      // =========================
      feedback: Material(
        color: Colors.transparent,

        child: Container(
          width: width * span,
          padding: const EdgeInsets.all(6),

          decoration: BoxDecoration(
            color: statusColor(status).withOpacity(0.9),
            borderRadius: BorderRadius.circular(6),

            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
              ),
            ],
          ),

          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),

      // =========================
      // Placeholder
      // =========================
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildBody(context),
      ),

      // =========================
      // Normal
      // =========================
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

  const BusCell(this.bus, {super.key});


  @override
  Widget build(BuildContext context) {

    return Container(
      width: 140,

      padding: const EdgeInsets.symmetric(horizontal: 12),

      alignment: Alignment.centerLeft,

      child: Text(
        bus,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
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


  final Map<String, TextEditingController> dDriveCtrls = {};
  final Map<String, TextEditingController> itinCtrls = {};
  final Map<String, TextEditingController> timeCtrls = {};
  final Map<String, TextEditingController> venueCtrls = {};
  final Map<String, TextEditingController> addrCtrls = {};
  final Map<String, TextEditingController> commentCtrls = {};


  final List<Map<String, dynamic>> rows = [];


  bool loading = true;
  bool saving = false;

  int activeIndex = 0;



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

  Future<void> load() async {

    final res = await supabase
        .from('samletdata')
        .select()
        .eq('produksjon', widget.production)
        .eq('kilde', widget.bus)
        .gte('dato', fmtDb(widget.from))
        .lte('dato', fmtDb(widget.to))
        .order('dato');


    final list = List<Map<String, dynamic>>.from(res);


    if (list.isEmpty) {

      setState(() {
        loading = false;
      });

      return;
    }


    sjaforCtrl.text = list.first['sjafor'] ?? '';
    statusCtrl.text = list.first['status'] ?? '';


    rows.addAll(list);


    for (final r in list) {

      final id = r['id'].toString();


      dDriveCtrls[id] =
          TextEditingController(text: r['d_drive'] ?? '');

      itinCtrls[id] =
          TextEditingController(text: r['getin'] ?? '');

      timeCtrls[id] =
          TextEditingController(text: r['tid'] ?? '');

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

      await supabase
          .from('samletdata')
          .update({
            'sjafor': sjaforCtrl.text.trim(),
            'status': statusCtrl.text.trim(),
          })
          .eq('produksjon', widget.production)
          .eq('kilde', widget.bus)
          .gte('dato', fmtDb(widget.from))
          .lte('dato', fmtDb(widget.to));


      for (final r in rows) {

        final id = r['id'].toString();


        await supabase
            .from('samletdata')
            .update({

              'd_drive': dDriveCtrls[id]?.text.trim() ?? '',
              'getin': itinCtrls[id]?.text.trim() ?? '',
              'tid': timeCtrls[id]?.text.trim() ?? '',
              'venue': venueCtrls[id]?.text.trim() ?? '',
              'adresse': addrCtrls[id]?.text.trim() ?? '',
              'kommentarer': commentCtrls[id]?.text.trim() ?? '',
            })
            .eq('id', id);
      }


      if (!mounted) return;

      Navigator.pop(context, true);

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


    for (final m in [

      dDriveCtrls,
      itinCtrls,
      timeCtrls,
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

                    _field("Sjåfør", sjaforCtrl),
                    _field("Status", statusCtrl),

                    const SizedBox(height: 16),
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
                    _dayField("Tid", timeCtrls),
                    _dayField("Venue", venueCtrls),
                    _dayField("Adresse", addrCtrls),
                    _multiDayField("Kommentar", commentCtrls),
                  ],
                ),
              ),
      ),


      actions: [

        TextButton(
          onPressed: saving
              ? null
              : () => Navigator.pop(context),
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
      ],
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