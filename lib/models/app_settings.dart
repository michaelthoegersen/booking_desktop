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
    );
  }
}