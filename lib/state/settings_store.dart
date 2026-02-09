import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_settings.dart';
import '../models/ferry_definition.dart';

class SettingsStore {

  // ===================================================
  // CURRENT SETTINGS (IN MEMORY)
  // ===================================================

  static AppSettings current = const AppSettings(
    dayPrice: 14000,
    extraKmPrice: 20,
    trailerDayPrice: 800,
    trailerKmPrice: 2,
    includedKmPerDay: 300,
    dDriveDayPrice: 3500,
    flightTicketPrice: 2500,
    dDriveKmThreshold: 600,
    dropboxRootPath: '',
    ferries: [],
  );

  // ===================================================
  // PREF KEYS
  // ===================================================

  static const _kDayPrice = "dayPrice";
  static const _kExtraKmPrice = "extraKmPrice";
  static const _kTrailerDayPrice = "trailerDayPrice";
  static const _kTrailerKmPrice = "trailerKmPrice";
  static const _kIncludedKmPerDay = "includedKmPerDay";
  static const _kDDriveDayPrice = "dDriveDayPrice";
  static const _kFlightTicketPrice = "flightTicketPrice";
  static const _kDDriveKmThreshold = "dDriveKmThreshold";
  static const _kDropboxRootPath = "dropboxRootPath";

  // ===================================================
  // LOAD FROM SHARED PREFS
  // ===================================================

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    current = current.copyWith(
      dayPrice: prefs.getDouble(_kDayPrice) ?? current.dayPrice,
      extraKmPrice: prefs.getDouble(_kExtraKmPrice) ?? current.extraKmPrice,
      trailerDayPrice:
          prefs.getDouble(_kTrailerDayPrice) ?? current.trailerDayPrice,
      trailerKmPrice:
          prefs.getDouble(_kTrailerKmPrice) ?? current.trailerKmPrice,
      includedKmPerDay:
          prefs.getDouble(_kIncludedKmPerDay) ?? current.includedKmPerDay,
      dDriveDayPrice:
          prefs.getDouble(_kDDriveDayPrice) ?? current.dDriveDayPrice,
      flightTicketPrice:
          prefs.getDouble(_kFlightTicketPrice) ?? current.flightTicketPrice,
      dDriveKmThreshold:
          prefs.getDouble(_kDDriveKmThreshold) ?? current.dDriveKmThreshold,
      dropboxRootPath:
          prefs.getString(_kDropboxRootPath) ?? current.dropboxRootPath,
      ferries: current.ferries,
    );
  }

  // ===================================================
  // SAVE TO SHARED PREFS
  // ===================================================

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(_kDayPrice, current.dayPrice);
    await prefs.setDouble(_kExtraKmPrice, current.extraKmPrice);
    await prefs.setDouble(_kTrailerDayPrice, current.trailerDayPrice);
    await prefs.setDouble(_kTrailerKmPrice, current.trailerKmPrice);
    await prefs.setDouble(_kIncludedKmPerDay, current.includedKmPerDay);
    await prefs.setDouble(_kDDriveDayPrice, current.dDriveDayPrice);
    await prefs.setDouble(_kFlightTicketPrice, current.flightTicketPrice);
    await prefs.setDouble(_kDDriveKmThreshold, current.dDriveKmThreshold);
    await prefs.setString(_kDropboxRootPath, current.dropboxRootPath);
  }

  // ===================================================
  // ✅ LOAD FERRIES FROM SUPABASE (Riktig felt!)
  // ===================================================

  static Future<void> loadFerries() async {
    final res = await Supabase.instance.client
        .from('ferries')
        .select()
        .order('name');

    final List<FerryDefinition> ferries =
        (res as List).map((row) {
      return FerryDefinition(
        name: row['name'] as String,

        // ✅ KORREKT: base_price
        price: row['base_price'] == null
            ? 0.0
            : (row['base_price'] as num).toDouble(),

        trailerPrice: row['trailer_price'] == null
            ? null
            : (row['trailer_price'] as num).toDouble(),
      );
    }).toList();

    current = current.copyWith(ferries: ferries);

    // Debug
    print(
      "⛴️ Ferries loaded (${ferries.length}): "
      "${ferries.map((f) => '${f.name}=${f.price}').join(', ')}",
    );
  }

  // ===================================================
  // OPTIONAL SETTERS
  // ===================================================

  static void setFerries(List<FerryDefinition> ferries) {
    current = current.copyWith(ferries: ferries);
  }

  static void set(AppSettings settings) {
    current = settings;
  }
}