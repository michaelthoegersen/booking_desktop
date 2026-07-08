const dashboardStrings = <String, Map<String, String>>{
  // --- Section headers ---
  'busLocationsToday': {
    'en': 'Bus locations today', 'no': 'Bussposisjoner i dag', 'sv': 'Busspositioner idag', 'de': 'Busstandorte heute', 'da': 'Buspositioner i dag',
  },
  'recentOffers': {
    'en': 'Recent offers', 'no': 'Nylige tilbud', 'sv': 'Senaste erbjudanden', 'de': 'Aktuelle Angebote', 'da': 'Seneste tilbud',
  },
  'offerStatus': {
    'en': 'Offer status', 'no': 'Tilbudsstatus', 'sv': 'Erbjudandestatus', 'de': 'Angebotsstatus', 'da': 'Tilbudsstatus',
  },
  'searchOffers': {
    'en': 'Search offers…', 'no': 'Søk i tilbud…', 'sv': 'Sök erbjudanden…', 'de': 'Angebote suchen…', 'da': 'Søg i tilbud…',
  },
  'noOffersYet': {
    'en': 'No offers yet.', 'no': 'Ingen tilbud ennå.', 'sv': 'Inga erbjudanden ännu.', 'de': 'Noch keine Angebote.', 'da': 'Ingen tilbud endnu.',
  },
  'awaitingApproval': {
    'en': 'Awaiting your approval', 'no': 'Venter på din godkjenning', 'sv': 'Väntar på ditt godkännande', 'de': 'Wartet auf Ihre Genehmigung', 'da': 'Afventer din godkendelse',
  },

  // --- Dialogs ---
  'deleteDraft': {
    'en': 'Delete draft', 'no': 'Slett utkast', 'sv': 'Radera utkast', 'de': 'Entwurf löschen', 'da': 'Slet udkast',
  },
  'keepInCalendar': {
    'en': 'Keep in calendar', 'no': 'Behold i kalender', 'sv': 'Behåll i kalender', 'de': 'Im Kalender behalten', 'da': 'Behold i kalender',
  },
  'removeFromCalendar': {
    'en': 'Remove from calendar', 'no': 'Fjern fra kalender', 'sv': 'Ta bort från kalender', 'de': 'Aus Kalender entfernen', 'da': 'Fjern fra kalender',
  },
  'removeFromCalendarQuestion': {
    'en': 'Do you also want to remove this draft from the calendar?',
    'no': 'Vil du også fjerne dette utkastet fra kalenderen?',
    'sv': 'Vill du också ta bort detta utkast från kalendern?',
    'de': 'Möchten Sie diesen Entwurf auch aus dem Kalender entfernen?',
    'da': 'Vil du også fjerne dette udkast fra kalenderen?',
  },
  'changeCreator': {
    'en': 'Change creator', 'no': 'Endre opprettet av', 'sv': 'Ändra skapare', 'de': 'Ersteller ändern', 'da': 'Skift opretter',
  },
  'pdfVersions': {
    'en': 'PDF Versions', 'no': 'PDF-versjoner', 'sv': 'PDF-versioner', 'de': 'PDF-Versionen', 'da': 'PDF-versioner',
  },
  'deletePdfVersion': {
    'en': 'Delete PDF version?', 'no': 'Slette PDF-versjon?', 'sv': 'Radera PDF-version?', 'de': 'PDF-Version löschen?', 'da': 'Slet PDF-version?',
  },
  'noPdfsYet': {
    'en': 'No PDFs have been generated yet.', 'no': 'Ingen PDF-er er generert ennå.', 'sv': 'Inga PDF-filer har genererats ännu.', 'de': 'Es wurden noch keine PDFs erstellt.', 'da': 'Ingen PDF-filer er genereret endnu.',
  },
  'pdfPreview': {
    'en': 'PDF Preview', 'no': 'PDF-forhåndsvisning', 'sv': 'PDF-förhandsgranskning', 'de': 'PDF-Vorschau', 'da': 'PDF-forhåndsvisning',
  },
  'refresh': {
    'en': 'Refresh', 'no': 'Oppdater', 'sv': 'Uppdatera', 'de': 'Aktualisieren', 'da': 'Opdater',
  },
  'retry': {
    'en': 'Retry', 'no': 'Prøv igjen', 'sv': 'Försök igen', 'de': 'Erneut versuchen', 'da': 'Prøv igen',
  },

  // --- Tooltips ---
  'tooltipPdfVersions': {
    'en': 'PDF versions', 'no': 'PDF-versjoner', 'sv': 'PDF-versioner', 'de': 'PDF-Versionen', 'da': 'PDF-versioner',
  },
  'tooltipArchive': {
    'en': 'Archive', 'no': 'Arkiver', 'sv': 'Arkivera', 'de': 'Archivieren', 'da': 'Arkiver',
  },
  'originalOffer': {
    'en': 'Original offer', 'no': 'Originalt tilbud', 'sv': 'Ursprungligt erbjudande', 'de': 'Originalangebot', 'da': 'Originalt tilbud',
  },
  'signedVersion': {
    'en': 'Signed version', 'no': 'Signert versjon', 'sv': 'Signerad version', 'de': 'Signierte Version', 'da': 'Signeret version',
  },

  // --- PDF version labels ---
  'savedOffer': {
    'en': 'Saved offer', 'no': 'Lagret tilbud', 'sv': 'Sparat erbjudande', 'de': 'Gespeichertes Angebot', 'da': 'Gemt tilbud',
  },
  'latestSavedVersion': {
    'en': 'Latest saved version', 'no': 'Siste lagrede versjon', 'sv': 'Senaste sparade version', 'de': 'Letzte gespeicherte Version', 'da': 'Seneste gemte version',
  },
  'signedByBothParties': {
    'en': 'Signed by both parties', 'no': 'Signert av begge parter', 'sv': 'Signerad av båda parter', 'de': 'Von beiden Parteien unterzeichnet', 'da': 'Signeret af begge parter',
  },

  // --- Snackbar ---
  'draftDeleted': {
    'en': 'Draft deleted', 'no': 'Utkast slettet', 'sv': 'Utkast raderat', 'de': 'Entwurf gelöscht', 'da': 'Udkast slettet',
  },

  // --- Metadata ---
  'created': {
    'en': 'Created', 'no': 'Opprettet', 'sv': 'Skapad', 'de': 'Erstellt', 'da': 'Oprettet',
  },
  'updated': {
    'en': 'Updated', 'no': 'Oppdatert', 'sv': 'Uppdaterad', 'de': 'Aktualisiert', 'da': 'Opdateret',
  },
  'lastUpdate': {
    'en': 'Last update', 'no': 'Sist oppdatert', 'sv': 'Senast uppdaterad', 'de': 'Letzte Aktualisierung', 'da': 'Sidst opdateret',
  },
};
