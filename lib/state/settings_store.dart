import 'package:shared_preferences/shared_preferences.dart';

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

    // ✅ NY – MÅ VÆRE MED
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
      dayPrice:
          prefs.getDouble(_kDayPrice) ?? current.dayPrice,
      extraKmPrice:
          prefs.getDouble(_kExtraKmPrice) ?? current.extraKmPrice,
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

      // 🚫 ferries lastes IKKE her
      // → behold eksisterende i memory
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

    // 🚫 ferries lagres IKKE i prefs
  }

  // ===================================================
  // ✅ SET FERRIES (FROM DB)
  // ===================================================

  static void setFerries(List<FerryDefinition> ferries) {
    current = current.copyWith(ferries: ferries);
  }

  // ===================================================
  // OPTIONAL FULL REPLACE
  // ===================================================

  static void set(AppSettings settings) {
    current = settings;
  }
}