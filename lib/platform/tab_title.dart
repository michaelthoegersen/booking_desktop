import 'tab_title_io.dart'
    if (dart.library.js_interop) 'tab_title_web.dart';

/// Viser antall uleste meldinger i nettlesarfanen, slik chat-tjenester gjør:
/// «(3) TourFlow». Gjør ingenting utenfor web.
void setUnreadBadge(int count) => setUnreadBadgePlatform(count);
