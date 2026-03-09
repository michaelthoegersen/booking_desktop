import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/active_company.dart';

class DropboxOAuthService {
  static SupabaseClient get _sb => Supabase.instance.client;

  static const _redirectPort = 8642;
  static const _redirectUri = 'http://localhost:$_redirectPort/callback';

  // ── Connect ─────────────────────────────────────────────

  /// Opens Dropbox OAuth2 in the browser (PKCE flow),
  /// starts a local HTTP server to capture the callback,
  /// then exchanges the code via the edge function.
  static Future<bool> connect({required String appKey}) async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) throw Exception('No active company');

    // Generate PKCE
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    // Build authorize URL
    final authorizeUrl = Uri.https('www.dropbox.com', '/oauth2/authorize', {
      'client_id': appKey,
      'response_type': 'code',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'redirect_uri': _redirectUri,
      'token_access_type': 'offline',
    });

    // Start local HTTP server to listen for the callback
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

    // Open browser
    final launched = await launchUrl(authorizeUrl, mode: LaunchMode.externalApplication);
    if (!launched) {
      await server.close();
      throw Exception('Could not open browser');
    }

    try {
      // Wait for callback (timeout after 5 min)
      final request = await server.first.timeout(const Duration(minutes: 5));
      final code = request.uri.queryParameters['code'];

      // Respond to the browser
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:sans-serif;text-align:center;padding:60px">'
          '<h2>Tilkoblet!</h2>'
          '<p>Du kan lukke dette vinduet og gå tilbake til TourFlow.</p>'
          '</body></html>',
        );
      await request.response.close();
      await server.close();

      if (code == null || code.isEmpty) {
        throw Exception('No authorization code received');
      }

      // Exchange code via edge function
      final res = await _sb.functions.invoke('dropbox-auth', body: {
        'action': 'exchange',
        'company_id': companyId,
        'code': code,
        'code_verifier': codeVerifier,
        'redirect_uri': _redirectUri,
      });

      final data = res.data as Map<String, dynamic>?;
      return data?['connected'] == true;
    } catch (e) {
      await server.close();
      rethrow;
    }
  }

  // ── Status ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> status() async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return {'connected': false};

    final res = await _sb.functions.invoke('dropbox-auth', body: {
      'action': 'status',
      'company_id': companyId,
    });

    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── Disconnect ──────────────────────────────────────────

  static Future<void> disconnect() async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return;

    await _sb.functions.invoke('dropbox-auth', body: {
      'action': 'disconnect',
      'company_id': companyId,
    });
  }

  // ── List folder ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> listFolder(String path) async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return [];

    final res = await _sb.functions.invoke('dropbox-list-folder', body: {
      'company_id': companyId,
      'path': path,
    });

    final data = res.data as Map<String, dynamic>?;
    final entries = data?['entries'] as List?;
    return entries?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  // ── PKCE Helpers ────────────────────────────────────────

  static String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _generateCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
