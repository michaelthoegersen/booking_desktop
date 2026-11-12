import 'package:flutter/material.dart';

class PollCreateDialog extends StatefulWidget {
  final Future<void> Function(String question, List<String> options) onCreate;
  const PollCreateDialog({super.key, required this.onCreate});

  @override
  State<PollCreateDialog> createState() => _PollCreateDialogState();
}

class _PollCreateDialogState extends State<PollCreateDialog> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _creating = false;
  String? _error;

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  bool get _isValid {
    return _questionController.text.trim().isNotEmpty &&
        _optionControllers.where((c) => c.text.trim().isNotEmpty).length >= 2;
  }

  Future<void> _create() async {
    if (!_isValid || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // Denne await-en lå naken før. Kastet onCreate - og den gjorde det
    // hver gang, fordi poll-tabellene ikke fantes i databasen - sto
    // _creating igjen som true, og knappen spant videre uten å si et ord
    // om hva som gikk galt. Nullstillingen hører hjemme i finally, slik at den
    // også holder hvis det legges til flere tidlige returer her senere.
    try {
      await widget.onCreate(_questionController.text.trim(), options);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Fikk ikke opprettet avstemmingen: $e');
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Opprett avstemming'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(
                labelText: 'Spørsmål',
                hintText: 'Hva vil du spørre om?',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            ...List.generate(_optionControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionControllers[i],
                        decoration: InputDecoration(
                          labelText: 'Alternativ ${i + 1}',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _removeOption(i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              );
            }),
            if (_optionControllers.length < 6)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Legg til alternativ'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFB3261E),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Avbryt'),
        ),
        FilledButton(
          onPressed: _isValid && !_creating ? _create : null,
          child: _creating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Opprett'),
        ),
      ],
    );
  }
}
