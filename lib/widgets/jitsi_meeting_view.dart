import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Jitsi Meet helper.
///
/// On desktop, WebRTC is not supported in WKWebView, so we open
/// the meeting in the system browser and show an in-app banner.
class JitsiMeetingHelper {
  static String roomUrl(String roomName) {
    final safeRoom = roomName.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
    return 'https://meet.jit.si/$safeRoom';
  }

  static Future<void> launchMeeting({
    required String roomName,
    required String displayName,
  }) async {
    final safeRoom = roomName.replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
    final config = Uri.encodeComponent('{"startWithAudioMuted":false,"startWithVideoMuted":false,"prejoinPageEnabled":false}');
    final userInfo = Uri.encodeComponent('{"displayName":"$displayName"}');
    final url = 'https://meet.jit.si/$safeRoom#config=$config&userInfo=$userInfo';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// In-app banner shown when a video meeting is active in the browser.
class JitsiMeetingBanner extends StatelessWidget {
  final String roomName;
  final VoidCallback onRejoin;
  final VoidCallback onStop;

  const JitsiMeetingBanner({
    super.key,
    required this.roomName,
    required this.onRejoin,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1a56db), Color(0xFF1e40af)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.videocam, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Videomøte pågår i nettleseren',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onRejoin,
            icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white70),
            label: const Text('Åpne igjen',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          TextButton.icon(
            onPressed: onStop,
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
            label: const Text('Avslutt',
                style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
