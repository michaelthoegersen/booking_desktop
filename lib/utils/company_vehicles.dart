import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

// ── Hardcoded fallbacks (used until DB is populated) ──────────────────────

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

// ── Cached DB config ──────────────────────────────────────────────────────

VehicleConfig? _cachedConfig;
String? _cachedCompanyId;

/// Get vehicle config for the active company.
/// Returns hardcoded fallback if DB config not yet loaded.
VehicleConfig getVehicleConfig() {
  final companyId = activeCompanyNotifier.value?.id;

  // Return cached DB config if available
  if (companyId != null && companyId == _cachedCompanyId && _cachedConfig != null) {
    return _cachedConfig!;
  }

  // Hardcoded fallback
  final name = activeCompanyNotifier.value?.name ?? '';
  if (name == 'Moss Turbusser') return _mossTruckVehicles;
  return _cssVehicles;
}

/// Load vehicle config from database. Falls back to hardcoded if DB empty.
Future<VehicleConfig> loadVehicleConfig() async {
  final companyId = activeCompanyNotifier.value?.id;
  if (companyId == null) return _cssVehicles;

  try {
    final sb = Supabase.instance.client;

    // Fetch vehicle types from DB
    final rows = await sb
        .from('vehicle_types')
        .select('name, description, is_conference')
        .eq('company_id', companyId)
        .eq('active', true)
        .order('sort_order');

    final vehicles = List<Map<String, dynamic>>.from(rows);

    // If DB is empty, use hardcoded fallback
    if (vehicles.isEmpty) {
      final name = activeCompanyNotifier.value?.name ?? '';
      final fallback = name == 'Moss Turbusser' ? _mossTruckVehicles : _cssVehicles;
      _cachedConfig = fallback;
      _cachedCompanyId = companyId;
      return fallback;
    }

    // Fetch company vehicle label settings
    final company = await sb
        .from('companies')
        .select('vehicle_label, vehicle_label_plural, vehicle_icon')
        .eq('id', companyId)
        .maybeSingle();

    final vehicleLabel = company?['vehicle_label'] as String? ?? 'bus';
    final vehicleLabelPlural = company?['vehicle_label_plural'] as String? ?? 'busser';
    final vehicleIconStr = company?['vehicle_icon'] as String? ?? 'directions_bus';

    IconData icon;
    switch (vehicleIconStr) {
      case 'local_shipping':
        icon = Icons.local_shipping;
        break;
      case 'airport_shuttle':
        icon = Icons.airport_shuttle;
        break;
      default:
        icon = Icons.directions_bus;
    }

    final all = vehicles.map((v) => v['name'] as String).toList();
    final allExclConf = vehicles
        .where((v) => v['is_conference'] != true)
        .map((v) => v['name'] as String)
        .toList();
    final types = <String, String>{
      for (final v in vehicles)
        v['name'] as String: v['description'] as String? ?? '',
    };

    final config = VehicleConfig(
      all: all,
      allExclConf: allExclConf,
      types: types,
      label: vehicleLabel,
      labelPlural: vehicleLabelPlural,
      icon: icon,
    );

    _cachedConfig = config;
    _cachedCompanyId = companyId;
    return config;
  } catch (e) {
    // DB error (table doesn't exist yet etc.) — use hardcoded fallback
    final name = activeCompanyNotifier.value?.name ?? '';
    return name == 'Moss Turbusser' ? _mossTruckVehicles : _cssVehicles;
  }
}

/// Clear cached config (call when vehicles are edited in settings).
void clearVehicleConfigCache() {
  _cachedConfig = null;
  _cachedCompanyId = null;
}
