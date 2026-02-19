import 'ferry_definition.dart';

class AppSettings {
  final double dayPrice;
  final double extraKmPrice;

  final double trailerDayPrice;
  final double trailerKmPrice;

  final double dDriveDayPrice;
  final double flightTicketPrice;

  final double includedKmPerDay;
  final double dDriveKmThreshold;

  /// ✅ NEW: Dropbox root folder path
  final String dropboxRootPath;

  /// ✅ NEW: Ferry definitions (used by TripCalculator)
  final List<FerryDefinition> ferries;

  /// Bank account number for invoices (e.g. "9710.05.12345")
  final String bankAccount;

  const AppSettings({
    required this.dayPrice,
    required this.extraKmPrice,
    required this.trailerDayPrice,
    required this.trailerKmPrice,
    required this.dDriveDayPrice,
    required this.flightTicketPrice,

    this.includedKmPerDay = 300,
    this.dDriveKmThreshold = 600,
    this.dropboxRootPath = '',
    this.bankAccount = '',

    /// ✅ NEW
    this.ferries = const [],
  });

  AppSettings copyWith({
    double? dayPrice,
    double? extraKmPrice,
    double? trailerDayPrice,
    double? trailerKmPrice,
    double? dDriveDayPrice,
    double? flightTicketPrice,
    double? includedKmPerDay,
    double? dDriveKmThreshold,
    String? dropboxRootPath,
    String? bankAccount,

    /// ✅ NEW
    List<FerryDefinition>? ferries,
  }) {
    return AppSettings(
      dayPrice: dayPrice ?? this.dayPrice,
      extraKmPrice: extraKmPrice ?? this.extraKmPrice,
      trailerDayPrice: trailerDayPrice ?? this.trailerDayPrice,
      trailerKmPrice: trailerKmPrice ?? this.trailerKmPrice,
      dDriveDayPrice: dDriveDayPrice ?? this.dDriveDayPrice,
      flightTicketPrice: flightTicketPrice ?? this.flightTicketPrice,
      includedKmPerDay: includedKmPerDay ?? this.includedKmPerDay,
      dDriveKmThreshold: dDriveKmThreshold ?? this.dDriveKmThreshold,
      dropboxRootPath: dropboxRootPath ?? this.dropboxRootPath,
      bankAccount: bankAccount ?? this.bankAccount,

      /// ✅ NEW
      ferries: ferries ?? this.ferries,
    );
  }
}