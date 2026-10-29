import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Flere mulige datoer for én og samme forespørsel.
///
/// Hver mulig dato er sin egen gig, så medlemmene ser og kan holde av alle
/// sammen. Alternativene deler [kGroup] slik at appen kan vise at de hører
/// sammen, og [kState] sier om datoen er uavklart, valgt eller utgått.
///
/// Et uavklart alternativ er ikke solgt. Det skal aldri telle i gigghyre eller
/// fakturering — bruk [isUnresolved] til å holde dem utenfor.
class DateOptionService {
  static final _sb = Supabase.instance.client;

  static const kGroup = 'date_option_group';
  static const kState = 'date_option_state';

  /// Kolonnene som må være med i en select for at hjelperne her skal virke.
  static const columns = '$kGroup, $kState';

  static bool isOption(Map<String, dynamic> gig) => gig[kGroup] != null;

  /// Uavklart: kunden har ikke valgt dato ennå.
  static bool isUnresolved(Map<String, dynamic> gig) =>
      gig[kState] == 'pending';

  static bool isExpired(Map<String, dynamic> gig) => gig[kState] == 'expired';

  static bool isChosen(Map<String, dynamic> gig) => gig[kState] == 'chosen';

  /// Alle alternativene i gruppa, tidligste dato først.
  static Future<List<Map<String, dynamic>>> siblings(String groupId) async {
    final rows = await _sb
        .from('gigs')
        .select('id, date_from, date_to, venue_name, city, status, $columns')
        .eq(kGroup, groupId)
        .order('date_from');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Legger til en ny mulig dato for [gigId]. Gigen kopieres med alt unntatt
  /// dato, så alternativet beskriver det samme oppdraget. Har gigen ingen
  /// gruppe fra før, opprettes en og den opprinnelige datoen blir alternativ 1.
  ///
  /// Returnerer id-en til den nye gigen.
  static Future<String> addOption({
    required String gigId,
    required DateTime date,
  }) async {
    final source = Map<String, dynamic>.from(
      await _sb.from('gigs').select().eq('id', gigId).single(),
    );

    var group = source[kGroup] as String?;
    if (group == null) {
      // Første alternativ: lag gruppa og meld inn den opprinnelige gigen.
      // Den opprinnelige gigen er ankeret: id-en dens blir gruppe-id. Da
      // trengs ingen uuid-generering på klienten, og det er alltid synlig
      // hvilken dato som kom først.
      final seeded = await _sb
          .from('gigs')
          .update({kGroup: gigId, kState: 'pending'})
          .eq('id', gigId)
          .select(kGroup)
          .single();
      group = seeded[kGroup] as String;
    }

    final iso = _isoDate(date);
    for (final key in const [
      'id',
      'created_at',
      'updated_at',
      'date_from',
      'date_to',
    ]) {
      source.remove(key);
    }
    // Den som legger til alternativet eier raden. Uten dette arver kopien
    // created_by fra originalen, og på et testtilbud ville RLS da gjemt den
    // for alle — også for den som nettopp lagde den.
    source['created_by'] = _sb.auth.currentUser?.id;
    source[kGroup] = group;
    source[kState] = 'pending';
    source['date_from'] = iso;
    source['date_to'] = null;

    final inserted =
        await _sb.from('gigs').insert(source).select('id').single();
    final newId = inserted['id'] as String;

    await _copyShows(gigId, newId);
    return newId;
  }

  /// Datoen er avklart: [gigId] ble valgt, søsknene merkes utgått.
  ///
  /// Den valgte settes først. Skulle andre steg feile, står gruppa igjen med
  /// ett valgt alternativ og resten uavklart — synlig og mulig å rette — i
  /// stedet for at alle blir utgått uten at noen er valgt.
  static Future<void> choose(String gigId) async {
    final row = await _sb
        .from('gigs')
        .select(kGroup)
        .eq('id', gigId)
        .maybeSingle();
    final group = row?[kGroup] as String?;
    if (group == null) return;

    await _sb.from('gigs').update({kState: 'chosen'}).eq('id', gigId);
    await _sb
        .from('gigs')
        .update({kState: 'expired'})
        .eq(kGroup, group)
        .neq('id', gigId);
  }

  /// Angrer avklaringen og setter hele gruppa tilbake til uavklart.
  static Future<void> reopen(String groupId) async {
    await _sb.from('gigs').update({kState: 'pending'}).eq(kGroup, groupId);
  }

  /// Løsner [gigId] fra gruppa si. Brukes når et alternativ likevel skal stå
  /// på egne bein som en vanlig gig.
  static Future<void> detach(String gigId) async {
    await _sb
        .from('gigs')
        .update({kGroup: null, kState: null}).eq('id', gigId);
  }

  static Future<void> _copyShows(String fromGigId, String toGigId) async {
    try {
      final shows =
          await _sb.from('gig_shows').select().eq('gig_id', fromGigId);
      final rows = <Map<String, dynamic>>[];
      for (final s in (shows as List)) {
        final copy = Map<String, dynamic>.from(s as Map);
        copy.remove('id');
        copy['gig_id'] = toGigId;
        rows.add(copy);
      }
      if (rows.isNotEmpty) await _sb.from('gig_shows').insert(rows);
    } catch (e) {
      // Showene er kopi-pynt; en alternativ dato uten dem er fortsatt riktig.
      debugPrint('Copy gig_shows to option failed: $e');
    }
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

}
