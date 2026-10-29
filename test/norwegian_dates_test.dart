import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// DateFormat med norsk locale kaster LocaleDataException ved konstruksjon
/// hvis locale-dataene ikke er lastet. Appen gjør det i main(); denne testen
/// holder fast på at de norske formatene faktisk virker når de er lastet, og
/// dokumenterer at de IKKE gjør det uten.
void main() {
  test('norske datoformater krever initializeDateFormatting', () {
    expect(
      () => DateFormat('MMMM yyyy', 'nb_NO'),
      throwsA(isA<Exception>()),
      reason: 'uten lasting skal det kaste — det er derfor main() laster',
    );
  });

  test('etter lasting formaterer nb og nb_NO', () async {
    await initializeDateFormatting('nb_NO');
    await initializeDateFormatting('nb');

    expect(DateFormat('MMMM yyyy', 'nb_NO').format(DateTime(2026, 3, 14)),
        'mars 2026');
    expect(DateFormat('d. MMMM yyyy', 'nb').format(DateTime(2026, 3, 14)),
        '14. mars 2026');
  });
}
