import 'package:flutter/material.dart';
import '../state/active_company.dart';

class VehicleConfig {
  final List<String> all;
  final List<String> allExclConf;
  final Map<String, String> types;
  final String label;       // "bus" / "lastebil"
  final String labelPlural; // "buses" / "lastebiler"
  final IconData icon;      // directions_bus / local_shipping

  const VehicleConfig({
    required this.all,
    required this.allExclConf,
    required this.types,
    required this.label,
    required this.labelPlural,
    required this.icon,
  });

  String get labelCap => _cap(label);
  String get labelPluralCap => _cap(labelPlural);
}

const _cssVehicles = VehicleConfig(
  label: 'bus',
  labelPlural: 'buses',
  icon: Icons.directions_bus,
  all: [
    'CSS_1034',
    'CSS_1023',
    'CSS_1008',
    'YCR 682',
    'ESW 337',
    'WYN 802',
    'RLC 29G',
    'Rental 1 (Hasse)',
    'Rental 2 (Rickard)',
    'Conference',
  ],
  allExclConf: [
    'CSS_1034',
    'CSS_1023',
    'CSS_1008',
    'YCR 682',
    'ESW 337',
    'WYN 802',
    'RLC 29G',
    'Rental 1 (Hasse)',
    'Rental 2 (Rickard)',
  ],
  types: {
    'CSS_1034': '12\u201318 bunks\n12 + Star room',
    'CSS_1023': '12\u201314 sleeper',
    'CSS_1008': '12 sleeper',
    'YCR 682': '16-sleeper',
    'ESW 337': '14-sleeper',
    'WYN 802': '14-sleeper',
    'RLC 29G': '16-sleeper',
    'Rental 1 (Hasse)': '16-sleeper',
    'Rental 2 (Rickard)': '16-sleeper',
    'Conference': '20-50 seats',
  },
);

const _mossTruckVehicles = VehicleConfig(
  label: 'lastebil',
  labelPlural: 'lastebiler',
  icon: Icons.local_shipping,
  all: [
    'Lastebil 1',
    'Lastebil 2',
    'Lastebil 3',
  ],
  allExclConf: [
    'Lastebil 1',
    'Lastebil 2',
    'Lastebil 3',
  ],
  types: {
    'Lastebil 1': 'Lastebil',
    'Lastebil 2': 'Lastebil',
    'Lastebil 3': 'Lastebil',
  },
);

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

VehicleConfig getVehicleConfig() {
  final name = activeCompanyNotifier.value?.name ?? '';
  if (name == 'Moss Turbusser') return _mossTruckVehicles;
  return _cssVehicles;
}
