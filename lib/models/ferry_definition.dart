class FerryDefinition {
  final String name;
  final double price;
  final double? trailerPrice;

  const FerryDefinition({
    required this.name,
    required this.price,
    this.trailerPrice,
  });
}