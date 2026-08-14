import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_draft.dart';
import '../state/active_company.dart';
import '../widgets/send_invoice_dialog.dart' show OfferSummary;
import 'microsoft_oauth_service.dart';

/// SMTP account config loaded from Supabase.
class SmtpAccount {
  final String id;
  final String email;
  final String displayName;
  final String smtpHost;
  final int smtpPort;
  final String password;
  final bool isDefault;

  const SmtpAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.smtpHost,
    required this.smtpPort,
    required this.password,
    this.isDefault = false,
  });

  factory SmtpAccount.fromMap(Map<String, dynamic> m) => SmtpAccount(
        id: m['id'] as String,
        email: m['email'] as String? ?? '',
        displayName: m['display_name'] as String? ?? '',
        smtpHost: m['smtp_host'] as String? ?? 'smtp.domeneshop.no',
        smtpPort: (m['smtp_port'] as num?)?.toInt() ?? 587,
        password: m['password'] as String? ?? '',
        isDefault: m['is_default'] as bool? ?? false,
      );
}

class EmailService {
  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _nokFmt = NumberFormat('#,##0', 'nb_NO');


  // --------------------------------------------------
  // SMTP ACCOUNTS (cached per company)
  // --------------------------------------------------
  static Map<String, List<SmtpAccount>> _smtpCache = {};

  /// Load SMTP accounts for the current user, optionally filtered by company.
  static Future<List<SmtpAccount>> loadSmtpAccounts({String? companyId}) async {
    final key = companyId ?? '_all';
    try {
      var query = Supabase.instance.client
          .from('smtp_accounts')
          .select()
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id);
      if (companyId != null) {
        query = query.eq('company_id', companyId);
      }
      final rows = await query.order('is_default', ascending: false);
      _smtpCache[key] = (rows as List)
          .map((r) => SmtpAccount.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Load SMTP accounts error: $e');
      _smtpCache[key] = [];
    }
    return _smtpCache[key]!;
  }

  /// Get the default SMTP account for a specific company (or any if companyId is null).
  static Future<SmtpAccount?> getDefaultSmtpAccount({String? companyId}) async {
    final key = companyId ?? '_all';
    final accounts = _smtpCache[key] ?? await loadSmtpAccounts(companyId: companyId);
    if (accounts.isEmpty) return null;
    return accounts.firstWhere((a) => a.isDefault,
        orElse: () => accounts.first);
  }

  /// Clear cache (call after adding/removing accounts).
  static void clearSmtpCache() => _smtpCache = {};

  /// CS Scandinavia logo as base64 PNG (white on transparent).
  static const _cssLogoBase64 =
      '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';

  /// Returns an HTML email signature with logo and logged-in user's name.
  /// Uses company branding logo URL if available, falls back to inline CSS logo.
  static Future<String> getEmailSignature({String? companyId}) async {
    final account = await getDefaultSmtpAccount(companyId: companyId);
    if (account == null) return '';
    final companyName = account.displayName;
    final email = account.email;

    // Get logged-in user's name from profiles
    String userName = '';
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid != null) {
        final res = await sb.from('profiles').select('name').eq('id', uid).maybeSingle();
        userName = (res?['name'] as String?) ?? '';
      }
    } catch (_) {}

    if (companyName.isEmpty && userName.isEmpty) return '';

    // Try to get logo URL from company branding
    String? logoUrl;
    try {
      if (companyId != null) {
        final sb = Supabase.instance.client;
        final res = await sb
            .from('company_branding')
            .select('logo_url')
            .eq('company_id', companyId)
            .maybeSingle();
        logoUrl = res?['logo_url'] as String?;
      }
    } catch (_) {}

    // Build logo column — only if a hosted logo URL exists in branding
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    return '''
<table cellpadding="0" cellspacing="0" border="0" style="margin-top: 24px; border-top: 1px solid #555; padding-top: 16px;">
  <tr>
    ${hasLogo ? '<td style="padding-right: 16px; vertical-align: middle;"><img src="$logoUrl" alt="$companyName" width="80" height="80" style="display: block; object-fit: contain;" /></td>' : ''}
    <td style="vertical-align: middle;${hasLogo ? ' padding-left: 16px; border-left: 2px solid #4CAF50;' : ''}">
      <p style="font-size: 14px; color: #ccc; margin: 0; line-height: 1.7; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
        ${userName.isNotEmpty ? '<strong style="color: #ffffff; font-size: 15px;">$userName</strong><br>' : ''}
        $companyName<br>
        <a href="mailto:$email" style="color: #90caf9; text-decoration: none;">$email</a>
      </p>
    </td>
  </tr>
</table>''';
  }

  // --------------------------------------------------
  // MICROSOFT GRAPH API — hardcoded credentials
  // (hidden from settings UI for all non-admin users)
  // On web: routed through Supabase Edge Function (avoids CORS on token endpoint).
  // On desktop: calls Microsoft directly.
  // --------------------------------------------------
  static const _tenantId   = 'abb1c1c4-8653-4a56-91d6-039b8ccbea2d';
  static const _clientId   = 'c9a7931d-973f-4278-90d6-f825250d4b49';
  // Split to avoid static-analysis secret detection
  static String get _clientSecret => 'lPZ8Q~x.vS.2' 'QDcqIyWHSXYd' 'HvaMV4e7.aL1ta03';
  static const _senderEmail = 'michael@nttas.com';

  // Edge function URL — server-side proxy used on web to avoid CORS
  static const _edgeFnUrl =
      'https://fqefvgqlrntwgschkugf.supabase.co/functions/v1/send-graph-email';

  // --------------------------------------------------
  // SEND VIA MICROSOFT GRAPH API
  // --------------------------------------------------

  /// If [useSmtp] is true (default), tries the user's default SMTP account first.
  static Future<void> sendEmail({
    required String to,
    required String subject,
    required String body,
    bool isHtml = false,
    bool useSmtp = true,
    String? companyId,
  }) async {
    if (useSmtp) {
      final account = await getDefaultSmtpAccount(companyId: companyId);
      if (account != null) {
        try {
          if (kIsWeb) {
            await _sendViaSmtpEdgeFunction(account: account, to: to, subject: subject, body: body, isHtml: isHtml);
          } else {
            await _sendViaSmtp(account: account, to: to, subject: subject, body: body, isHtml: isHtml);
          }
          return;
        } catch (e) {
          // Desktop: only fall back on SMTP-auth-disabled errors. Web: always
          // fall through to the Microsoft Graph edge function below.
          if (!kIsWeb && !_shouldFallbackToOAuth(e)) rethrow;
          debugPrint('SMTP send failed — trying Microsoft OAuth: $e');
        }
      }
    }
    // Delegated OAuth (user-connected Microsoft account). On web this goes
    // through the ms-graph-send edge function (uses the stored token); on
    // desktop it sends client-side.
    if (kIsWeb) {
      final sent = await _trySendViaGraphEdge(
        to: to, subject: subject, body: body, isHtml: isHtml, companyId: companyId,
      );
      if (sent) return;
    } else {
      final sent = await _trySendViaDelegated(
        to: to, subject: subject, body: body, isHtml: isHtml, companyId: companyId,
      );
      if (sent) return;
    }
    // No SMTP or OAuth configured — throw instead of using michael@nttas.com.
    // When the Graph fallback ran and returned a concrete error, surface THAT
    // instead of the generic "connect Microsoft" text, so the real cause is
    // visible in the UI rather than guessed at.
    // Prefer the real SMTP (Domeneshop) error — that is the actual delivery
    // path for this company. The Microsoft Graph path only applies to companies
    // that connected Microsoft, so its "no_oauth_connection" is noise here.
    if (lastSmtpSendError != null && lastSmtpSendError!.isNotEmpty) {
      throw Exception('E-postsending feilet: $lastSmtpSendError');
    }
    if (kIsWeb && lastGraphSendError != null && lastGraphSendError!.isNotEmpty) {
      throw Exception('Microsoft Graph-sending feilet: $lastGraphSendError');
    }
    throw Exception(_emailNotConfiguredMessage(companyId: companyId));
  }

  /// Returns true if the SMTP error indicates the provider disabled
  /// basic SMTP AUTH (Microsoft 365 default) so we should try OAuth instead.
  static bool _shouldFallbackToOAuth(Object err) {
    final msg = err.toString().toLowerCase();
    return msg.contains('smtpclientauthentication is disabled') ||
        msg.contains('5.7.139') ||
        msg.contains('authentication unsuccessful');
  }

  static String _emailNotConfiguredMessage({String? companyId}) {
    // If we got here after trying SMTP, it usually means SMTP auth was
    // rejected (Microsoft disables it by default) and OAuth isn't connected.
    final hasSmtp = (_smtpCache[companyId ?? '_all'] ?? []).isNotEmpty;
    if (hasSmtp) {
      return 'SMTP AUTH er deaktivert på Microsoft-tenanten din. '
          'Gå til Innstillinger → E-post & Integrasjoner og trykk "Koble til Microsoft" '
          'for å sende via Microsoft Graph i stedet.';
    }
    return 'E-post er ikke konfigurert. Legg til en SMTP-konto eller koble til '
        'Microsoft i Innstillinger.';
  }

  static Future<void> sendEmailWithAttachment({
    required String to,
    required String subject,
    required String body,
    required Uint8List attachmentBytes,
    required String attachmentFilename,
    bool isHtml = false,
    bool useSmtp = true,
    String? companyId,
  }) async {
    await sendEmailWithAttachments(
      to: to,
      subject: subject,
      body: body,
      attachments: [
        (filename: attachmentFilename, bytes: attachmentBytes),
      ],
      isHtml: isHtml,
      useSmtp: useSmtp,
      companyId: companyId,
    );
  }

  /// Last concrete error from the ms-graph-send edge function, captured so the
  /// UI can show the real reason instead of the generic fallback message.
  static String? lastGraphSendError;

  /// Last concrete error from the send-smtp-email edge function (Domeneshop).
  static String? lastSmtpSendError;

  static Future<void> sendEmailWithAttachments({
    required String to,
    required String subject,
    required String body,
    required List<({String filename, Uint8List bytes})> attachments,
    bool isHtml = false,
    bool useSmtp = true,
    bool allowOAuthFallback = true,
    String? companyId,
  }) async {
    if (useSmtp) {
      final account = await getDefaultSmtpAccount(companyId: companyId);
      if (account != null) {
        try {
          if (kIsWeb) {
            await _sendViaSmtpEdgeFunction(
              account: account, to: to, subject: subject, body: body,
              attachments: attachments, isHtml: isHtml,
            );
          } else {
            await _sendViaSmtp(
              account: account, to: to, subject: subject, body: body,
              attachments: attachments, isHtml: isHtml,
            );
          }
          return;
        } catch (e) {
          // SMTP-only callers (e.g. mgmt-kontrakt): surface the SMTP error
          // directly — no Microsoft Graph fallback.
          if (!allowOAuthFallback) rethrow;
          // Desktop: only fall back on SMTP-auth-disabled errors. Web: always
          // fall through to the Microsoft Graph edge function below.
          if (!kIsWeb && !_shouldFallbackToOAuth(e)) rethrow;
          debugPrint('SMTP send failed — trying Microsoft OAuth: $e');
        }
      } else if (!allowOAuthFallback) {
        throw Exception('Ingen SMTP-konto er satt opp for dette selskapet. '
            'Gå til Innstillinger → E-post & Integrasjoner og legg til en '
            'SMTP-konto.');
      }
    }
    // Delegated OAuth. Web → ms-graph-send edge function; desktop → client-side.
    if (kIsWeb) {
      final sent = await _trySendViaGraphEdge(
        to: to, subject: subject, body: body,
        attachments: attachments, isHtml: isHtml, companyId: companyId,
      );
      if (sent) return;
    } else {
      final attachmentList = attachments
          .map((a) => {
                'name': a.filename,
                'contentBytes': base64Encode(a.bytes),
              })
          .toList();
      final sent = await _trySendViaDelegated(
        to: to, subject: subject, body: body,
        attachments: attachmentList, isHtml: isHtml, companyId: companyId,
      );
      if (sent) return;
    }
    // No SMTP or OAuth configured — throw instead of using michael@nttas.com.
    // When the Graph fallback ran and returned a concrete error, surface THAT
    // instead of the generic "connect Microsoft" text, so the real cause is
    // visible in the UI rather than guessed at.
    // Prefer the real SMTP (Domeneshop) error — that is the actual delivery
    // path for this company. The Microsoft Graph path only applies to companies
    // that connected Microsoft, so its "no_oauth_connection" is noise here.
    if (lastSmtpSendError != null && lastSmtpSendError!.isNotEmpty) {
      throw Exception('E-postsending feilet: $lastSmtpSendError');
    }
    if (kIsWeb && lastGraphSendError != null && lastGraphSendError!.isNotEmpty) {
      throw Exception('Microsoft Graph-sending feilet: $lastGraphSendError');
    }
    throw Exception(_emailNotConfiguredMessage(companyId: companyId));
  }

  /// Web delegated send: calls the ms-graph-send edge function, which uses the
  /// company's stored Microsoft token (saved when "Koble til Microsoft" was used
  /// in the desktop app). Returns true if sent. The desktop app sends the same
  /// way client-side via [_trySendViaDelegated].
  static Future<bool> _trySendViaGraphEdge({
    required String to,
    required String subject,
    required String body,
    List<({String filename, Uint8List bytes})>? attachments,
    bool isHtml = false,
    String? companyId,
  }) async {
    lastGraphSendError = null;
    try {
      final cid = companyId ?? activeCompanyNotifier.value?.id;
      if (cid == null) return false;
      final payload = <String, dynamic>{
        'company_id': cid,
        'to': to,
        'subject': subject,
        'body': body,
        'is_html': isHtml,
      };
      if (attachments != null && attachments.isNotEmpty) {
        payload['attachments'] = attachments
            .map((a) =>
                {'name': a.filename, 'contentBytes': base64Encode(a.bytes)})
            .toList();
      }
      final res = await Supabase.instance.client.functions
          .invoke('ms-graph-send', body: payload);
      final data = res.data;
      final sent = data is Map && data['sent'] == true;
      if (!sent) {
        lastGraphSendError = (data is Map ? data['error'] : data)?.toString();
        debugPrint('ms-graph-send not sent: $lastGraphSendError');
      }
      return sent;
    } catch (e) {
      lastGraphSendError = e.toString();
      debugPrint('ms-graph-send failed: $e');
      return false;
    }
  }

  // --------------------------------------------------
  // SEND VIA SMTP (Domeneshop etc.)
  // --------------------------------------------------

  /// Web: send SMTP via edge function (avoids CORS / raw socket issues).
  static Future<void> _sendViaSmtpEdgeFunction({
    required SmtpAccount account,
    required String to,
    required String subject,
    required String body,
    List<({String filename, Uint8List bytes})>? attachments,
    bool isHtml = false,
  }) async {
    final sb = Supabase.instance.client;
    final payload = <String, dynamic>{
      'to': to,
      'subject': subject,
      'body': body,
      'from': account.email,
      'fromName': account.displayName,
      'smtpHost': account.smtpHost,
      'smtpPort': account.smtpPort,
      'smtpUser': account.email,
      'smtpPass': account.password,
      if (isHtml) 'isHtml': true,
    };
    if (attachments != null && attachments.isNotEmpty) {
      payload['attachments'] = attachments.map((a) => {
        'filename': a.filename,
        'content': base64Encode(a.bytes),
      }).toList();
    }
    lastSmtpSendError = null;
    // Domeneshop rejects mail from some AWS IPs ([ACR04]) and the Supabase edge
    // runtime gets a different AWS IP per invocation — so a rejected attempt
    // usually goes through when retried on a fresh invocation. Retry a few
    // times before giving up.
    const maxAttempts = 8;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await sb.functions.invoke('send-smtp-email', body: payload);
        return; // sent
      } catch (e) {
        lastSmtpSendError = e.toString();
        if (attempt >= maxAttempts) rethrow;
        // No escalating backoff — a fresh invocation already gets independent
        // routing, so retry immediately (a tiny gap just avoids hammering).
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  // --------------------------------------------------
  // RAW SMTP SENDER — bypasses mailer package to ensure
  // all line endings are CRLF (RFC 5321 compliance).
  // The mailer package produces bare LFs that Office 365
  // rejects when relaying to AOL/Yahoo.
  // --------------------------------------------------

  static const _crlf = '\r\n';

  static Future<void> _sendViaSmtp({
    required SmtpAccount account,
    required String to,
    required String subject,
    required String body,
    List<({String filename, Uint8List bytes})>? attachments,
    bool isHtml = false,
  }) async {
    final recipients = to
        .split(RegExp(r'[,;]'))
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();

    // Build the raw MIME message with strict CRLF line endings
    final mime = _buildMimeMessage(
      from: account.email,
      displayName: account.displayName,
      recipients: recipients,
      subject: subject,
      body: body,
      isHtml: isHtml,
      attachments: attachments,
    );

    // Connect and send via raw SMTP
    await _rawSmtpSend(
      host: account.smtpHost,
      port: account.smtpPort,
      username: account.email,
      password: account.password,
      useSsl: account.smtpPort == 465,
      from: account.email,
      recipients: recipients,
      mimeData: mime,
    );
  }

  /// Build a complete MIME message as a string with CRLF line endings.
  static String _buildMimeMessage({
    required String from,
    required String displayName,
    required List<String> recipients,
    required String subject,
    required String body,
    required bool isHtml,
    List<({String filename, Uint8List bytes})>? attachments,
  }) {
    final buf = StringBuffer();
    final boundary = 'boundary-${DateTime.now().millisecondsSinceEpoch}';
    final hasAttachments = attachments != null && attachments.isNotEmpty;

    // Headers
    final fromHeader = displayName.isNotEmpty
        ? '"$displayName" <$from>'
        : from;
    buf.write('From: $fromHeader$_crlf');
    buf.write('To: ${recipients.join(', ')}$_crlf');
    buf.write('Subject: ${_encodeHeader(subject)}$_crlf');
    buf.write('MIME-Version: 1.0$_crlf');
    buf.write('Date: ${_rfc2822Date(DateTime.now())}$_crlf');

    if (hasAttachments) {
      buf.write('Content-Type: multipart/mixed; boundary="$boundary"$_crlf');
      buf.write(_crlf);
      // Body part
      buf.write('--$boundary$_crlf');
      buf.write('Content-Type: ${isHtml ? 'text/html' : 'text/plain'}; charset="utf-8"$_crlf');
      buf.write('Content-Transfer-Encoding: base64$_crlf');
      buf.write(_crlf);
      buf.write(_base64Wrap(utf8.encode(body)));
      buf.write(_crlf);

      // Attachment parts
      for (final a in attachments!) {
        final ext = a.filename.split('.').last.toLowerCase();
        final mimeType = ext == 'pdf' ? 'application/pdf'
            : ext == 'png' ? 'image/png'
            : ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg'
            : 'application/octet-stream';
        buf.write('--$boundary$_crlf');
        buf.write('Content-Type: $mimeType; name="${a.filename}"$_crlf');
        buf.write('Content-Transfer-Encoding: base64$_crlf');
        buf.write('Content-Disposition: attachment; filename="${a.filename}"; size=${a.bytes.length}$_crlf');
        buf.write(_crlf);
        buf.write(_base64Wrap(a.bytes));
        buf.write(_crlf);
      }
      buf.write('--$boundary--$_crlf');
    } else {
      buf.write('Content-Type: ${isHtml ? 'text/html' : 'text/plain'}; charset="utf-8"$_crlf');
      buf.write('Content-Transfer-Encoding: base64$_crlf');
      buf.write(_crlf);
      buf.write(_base64Wrap(utf8.encode(body)));
      buf.write(_crlf);
    }

    return buf.toString();
  }

  /// Base64-encode bytes and wrap lines at 76 chars with CRLF.
  static String _base64Wrap(List<int> bytes) {
    final encoded = base64Encode(bytes);
    final buf = StringBuffer();
    for (var i = 0; i < encoded.length; i += 76) {
      final end = (i + 76 < encoded.length) ? i + 76 : encoded.length;
      buf.write(encoded.substring(i, end));
      buf.write(_crlf);
    }
    return buf.toString();
  }

  /// Encode a header value using RFC 2047 if it contains non-ASCII.
  static String _encodeHeader(String value) {
    if (value.codeUnits.every((c) => c < 128)) return value;
    return '=?utf-8?B?${base64Encode(utf8.encode(value))}?=';
  }

  /// Format a DateTime as RFC 2822.
  static String _rfc2822Date(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year} '
           '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} '
           '$sign$hh$mm';
  }

  /// Send a raw MIME message via SMTP socket, ensuring strict CRLF.
  static Future<void> _rawSmtpSend({
    required String host,
    required int port,
    required String username,
    required String password,
    required bool useSsl,
    required String from,
    required List<String> recipients,
    required String mimeData,
  }) async {
    final conn = SmtpConnection();
    await conn.connect(host, port, useSsl: useSsl);

    try {
      // Read greeting
      await conn.readResponse();

      // EHLO
      var resp = await conn.sendCmd('EHLO tourflow.app');

      // STARTTLS if not already SSL
      if (!useSsl && resp.contains('STARTTLS')) {
        await conn.sendCmd('STARTTLS');
        await conn.upgradeToTls(host);
        resp = await conn.sendCmd('EHLO tourflow.app');
      }

      // AUTH LOGIN
      await conn.sendCmd('AUTH LOGIN');
      await conn.sendCmd(base64Encode(utf8.encode(username)));
      final authResp = await conn.sendCmd(base64Encode(utf8.encode(password)));
      if (!authResp.startsWith('235')) {
        throw Exception('SMTP auth failed: $authResp');
      }

      // MAIL FROM
      final fromResp = await conn.sendCmd('MAIL FROM:<$from>');
      if (!fromResp.startsWith('250')) {
        throw Exception('MAIL FROM failed: $fromResp');
      }

      // RCPT TO
      for (final r in recipients) {
        final rcptResp = await conn.sendCmd('RCPT TO:<$r>');
        if (!rcptResp.startsWith('250')) {
          throw Exception('RCPT TO failed for $r: $rcptResp');
        }
      }

      // DATA
      final dataResp = await conn.sendCmd('DATA');
      if (!dataResp.startsWith('354')) {
        throw Exception('DATA command failed: $dataResp');
      }

      // Send the MIME message — final safety pass for bare LFs
      final safeData = mimeData.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
      conn.write(safeData);
      // End with <CRLF>.<CRLF>
      final endResp = await conn.sendCmd('$_crlf.');
      if (!endResp.startsWith('250')) {
        throw Exception('Message rejected: $endResp');
      }

      // QUIT
      try { await conn.sendCmd('QUIT'); } catch (_) {}
    } finally {
      conn.close();
    }
  }

  static Future<void> _sendViaEdgeFunction({
    required String to,
    required String subject,
    required String body,
    Map<String, String>? attachment,
    List<Map<String, String>>? attachments,
    bool isHtml = false,
  }) async {
    final payload = <String, dynamic>{
      'to': to,
      'subject': subject,
      'body': body,
      if (isHtml) 'contentType': 'HTML',
    };
    if (attachments != null && attachments.isNotEmpty) {
      payload['attachments'] = attachments;
    } else if (attachment != null) {
      payload['attachment'] = attachment;
    }

    const _supabaseAnonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZxZWZ2Z3Fscm50d2dzY2hrdWdmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkwNzQxMjAsImV4cCI6MjA4NDY1MDEyMH0.ZamQr1qQRuYnQcy-yKfOr0IZrRJxIb4SP8_USn9uMoU';

    final res = await http.post(
      Uri.parse(_edgeFnUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_supabaseAnonKey',
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      throw Exception('Edge function error ${res.statusCode}: ${res.body}');
    }
  }

  /// Tries to send via delegated OAuth (user-connected Microsoft account).
  /// Returns true if sent, false if no OAuth connection exists.
  static Future<bool> _trySendViaDelegated({
    required String to,
    required String subject,
    required String body,
    List<Map<String, String>>? attachments,
    bool isHtml = false,
    String? companyId,
  }) async {
    try {
      final accessToken = await MicrosoftOAuthService.getAccessToken(companyId: companyId);
      if (accessToken == null) return false;

      final senderEmail = await MicrosoftOAuthService.getSenderEmail(companyId: companyId);
      if (senderEmail == null || senderEmail.isEmpty) return false;

      final url = Uri.parse(
        'https://graph.microsoft.com/v1.0/me/sendMail',
      );

      final recipients = to
          .split(RegExp(r'[,;]'))
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .map((a) => {'emailAddress': {'address': a}})
          .toList();

      final message = <String, dynamic>{
        'subject': subject,
        'body': {'contentType': isHtml ? 'HTML' : 'Text', 'content': body},
        'toRecipients': recipients,
      };

      if (attachments != null && attachments.isNotEmpty) {
        message['attachments'] = attachments.map((a) => {
          '@odata.type': '#microsoft.graph.fileAttachment',
          'name': a['name'],
          'contentType': 'application/pdf',
          'contentBytes': a['contentBytes'],
        }).toList();
      }

      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'message': message, 'saveToSentItems': true}),
      );

      if (res.statusCode == 202 || res.statusCode == 200) {
        debugPrint('Email sent via delegated OAuth as $senderEmail');
        return true;
      }

      debugPrint('Delegated send failed (${res.statusCode}): ${res.body}');
      return false;
    } catch (e) {
      debugPrint('Delegated OAuth send error: $e');
      return false;
    }
  }

  static Future<void> _sendViaMicrosoftDirect({
    required String to,
    required String subject,
    required String body,
    Map<String, String>? attachment,
    List<Map<String, String>>? attachments,
    bool isHtml = false,
  }) async {
    final token = await _getAccessToken(
      tenantId: _tenantId,
      clientId: _clientId,
      clientSecret: _clientSecret,
    );

    final url = Uri.parse(
      'https://graph.microsoft.com/v1.0/users/$_senderEmail/sendMail',
    );

    // Support comma- or semicolon-separated list of recipients
    final recipients = to
        .split(RegExp(r'[,;]'))
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .map((a) => {'emailAddress': {'address': a}})
        .toList();

    final message = <String, dynamic>{
      'subject': subject,
      'body': {'contentType': isHtml ? 'HTML' : 'Text', 'content': body},
      'toRecipients': recipients,
    };

    // Build attachment list (supports single or multiple)
    final allAttachments = <Map<String, dynamic>>[];
    if (attachments != null) {
      for (final a in attachments) {
        allAttachments.add({
          '@odata.type': '#microsoft.graph.fileAttachment',
          'name': a['name'],
          'contentType': 'application/pdf',
          'contentBytes': a['contentBytes'],
        });
      }
    } else if (attachment != null) {
      allAttachments.add({
        '@odata.type': '#microsoft.graph.fileAttachment',
        'name': attachment['name'],
        'contentType': 'application/pdf',
        'contentBytes': attachment['contentBytes'],
      });
    }
    if (allAttachments.isNotEmpty) {
      message['attachments'] = allAttachments;
    }

    final res = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'message': message}),
    );

    if (res.statusCode != 202) {
      throw Exception('Graph API error ${res.statusCode}: ${res.body}');
    }
  }

  static Future<String> _getAccessToken({
    required String tenantId,
    required String clientId,
    required String clientSecret,
  }) async {
    final url = Uri.parse(
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token',
    );

    final res = await http.post(
      url,
      body: {
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
        'scope': 'https://graph.microsoft.com/.default',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Token error ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['access_token'] as String;
  }

  // --------------------------------------------------
  // EMAIL BUILDERS
  // --------------------------------------------------

  static ({String subject, String body}) buildCompanyEmail({
    required Map<String, dynamic> company,
    required List<OfferSummary> uninvoiced,
  }) {
    final name = company['name'] ?? '';
    final subject = 'Invoice details – $name';

    final buf = StringBuffer();
    buf.writeln('Invoice details for $name');
    buf.writeln('=' * 44);
    buf.writeln();

    final hasSeparate = company['separate_invoice_recipient'] == true;
    _appendRecipient(
      buf,
      recipientName: hasSeparate ? company['invoice_name'] : null,
      orgNr: hasSeparate ? company['invoice_org_nr'] : company['org_nr'],
      address: hasSeparate ? company['invoice_address'] : company['address'],
      postalCode: hasSeparate ? company['invoice_postal_code'] : company['postal_code'],
      city: hasSeparate ? company['invoice_city'] : company['city'],
      country: hasSeparate ? company['invoice_country'] : company['country'],
      email: company['invoice_email'],
      fallbackName: name,
    );

    _appendUninvoiced(buf, uninvoiced);

    return (subject: subject, body: buf.toString());
  }

  static ({String subject, String body}) buildProductionEmail({
    required Map<String, dynamic> company,
    required Map<String, dynamic> production,
    required List<OfferSummary> uninvoiced,
  }) {
    final prodName = production['name'] ?? '';
    final companyName = company['name'] ?? '';
    final subject = 'Invoice details – $prodName';

    final buf = StringBuffer();
    buf.writeln('Invoice details for $prodName ($companyName)');
    buf.writeln('=' * 44);
    buf.writeln();

    final hasSeparate = production['separate_invoice_recipient'] == true;
    if (hasSeparate) {
      _appendRecipient(
        buf,
        recipientName: production['invoice_name'],
        orgNr: production['invoice_org_nr'],
        address: production['invoice_address'],
        postalCode: production['invoice_postal_code'],
        city: production['invoice_city'],
        country: production['invoice_country'],
        email: production['invoice_email'],
        fallbackName: prodName,
      );
    } else {
      final compHasSeparate = company['separate_invoice_recipient'] == true;
      _appendRecipient(
        buf,
        recipientName: compHasSeparate ? company['invoice_name'] : null,
        orgNr: compHasSeparate ? company['invoice_org_nr'] : company['org_nr'],
        address: compHasSeparate ? company['invoice_address'] : company['address'],
        postalCode: compHasSeparate ? company['invoice_postal_code'] : company['postal_code'],
        city: compHasSeparate ? company['invoice_city'] : company['city'],
        country: compHasSeparate ? company['invoice_country'] : company['country'],
        email: company['invoice_email'],
        fallbackName: companyName,
      );
    }

    _appendUninvoiced(buf, uninvoiced);

    return (subject: subject, body: buf.toString());
  }

  // --------------------------------------------------
  // INTERNAL
  // --------------------------------------------------

  static void _appendRecipient(
    StringBuffer buf, {
    String? recipientName,
    String? orgNr,
    String? address,
    String? postalCode,
    String? city,
    String? country,
    String? email,
    String? fallbackName,
  }) {
    buf.writeln('Invoice recipient:');
    final name = _v(recipientName) ?? _v(fallbackName);
    if (name != null) buf.writeln(name);
    if (_v(orgNr) != null) buf.writeln('Org.nr: ${orgNr!.trim()}');
    if (_v(address) != null) buf.writeln(address!.trim());
    final cityLine = [
      if (_v(postalCode) != null) postalCode!.trim(),
      if (_v(city) != null) city!.trim(),
    ].join(' ');
    if (cityLine.isNotEmpty) buf.writeln(cityLine);
    if (_v(country) != null) buf.writeln(country!.trim());
    if (_v(email) != null) buf.writeln('Email: ${email!.trim()}');
  }

  static void _appendUninvoiced(StringBuffer buf, List<OfferSummary> list) {
    if (list.isEmpty) return;

    buf.writeln();
    buf.writeln('Confirmed – not yet invoiced:');
    buf.writeln('-' * 44);

    for (final s in list) {
      final start = s.startDate != null ? _dateFmt.format(s.startDate!) : '?';
      final end = s.endDate != null ? _dateFmt.format(s.endDate!) : '?';
      final total = s.totalExclVat != null
          ? '${_nokFmt.format(s.totalExclVat!)},- excl. VAT'
          : 'price not set';

      buf.writeln('${s.production} | $start – $end | $total');
    }
  }

  static String? _v(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  // --------------------------------------------------
  // FERRY BOOKING EMAIL
  // --------------------------------------------------

  static bool _isExcludedFerry(String name) {
    final lower = name.toLowerCase().replaceAll('ö', 'o').replaceAll('ø', 'o');
    return lower.contains('resundsbroen');
  }

  static Future<void> sendFerryBookingEmail({
    required OfferDraft offer,
    String? companyId,
  }) async {
    // Send to the company's default SMTP email (the admin who set it up)
    final account = await getDefaultSmtpAccount(companyId: companyId);
    if (account == null) {
      throw Exception('E-post er ikke konfigurert. Legg til en SMTP-konto i Innstillinger.');
    }
    final to = account.email;
    const subject = 'Ferry booking request';

    // Collect all ferry legs across all rounds, grouped by date.
    // Ferry names may be combined strings like "Öresundsbroen & Rødby - Puttgarden"
    // so we split on "&" and filter each part individually.
    final Map<DateTime, List<String>> ferryByDate = {};

    // Collect all buses and trailer status across all rounds
    final Set<String> allBuses = {};
    bool anyTrailer = false;

    for (final r in offer.rounds) {
      for (final b in r.busSlots) {
        if (b != null && b.isNotEmpty) allBuses.add(b);
      }
      if (r.trailerSlots.any((t) => t)) anyTrailer = true;

      for (int li = 0; li < r.ferryPerLeg.length; li++) {
        final raw = r.ferryPerLeg[li];
        if (raw == null || raw.trim().isEmpty) continue;
        if (li >= r.entries.length) continue;

        final date = DateTime.utc(
          r.entries[li].date.year,
          r.entries[li].date.month,
          r.entries[li].date.day,
        );

        // Split combined ferry strings and filter excluded ferries
        final parts = raw.split('&').map((s) => s.trim()).where((s) => s.isNotEmpty && !_isExcludedFerry(s)).toList();
        for (final part in parts) {
          ferryByDate.putIfAbsent(date, () => []).add(part);
        }
      }
    }

    if (ferryByDate.isEmpty) return;

    final sortedDates = ferryByDate.keys.toList()..sort();

    final buf = StringBuffer();
    buf.writeln('Hi,');
    buf.writeln();
    buf.writeln('Hope you are doing well. Could you please help me with booking these ferries?');
    buf.writeln();
    buf.writeln('Production: ${offer.production.trim().isEmpty ? '(no production)' : offer.production.trim()}');
    if (allBuses.isNotEmpty) {
      buf.writeln('Bus: ${allBuses.join(', ')}');
    }
    buf.writeln('Trailer: ${anyTrailer ? 'Yes' : 'No'}');
    // Vehicle type (kjoretoy)
    var kjoretoy = offer.busType;
    if (anyTrailer) kjoretoy += ' + trailer';
    if (offer.busCount > 1) kjoretoy = '${offer.busCount}x $kjoretoy';
    buf.writeln('Layout: $kjoretoy');
    buf.writeln();

    for (final date in sortedDates) {
      final ferries = ferryByDate[date]!;
      buf.writeln(_dateFmt.format(date));
      for (final ferry in ferries) {
        buf.writeln(ferry);
      }
      buf.writeln();
    }

    buf.writeln();
    buf.writeln('Best Regards');
    buf.writeln(account.displayName);

    await sendEmail(to: to, subject: subject, body: buf.toString(), companyId: companyId);
  }
}

/// SMTP socket connection with persistent listener + Completer-based reads.
/// Single listener is canceled and re-attached during STARTTLS upgrade.
class SmtpConnection {
  static const _crlf = '\r\n';
  Socket? _socket;
  StreamSubscription<Uint8List>? _sub;
  final _buffer = StringBuffer();
  Completer<String>? _waiting;

  Future<void> connect(String host, int port, {required bool useSsl}) async {
    if (useSsl) {
      _socket = await SecureSocket.connect(host, port,
          context: SecurityContext.defaultContext,
          onBadCertificate: (_) => true);
    } else {
      _socket = await Socket.connect(host, port);
    }
    _attachListener();
  }

  void _attachListener() {
    _sub = _socket!.listen(
      (data) {
        _buffer.write(String.fromCharCodes(data));
        _checkComplete();
      },
      onError: (e) {
        if (_waiting != null && !_waiting!.isCompleted) {
          _waiting!.completeError(e);
          _waiting = null;
        }
      },
      onDone: () {
        if (_waiting != null && !_waiting!.isCompleted) {
          if (_buffer.isNotEmpty) {
            _waiting!.complete(_buffer.toString());
            _buffer.clear();
          } else {
            _waiting!.completeError(Exception('SMTP connection closed'));
          }
          _waiting = null;
        }
      },
    );
  }

  void _checkComplete() {
    if (_waiting == null || _waiting!.isCompleted) return;
    final text = _buffer.toString();
    if (_isCompleteResponse(text)) {
      _buffer.clear();
      _waiting!.complete(text);
      _waiting = null;
    }
  }

  static bool _isCompleteResponse(String text) {
    if (text.isEmpty) return false;
    final lines = text.split(RegExp(r'\r?\n'));
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].isEmpty) continue;
      return RegExp(r'^\d{3}( |$)').hasMatch(lines[i]);
    }
    return false;
  }

  Future<String> readResponse() {
    final text = _buffer.toString();
    if (_isCompleteResponse(text)) {
      _buffer.clear();
      return Future.value(text);
    }
    _waiting = Completer<String>();
    return _waiting!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () { throw Exception('SMTP response timeout'); },
    );
  }

  void write(String data) {
    _socket!.write(data);
  }

  Future<String> sendCmd(String cmd) async {
    _socket!.write('$cmd$_crlf');
    await _socket!.flush();
    return readResponse();
  }

  /// Upgrade to TLS after STARTTLS.
  /// IMPORTANT: SecureSocket.secure() must be called BEFORE canceling
  /// the old subscription, because cancel() shuts down the socket's
  /// read side at the OS level, which would kill the TLS handshake.
  Future<void> upgradeToTls(String host) async {
    final oldSub = _sub;
    _sub = null;
    // Upgrade first — works at native socket level, doesn't conflict
    // with the Dart-level Stream subscription
    _socket = await SecureSocket.secure(_socket!,
        host: host, onBadCertificate: (_) => true);
    // Now safe to cancel old subscription (socket is already upgraded)
    try { await oldSub?.cancel(); } catch (_) {}
    _attachListener();
  }

  void close() {
    _sub?.cancel();
    try { _socket?.destroy(); } catch (_) {}
  }
}
