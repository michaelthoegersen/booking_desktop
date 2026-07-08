import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/company_branding.dart';

class BrandingService {
  static final _sb = Supabase.instance.client;

  /// Cache per company so we don't hit DB on every PDF export.
  static final Map<String, CompanyBranding?> _cache = {};

  static void clearCache([String? companyId]) {
    if (companyId != null) {
      _cache.remove(companyId);
    } else {
      _cache.clear();
    }
  }

  /// Load branding for a company. Returns null if none configured.
  static Future<CompanyBranding?> load(String companyId) async {
    if (_cache.containsKey(companyId)) return _cache[companyId];

    try {
      final res = await _sb
          .from('company_branding')
          .select()
          .eq('company_id', companyId)
          .maybeSingle();

      final branding =
          res != null ? CompanyBranding.fromJson(res) : null;
      _cache[companyId] = branding;
      return branding;
    } catch (e) {
      debugPrint('BrandingService.load error: $e');
      return null;
    }
  }

  /// Upsert branding for a company.
  static Future<void> save(CompanyBranding branding) async {
    try {
      await _sb.from('company_branding').upsert(
        branding.toJson(),
        onConflict: 'company_id',
      );
      _cache[branding.companyId] = branding;
    } catch (e) {
      debugPrint('BrandingService.save error: $e');
      rethrow;
    }
  }

  /// Upload logo to Supabase Storage and return the public URL.
  static Future<String> uploadLogo({
    required String companyId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final ext = filename.split('.').last.toLowerCase();
    final path = '$companyId/logo.$ext';

    await _sb.storage.from('company-logos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final url =
        _sb.storage.from('company-logos').getPublicUrl(path);
    return url;
  }

  /// Download logo bytes from a URL for PDF embedding.
  static Future<Uint8List?> downloadLogoBytes(String url) async {
    try {
      // Extract storage path from public URL
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      // URL format: .../storage/v1/object/public/company-logos/companyId/logo.png
      final bucketIdx = segments.indexOf('company-logos');
      if (bucketIdx < 0) return null;
      final path = segments.sublist(bucketIdx + 1).join('/');

      return await _sb.storage.from('company-logos').download(path);
    } catch (e) {
      debugPrint('BrandingService.downloadLogoBytes error: $e');
      return null;
    }
  }
}
