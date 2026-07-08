import 'package:supabase_flutter/supabase_flutter.dart';
import '../state/active_company.dart';

class CustomersService {
  final SupabaseClient _client = Supabase.instance.client;

  // -----------------------------------
  // LOAD COMPANIES (filtered by owner)
  // -----------------------------------
  Future<List<Map<String, dynamic>>> getCompanies() async {
    var query = _client.from('companies').select();
    final ownerId = activeCompanyNotifier.value?.id;
    if (ownerId != null) {
      query = query.eq('owner_company_id', ownerId);
    }
    final res = await query.order('name');
    return (res as List).cast<Map<String, dynamic>>();
  }

  // -----------------------------------
  // LOAD CONTACTS
  // -----------------------------------
  Future<List<Map<String, dynamic>>> getContacts(String companyId) async {
    final res = await _client
        .from('contacts')
        .select()
        .eq('company_id', companyId)
        .order('name');

    return (res as List).cast<Map<String, dynamic>>();
  }

  // -----------------------------------
  // LOAD PRODUCTIONS
  // -----------------------------------
  Future<List<Map<String, dynamic>>> getProductions(String companyId) async {
    final res = await _client
        .from('productions')
        .select()
        .eq('company_id', companyId)
        .order('name');

    return (res as List).cast<Map<String, dynamic>>();
  }
}