/// Strings for: customers, invoices, economy, issues, archive,
/// bus_requests, routes_admin, edit_offer pages.
const pagesStrings = <String, Map<String, String>>{

  // ===== SHARED / REUSED =====
  'all': {
    'en': 'All', 'no': 'Alle', 'sv': 'Alla', 'de': 'Alle', 'da': 'Alle',
  },
  'status': {
    'en': 'Status', 'no': 'Status', 'sv': 'Status', 'de': 'Status', 'da': 'Status',
  },
  'production': {
    'en': 'Production', 'no': 'Produksjon', 'sv': 'Produktion', 'de': 'Produktion', 'da': 'Produktion',
  },
  'date': {
    'en': 'Date', 'no': 'Dato', 'sv': 'Datum', 'de': 'Datum', 'da': 'Dato',
  },
  'total': {
    'en': 'Total', 'no': 'Total', 'sv': 'Totalt', 'de': 'Gesamt', 'da': 'Total',
  },
  'description': {
    'en': 'Description', 'no': 'Beskrivelse', 'sv': 'Beskrivning', 'de': 'Beschreibung', 'da': 'Beskrivelse',
  },
  'photo': {
    'en': 'Photo', 'no': 'Bilde', 'sv': 'Foto', 'de': 'Foto', 'da': 'Foto',
  },
  'saved': {
    'en': 'Saved', 'no': 'Lagret', 'sv': 'Sparat', 'de': 'Gespeichert', 'da': 'Gemt',
  },
  'loadError': {
    'en': 'Load error', 'no': 'Lastefeil', 'sv': 'Laddningsfel', 'de': 'Ladefehler', 'da': 'Indlæsningsfejl',
  },
  'deletePermanently': {
    'en': 'Delete permanently', 'no': 'Slett permanent', 'sv': 'Radera permanent', 'de': 'Dauerhaft löschen', 'da': 'Slet permanent',
  },
  'cannotBeUndone': {
    'en': 'This action cannot be undone.', 'no': 'Denne handlingen kan ikke angres.', 'sv': 'Denna åtgärd kan inte ångras.', 'de': 'Diese Aktion kann nicht rückgängig gemacht werden.', 'da': 'Denne handling kan ikke fortrydes.',
  },
  'deleteForever': {
    'en': 'Delete forever', 'no': 'Slett for alltid', 'sv': 'Radera för alltid', 'de': 'Endgültig löschen', 'da': 'Slet for altid',
  },
  'restore': {
    'en': 'Restore', 'no': 'Gjenopprett', 'sv': 'Återställ', 'de': 'Wiederherstellen', 'da': 'Gendan',
  },
  'active': {
    'en': 'Active', 'no': 'Aktiv', 'sv': 'Aktiv', 'de': 'Aktiv', 'da': 'Aktiv',
  },
  'archived': {
    'en': 'Archived', 'no': 'Arkivert', 'sv': 'Arkiverad', 'de': 'Archiviert', 'da': 'Arkiveret',
  },
  'received': {
    'en': 'Received', 'no': 'Mottatt', 'sv': 'Mottagen', 'de': 'Empfangen', 'da': 'Modtaget',
  },
  'from': {
    'en': 'From', 'no': 'Fra', 'sv': 'Från', 'de': 'Von', 'da': 'Fra',
  },
  'to': {
    'en': 'To', 'no': 'Til', 'sv': 'Till', 'de': 'Nach', 'da': 'Til',
  },
  'contact': {
    'en': 'Contact', 'no': 'Kontakt', 'sv': 'Kontakt', 'de': 'Kontakt', 'da': 'Kontakt',
  },
  'noData': {
    'en': 'No data', 'no': 'Ingen data', 'sv': 'Inga data', 'de': 'Keine Daten', 'da': 'Ingen data',
  },
  'updatedBy': {
    'en': 'Updated by', 'no': 'Oppdatert av', 'sv': 'Uppdaterad av', 'de': 'Aktualisiert von', 'da': 'Opdateret af',
  },
  'confirm': {
    'en': 'Confirm', 'no': 'Bekreft', 'sv': 'Bekräfta', 'de': 'Bestätigen', 'da': 'Bekræft',
  },
  'reject': {
    'en': 'Reject', 'no': 'Avslå', 'sv': 'Avslå', 'de': 'Ablehnen', 'da': 'Afvis',
  },
  'pending': {
    'en': 'Pending', 'no': 'Ventende', 'sv': 'Väntande', 'de': 'Ausstehend', 'da': 'Afventende',
  },
  'currency': {
    'en': 'Currency', 'no': 'Valuta', 'sv': 'Valuta', 'de': 'Währung', 'da': 'Valuta',
  },
  'ferry': {
    'en': 'Ferry', 'no': 'Ferge', 'sv': 'Färja', 'de': 'Fähre', 'da': 'Færge',
  },
  'bridge': {
    'en': 'Bridge', 'no': 'Bro', 'sv': 'Bro', 'de': 'Brücke', 'da': 'Bro',
  },
  'trailer': {
    'en': 'Trailer', 'no': 'Henger', 'sv': 'Släp', 'de': 'Anhänger', 'da': 'Trailer',
  },
  'passengers': {
    'en': 'passengers', 'no': 'passasjerer', 'sv': 'passagerare', 'de': 'Passagiere', 'da': 'passagerer',
  },

  // ===== CUSTOMERS =====
  'companies': {
    'en': 'Companies', 'no': 'Selskaper', 'sv': 'Företag', 'de': 'Unternehmen', 'da': 'Virksomheder',
  },
  'noContacts': {
    'en': 'No contacts', 'no': 'Ingen kontakter', 'sv': 'Inga kontakter', 'de': 'Keine Kontakte', 'da': 'Ingen kontakter',
  },
  'productions': {
    'en': 'Productions', 'no': 'Produksjoner', 'sv': 'Produktioner', 'de': 'Produktionen', 'da': 'Produktioner',
  },
  'noProductions': {
    'en': 'No productions', 'no': 'Ingen produksjoner', 'sv': 'Inga produktioner', 'de': 'Keine Produktionen', 'da': 'Ingen produktioner',
  },
  'deleteCompany': {
    'en': 'Delete company', 'no': 'Slett selskap', 'sv': 'Radera företag', 'de': 'Unternehmen löschen', 'da': 'Slet virksomhed',
  },
  'orgNr': {
    'en': 'Org.nr', 'no': 'Org.nr', 'sv': 'Org.nr', 'de': 'Org.Nr.', 'da': 'CVR-nr.',
  },
  'invoiceEmail': {
    'en': 'Invoice email', 'no': 'Faktura-e-post', 'sv': 'Faktura-e-post', 'de': 'Rechnungs-E-Mail', 'da': 'Faktura-e-mail',
  },
  'notSet': {
    'en': 'Not set', 'no': 'Ikke satt', 'sv': 'Ej angiven', 'de': 'Nicht gesetzt', 'da': 'Ikke angivet',
  },
  'editInvoiceEmail': {
    'en': 'Edit invoice email', 'no': 'Rediger faktura-e-post', 'sv': 'Redigera faktura-e-post', 'de': 'Rechnungs-E-Mail bearbeiten', 'da': 'Rediger faktura-e-mail',
  },
  'invoiceRecipient': {
    'en': 'Invoice recipient', 'no': 'Fakturamottaker', 'sv': 'Fakturamottagare', 'de': 'Rechnungsempfänger', 'da': 'Fakturamodtager',
  },
  'sendInvoiceDetails': {
    'en': 'Send invoice details', 'no': 'Send fakturadetaljer', 'sv': 'Skicka fakturadetaljer', 'de': 'Rechnungsdetails senden', 'da': 'Send fakturaoplysninger',
  },

  // ===== INVOICES =====
  'unpaid': {
    'en': 'Unpaid', 'no': 'Ubetalt', 'sv': 'Obetald', 'de': 'Unbezahlt', 'da': 'Ubetalt',
  },
  'paid': {
    'en': 'Paid', 'no': 'Betalt', 'sv': 'Betald', 'de': 'Bezahlt', 'da': 'Betalt',
  },
  'cancelled': {
    'en': 'Cancelled', 'no': 'Kansellert', 'sv': 'Avbruten', 'de': 'Storniert', 'da': 'Annulleret',
  },
  'invoiceNr': {
    'en': 'Invoice #', 'no': 'Faktura #', 'sv': 'Faktura #', 'de': 'Rechnung #', 'da': 'Faktura #',
  },
  'totalInclVat': {
    'en': 'Total incl. VAT', 'no': 'Total inkl. mva', 'sv': 'Totalt inkl. moms', 'de': 'Gesamt inkl. MwSt.', 'da': 'Total inkl. moms',
  },
  'noInvoicesFound': {
    'en': 'No invoices found.', 'no': 'Ingen fakturaer funnet.', 'sv': 'Inga fakturor hittades.', 'de': 'Keine Rechnungen gefunden.', 'da': 'Ingen fakturaer fundet.',
  },
  'downloadPdf': {
    'en': 'Download PDF', 'no': 'Last ned PDF', 'sv': 'Ladda ner PDF', 'de': 'PDF herunterladen', 'da': 'Download PDF',
  },
  'markAsPaid': {
    'en': 'Mark as paid', 'no': 'Marker som betalt', 'sv': 'Markera som betald', 'de': 'Als bezahlt markieren', 'da': 'Marker som betalt',
  },
  'markAsCancelled': {
    'en': 'Mark as cancelled', 'no': 'Marker som kansellert', 'sv': 'Markera som avbruten', 'de': 'Als storniert markieren', 'da': 'Marker som annulleret',
  },
  'deleteInvoice': {
    'en': 'Delete invoice?', 'no': 'Slette faktura?', 'sv': 'Radera faktura?', 'de': 'Rechnung löschen?', 'da': 'Slet faktura?',
  },
  'pdfError': {
    'en': 'PDF error', 'no': 'PDF-feil', 'sv': 'PDF-fel', 'de': 'PDF-Fehler', 'da': 'PDF-fejl',
  },

  // ===== ECONOMY =====
  'confirmedAndInvoiced': {
    'en': 'Confirmed + Invoiced', 'no': 'Bekreftet + Fakturert', 'sv': 'Bekräftad + Fakturerad', 'de': 'Bestätigt + In Rechnung gestellt', 'da': 'Bekræftet + Faktureret',
  },
  'confirmedOnly': {
    'en': 'Confirmed only', 'no': 'Kun bekreftet', 'sv': 'Enbart bekräftade', 'de': 'Nur bestätigt', 'da': 'Kun bekræftet',
  },
  'invoicedOnly': {
    'en': 'Invoiced only', 'no': 'Kun fakturert', 'sv': 'Enbart fakturerade', 'de': 'Nur in Rechnung gestellt', 'da': 'Kun faktureret',
  },
  'inquiryOnly': {
    'en': 'Inquiry only', 'no': 'Kun forespørsel', 'sv': 'Enbart förfrågningar', 'de': 'Nur Anfragen', 'da': 'Kun forespørgsel',
  },
  'manualBlocks': {
    'en': 'Manual blocks', 'no': 'Manuelle blokkeringer', 'sv': 'Manuella blockeringar', 'de': 'Manuelle Blöcke', 'da': 'Manuelle blokeringer',
  },
  'allCreators': {
    'en': 'All creators', 'no': 'Alle opprettere', 'sv': 'Alla skapare', 'de': 'Alle Ersteller', 'da': 'Alle oprettere',
  },
  'avgPerActiveMonth': {
    'en': 'Avg per active month', 'no': 'Gj.snitt per aktiv måned', 'sv': 'Snitt per aktiv månad', 'de': 'Durchschnitt pro aktivem Monat', 'da': 'Gns. per aktiv måned',
  },
  'daysWithBusesOut': {
    'en': 'Days with buses out', 'no': 'Dager med busser ute', 'sv': 'Dagar med bussar ute', 'de': 'Tage mit Bussen unterwegs', 'da': 'Dage med busser ude',
  },
  'monthlyBreakdown': {
    'en': 'Monthly Breakdown', 'no': 'Månedlig oversikt', 'sv': 'Månadsöversikt', 'de': 'Monatliche Übersicht', 'da': 'Månedlig oversigt',
  },
  'perProduction': {
    'en': 'Per Production', 'no': 'Per produksjon', 'sv': 'Per produktion', 'de': 'Pro Produktion', 'da': 'Per produktion',
  },
  'month': {
    'en': 'Month', 'no': 'Måned', 'sv': 'Månad', 'de': 'Monat', 'da': 'Måned',
  },
  'days': {
    'en': 'Days', 'no': 'Dager', 'sv': 'Dagar', 'de': 'Tage', 'da': 'Dage',
  },
  'revenue': {
    'en': 'Revenue', 'no': 'Inntekt', 'sv': 'Intäkter', 'de': 'Umsatz', 'da': 'Omsætning',
  },

  // ===== ISSUES =====
  'issueReports': {
    'en': 'Issue Reports', 'no': 'Feilrapporter', 'sv': 'Felrapporter', 'de': 'Problemberichte', 'da': 'Fejlrapporter',
  },
  'backToActiveReports': {
    'en': 'Back to active reports', 'no': 'Tilbake til aktive rapporter', 'sv': 'Tillbaka till aktiva rapporter', 'de': 'Zurück zu aktiven Berichten', 'da': 'Tilbage til aktive rapporter',
  },
  'viewArchive': {
    'en': 'View archive', 'no': 'Se arkiv', 'sv': 'Visa arkiv', 'de': 'Archiv anzeigen', 'da': 'Se arkiv',
  },
  'open': {
    'en': 'Open', 'no': 'Åpen', 'sv': 'Öppen', 'de': 'Offen', 'da': 'Åben',
  },
  'inProgress': {
    'en': 'In Progress', 'no': 'Under arbeid', 'sv': 'Pågående', 'de': 'In Bearbeitung', 'da': 'I gang',
  },
  'resolved': {
    'en': 'Resolved', 'no': 'Løst', 'sv': 'Löst', 'de': 'Gelöst', 'da': 'Løst',
  },
  'critical': {
    'en': 'Critical', 'no': 'Kritisk', 'sv': 'Kritisk', 'de': 'Kritisch', 'da': 'Kritisk',
  },
  'archivedReportsReadOnly': {
    'en': 'Archived reports — read only', 'no': 'Arkiverte rapporter — kun lesing', 'sv': 'Arkiverade rapporter — skrivskyddade', 'de': 'Archivierte Berichte — schreibgeschützt', 'da': 'Arkiverede rapporter — kun læsning',
  },
  'noArchivedReports': {
    'en': 'No archived reports', 'no': 'Ingen arkiverte rapporter', 'sv': 'Inga arkiverade rapporter', 'de': 'Keine archivierten Berichte', 'da': 'Ingen arkiverede rapporter',
  },
  'noReports': {
    'en': 'No reports', 'no': 'Ingen rapporter', 'sv': 'Inga rapporter', 'de': 'Keine Berichte', 'da': 'Ingen rapporter',
  },
  'engine': {
    'en': 'Engine', 'no': 'Motor', 'sv': 'Motor', 'de': 'Motor', 'da': 'Motor',
  },
  'brakes': {
    'en': 'Brakes', 'no': 'Bremser', 'sv': 'Bromsar', 'de': 'Bremsen', 'da': 'Bremser',
  },
  'electrical': {
    'en': 'Electrical', 'no': 'Elektrisk', 'sv': 'Elektrisk', 'de': 'Elektrisch', 'da': 'Elektrisk',
  },
  'interior': {
    'en': 'Interior', 'no': 'Interiør', 'sv': 'Interiör', 'de': 'Innenraum', 'da': 'Interiør',
  },
  'couldNotLoadImage': {
    'en': 'Could not load image', 'no': 'Kunne ikke laste bilde', 'sv': 'Kunde inte ladda bild', 'de': 'Bild konnte nicht geladen werden', 'da': 'Kunne ikke indlæse billede',
  },
  'noteToDriver': {
    'en': 'Note to driver (shown in app)', 'no': 'Notat til sjåfør (vises i appen)', 'sv': 'Notering till föraren (visas i appen)', 'de': 'Notiz an Fahrer (in der App angezeigt)', 'da': 'Note til chauffør (vises i app)',
  },
  'describeWhatWasDone': {
    'en': 'Describe what was done or what is happening...', 'no': 'Beskriv hva som ble gjort eller hva som skjer...', 'sv': 'Beskriv vad som gjordes eller vad som händer...', 'de': 'Beschreiben Sie, was getan wurde oder was passiert...', 'da': 'Beskriv hvad der blev gjort eller hvad der sker...',
  },
  'saveAndNotifyDriver': {
    'en': 'Save and notify driver', 'no': 'Lagre og varsle sjåfør', 'sv': 'Spara och meddela föraren', 'de': 'Speichern und Fahrer benachrichtigen', 'da': 'Gem og underret chauffør',
  },
  'archiveReport': {
    'en': 'Archive report', 'no': 'Arkiver rapport', 'sv': 'Arkivera rapport', 'de': 'Bericht archivieren', 'da': 'Arkiver rapport',
  },
  'archiveReportDesc': {
    'en': 'This report will be moved to the archive. You can find it there later and delete it if needed.',
    'no': 'Denne rapporten flyttes til arkivet. Du kan finne den der senere og slette den om nødvendig.',
    'sv': 'Denna rapport flyttas till arkivet. Du kan hitta den där senare och radera den vid behov.',
    'de': 'Dieser Bericht wird ins Archiv verschoben. Sie können ihn dort später finden und bei Bedarf löschen.',
    'da': 'Denne rapport flyttes til arkivet. Du kan finde den der senere og slette den om nødvendigt.',
  },
  'deletePermanentlyDesc': {
    'en': 'This will permanently delete the report. This cannot be undone.',
    'no': 'Dette vil slette rapporten permanent. Dette kan ikke angres.',
    'sv': 'Detta raderar rapporten permanent. Detta kan inte ångras.',
    'de': 'Dies löscht den Bericht dauerhaft. Dies kann nicht rückgängig gemacht werden.',
    'da': 'Dette sletter rapporten permanent. Dette kan ikke fortrydes.',
  },
  'restoreToActive': {
    'en': 'Restore to active', 'no': 'Gjenopprett til aktiv', 'sv': 'Återställ till aktiv', 'de': 'Zu aktiv wiederherstellen', 'da': 'Gendan til aktiv',
  },
  'issueResolved': {
    'en': 'Issue resolved', 'no': 'Problem løst', 'sv': 'Ärende löst', 'de': 'Problem gelöst', 'da': 'Problem løst',
  },
  'issueUpdated': {
    'en': 'Issue updated', 'no': 'Problem oppdatert', 'sv': 'Ärende uppdaterat', 'de': 'Problem aktualisiert', 'da': 'Problem opdateret',
  },

  // ===== ARCHIVE =====
  'searchArchive': {
    'en': 'Search archive…', 'no': 'Søk i arkiv…', 'sv': 'Sök i arkiv…', 'de': 'Archiv durchsuchen…', 'da': 'Søg i arkiv…',
  },
  'noArchivedOffers': {
    'en': 'No archived offers.', 'no': 'Ingen arkiverte tilbud.', 'sv': 'Inga arkiverade erbjudanden.', 'de': 'Keine archivierten Angebote.', 'da': 'Ingen arkiverede tilbud.',
  },
  'restored': {
    'en': 'Restored', 'no': 'Gjenopprettet', 'sv': 'Återställd', 'de': 'Wiederhergestellt', 'da': 'Gendannet',
  },
  'restoreFailed': {
    'en': 'Restore failed', 'no': 'Gjenoppretting feilet', 'sv': 'Återställning misslyckades', 'de': 'Wiederherstellung fehlgeschlagen', 'da': 'Gendannelse mislykkedes',
  },
  'deleteFailed': {
    'en': 'Delete failed', 'no': 'Sletting feilet', 'sv': 'Radering misslyckades', 'de': 'Löschung fehlgeschlagen', 'da': 'Sletning mislykkedes',
  },
  'permanentlyDeleted': {
    'en': 'Permanently deleted', 'no': 'Permanent slettet', 'sv': 'Permanent raderad', 'de': 'Dauerhaft gelöscht', 'da': 'Permanent slettet',
  },

  // ===== BUS REQUESTS =====
  'incomingRequests': {
    'en': 'Incoming requests from management companies', 'no': 'Innkommende forespørsler fra managementselskaper', 'sv': 'Inkommande förfrågningar från managementföretag', 'de': 'Eingehende Anfragen von Management-Unternehmen', 'da': 'Indkommende forespørgsler fra managementselskaber',
  },
  'quoted': {
    'en': 'Quoted', 'no': 'Tilbudt', 'sv': 'Offererad', 'de': 'Angeboten', 'da': 'Tilbudt',
  },
  'awaitingConfirm': {
    'en': 'Awaiting confirm', 'no': 'Venter på bekreftelse', 'sv': 'Väntar på bekräftelse', 'de': 'Wartet auf Bestätigung', 'da': 'Afventer bekræftelse',
  },
  'noPendingRequests': {
    'en': 'No pending requests', 'no': 'Ingen ventende forespørsler', 'sv': 'Inga väntande förfrågningar', 'de': 'Keine ausstehenden Anfragen', 'da': 'Ingen afventende forespørgsler',
  },
  'noArchivedRequests': {
    'en': 'No archived requests', 'no': 'Ingen arkiverte forespørsler', 'sv': 'Inga arkiverade förfrågningar', 'de': 'Keine archivierten Anfragen', 'da': 'Ingen arkiverede forespørgsler',
  },
  'noRequests': {
    'en': 'No requests', 'no': 'Ingen forespørsler', 'sv': 'Inga förfrågningar', 'de': 'Keine Anfragen', 'da': 'Ingen forespørgsler',
  },
  'rejectRequest': {
    'en': 'Reject request?', 'no': 'Avslå forespørsel?', 'sv': 'Avslå förfrågan?', 'de': 'Anfrage ablehnen?', 'da': 'Afvis forespørgsel?',
  },
  'rejectRequestDesc': {
    'en': 'This will mark the request as rejected.', 'no': 'Dette vil merke forespørselen som avslått.', 'sv': 'Detta markerar förfrågan som avslagen.', 'de': 'Dies markiert die Anfrage als abgelehnt.', 'da': 'Dette markerer forespørgslen som afvist.',
  },
  'archiveRequest': {
    'en': 'Archive request?', 'no': 'Arkivere forespørsel?', 'sv': 'Arkivera förfrågan?', 'de': 'Anfrage archivieren?', 'da': 'Arkiver forespørgsel?',
  },
  'archiveRequestDesc': {
    'en': 'This request will be moved to your archive.', 'no': 'Denne forespørselen flyttes til arkivet ditt.', 'sv': 'Denna förfrågan flyttas till ditt arkiv.', 'de': 'Diese Anfrage wird in Ihr Archiv verschoben.', 'da': 'Denne forespørgsel flyttes til dit arkiv.',
  },
  'deleteRequestDesc': {
    'en': 'This request will be permanently deleted. This action cannot be undone.',
    'no': 'Denne forespørselen blir permanent slettet. Denne handlingen kan ikke angres.',
    'sv': 'Denna förfrågan raderas permanent. Denna åtgärd kan inte ångras.',
    'de': 'Diese Anfrage wird dauerhaft gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
    'da': 'Denne forespørgsel slettes permanent. Denne handling kan ikke fortrydes.',
  },
  'createOffer': {
    'en': 'Create offer', 'no': 'Opprett tilbud', 'sv': 'Skapa erbjudande', 'de': 'Angebot erstellen', 'da': 'Opret tilbud',
  },
  'checkingAvailability': {
    'en': 'Checking availability...', 'no': 'Sjekker tilgjengelighet...', 'sv': 'Kontrollerar tillgänglighet...', 'de': 'Verfügbarkeit wird geprüft...', 'da': 'Tjekker tilgængelighed...',
  },
  'requestConfirmed': {
    'en': 'Request confirmed', 'no': 'Forespørsel bekreftet', 'sv': 'Förfrågan bekräftad', 'de': 'Anfrage bestätigt', 'da': 'Forespørgsel bekræftet',
  },

  // ===== ROUTES ADMIN =====
  'manageFerries': {
    'en': 'Manage ferries', 'no': 'Administrer ferger', 'sv': 'Hantera färjor', 'de': 'Fähren verwalten', 'da': 'Administrer færger',
  },
  'searchFromTo': {
    'en': 'Search from / to…', 'no': 'Søk fra / til…', 'sv': 'Sök från / till…', 'de': 'Suche von / nach…', 'da': 'Søg fra / til…',
  },
  'noRoutes': {
    'en': 'No routes', 'no': 'Ingen ruter', 'sv': 'Inga rutter', 'de': 'Keine Routen', 'da': 'Ingen ruter',
  },
  'editRoute': {
    'en': 'Edit route', 'no': 'Rediger rute', 'sv': 'Redigera rutt', 'de': 'Route bearbeiten', 'da': 'Rediger rute',
  },
  'totalKm': {
    'en': 'Total km', 'no': 'Totalt km', 'sv': 'Totalt km', 'de': 'Gesamt km', 'da': 'Total km',
  },
  'ferryNameOptional': {
    'en': 'Ferry name (optional)', 'no': 'Fergenavn (valgfritt)', 'sv': 'Färjenamn (valfritt)', 'de': 'Fährname (optional)', 'da': 'Færgenavn (valgfrit)',
  },
  'noDDrive': {
    'en': 'No D.Drive', 'no': 'Ingen D.Drive', 'sv': 'Ingen D.Drive', 'de': 'Kein D.Drive', 'da': 'Ingen D.Drive',
  },
  'noDDriveDesc': {
    'en': 'Route km >= 600 but should not trigger D.Drive', 'no': 'Rute km >= 600 men skal ikke utløse D.Drive', 'sv': 'Rutt km >= 600 men ska inte utlösa D.Drive', 'de': 'Route km >= 600 aber soll kein D.Drive auslösen', 'da': 'Rute km >= 600 men skal ikke udløse D.Drive',
  },
  'kmPerCountry': {
    'en': 'Km per country', 'no': 'Km per land', 'sv': 'Km per land', 'de': 'Km pro Land', 'da': 'Km per land',
  },
  'routeUpdated': {
    'en': 'Route updated', 'no': 'Rute oppdatert', 'sv': 'Rutt uppdaterad', 'de': 'Route aktualisiert', 'da': 'Rute opdateret',
  },
  'addFerry': {
    'en': 'Add ferry', 'no': 'Legg til ferge', 'sv': 'Lägg till färja', 'de': 'Fähre hinzufügen', 'da': 'Tilføj færge',
  },
  'ferryName': {
    'en': 'Ferry name', 'no': 'Fergenavn', 'sv': 'Färjenamn', 'de': 'Fährname', 'da': 'Færgenavn',
  },
  'basePrice': {
    'en': 'Base price', 'no': 'Grunnpris', 'sv': 'Grundpris', 'de': 'Grundpreis', 'da': 'Grundpris',
  },
  'trailerPrice': {
    'en': 'Trailer price', 'no': 'Hengerpris', 'sv': 'Släppris', 'de': 'Anhängerpreis', 'da': 'Trailerpris',
  },
  'ferrySaved': {
    'en': 'Ferry saved', 'no': 'Ferge lagret', 'sv': 'Färja sparad', 'de': 'Fähre gespeichert', 'da': 'Færge gemt',
  },
  'editFerry': {
    'en': 'Edit ferry', 'no': 'Rediger ferge', 'sv': 'Redigera färja', 'de': 'Fähre bearbeiten', 'da': 'Rediger færge',
  },
  'ferryDeleted': {
    'en': 'Ferry deleted', 'no': 'Ferge slettet', 'sv': 'Färja borttagen', 'de': 'Fähre gelöscht', 'da': 'Færge slettet',
  },
  'noFerries': {
    'en': 'No ferries', 'no': 'Ingen ferger', 'sv': 'Inga färjor', 'de': 'Keine Fähren', 'da': 'Ingen færger',
  },
  'extra': {
    'en': 'Extra', 'no': 'Ekstra', 'sv': 'Extra', 'de': 'Extra', 'da': 'Ekstra',
  },
  'addRoute': {
    'en': 'Add route', 'no': 'Legg til rute', 'sv': 'Lägg till rutt', 'de': 'Route hinzufügen', 'da': 'Tilføj rute',
  },
  'routeAdded': {
    'en': 'Route added', 'no': 'Rute lagt til', 'sv': 'Rutt tillagd', 'de': 'Route hinzugefügt', 'da': 'Rute tilføjet',
  },
  'fillAllFields': {
    'en': 'Fill all fields', 'no': 'Fyll ut alle felt', 'sv': 'Fyll i alla fält', 'de': 'Alle Felder ausfüllen', 'da': 'Udfyld alle felter',
  },
  'extraEgFerry': {
    'en': 'Extra (ex: Ferry)', 'no': 'Ekstra (f.eks: Ferge)', 'sv': 'Extra (t.ex: Färja)', 'de': 'Extra (z.B.: Fähre)', 'da': 'Ekstra (f.eks: Færge)',
  },
};
