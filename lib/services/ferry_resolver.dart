import '../models/ferry_definition.dart';

class FerryResolver {

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(' ', '').replaceAll('-', '');

  static double resolveTotalFerryCost({
    required List<String> extraPerLeg,
    required List<FerryDefinition> ferries,
    required bool trailer,
  }) {
    double total = 0;

    for (final extra in extraPerLeg) {
      final cleaned = _normalize(extra);

      final FerryDefinition? match = ferries.cast<FerryDefinition?>().firstWhere(
        (f) => _normalize(f!.name) == cleaned,
        orElse: () => null,
      );

      if (match == null) continue;

      total += trailer && match.trailerPrice != null
          ? match.trailerPrice!
          : match.price;
    }

    return total;
  }
}