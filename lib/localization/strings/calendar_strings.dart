const calendarStrings = <String, Map<String, String>>{
  // --- Header ---
  'block': {'en': 'Block', 'no': 'Blokk', 'sv': 'Block', 'de': 'Block', 'da': 'Blok'},
  'export': {'en': 'Export', 'no': 'Eksporter', 'sv': 'Exportera', 'de': 'Exportieren', 'da': 'Eksporter'},
  'week': {'en': 'Week', 'no': 'Uke', 'sv': 'Vecka', 'de': 'Woche', 'da': 'Uge'},
  'monthView': {'en': 'Month', 'no': 'Måned', 'sv': 'Månad', 'de': 'Monat', 'da': 'Måned'},

  // --- Waiting list ---
  'waitingList': {'en': 'Waiting List', 'no': 'Venteliste', 'sv': 'Väntelista', 'de': 'Warteliste', 'da': 'Venteliste'},
  'noJobsInWaitingList': {'en': 'No jobs in waiting list', 'no': 'Ingen jobber på ventelisten', 'sv': 'Inga jobb i väntelistan', 'de': 'Keine Aufträge auf der Warteliste', 'da': 'Ingen jobs på ventelisten'},
  'refreshWaitingList': {'en': 'Refresh waiting list', 'no': 'Oppdater ventelisten', 'sv': 'Uppdatera väntelistan', 'de': 'Warteliste aktualisieren', 'da': 'Opdater ventelisten'},
  'addToWaitingList': {'en': 'Add to waiting list', 'no': 'Legg til ventelisten', 'sv': 'Lägg till i väntelistan', 'de': 'Zur Warteliste hinzufügen', 'da': 'Tilføj til ventelisten'},
  'removeFromWaitingList': {'en': 'Remove from waiting list', 'no': 'Fjern fra ventelisten', 'sv': 'Ta bort från väntelistan', 'de': 'Von Warteliste entfernen', 'da': 'Fjern fra ventelisten'},
  'assignToBus': {'en': 'Assign to bus', 'no': 'Tildel til buss', 'sv': 'Tilldela till buss', 'de': 'Bus zuweisen', 'da': 'Tildel til bus'},
  'sendInfo': {'en': 'Send info', 'no': 'Send info', 'sv': 'Skicka info', 'de': 'Info senden', 'da': 'Send info'},
  'assign': {'en': 'Assign', 'no': 'Tildel', 'sv': 'Tilldela', 'de': 'Zuweisen', 'da': 'Tildel'},

  // --- Statuses ---
  'draft': {'en': 'Draft', 'no': 'Utkast', 'sv': 'Utkast', 'de': 'Entwurf', 'da': 'Udkast'},
  'inquiry': {'en': 'Inquiry', 'no': 'Forespørsel', 'sv': 'Förfrågan', 'de': 'Anfrage', 'da': 'Forespørgsel'},
  'confirmed': {'en': 'Confirmed', 'no': 'Bekreftet', 'sv': 'Bekräftad', 'de': 'Bestätigt', 'da': 'Bekræftet'},
  'invoiced': {'en': 'Invoiced', 'no': 'Fakturert', 'sv': 'Fakturerad', 'de': 'In Rechnung gestellt', 'da': 'Faktureret'},

  // --- Edit venue ---
  'editVenue': {'en': 'Edit venue', 'no': 'Rediger sted', 'sv': 'Redigera plats', 'de': 'Veranstaltungsort bearbeiten', 'da': 'Rediger sted'},
  'venue': {'en': 'Venue', 'no': 'Sted', 'sv': 'Plats', 'de': 'Veranstaltungsort', 'da': 'Sted'},
  'address': {'en': 'Address', 'no': 'Adresse', 'sv': 'Adress', 'de': 'Adresse', 'da': 'Adresse'},
  'comment': {'en': 'Comment', 'no': 'Kommentar', 'sv': 'Kommentar', 'de': 'Kommentar', 'da': 'Kommentar'},

  // --- Edit calendar dialog ---
  'sumKr': {'en': 'Sum (kr)', 'no': 'Sum (kr)', 'sv': 'Summa (kr)', 'de': 'Summe (kr)', 'da': 'Sum (kr)'},
  'noDriverAllocated': {'en': 'No driver allocated', 'no': 'Ingen sjåfør tildelt', 'sv': 'Ingen förare tilldelad', 'de': 'Kein Fahrer zugewiesen', 'da': 'Ingen chauffør tildelt'},
  'contactPerson': {'en': 'Contact person', 'no': 'Kontaktperson', 'sv': 'Kontaktperson', 'de': 'Kontaktperson', 'da': 'Kontaktperson'},
  'itinerary': {'en': 'Itinerary', 'no': 'Reiserute', 'sv': 'Resplan', 'de': 'Reiseroute', 'da': 'Rejseplan'},
  'attachments': {'en': 'Attachments', 'no': 'Vedlegg', 'sv': 'Bilagor', 'de': 'Anhänge', 'da': 'Vedhæftninger'},
  'deleteBlock': {'en': 'Delete block?', 'no': 'Slette blokk?', 'sv': 'Radera block?', 'de': 'Block löschen?', 'da': 'Slet blok?'},
  'deleteBlockDesc': {'en': 'This will permanently remove this manual block.', 'no': 'Dette vil permanent fjerne denne manuelle blokken.', 'sv': 'Detta raderar permanent detta manuella block.', 'de': 'Dies entfernt diesen manuellen Block dauerhaft.', 'da': 'Dette fjerner permanent denne manuelle blok.'},
  'sendPdf': {'en': 'Send PDF', 'no': 'Send PDF', 'sv': 'Skicka PDF', 'de': 'PDF senden', 'da': 'Send PDF'},
  'noCalendarData': {'en': 'No calendar data found.', 'no': 'Ingen kalenderdata funnet.', 'sv': 'Ingen kalenderdata hittades.', 'de': 'Keine Kalenderdaten gefunden.', 'da': 'Ingen kalenderdata fundet.'},
  'dDrive': {'en': 'D.Drive', 'no': 'D.Drive', 'sv': 'D.Drive', 'de': 'D.Drive', 'da': 'D.Drive'},
  'noDriver': {'en': 'No driver', 'no': 'Ingen sjåfør', 'sv': 'Ingen förare', 'de': 'Kein Fahrer', 'da': 'Ingen chauffør'},

  // --- Manual block dialog ---
  'addBlock': {'en': 'Add block', 'no': 'Legg til blokk', 'sv': 'Lägg till block', 'de': 'Block hinzufügen', 'da': 'Tilføj blok'},
  'editBlock': {'en': 'Edit block', 'no': 'Rediger blokk', 'sv': 'Redigera block', 'de': 'Block bearbeiten', 'da': 'Rediger blok'},
  'bus': {'en': 'Bus', 'no': 'Buss', 'sv': 'Buss', 'de': 'Bus', 'da': 'Bus'},
  'optionalShowsInEconomy': {'en': 'Optional — shows in Economy', 'no': 'Valgfritt — vises i Økonomi', 'sv': 'Valfritt — visas i Ekonomi', 'de': 'Optional — wird in Finanzen angezeigt', 'da': 'Valgfrit — vises i Økonomi'},
  'pickDate': {'en': 'Pick date', 'no': 'Velg dato', 'sv': 'Välj datum', 'de': 'Datum wählen', 'da': 'Vælg dato'},
  'dateFrom': {'en': 'Date from', 'no': 'Dato fra', 'sv': 'Datum från', 'de': 'Datum von', 'da': 'Dato fra'},
  'dateTo': {'en': 'Date to', 'no': 'Dato til', 'sv': 'Datum till', 'de': 'Datum bis', 'da': 'Dato til'},
  'notes': {'en': 'Notes', 'no': 'Notater', 'sv': 'Anteckningar', 'de': 'Notizen', 'da': 'Noter'},
  'add': {'en': 'Add', 'no': 'Legg til', 'sv': 'Lägg till', 'de': 'Hinzufügen', 'da': 'Tilføj'},

  // --- Status date picker ---
  'selectDates': {'en': 'Select dates', 'no': 'Velg datoer', 'sv': 'Välj datum', 'de': 'Datum wählen', 'da': 'Vælg datoer'},
  'apply': {'en': 'Apply', 'no': 'Bruk', 'sv': 'Tillämpa', 'de': 'Anwenden', 'da': 'Anvend'},

  // --- Send tour schedule ---
  'sendTourSchedule': {'en': 'Send tour schedule', 'no': 'Send turplan', 'sv': 'Skicka turschema', 'de': 'Tourplan senden', 'da': 'Send turplan'},
  'nameOrEmail': {'en': 'Name or email...', 'no': 'Navn eller e-post...', 'sv': 'Namn eller e-post...', 'de': 'Name oder E-Mail...', 'da': 'Navn eller e-mail...'},
  'subject': {'en': 'Subject', 'no': 'Emne', 'sv': 'Ämne', 'de': 'Betreff', 'da': 'Emne'},
  'messageOptional': {'en': 'Message (optional)', 'no': 'Melding (valgfritt)', 'sv': 'Meddelande (valfritt)', 'de': 'Nachricht (optional)', 'da': 'Besked (valgfrit)'},
  'tourScheduleSent': {'en': 'Tour schedule sent!', 'no': 'Turplan sendt!', 'sv': 'Turschema skickat!', 'de': 'Tourplan gesendet!', 'da': 'Turplan sendt!'},

  // --- Copy dialog ---
  'copyTo': {'en': 'Copy to', 'no': 'Kopier til', 'sv': 'Kopiera till', 'de': 'Kopieren nach', 'da': 'Kopier til'},
  'copyToBus': {'en': 'Copy to bus', 'no': 'Kopier til buss', 'sv': 'Kopiera till buss', 'de': 'Auf Bus kopieren', 'da': 'Kopier til bus'},

  // --- Export calendar ---
  'exportCalendar': {'en': 'Export Calendar', 'no': 'Eksporter kalender', 'sv': 'Exportera kalender', 'de': 'Kalender exportieren', 'da': 'Eksporter kalender'},
  'monthRange': {'en': 'Month range', 'no': 'Månedområde', 'sv': 'Månadsintervall', 'de': 'Monatsbereich', 'da': 'Månedinterval'},
  'buses': {'en': 'Buses', 'no': 'Busser', 'sv': 'Bussar', 'de': 'Busse', 'da': 'Busser'},
  'none': {'en': 'None', 'no': 'Ingen', 'sv': 'Inga', 'de': 'Keine', 'da': 'Ingen'},
  'next': {'en': 'Next', 'no': 'Neste', 'sv': 'Nästa', 'de': 'Weiter', 'da': 'Næste'},
  'sendCalendar': {'en': 'Send Calendar', 'no': 'Send kalender', 'sv': 'Skicka kalender', 'de': 'Kalender senden', 'da': 'Send kalender'},
  'sending': {'en': 'Sending...', 'no': 'Sender...', 'sv': 'Skickar...', 'de': 'Wird gesendet...', 'da': 'Sender...'},
  'send': {'en': 'Send', 'no': 'Send', 'sv': 'Skicka', 'de': 'Senden', 'da': 'Send'},

  // --- Snackbars ---
  'ferryBookingEmailSent': {'en': 'Ferry booking email sent ✅', 'no': 'Fergebooking-e-post sendt ✅', 'sv': 'Färjebokningsmail skickat ✅', 'de': 'Fährbuchungs-E-Mail gesendet ✅', 'da': 'Færgebooking-e-mail sendt ✅'},
  'couldNotPrepareTourSchedule': {'en': 'Could not prepare tour schedule', 'no': 'Kunne ikke forberede turplan', 'sv': 'Kunde inte förbereda turschema', 'de': 'Tourplan konnte nicht vorbereitet werden', 'da': 'Kunne ikke forberede turplan'},
  'couldNotPrepareSummary': {'en': 'Could not prepare summary', 'no': 'Kunne ikke forberede sammendrag', 'sv': 'Kunde inte förbereda sammanfattning', 'de': 'Zusammenfassung konnte nicht vorbereitet werden', 'da': 'Kunne ikke forberede sammendrag'},
};
