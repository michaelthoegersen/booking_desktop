import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'agora_meeting_view.dart';
import 'agora_meeting_stub.dart'
    if (dart.library.js_interop) 'agora_meeting_view_web.dart';

/// Global overlay that listens for incoming video calls via Supabase Realtime.
/// Place this as a child of a Stack at the app shell level.
class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  final _sb = Supabase.instance.client;
  RealtimeChannel? _channel;

  Map<String, dynamic>? _incomingCall;
  String _callerName = '';
  Timer? _autoDeclineTimer;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _autoDeclineTimer?.cancel();
    super.dispose();
  }

  void _subscribe() {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return;

    _channel = _sb.channel('video_calls_$myId');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'video_calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'callee_id',
            value: myId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row['status'] == 'ringing') {
              _onIncomingCall(row);
            }
          },
        )
        .subscribe();
  }

  Future<void> _onIncomingCall(Map<String, dynamic> call) async {
    // Look up caller name
    final callerId = call['caller_id'] as String;
    try {
      final profile = await _sb
          .from('profiles')
          .select('name')
          .eq('id', callerId)
          .maybeSingle();
      _callerName = (profile?['name'] as String?) ?? 'Ukjent';
    } catch (_) {
      _callerName = 'Ukjent';
    }

    if (mounted) {
      setState(() => _incomingCall = call);
    }

    // Auto-decline after 30 seconds
    _autoDeclineTimer?.cancel();
    _autoDeclineTimer = Timer(const Duration(seconds: 30), () {
      if (_incomingCall != null) {
        _decline();
      }
    });
  }

  Future<void> _answer() async {
    final call = _incomingCall;
    if (call == null) return;

    _autoDeclineTimer?.cancel();

    // Update status
    await _sb
        .from('video_calls')
        .update({'status': 'answered', 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', call['id']);

    final channelName = call['channel_name'] as String;
    final myName = await _getMyName();

    setState(() => _incomingCall = null);

    if (mounted) {
      // Show video call dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 800,
              height: 600,
              child: kIsWeb
                  ? AgoraMeetingViewWeb(
                      channelName: channelName,
                      displayName: myName,
                      onLeave: () => Navigator.of(ctx).pop(),
                    )
                  : AgoraMeetingView(
                      channelName: channelName,
                      displayName: myName,
                      onLeave: () => Navigator.of(ctx).pop(),
                    ),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _decline() async {
    final call = _incomingCall;
    if (call == null) return;

    _autoDeclineTimer?.cancel();

    await _sb
        .from('video_calls')
        .update({'status': 'declined', 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', call['id']);

    if (mounted) setState(() => _incomingCall = null);
  }

  Future<String> _getMyName() async {
    final myId = _sb.auth.currentUser?.id;
    if (myId == null) return 'Deltaker';
    try {
      final profile = await _sb
          .from('profiles')
          .select('name')
          .eq('id', myId)
          .maybeSingle();
      return (profile?['name'] as String?) ?? 'Deltaker';
    } catch (_) {
      return 'Deltaker';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_incomingCall == null) return const SizedBox.shrink();

    return Positioned(
      top: 20,
      right: 20,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a1a),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam, color: Colors.white, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Innkommende videosamtale',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _decline,
                      icon: const Icon(Icons.call_end, size: 20),
                      label: const Text('Avslå'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _answer,
                      icon: const Icon(Icons.videocam, size: 20),
                      label: const Text('Svar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
