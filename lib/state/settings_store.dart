import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_settings.dart';
import '../models/ferry_definition.dart';
import '../models/swe_settings.dart';

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
    bankAccount: '',
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
  static const _kBankAccount = "bankAccount";
  static const _kGraphTenantId = "graphTenantId";
  static const _kGraphClientId = "graphClientId";
  static const _kGraphClientSecret = "graphClientSecret";
  static const _kGraphSenderEmail = "graphSenderEmail";

  // --- Swedish pricing model ---
  static const _kSweTimlon = "swe_timlon";
  static const _kSweTimmarPerDag = "swe_timmarPerDag";
  static const _kSweArbGAvg = "swe_arbGAvg";
  static const _kSweTraktamente = "swe_traktamente";
  static const _kSweChaufforMarginal = "swe_chaufforMarginal";

  static const _kSweKopPris = "swe_kopPris";
  static const _kSweAvskrivningAr = "swe_avskrivningAr";
  static const _kSweRantaPerAr = "swe_rantaPerAr";
  static const _kSweForsakringPerAr = "swe_forsakringPerAr";
  static const _kSweSkattPerAr = "swe_skattPerAr";
  static const _kSweParkeringPerAr = "swe_parkeringPerAr";
  static const _kSweKordagarPerAr = "swe_kordagarPerAr";
  static const _kSweFordonMarginal = "swe_fordonMarginal";

  static const _kSweDieselprisPerLiter = "swe_dieselprisPerLiter";
  static const _kSweDieselforbrukningPerMil = "swe_dieselforbrukningPerMil";
  static const _kSweDackKostnadPerMil = "swe_dackKostnadPerMil";
  static const _kSweOljaKostnadPerMil = "swe_oljaKostnadPerMil";
  static const _kSweVerkstadKostnadPerMil = "swe_verkstadKostnadPerMil";
  static const _kSweOvrigtKostnadPerMil = "swe_ovrigtKostnadPerMil";
  static const _kSweKmMarginal = "swe_kmMarginal";

  static const _kSweDdTimlon = "swe_ddTimlon";
  static const _kSweDdTimmarPerDag = "swe_ddTimmarPerDag";
  static const _kSweDdArbGAvg = "swe_ddArbGAvg";
  static const _kSweDdTraktamente = "swe_ddTraktamente";
  static const _kSweDdResor = "swe_ddResor";
  static const _kSweDdHotell = "swe_ddHotell";
  static const _kSweDdMarginal = "swe_ddMarginal";
  static const _kSweDdKmGrans = "swe_ddKmGrans";

  static const _kSweTrailerhyraPerDygn = "swe_trailerhyraPerDygn";
  static const _kSweUtlandstraktamente = "swe_utlandstraktamente";

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
      bankAccount:
          prefs.getString(_kBankAccount) ?? current.bankAccount,
      graphTenantId:
          prefs.getString(_kGraphTenantId) ?? current.graphTenantId,
      graphClientId:
          prefs.getString(_kGraphClientId) ?? current.graphClientId,
      graphClientSecret:
          prefs.getString(_kGraphClientSecret) ?? current.graphClientSecret,
      graphSenderEmail:
          prefs.getString(_kGraphSenderEmail) ?? current.graphSenderEmail,
      ferries: current.ferries,
      sweSettings: current.sweSettings.copyWith(
        timlon: prefs.getDouble(_kSweTimlon),
        timmarPerDag: prefs.getDouble(_kSweTimmarPerDag),
        arbGAvg: prefs.getDouble(_kSweArbGAvg),
        traktamente: prefs.getDouble(_kSweTraktamente),
        chaufforMarginal: prefs.getDouble(_kSweChaufforMarginal),
        kopPris: prefs.getDouble(_kSweKopPris),
        avskrivningAr: prefs.getDouble(_kSweAvskrivningAr),
        rantaPerAr: prefs.getDouble(_kSweRantaPerAr),
        forsakringPerAr: prefs.getDouble(_kSweForsakringPerAr),
        skattPerAr: prefs.getDouble(_kSweSkattPerAr),
        parkeringPerAr: prefs.getDouble(_kSweParkeringPerAr),
        kordagarPerAr: prefs.getDouble(_kSweKordagarPerAr),
        fordonMarginal: prefs.getDouble(_kSweFordonMarginal),
        dieselprisPerLiter: prefs.getDouble(_kSweDieselprisPerLiter),
        dieselforbrukningPerMil: prefs.getDouble(_kSweDieselforbrukningPerMil),
        dackKostnadPerMil: prefs.getDouble(_kSweDackKostnadPerMil),
        oljaKostnadPerMil: prefs.getDouble(_kSweOljaKostnadPerMil),
        verkstadKostnadPerMil: prefs.getDouble(_kSweVerkstadKostnadPerMil),
        ovrigtKostnadPerMil: prefs.getDouble(_kSweOvrigtKostnadPerMil),
        kmMarginal: prefs.getDouble(_kSweKmMarginal),
        ddTimlon: prefs.getDouble(_kSweDdTimlon),
        ddTimmarPerDag: prefs.getDouble(_kSweDdTimmarPerDag),
        ddArbGAvg: prefs.getDouble(_kSweDdArbGAvg),
        ddTraktamente: prefs.getDouble(_kSweDdTraktamente),
        ddResor: prefs.getDouble(_kSweDdResor),
        ddHotell: prefs.getDouble(_kSweDdHotell),
        ddMarginal: prefs.getDouble(_kSweDdMarginal),
        ddKmGrans: prefs.getDouble(_kSweDdKmGrans),
        trailerhyraPerDygn: prefs.getDouble(_kSweTrailerhyraPerDygn),
        utlandstraktamente: prefs.getDouble(_kSweUtlandstraktamente),
      ),
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
    await prefs.setString(_kBankAccount, current.bankAccount);
    await prefs.setString(_kGraphTenantId, current.graphTenantId);
    await prefs.setString(_kGraphClientId, current.graphClientId);
    await prefs.setString(_kGraphClientSecret, current.graphClientSecret);
    await prefs.setString(_kGraphSenderEmail, current.graphSenderEmail);

    final swe = current.sweSettings;
    await prefs.setDouble(_kSweTimlon, swe.timlon);
    await prefs.setDouble(_kSweTimmarPerDag, swe.timmarPerDag);
    await prefs.setDouble(_kSweArbGAvg, swe.arbGAvg);
    await prefs.setDouble(_kSweTraktamente, swe.traktamente);
    await prefs.setDouble(_kSweChaufforMarginal, swe.chaufforMarginal);
    await prefs.setDouble(_kSweKopPris, swe.kopPris);
    await prefs.setDouble(_kSweAvskrivningAr, swe.avskrivningAr);
    await prefs.setDouble(_kSweRantaPerAr, swe.rantaPerAr);
    await prefs.setDouble(_kSweForsakringPerAr, swe.forsakringPerAr);
    await prefs.setDouble(_kSweSkattPerAr, swe.skattPerAr);
    await prefs.setDouble(_kSweParkeringPerAr, swe.parkeringPerAr);
    await prefs.setDouble(_kSweKordagarPerAr, swe.kordagarPerAr);
    await prefs.setDouble(_kSweFordonMarginal, swe.fordonMarginal);
    await prefs.setDouble(_kSweDieselprisPerLiter, swe.dieselprisPerLiter);
    await prefs.setDouble(_kSweDieselforbrukningPerMil, swe.dieselforbrukningPerMil);
    await prefs.setDouble(_kSweDackKostnadPerMil, swe.dackKostnadPerMil);
    await prefs.setDouble(_kSweOljaKostnadPerMil, swe.oljaKostnadPerMil);
    await prefs.setDouble(_kSweVerkstadKostnadPerMil, swe.verkstadKostnadPerMil);
    await prefs.setDouble(_kSweOvrigtKostnadPerMil, swe.ovrigtKostnadPerMil);
    await prefs.setDouble(_kSweKmMarginal, swe.kmMarginal);
    await prefs.setDouble(_kSweDdTimlon, swe.ddTimlon);
    await prefs.setDouble(_kSweDdTimmarPerDag, swe.ddTimmarPerDag);
    await prefs.setDouble(_kSweDdArbGAvg, swe.ddArbGAvg);
    await prefs.setDouble(_kSweDdTraktamente, swe.ddTraktamente);
    await prefs.setDouble(_kSweDdResor, swe.ddResor);
    await prefs.setDouble(_kSweDdHotell, swe.ddHotell);
    await prefs.setDouble(_kSweDdMarginal, swe.ddMarginal);
    await prefs.setDouble(_kSweDdKmGrans, swe.ddKmGrans);
    await prefs.setDouble(_kSweTrailerhyraPerDygn, swe.trailerhyraPerDygn);
    await prefs.setDouble(_kSweUtlandstraktamente, swe.utlandstraktamente);
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