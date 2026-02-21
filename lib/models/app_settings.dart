import 'ferry_definition.dart';
import 'swe_settings.dart';

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

  /// Microsoft Graph API credentials for sending invoice emails
  final String graphTenantId;
  final String graphClientId;
  final String graphClientSecret;
  final String graphSenderEmail;

  /// Swedish per-leg pricing model parameters
  final SweSettings sweSettings;

  /// Toll rate per km (NOK/km). Default 2.8.
  final double tollKmRate;

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
    this.graphTenantId = '',
    this.graphClientId = '',
    this.graphClientSecret = '',
    this.graphSenderEmail = '',
    this.tollKmRate = 2.8,

    /// ✅ NEW
    this.ferries = const [],
    this.sweSettings = const SweSettings(),
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
    String? graphTenantId,
    String? graphClientId,
    String? graphClientSecret,
    String? graphSenderEmail,
    double? tollKmRate,

    /// ✅ NEW
    List<FerryDefinition>? ferries,
    SweSettings? sweSettings,
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
      graphTenantId: graphTenantId ?? this.graphTenantId,
      graphClientId: graphClientId ?? this.graphClientId,
      graphClientSecret: graphClientSecret ?? this.graphClientSecret,
      graphSenderEmail: graphSenderEmail ?? this.graphSenderEmail,
      tollKmRate: tollKmRate ?? this.tollKmRate,

      /// ✅ NEW
      ferries: ferries ?? this.ferries,
      sweSettings: sweSettings ?? this.sweSettings,
    );
  }
}