import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/active_company.dart';

/// OAuth2 Authorization Code + PKCE flow for Microsoft Graph (delegated).
/// Allows sending email as the signed-in user (e.g. sales@coachservicescandinavia.com).
class MicrosoftOAuthService {
  static SupabaseClient get _sb => Supabase.instance.client;

  static const _clientId = 'c9a7931d-973f-4278-90d6-f825250d4b49';
  static const _redirectPort = 8643;
  static const _redirectUri = 'http://localhost:$_redirectPort/callback';
  static const _scope = 'Mail.Send offline_access User.Read';

  // Cache: companyId → {access_token, expires_at, email}
  static final Map<String, Map<String, dynamic>> _tokenCache = {};

  // ── Connect ─────────────────────────────────────────────

  /// Opens Microsoft login in browser, captures auth code via local server,
  /// exchanges for tokens, and stores refresh token in Supabase.
  static Future<bool> connect() async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) throw Exception('No active company');

    // Generate PKCE
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    // Use "organizations" for multi-tenant (any work/school account)
    final authorizeUrl = Uri.https(
      'login.microsoftonline.com',
      '/organizations/oauth2/v2.0/authorize',
      {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': _scope,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'prompt': 'select_account',
      },
    );

    // Start local HTTP server
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);

    final launched = await launchUrl(authorizeUrl, mode: LaunchMode.externalApplication);
    if (!launched) {
      await server.close();
      throw Exception('Could not open browser');
    }

    try {
      final request = await server.first.timeout(const Duration(minutes: 5));
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      if (error != null) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body style="font-family:sans-serif;text-align:center;padding:60px">'
            '<h2>Login failed</h2>'
            '<p>$error: ${request.uri.queryParameters['error_description'] ?? ''}</p>'
            '</body></html>',
          );
        await request.response.close();
        await server.close();
        throw Exception('OAuth error: $error');
      }

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body style="font-family:sans-serif;text-align:center;padding:60px">'
          '<h2>Connected!</h2>'
          '<p>You can close this window and return to TourFlow.</p>'
          '</body></html>',
        );
      await request.response.close();
      await server.close();

      if (code == null || code.isEmpty) {
        throw Exception('No authorization code received');
      }

      // Exchange code for tokens
      final tokens = await _exchangeCode(code, codeVerifier);
      final accessToken = tokens['access_token'] as String;
      final refreshToken = tokens['refresh_token'] as String?;
      final expiresIn = tokens['expires_in'] as int? ?? 3600;

      // Get user email from Graph
      final email = await _getUserEmail(accessToken);

      // Store refresh token in Supabase
      await _sb.from('microsoft_oauth_tokens').upsert({
        'company_id': companyId,
        'email': email,
        'refresh_token': refreshToken ?? '',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'company_id');

      // Cache access token
      _tokenCache[companyId] = {
        'access_token': accessToken,
        'expires_at': DateTime.now().add(Duration(seconds: expiresIn - 60)),
        'email': email,
      };

      debugPrint('Microsoft OAuth: connected as $email for company $companyId');
      return true;
    } catch (e) {
      await server.close();
      rethrow;
    }
  }

  // ── Status ──────────────────────────────────────────────

  /// Returns the connected email for the active company, or null.
  static Future<String?> getConnectedEmail({String? companyId}) async {
    final cid = companyId ?? activeCompanyNotifier.value?.id;
    if (cid == null) return null;

    // Check cache first
    final cached = _tokenCache[cid];
    if (cached != null) return cached['email'] as String?;

    // Check database
    final row = await _sb
        .from('microsoft_oauth_tokens')
        .select('email')
        .eq('company_id', cid)
        .maybeSingle();

    return row?['email'] as String?;
  }

  // ── Disconnect ──────────────────────────────────────────

  static Future<void> disconnect() async {
    final companyId = activeCompanyNotifier.value?.id;
    if (companyId == null) return;

    await _sb
        .from('microsoft_oauth_tokens')
        .delete()
        .eq('company_id', companyId);

    _tokenCache.remove(companyId);
  }

  // ── Get Access Token (for sending) ──────────────────────

  /// Returns a valid access token for the company, refreshing if needed.
  /// Returns null if no OAuth connection exists.
  static Future<String?> getAccessToken({String? companyId}) async {
    final cid = companyId ?? activeCompanyNotifier.value?.id;
    if (cid == null) return null;

    // Check cache
    final cached = _tokenCache[cid];
    if (cached != null) {
      final expiresAt = cached['expires_at'] as DateTime;
      if (DateTime.now().isBefore(expiresAt)) {
        return cached['access_token'] as String;
      }
    }

    // Load refresh token from DB
    final row = await _sb
        .from('microsoft_oauth_tokens')
        .select()
        .eq('company_id', cid)
        .maybeSingle();

    if (row == null) return null;

    final refreshToken = row['refresh_token'] as String? ?? '';
    if (refreshToken.isEmpty) return null;

    // Refresh
    try {
      final tokens = await _refreshAccessToken(refreshToken);
      final accessToken = tokens['access_token'] as String;
      final newRefresh = tokens['refresh_token'] as String?;
      final expiresIn = tokens['expires_in'] as int? ?? 3600;
      final email = row['email'] as String? ?? '';

      // Update refresh token if rotated
      if (newRefresh != null && newRefresh != refreshToken) {
        await _sb.from('microsoft_oauth_tokens').update({
          'refresh_token': newRefresh,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('company_id', cid);
      }

      // Cache
      _tokenCache[cid] = {
        'access_token': accessToken,
        'expires_at': DateTime.now().add(Duration(seconds: expiresIn - 60)),
        'email': email,
      };

      return accessToken;
    } catch (e) {
      debugPrint('Microsoft OAuth refresh failed: $e');
      return null;
    }
  }

  /// Returns the sender email for the company (from OAuth connection).
  static Future<String?> getSenderEmail({String? companyId}) async {
    final cid = companyId ?? activeCompanyNotifier.value?.id;
    if (cid == null) return null;

    final cached = _tokenCache[cid];
    if (cached != null) return cached['email'] as String?;

    final row = await _sb
        .from('microsoft_oauth_tokens')
        .select('email')
        .eq('company_id', cid)
        .maybeSingle();

    return row?['email'] as String?;
  }

  // ── Token Exchange ──────────────────────────────────────

  static Future<Map<String, dynamic>> _exchangeCode(
    String code,
    String codeVerifier,
  ) async {
    final url = Uri.parse(
      'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
    );

    final res = await HttpClient()
        .postUrl(url)
        .then((req) {
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write(Uri(queryParameters: {
        'client_id': _clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': codeVerifier,
        'scope': _scope,
      }).query);
      return req.close();
    });

    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('Token exchange failed (${res.statusCode}): $body');
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _refreshAccessToken(
    String refreshToken,
  ) async {
    final url = Uri.parse(
      'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
    );

    final res = await HttpClient()
        .postUrl(url)
        .then((req) {
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.write(Uri(queryParameters: {
        'client_id': _clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'scope': _scope,
      }).query);
      return req.close();
    });

    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('Token refresh failed (${res.statusCode}): $body');
    }

    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<String> _getUserEmail(String accessToken) async {
    final url = Uri.parse('https://graph.microsoft.com/v1.0/me');

    final res = await HttpClient()
        .getUrl(url)
        .then((req) {
      req.headers.set('Authorization', 'Bearer $accessToken');
      return req.close();
    });

    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('Failed to get user info: $body');
    }

    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['mail'] as String? ??
        data['userPrincipalName'] as String? ??
        '';
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
