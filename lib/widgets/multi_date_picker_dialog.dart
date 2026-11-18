import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ============================================================================
// MULTI-DATE PICKER
//
// Lives here rather than inside one page because two places need the same
// calendar: «Gjenta på flere datoer» when an activity is created, and
// «Dupliser til datoer…» on an activity that already exists.
// ============================================================================
class MultiDatePickerDialog extends StatefulWidget {
  /// Initially-selected dates (date-only — time component ignored).
  final Set<DateTime> initial;

  /// Dates that should not be selectable (e.g. the primary "Dato fra" already
  /// chosen on the parent dialog).
  final Set<DateTime> excludeDates;

  const MultiDatePickerDialog({
    super.key,
    required this.initial,
    this.excludeDates = const {},
  });

  @override
  State<MultiDatePickerDialog> createState() =>
      _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<MultiDatePickerDialog> {
  late final Set<DateTime> _selected;
  late DateTime _viewMonth;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.map(_d).toSet();
    final now = DateTime.now();
    _viewMonth = DateTime(now.year, now.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _viewMonth =
          DateTime(_viewMonth.year, _viewMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthFmt = DateFormat('MMMM yyyy', 'nb_NO');
    final firstWeekday = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday;
    // Monday-first: shift so weekday 1 (Mon) lands at column 0
    final leadingBlanks = (firstWeekday - 1) % 7;
    final daysInMonth =
        DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final today = _d(DateTime.now());

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Velg datoer å gjenta på',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Trykk en dag for å markere/avmarkere. ${_selected.length} valgt.',
                style:
                    TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shiftMonth(-1),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        monthFmt.format(_viewMonth),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shiftMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Weekday header
              Row(
                children: ['Ma', 'Ti', 'On', 'To', 'Fr', 'Lø', 'Sø']
                    .map((w) => Expanded(
                          child: Center(
                            child: Text(
                              w,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 4),
              // Calendar grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leadingBlanks + daysInMonth,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, i) {
                  if (i < leadingBlanks) return const SizedBox.shrink();
                  final day = i - leadingBlanks + 1;
                  final date = DateTime(_viewMonth.year, _viewMonth.month, day);
                  final isSelected = _selected.contains(date);
                  final isExcluded = widget.excludeDates.contains(date);
                  final isToday = date == today;
                  final isPast = date.isBefore(today);

                  Color? bg;
                  Color fg = cs.onSurface;
                  FontWeight weight = FontWeight.w500;
                  if (isExcluded) {
                    bg = cs.primary.withValues(alpha: 0.15);
                    fg = cs.primary;
                    weight = FontWeight.w800;
                  } else if (isSelected) {
                    bg = Colors.black;
                    fg = Colors.white;
                    weight = FontWeight.w800;
                  } else if (isToday) {
                    bg = cs.surfaceContainerHigh;
                    weight = FontWeight.w800;
                  } else if (isPast) {
                    fg = cs.onSurfaceVariant.withValues(alpha: 0.5);
                  }

                  return Padding(
                    padding: const EdgeInsets.all(2),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: isExcluded
                          ? null
                          : () => setState(() {
                                if (_selected.contains(date)) {
                                  _selected.remove(date);
                                } else {
                                  _selected.add(date);
                                }
                              }),
                      child: Container(
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: weight,
                              color: fg,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_selected.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() => _selected.clear()),
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Tøm'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Avbryt'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text('Bruk (${_selected.length})'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
