const settingsStrings = <String, Map<String, String>>{

  // --- Tabs ---
  'tabGeneral': {
    'en': 'General', 'no': 'Generelt', 'sv': 'Allmänt', 'de': 'Allgemein', 'da': 'Generelt',
  },
  'tabIntegrations': {
    'en': 'Email & Integrations', 'no': 'E-post & Integrasjoner', 'sv': 'E-post & Integrationer', 'de': 'E-Mail & Integrationen', 'da': 'E-mail & Integrationer',
  },
  'tabPricing': {
    'en': 'Pricing', 'no': 'Prising', 'sv': 'Prissättning', 'de': 'Preisgestaltung', 'da': 'Prissætning',
  },
  'tabAdmin': {
    'en': 'Admin', 'no': 'Admin', 'sv': 'Admin', 'de': 'Admin', 'da': 'Admin',
  },

  // --- Branding ---
  'branding': {
    'en': 'Branding', 'no': 'Merkevare', 'sv': 'Varumärke', 'de': 'Branding', 'da': 'Branding',
  },
  'brandingDesc': {
    'en': 'Logo and text shown on offers, invoices and other PDFs.',
    'no': 'Logo og tekst som vises på tilbud, fakturaer og andre PDF-er.',
    'sv': 'Logotyp och text som visas på erbjudanden, fakturor och andra PDF-filer.',
    'de': 'Logo und Text, die auf Angeboten, Rechnungen und anderen PDFs angezeigt werden.',
    'da': 'Logo og tekst der vises på tilbud, fakturaer og andre PDF-filer.',
  },
  'logo': {
    'en': 'Logo', 'no': 'Logo', 'sv': 'Logotyp', 'de': 'Logo', 'da': 'Logo',
  },
  'uploadLogo': {
    'en': 'Upload logo', 'no': 'Last opp logo', 'sv': 'Ladda upp logotyp', 'de': 'Logo hochladen', 'da': 'Upload logo',
  },
  'removeLogo': {
    'en': 'Remove logo', 'no': 'Fjern logo', 'sv': 'Ta bort logotyp', 'de': 'Logo entfernen', 'da': 'Fjern logo',
  },
  'companyNameLabel': {
    'en': 'Company name (on PDFs)', 'no': 'Selskapsnavn (på PDF-er)', 'sv': 'Företagsnamn (på PDF-filer)', 'de': 'Firmenname (auf PDFs)', 'da': 'Virksomhedsnavn (på PDF-filer)',
  },
  'addressLineLabel': {
    'en': 'Address', 'no': 'Adresse', 'sv': 'Adress', 'de': 'Adresse', 'da': 'Adresse',
  },
  'contactLine1Label': {
    'en': 'Contact line 1', 'no': 'Kontaktlinje 1', 'sv': 'Kontaktrad 1', 'de': 'Kontaktzeile 1', 'da': 'Kontaktlinje 1',
  },
  'contactLine2Label': {
    'en': 'Contact line 2 (optional)', 'no': 'Kontaktlinje 2 (valgfritt)', 'sv': 'Kontaktrad 2 (valfritt)', 'de': 'Kontaktzeile 2 (optional)', 'da': 'Kontaktlinje 2 (valgfrit)',
  },
  'signatureNameLabel': {
    'en': 'Signature name (on offers)', 'no': 'Signaturnavn (på tilbud)', 'sv': 'Signaturnamn (på erbjudanden)', 'de': 'Unterschriftsname (auf Angeboten)', 'da': 'Signaturnavn (på tilbud)',
  },
  'termsAndConditions': {
    'en': 'Terms & conditions', 'no': 'Vilkår og betingelser', 'sv': 'Villkor', 'de': 'Geschäftsbedingungen', 'da': 'Vilkår og betingelser',
  },
  'termsHint': {
    'en': 'Shown on the last page of offer PDFs', 'no': 'Vises på siste side av tilbuds-PDF-er', 'sv': 'Visas på sista sidan av erbjudande-PDF-filer', 'de': 'Wird auf der letzten Seite der Angebots-PDFs angezeigt', 'da': 'Vises på sidste side af tilbuds-PDF-filer',
  },
  'brandingSaved': {
    'en': 'Branding saved', 'no': 'Merkevare lagret', 'sv': 'Varumärke sparat', 'de': 'Branding gespeichert', 'da': 'Branding gemt',
  },
  'logoUploaded': {
    'en': 'Logo uploaded', 'no': 'Logo lastet opp', 'sv': 'Logotyp uppladdad', 'de': 'Logo hochgeladen', 'da': 'Logo uploadet',
  },
  'logoRemoved': {
    'en': 'Logo removed', 'no': 'Logo fjernet', 'sv': 'Logotyp borttagen', 'de': 'Logo entfernt', 'da': 'Logo fjernet',
  },

  // --- Page ---
  'dropbox': {
    'en': 'Dropbox', 'no': 'Dropbox', 'sv': 'Dropbox', 'de': 'Dropbox', 'da': 'Dropbox',
  },
  'dropboxFolder': {
    'en': 'Dropbox folder', 'no': 'Dropbox-mappe', 'sv': 'Dropbox-mapp', 'de': 'Dropbox-Ordner', 'da': 'Dropbox-mappe',
  },
  'selectDropboxFolder': {
    'en': 'Select Dropbox folder…', 'no': 'Velg Dropbox-mappe…', 'sv': 'Välj Dropbox-mapp…', 'de': 'Dropbox-Ordner wählen…', 'da': 'Vælg Dropbox-mappe…',
  },
  'choose': {
    'en': 'Choose', 'no': 'Velg', 'sv': 'Välj', 'de': 'Auswählen', 'da': 'Vælg',
  },

  // --- Email Account ---
  'emailAccount': {
    'en': 'Email Account', 'no': 'E-postkonto', 'sv': 'E-postkonto', 'de': 'E-Mail-Konto', 'da': 'E-mailkonto',
  },
  'emailAccountDesc': {
    'en': 'Set up an SMTP account to send emails from a custom address (e.g. Office 365, Gmail).',
    'no': 'Sett opp en SMTP-konto for å sende e-post fra en egendefinert adresse (f.eks. Office 365, Gmail).',
    'sv': 'Ställ in ett SMTP-konto för att skicka e-post från en anpassad adress (t.ex. Office 365, Gmail).',
    'de': 'Richten Sie ein SMTP-Konto ein, um E-Mails von einer benutzerdefinierten Adresse zu senden (z.B. Office 365, Gmail).',
    'da': 'Opsæt en SMTP-konto for at sende e-mails fra en brugerdefineret adresse (f.eks. Office 365, Gmail).',
  },
  'editEmailAccount': {
    'en': 'Edit email account', 'no': 'Rediger e-postkonto', 'sv': 'Redigera e-postkonto', 'de': 'E-Mail-Konto bearbeiten', 'da': 'Rediger e-mailkonto',
  },
  'addEmailAccount': {
    'en': 'Add email account', 'no': 'Legg til e-postkonto', 'sv': 'Lägg till e-postkonto', 'de': 'E-Mail-Konto hinzufügen', 'da': 'Tilføj e-mailkonto',
  },
  'emailAddress': {
    'en': 'Email address', 'no': 'E-postadresse', 'sv': 'E-postadress', 'de': 'E-Mail-Adresse', 'da': 'E-mailadresse',
  },
  'displayName': {
    'en': 'Display name', 'no': 'Visningsnavn', 'sv': 'Visningsnamn', 'de': 'Anzeigename', 'da': 'Visningsnavn',
  },
  'smtpHost': {
    'en': 'SMTP host', 'no': 'SMTP-vert', 'sv': 'SMTP-värd', 'de': 'SMTP-Host', 'da': 'SMTP-vært',
  },
  'port': {
    'en': 'Port', 'no': 'Port', 'sv': 'Port', 'de': 'Port', 'da': 'Port',
  },
  'password': {
    'en': 'Password', 'no': 'Passord', 'sv': 'Lösenord', 'de': 'Passwort', 'da': 'Adgangskode',
  },
  'saving': {
    'en': 'Saving…', 'no': 'Lagrer…', 'sv': 'Sparar…', 'de': 'Speichern…', 'da': 'Gemmer…',
  },
  'removeEmailAccount': {
    'en': 'Remove email account?', 'no': 'Fjerne e-postkonto?', 'sv': 'Ta bort e-postkonto?', 'de': 'E-Mail-Konto entfernen?', 'da': 'Fjern e-mailkonto?',
  },
  'remove': {
    'en': 'Remove', 'no': 'Fjern', 'sv': 'Ta bort', 'de': 'Entfernen', 'da': 'Fjern',
  },
  'edit': {
    'en': 'Edit', 'no': 'Rediger', 'sv': 'Redigera', 'de': 'Bearbeiten', 'da': 'Rediger',
  },

  // --- Invoice ---
  'invoice': {
    'en': 'Invoice', 'no': 'Faktura', 'sv': 'Faktura', 'de': 'Rechnung', 'da': 'Faktura',
  },
  'bankAccountNumber': {
    'en': 'Bank account number', 'no': 'Bankkontonummer', 'sv': 'Bankkontonummer', 'de': 'Bankkontonummer', 'da': 'Bankkontonummer',
  },

  // --- Pricing ---
  'completePricing': {
    'en': 'Complete — pricing parameters', 'no': 'Complete — prisparametre', 'sv': 'Complete — prisparametrar', 'de': 'Complete — Preisparameter', 'da': 'Complete — prisparametre',
  },
  'creoFeeMinimum': {
    'en': 'Creo fee minimum', 'no': 'Creo-gebyr minimum', 'sv': 'Creo-avgift minimum', 'de': 'Creo-Gebühr Minimum', 'da': 'Creo-gebyr minimum',
  },
  'extraShowFee': {
    'en': 'Extra show fee', 'no': 'Ekstra show-gebyr', 'sv': 'Extra showavgift', 'de': 'Zusätzliche Showgebühr', 'da': 'Ekstra show-gebyr',
  },
  'markup': {
    'en': 'Markup', 'no': 'Påslag', 'sv': 'Påslag', 'de': 'Aufschlag', 'da': 'Avance',
  },
  'inEarPrice': {
    'en': 'In-ear price', 'no': 'In-ear-pris', 'sv': 'In-ear-pris', 'de': 'In-Ear-Preis', 'da': 'In-ear-pris',
  },
  'transportKmPrice': {
    'en': 'Transport kr/km', 'no': 'Transport kr/km', 'sv': 'Transport kr/km', 'de': 'Transport kr/km', 'da': 'Transport kr/km',
  },

  // --- Swedish pricing ---
  'swedishPricingModel': {
    'en': 'Swedish pricing model (per leg)', 'no': 'Svensk prismodell (per etappe)', 'sv': 'Svensk prismodell (per sträcka)', 'de': 'Schwedisches Preismodell (pro Etappe)', 'da': 'Svensk prismodel (per etape)',
  },
  'vehicle': {
    'en': 'Vehicle', 'no': 'Kjøretøy', 'sv': 'Fordon', 'de': 'Fahrzeug', 'da': 'Køretøj',
  },
  'driver': {
    'en': 'Driver', 'no': 'Sjåfør', 'sv': 'Förare', 'de': 'Fahrer', 'da': 'Chauffør',
  },
  'hourlyRate': {
    'en': 'Hourly rate', 'no': 'Timepris', 'sv': 'Timpris', 'de': 'Stundensatz', 'da': 'Timepris',
  },
  'hoursPerDay': {
    'en': 'Hours/day', 'no': 'Timer/dag', 'sv': 'Timmar/dag', 'de': 'Stunden/Tag', 'da': 'Timer/dag',
  },
  'employerTax': {
    'en': 'Employer tax', 'no': 'Arbeidsgiveravgift', 'sv': 'Arbetsgivaravgift', 'de': 'Arbeitgeberabgabe', 'da': 'Arbejdsgiverafgift',
  },
  'allowance': {
    'en': 'Allowance', 'no': 'Diett', 'sv': 'Traktamente', 'de': 'Zuschuss', 'da': 'Diæt',
  },
  'margin': {
    'en': 'Margin', 'no': 'Margin', 'sv': 'Marginal', 'de': 'Marge', 'da': 'Margin',
  },
  'purchasePrice': {
    'en': 'Purchase price', 'no': 'Innkjøpspris', 'sv': 'Inköpspris', 'de': 'Kaufpreis', 'da': 'Indkøbspris',
  },
  'depreciation': {
    'en': 'Depreciation', 'no': 'Avskrivning', 'sv': 'Avskrivning', 'de': 'Abschreibung', 'da': 'Afskrivning',
  },
  'interest': {
    'en': 'Interest', 'no': 'Rente', 'sv': 'Ränta', 'de': 'Zinsen', 'da': 'Rente',
  },
  'insurance': {
    'en': 'Insurance', 'no': 'Forsikring', 'sv': 'Försäkring', 'de': 'Versicherung', 'da': 'Forsikring',
  },
  'tax': {
    'en': 'Tax', 'no': 'Skatt', 'sv': 'Skatt', 'de': 'Steuer', 'da': 'Skat',
  },
  'parking': {
    'en': 'Parking', 'no': 'Parkering', 'sv': 'Parkering', 'de': 'Parken', 'da': 'Parkering',
  },
  'drivingDays': {
    'en': 'Driving days', 'no': 'Kjøredager', 'sv': 'Körbara dagar', 'de': 'Fahrtage', 'da': 'Køredage',
  },
  'kmPriceVariable': {
    'en': 'Km price (variable, per 10 km)', 'no': 'Km-pris (variabel, per 10 km)', 'sv': 'Km-pris (variabel, per 10 km)', 'de': 'Km-Preis (variabel, pro 10 km)', 'da': 'Km-pris (variabel, per 10 km)',
  },
  'dieselPrice': {
    'en': 'Diesel price', 'no': 'Dieselpris', 'sv': 'Dieselpris', 'de': 'Dieselpreis', 'da': 'Dieselpris',
  },
  'consumption': {
    'en': 'Consumption', 'no': 'Forbruk', 'sv': 'Förbrukning', 'de': 'Verbrauch', 'da': 'Forbrug',
  },
  'tires': {
    'en': 'Tires', 'no': 'Dekk', 'sv': 'Däck', 'de': 'Reifen', 'da': 'Dæk',
  },
  'oil': {
    'en': 'Oil', 'no': 'Olje', 'sv': 'Olja', 'de': 'Öl', 'da': 'Olie',
  },
  'workshop': {
    'en': 'Workshop', 'no': 'Verksted', 'sv': 'Verkstad', 'de': 'Werkstatt', 'da': 'Værksted',
  },
  'other': {
    'en': 'Other', 'no': 'Annet', 'sv': 'Övrigt', 'de': 'Sonstiges', 'da': 'Andet',
  },
  'doubleDriver': {
    'en': 'Double driver (DD)', 'no': 'Dobbeltsjåfør (DD)', 'sv': 'Dubbelförare (DD)', 'de': 'Doppelfahrer (DD)', 'da': 'Dobbeltchauffør (DD)',
  },
  'travel': {
    'en': 'Travel', 'no': 'Reise', 'sv': 'Resa', 'de': 'Reise', 'da': 'Rejse',
  },
  'hotel': {
    'en': 'Hotel', 'no': 'Hotell', 'sv': 'Hotell', 'de': 'Hotel', 'da': 'Hotel',
  },
  'kmThreshold': {
    'en': 'Km threshold', 'no': 'Km-terskel', 'sv': 'Km-tröskel', 'de': 'Km-Schwelle', 'da': 'Km-tærskel',
  },
  'trailerHire': {
    'en': 'Trailer hire', 'no': 'Henger-leie', 'sv': 'Släphyra', 'de': 'Anhängermiete', 'da': 'Trailerleje',
  },
  'internationalAllowance': {
    'en': 'International allowance', 'no': 'Internasjonal diett', 'sv': 'Internationellt traktamente', 'de': 'Internationale Zulage', 'da': 'International diæt',
  },

  // --- Norwegian pricing ---
  'norwegianPricingModel': {
    'en': 'Norwegian pricing model', 'no': 'Norsk prismodell', 'sv': 'Norsk prismodell', 'de': 'Norwegisches Preismodell', 'da': 'Norsk prismodel',
  },
  'dayPrice': {
    'en': 'Day price', 'no': 'Dagpris', 'sv': 'Dagspris', 'de': 'Tagespreis', 'da': 'Dagspris',
  },
  'extraKmPrice': {
    'en': 'Extra km price', 'no': 'Ekstra km-pris', 'sv': 'Extra km-pris', 'de': 'Extra km-Preis', 'da': 'Ekstra km-pris',
  },
  'trailerDayPrice': {
    'en': 'Trailer day price', 'no': 'Henger dagpris', 'sv': 'Släp dagspris', 'de': 'Anhänger Tagespreis', 'da': 'Trailer dagspris',
  },
  'trailerKmPrice': {
    'en': 'Trailer km price', 'no': 'Henger km-pris', 'sv': 'Släp km-pris', 'de': 'Anhänger km-Preis', 'da': 'Trailer km-pris',
  },
  'dDriveDayPrice': {
    'en': 'D.Drive day price', 'no': 'D.Drive dagpris', 'sv': 'D.Drive dagspris', 'de': 'D.Drive Tagespreis', 'da': 'D.Drive dagspris',
  },
  'flightTicketPrice': {
    'en': 'Flight ticket price', 'no': 'Flybillettpris', 'sv': 'Flygbiljettpris', 'de': 'Flugticketpreis', 'da': 'Flybilletpris',
  },
  'tollKmRate': {
    'en': 'Toll km-rate', 'no': 'Bom km-rate', 'sv': 'Vägtull km-rate', 'de': 'Maut km-Rate', 'da': 'Bomafgift km-rate',
  },

  // --- Actions ---
  'manageRoutes': {
    'en': 'Manage routes', 'no': 'Administrer ruter', 'sv': 'Hantera rutter', 'de': 'Routen verwalten', 'da': 'Administrer ruter',
  },
  'updateKmSweden': {
    'en': 'Update km Sweden', 'no': 'Oppdater km Sverige', 'sv': 'Uppdatera km Sverige', 'de': 'Km Schweden aktualisieren', 'da': 'Opdater km Sverige',
  },
  'addUser': {
    'en': 'Add user', 'no': 'Legg til bruker', 'sv': 'Lägg till användare', 'de': 'Benutzer hinzufügen', 'da': 'Tilføj bruger',
  },
  'changePassword': {
    'en': 'Change password', 'no': 'Endre passord', 'sv': 'Ändra lösenord', 'de': 'Passwort ändern', 'da': 'Skift adgangskode',
  },
  'settingsSaved': {
    'en': 'Settings saved', 'no': 'Innstillinger lagret', 'sv': 'Inställningar sparade', 'de': 'Einstellungen gespeichert', 'da': 'Indstillinger gemt',
  },

  // --- Add user dialog ---
  'name': {
    'en': 'Name', 'no': 'Navn', 'sv': 'Namn', 'de': 'Name', 'da': 'Navn',
  },
  'email': {
    'en': 'Email', 'no': 'E-post', 'sv': 'E-post', 'de': 'E-Mail', 'da': 'E-mail',
  },
  'phone': {
    'en': 'Phone', 'no': 'Telefon', 'sv': 'Telefon', 'de': 'Telefon', 'da': 'Telefon',
  },
  'role': {
    'en': 'Role', 'no': 'Rolle', 'sv': 'Roll', 'de': 'Rolle', 'da': 'Rolle',
  },
  'roleDriver': {
    'en': 'driver', 'no': 'sjåfør', 'sv': 'förare', 'de': 'Fahrer', 'da': 'chauffør',
  },
  'roleAdmin': {
    'en': 'admin', 'no': 'admin', 'sv': 'admin', 'de': 'Admin', 'da': 'admin',
  },
  'roleManagement': {
    'en': 'management', 'no': 'ledelse', 'sv': 'ledning', 'de': 'Management', 'da': 'ledelse',
  },
  'company': {
    'en': 'Company', 'no': 'Selskap', 'sv': 'Företag', 'de': 'Unternehmen', 'da': 'Virksomhed',
  },
  'selectCompany': {
    'en': 'Select company', 'no': 'Velg selskap', 'sv': 'Välj företag', 'de': 'Unternehmen wählen', 'da': 'Vælg virksomhed',
  },
  'create': {
    'en': 'Create', 'no': 'Opprett', 'sv': 'Skapa', 'de': 'Erstellen', 'da': 'Opret',
  },
  'selectCompanyForManagement': {
    'en': 'Please select a company for management users',
    'no': 'Velg et selskap for ledelsesbrukere',
    'sv': 'Välj ett företag för ledningsanvändare',
    'de': 'Bitte wählen Sie ein Unternehmen für Management-Benutzer',
    'da': 'Vælg venligst en virksomhed for ledelsesbrugere',
  },
  'userCreated': {
    'en': 'User created', 'no': 'Bruker opprettet', 'sv': 'Användare skapad', 'de': 'Benutzer erstellt', 'da': 'Bruger oprettet',
  },
  'sendLoginDetails': {
    'en': 'Send these login details to', 'no': 'Send disse innloggingsdetaljene til', 'sv': 'Skicka dessa inloggningsuppgifter till', 'de': 'Senden Sie diese Anmeldedaten an', 'da': 'Send disse loginoplysninger til',
  },
  'changePasswordAfterLogin': {
    'en': 'The user should change their password after first login.',
    'no': 'Brukeren bør endre passord etter første innlogging.',
    'sv': 'Användaren bör ändra sitt lösenord efter första inloggningen.',
    'de': 'Der Benutzer sollte sein Passwort nach der ersten Anmeldung ändern.',
    'da': 'Brugeren bør ændre sin adgangskode efter første login.',
  },
  'ok': {
    'en': 'OK', 'no': 'OK', 'sv': 'OK', 'de': 'OK', 'da': 'OK',
  },

  // --- Change password dialog ---
  'newPassword': {
    'en': 'New password', 'no': 'Nytt passord', 'sv': 'Nytt lösenord', 'de': 'Neues Passwort', 'da': 'Ny adgangskode',
  },
  'confirmPassword': {
    'en': 'Confirm password', 'no': 'Bekreft passord', 'sv': 'Bekräfta lösenord', 'de': 'Passwort bestätigen', 'da': 'Bekræft adgangskode',
  },
  'update': {
    'en': 'Update', 'no': 'Oppdater', 'sv': 'Uppdatera', 'de': 'Aktualisieren', 'da': 'Opdater',
  },
  'passwordsDoNotMatch': {
    'en': 'Passwords do not match', 'no': 'Passordene samsvarer ikke', 'sv': 'Lösenorden matchar inte', 'de': 'Passwörter stimmen nicht überein', 'da': 'Adgangskoderne matcher ikke',
  },
  'passwordUpdated': {
    'en': 'Password updated', 'no': 'Passord oppdatert', 'sv': 'Lösenord uppdaterat', 'de': 'Passwort aktualisiert', 'da': 'Adgangskode opdateret',
  },
  'close': {
    'en': 'Close', 'no': 'Lukk', 'sv': 'Stäng', 'de': 'Schließen', 'da': 'Luk',
  },
};
