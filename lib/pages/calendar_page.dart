import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ------------------------------------------------------------
// STATUS COLORS
// ------------------------------------------------------------
Color _statusColor(String? status) {
  switch (status?.toLowerCase()) {
    case 'draft':
      return Colors.purple.shade200;

    case 'inquiry':
      return Colors.orange.shade200;

    case 'confirmed':
      return Colors.green.shade200;

    default:
      return Colors.blue.shade100;
  }
}

// ------------------------------------------------------------
// CALENDAR PAGE
// ------------------------------------------------------------
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final supabase = Supabase.instance.client;

  late DateTime weekStart;

  bool loading = false;
  String? error;

  Map<String, Map<DateTime, List<Map<String, dynamic>>>> data = {};

  final buses = [
    "CSS_1034",
    "CSS_1023",
    "CSS_1008",
  ];

  @override
  void initState() {
    super.initState();
    weekStart = _startOfWeek(DateTime.now());
    _loadWeek();
  }

  // --------------------------------------------------
  // LOAD (with buffer)
  // --------------------------------------------------
  Future<void> _loadWeek() async {
    setState(() {
      loading = true;
      error = null;
    });

    final start = weekStart.subtract(const Duration(days: 7));
    final end = weekStart.add(const Duration(days: 13));

    try {
      final res = await supabase
          .from('samletdata')
          .select()
          .gte('dato', _fmtDb(start))
          .lte('dato', _fmtDb(end));

      final rows = List<Map<String, dynamic>>.from(res);

      final map =
          <String, Map<DateTime, List<Map<String, dynamic>>>>{};

      for (final r in rows) {
        final bus = r['kilde']?.toString();
        final dateStr = r['dato'];

        if (bus == null || dateStr == null) continue;

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

      if (mounted) {
        setState(() => data = map);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final days =
        List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _buildHeader(days),
          const SizedBox(height: 12),
          Expanded(child: _buildContent(days)),
        ],
      ),
    );
  }

  Widget _buildHeader(List<DateTime> days) {
    return Row(
      children: [
        const Text(
          "Calendar",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        IconButton(
            onPressed: _prevWeek,
            icon: const Icon(Icons.chevron_left)),
        Text("${_fmt(days.first)} - ${_fmt(days.last)}"),
        IconButton(
            onPressed: _nextWeek,
            icon: const Icon(Icons.chevron_right)),
      ],
    );
  }

  Widget _buildContent(List<DateTime> days) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return _ErrorBox(error!);
    }

    return _buildGrid(days);
  }

  Widget _buildGrid(List<DateTime> days) {
    return Column(
      children: [
        _buildHeaderRow(days),
        for (final bus in buses) _buildTimelineRow(bus, days),
      ],
    );
  }

  Widget _buildHeaderRow(List<DateTime> days) {
    return Container(
      height: 44,
      color: Colors.grey.shade100,
      child: Row(
        children: [
          const SizedBox(width: 140),
          for (final d in days)
            Expanded(
              child: Center(
                child: Text(
                  DateFormat("EEE\ndd.MM").format(d),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineRow(String bus, List<DateTime> days) {
  return DragTarget<_DragBookingData>(
    onWillAccept: (data) {
      return data != null && data.fromBus != bus;
    },

    onAccept: (data) async {
      await supabase
          .from('samletdata')
          .update({'kilde': bus})
          .eq('produksjon', data.production)
          .eq('kilde', data.fromBus)
          .gte('dato', _fmtDb(data.from))
          .lte('dato', _fmtDb(data.to));

      if (mounted) {
        _loadWeek();
      }
    },

    builder: (context, candidate, rejected) {
      final segments = _buildSegments(bus, days);

      return Container(
        height: 64,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: candidate.isNotEmpty
                  ? Colors.blue
                  : Colors.black12,
              width: candidate.isNotEmpty ? 2 : 1,
            ),
          ),
        ),
        child: Row(
          children: [
            _BusCell(bus),
            Expanded(child: Row(children: segments)),
          ],
        ),
      );
    },
  );
}

  // --------------------------------------------------
  // SEGMENTS
  // --------------------------------------------------
  List<Widget> _buildSegments(String bus, List<DateTime> days) {
    final result = <Widget>[];

    int i = 0;

    while (i < days.length) {
      final current = _normalize(days[i]);

      final items = data[bus]?[current] ?? [];

      if (items.isEmpty) {
        result.add(const Expanded(child: SizedBox()));
        i++;
        continue;
      }

      final prod =
          items.first['produksjon']?.toString().trim() ?? '';

      final status =
          items.first['status']?.toString().trim();

      if (prod.isEmpty) {
        result.add(const Expanded(child: SizedBox()));
        i++;
        continue;
      }

      DateTime from = current;
      DateTime check = current.subtract(const Duration(days: 1));

      while (true) {
        final prev = data[bus]?[check];

        if (prev == null || prev.isEmpty) break;

        final p =
            prev.first['produksjon']?.toString().trim() ?? '';

        if (p != prod) break;

        from = check;
        check = check.subtract(const Duration(days: 1));
      }

      DateTime to = current;

      check = current.add(const Duration(days: 1));

      while (true) {
        final next = data[bus]?[check];

        if (next == null || next.isEmpty) break;

        final p =
            next.first['produksjon']?.toString().trim() ?? '';

        if (p != prod) break;

        to = check;
        check = check.add(const Duration(days: 1));
      }

      int span = 1;

      for (int j = i + 1; j < days.length; j++) {
        final d = _normalize(days[j]);

        if (d.isAfter(to)) break;

        final next = data[bus]?[d];

        if (next == null || next.isEmpty) break;

        final p =
            next.first['produksjon']?.toString().trim() ?? '';

        if (p != prod) break;

        span++;
      }

      result.add(
        _BookingSegment(
          title: prod,
          span: span,
          bus: bus,
          from: from,
          to: to,
          status: status,
        ),
      );

      i += span;
    }

    return result;
  }

  DateTime _normalize(DateTime d) =>
      DateTime(d.year, d.month, d.day);
}

// --------------------------------------------------
// BOOKING SEGMENT
// --------------------------------------------------
class _BookingSegment extends StatelessWidget {
  final String title;
  final int span;
  final String bus;
  final DateTime from;
  final DateTime to;
  final String? status;

  const _BookingSegment({
    required this.title,
    required this.span,
    required this.bus,
    required this.from,
    required this.to,
    this.status,
  });

  // --------------------------------------------------
  // STATUS → COLOR
  // --------------------------------------------------
  Color _statusColor() {
    switch ((status ?? '').toLowerCase()) {
      case 'draft':
        return Colors.purple.shade300;

      case 'inquiry':
        return Colors.orange.shade300;

      case 'confirmed':
        return Colors.green.shade400;

      default:
        return Colors.blue.shade100;
    }
  }

  // --------------------------------------------------
  // UPDATE STATUS
  // --------------------------------------------------
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
        .gte('dato', _fmtDb(from))
        .lte('dato', _fmtDb(to));

    if (context.mounted) {
      final parent =
          context.findAncestorStateOfType<_CalendarPageState>();

      parent?._loadWeek();
    }
  }

  // --------------------------------------------------
  // CONTEXT MENU (RIGHT CLICK)
  // --------------------------------------------------
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
          child: Row(
            children: [
              Icon(Icons.circle, color: Colors.purple, size: 12),
              SizedBox(width: 8),
              Text("Draft"),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'inquiry',
          child: Row(
            children: [
              Icon(Icons.circle, color: Colors.orange, size: 12),
              SizedBox(width: 8),
              Text("Inquiry"),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'confirmed',
          child: Row(
            children: [
              Icon(Icons.circle, color: Colors.green, size: 12),
              SizedBox(width: 8),
              Text("Confirmed"),
            ],
          ),
        ),
      ],
    );

    if (selected != null) {
      await _updateStatus(context, selected);
    }
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: span,

      // 🔥 NYTT: Draggable wrapper
      child: Draggable<_DragBookingData>(
        data: _DragBookingData(
          production: title,
          fromBus: bus,
          from: from,
          to: to,
        ),

        // Når man drar
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 160 * span.toDouble(),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _statusColor().withOpacity(0.85),
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

        // Når feltet er tomt mens man drar
        childWhenDragging: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(6),
          ),
        ),

        // 👇 Din originale widget (uratørt)
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,

          // ---------------- Double click → Edit
          onDoubleTap: () async {
            final changed = await showDialog<bool>(
              context: context,
              builder: (_) => _EditCalendarDialog(
                production: title,
                bus: bus,
                from: from,
                to: to,
              ),
            );

            if (changed == true && context.mounted) {
              final parent =
                  context.findAncestorStateOfType<_CalendarPageState>();

              parent?._loadWeek();
            }
          },

          // ---------------- Right click → Status menu
          onSecondaryTapDown: (details) {
            _showStatusMenu(context, details);
          },

          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _statusColor(),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// UPDATE STATUS
// --------------------------------------------------
Future<void> _updateStatus(
  BuildContext context,
  String status,
  String production,
  String bus,
  DateTime from,
  DateTime to,
) async {
  final sb = Supabase.instance.client;

  await sb
      .from('samletdata')
      .update({'status': status})
      .eq('produksjon', production)
      .eq('kilde', bus)
      .gte('dato', _fmtDb(from))
      .lte('dato', _fmtDb(to));

  if (context.mounted) {
    final parent =
        context.findAncestorStateOfType<_CalendarPageState>();

    parent?._loadWeek();
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(bus,
          style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

// --------------------------------------------------
// ERROR BOX
// --------------------------------------------------
class _ErrorBox extends StatelessWidget {
  final String error;

  const _ErrorBox(this.error);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(error,
          style: const TextStyle(color: Colors.red)),
    );
  }
}

// --------------------------------------------------
// EDIT DIALOG (UNCHANGED)
// --------------------------------------------------
class _EditCalendarDialog extends StatefulWidget {
  final String production;
  final String bus;
  final DateTime from;
  final DateTime to;

  const _EditCalendarDialog({
    required this.production,
    required this.bus,
    required this.from,
    required this.to,
  });

  @override
  State<_EditCalendarDialog> createState() =>
      _EditCalendarDialogState();
}

class _EditCalendarDialogState
    extends State<_EditCalendarDialog> {

  final supabase = Supabase.instance.client;

  final sjafor = TextEditingController();
  final status = TextEditingController();

  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await supabase
        .from('samletdata')
        .select()
        .eq('produksjon', widget.production)
        .eq('kilde', widget.bus)
        .gte('dato', _fmtDb(widget.from))
        .lte('dato', _fmtDb(widget.to));

    final rows = List<Map<String, dynamic>>.from(res);

    if (rows.isNotEmpty) {
      sjafor.text = rows.first['sjafor'] ?? '';
      status.text = rows.first['status'] ?? '';
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (saving) return;

    setState(() => saving = true);

    try {
      await supabase
          .from('samletdata')
          .update({
            'sjafor': sjafor.text.trim(),
            'status': status.text.trim(),
          })
          .eq('produksjon', widget.production)
          .eq('kilde', widget.bus)
          .gte('dato', _fmtDb(widget.from))
          .lte('dato', _fmtDb(widget.to));

      if (!mounted) return;

      Navigator.pop(context, true);

    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  void dispose() {
    sjafor.dispose();
    status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        "Edit ${widget.production}\n"
        "${_fmt(widget.from)} - ${_fmt(widget.to)}",
      ),

      content: SizedBox(
        width: 400,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field("Sjåfør", sjafor),
                  _field("Status", status),
                ],
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
          onPressed: saving ? null : _save,
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
}
// --------------------------------------------------
// DRAG DATA
// --------------------------------------------------
class _DragBookingData {
  final String production;
  final String fromBus;
  final DateTime from;
  final DateTime to;

  _DragBookingData({
    required this.production,
    required this.fromBus,
    required this.from,
    required this.to,
  });
}

// --------------------------------------------------
// HELPERS
// --------------------------------------------------
DateTime _startOfWeek(DateTime d) {
  final diff = d.weekday - DateTime.monday;
  return DateTime(d.year, d.month, d.day - diff);
}

String _fmt(DateTime d) =>
    DateFormat("dd.MM.yyyy").format(d);

String _fmtDb(DateTime d) =>
    DateFormat("yyyy-MM-dd").format(d);