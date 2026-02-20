/// Swedish per-leg pricing model — all parameters editable in Settings.
/// Computed getters mirror the Excel "Background data" formulas exactly.
class SweSettings {
  // ===================================================
  // CHAUFFÖR  (driver)
  // ===================================================
  final double timlon;          // Timlön SEK/h
  final double timmarPerDag;    // Timmar/dag
  final double arbGAvg;         // ArbG-avgift, fraction e.g. 0.3142
  final double traktamente;     // Traktamente SEK/dag
  final double chaufforMarginal; // Marginal fraction e.g. 0.30

  // ===================================================
  // FORDON  (vehicle)
  // ===================================================
  final double kopPris;         // Köppris SEK
  final double avskrivningAr;   // Avskrivning år
  final double rantaPerAr;      // Ränta per år fraction e.g. 0.05
  final double forsakringPerAr; // Försäkring SEK/år
  final double skattPerAr;      // Skatt SEK/år
  final double parkeringPerAr;  // Parkering SEK/år
  final double kordagarPerAr;   // Kördagar per år
  final double fordonMarginal;  // Marginal fraction e.g. 0.20

  // ===================================================
  // MILPRIS  (variable km cost, per mil = 10 km)
  // ===================================================
  final double dieselprisPerLiter;         // SEK/l
  final double dieselforbrukningPerMil;    // l/mil (liters per 10 km)
  final double dackKostnadPerMil;          // Däck SEK/mil
  final double oljaKostnadPerMil;          // Olja SEK/mil
  final double verkstadKostnadPerMil;      // Verkstad SEK/mil
  final double ovrigtKostnadPerMil;        // Övrigt SEK/mil
  final double kmMarginal;                 // Marginal fraction e.g. 0.30

  // ===================================================
  // DD  (dubbel chaufför / double driver)
  // ===================================================
  final double ddTimlon;        // Timlön SEK/h
  final double ddTimmarPerDag;  // Timmar/dag
  final double ddArbGAvg;       // ArbG-avgift fraction
  final double ddTraktamente;   // Traktamente SEK
  final double ddResor;         // Resor SEK
  final double ddHotell;        // Hotell SEK
  final double ddMarginal;      // Marginal fraction e.g. 0.30
  final double ddKmGrans;       // Km-gräns: DD triggered when km > this

  // ===================================================
  // ÖVRIGT  (other)
  // ===================================================
  final double trailerhyraPerDygn;  // Trailerhyra SEK/dag
  final double utlandstraktamente;  // Utlandstraktamente SEK/enhet

  const SweSettings({
    this.timlon = 250,
    this.timmarPerDag = 9,
    this.arbGAvg = 0.3142,
    this.traktamente = 490,
    this.chaufforMarginal = 0.30,

    this.kopPris = 5000000,
    this.avskrivningAr = 12,
    this.rantaPerAr = 0.05,
    this.forsakringPerAr = 75000,
    this.skattPerAr = 25000,
    this.parkeringPerAr = 12000,
    this.kordagarPerAr = 200,
    this.fordonMarginal = 0.20,

    this.dieselprisPerLiter = 20,
    this.dieselforbrukningPerMil = 3.3,
    this.dackKostnadPerMil = 10,
    this.oljaKostnadPerMil = 5,
    this.verkstadKostnadPerMil = 15,
    this.ovrigtKostnadPerMil = 5,
    this.kmMarginal = 0.30,

    this.ddTimlon = 250,
    this.ddTimmarPerDag = 9,
    this.ddArbGAvg = 0.3142,
    this.ddTraktamente = 490,
    this.ddResor = 500,
    this.ddHotell = 500,
    this.ddMarginal = 0.30,
    this.ddKmGrans = 625,

    this.trailerhyraPerDygn = 1000,
    this.utlandstraktamente = 300,
  });

  // ===================================================
  // COMPUTED PRICES  (mirrors Excel "Background data")
  // ===================================================

  /// Chauffeur cost per day (SEK), including employer tax and margin.
  double get chaufforDagpris {
    final lonKostnad = timlon * timmarPerDag * (1 + arbGAvg);
    final totalKostnad = lonKostnad + traktamente;
    return totalKostnad / (1 - chaufforMarginal);
  }

  /// Vehicle cost per day (SEK), including fixed annual costs and margin.
  /// Rounded UP to nearest 100 SEK (matches Excel).
  double get fordonDagpris {
    final avskrivning = kopPris / avskrivningAr;
    final ranta = kopPris * rantaPerAr;
    final fixKostnader =
        avskrivning + ranta + forsakringPerAr + skattPerAr + parkeringPerAr;
    final perDag = fixKostnader / kordagarPerAr;
    final raw = perDag / (1 - fordonMarginal);
    return (raw / 100).ceil() * 100.0;
  }

  /// Variable km price per mil (10 km) (SEK), including margin.
  /// Rounded UP to nearest 1 SEK (matches Excel).
  double get milpris {
    final bransle = dieselprisPerLiter * dieselforbrukningPerMil;
    final ovrigt = dackKostnadPerMil +
        oljaKostnadPerMil +
        verkstadKostnadPerMil +
        ovrigtKostnadPerMil;
    final raw = (bransle + ovrigt) / (1 - kmMarginal);
    return raw.ceilToDouble();
  }

  /// Variable km price per km (SEK).
  double get kmPrisPerKm => milpris / 10;

  /// Double-driver cost per day (SEK), including all costs and margin.
  double get ddDagpris {
    final lonKostnad = ddTimlon * ddTimmarPerDag * (1 + ddArbGAvg);
    final totalKostnad = lonKostnad + ddTraktamente + ddResor + ddHotell;
    return totalKostnad / (1 - ddMarginal);
  }

  // ===================================================
  // COPY WITH
  // ===================================================

  SweSettings copyWith({
    double? timlon,
    double? timmarPerDag,
    double? arbGAvg,
    double? traktamente,
    double? chaufforMarginal,
    double? kopPris,
    double? avskrivningAr,
    double? rantaPerAr,
    double? forsakringPerAr,
    double? skattPerAr,
    double? parkeringPerAr,
    double? kordagarPerAr,
    double? fordonMarginal,
    double? dieselprisPerLiter,
    double? dieselforbrukningPerMil,
    double? dackKostnadPerMil,
    double? oljaKostnadPerMil,
    double? verkstadKostnadPerMil,
    double? ovrigtKostnadPerMil,
    double? kmMarginal,
    double? ddTimlon,
    double? ddTimmarPerDag,
    double? ddArbGAvg,
    double? ddTraktamente,
    double? ddResor,
    double? ddHotell,
    double? ddMarginal,
    double? ddKmGrans,
    double? trailerhyraPerDygn,
    double? utlandstraktamente,
  }) {
    return SweSettings(
      timlon: timlon ?? this.timlon,
      timmarPerDag: timmarPerDag ?? this.timmarPerDag,
      arbGAvg: arbGAvg ?? this.arbGAvg,
      traktamente: traktamente ?? this.traktamente,
      chaufforMarginal: chaufforMarginal ?? this.chaufforMarginal,
      kopPris: kopPris ?? this.kopPris,
      avskrivningAr: avskrivningAr ?? this.avskrivningAr,
      rantaPerAr: rantaPerAr ?? this.rantaPerAr,
      forsakringPerAr: forsakringPerAr ?? this.forsakringPerAr,
      skattPerAr: skattPerAr ?? this.skattPerAr,
      parkeringPerAr: parkeringPerAr ?? this.parkeringPerAr,
      kordagarPerAr: kordagarPerAr ?? this.kordagarPerAr,
      fordonMarginal: fordonMarginal ?? this.fordonMarginal,
      dieselprisPerLiter: dieselprisPerLiter ?? this.dieselprisPerLiter,
      dieselforbrukningPerMil:
          dieselforbrukningPerMil ?? this.dieselforbrukningPerMil,
      dackKostnadPerMil: dackKostnadPerMil ?? this.dackKostnadPerMil,
      oljaKostnadPerMil: oljaKostnadPerMil ?? this.oljaKostnadPerMil,
      verkstadKostnadPerMil:
          verkstadKostnadPerMil ?? this.verkstadKostnadPerMil,
      ovrigtKostnadPerMil: ovrigtKostnadPerMil ?? this.ovrigtKostnadPerMil,
      kmMarginal: kmMarginal ?? this.kmMarginal,
      ddTimlon: ddTimlon ?? this.ddTimlon,
      ddTimmarPerDag: ddTimmarPerDag ?? this.ddTimmarPerDag,
      ddArbGAvg: ddArbGAvg ?? this.ddArbGAvg,
      ddTraktamente: ddTraktamente ?? this.ddTraktamente,
      ddResor: ddResor ?? this.ddResor,
      ddHotell: ddHotell ?? this.ddHotell,
      ddMarginal: ddMarginal ?? this.ddMarginal,
      ddKmGrans: ddKmGrans ?? this.ddKmGrans,
      trailerhyraPerDygn: trailerhyraPerDygn ?? this.trailerhyraPerDygn,
      utlandstraktamente: utlandstraktamente ?? this.utlandstraktamente,
    );
  }
}
