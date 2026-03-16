import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const _agoraAppId = '4fe1ae5ea7454ba9adc19030d559ce74';
const _tokenUrl =
    'https://fqefvgqlrntwgschkugf.supabase.co/functions/v1/agora-token';

@JS('agoraWeb.init')
external JSPromise<JSBoolean> _jsInit(
    JSString appId, JSString channel, JSString token, JSNumber uid);

@JS('agoraWeb.leave')
external JSPromise _jsLeave();

@JS('agoraWeb.muteAudio')
external void _jsMuteAudio(JSBoolean muted);

@JS('agoraWeb.muteVideo')
external void _jsMuteVideo(JSBoolean muted);

/// Agora video meeting widget for Flutter Web.
/// Uses the Agora Web SDK via JS interop.
class AgoraMeetingViewWeb extends StatefulWidget {
  final String channelName;
  final String displayName;
  final VoidCallback? onLeave;

  const AgoraMeetingViewWeb({
    super.key,
    required this.channelName,
    required this.displayName,
    this.onLeave,
  });

  @override
  State<AgoraMeetingViewWeb> createState() => _AgoraMeetingViewWebState();
}

class _AgoraMeetingViewWebState extends State<AgoraMeetingViewWeb> {
  bool _joined = false;
  bool _loading = true;
  bool _audioMuted = false;
  bool _videoMuted = false;
  late String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'agora-container-${widget.channelName.hashCode}';
    _registerView();
    _initAgora();
  }

  void _registerView() {
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final div = web.document.createElement('div') as web.HTMLDivElement;
      div.id = 'agora-wrapper';
      div.style.width = '100%';
      div.style.height = '100%';
      div.style.backgroundColor = '#1a1a1a';
      div.style.display = 'flex';
      div.style.position = 'relative';

      // Local video (small PiP)
      final localDiv =
          web.document.createElement('div') as web.HTMLDivElement;
      localDiv.id = 'agora-local-video';
      localDiv.style.position = 'absolute';
      localDiv.style.right = '12px';
      localDiv.style.top = '12px';
      localDiv.style.width = '160px';
      localDiv.style.height = '120px';
      localDiv.style.borderRadius = '8px';
      localDiv.style.overflow = 'hidden';
      localDiv.style.zIndex = '10';
      localDiv.style.border = '2px solid rgba(255,255,255,0.3)';

      // Remote area (full size)
      final remoteDiv =
          web.document.createElement('div') as web.HTMLDivElement;
      remoteDiv.id = 'agora-remote-area';
      remoteDiv.style.width = '100%';
      remoteDiv.style.height = '100%';
      remoteDiv.style.display = 'flex';
      remoteDiv.style.flexWrap = 'wrap';

      div.appendChild(remoteDiv);
      div.appendChild(localDiv);
      return div;
    });
  }

  Future<String> _fetchToken() async {
    final resp = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channelName': widget.channelName, 'uid': 0}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Token fetch failed: ${resp.statusCode}');
    }
    return (jsonDecode(resp.body) as Map)['token'] as String;
  }

  Future<void> _initAgora() async {
    try {
      final token = await _fetchToken();

      final result = await _jsInit(
        _agoraAppId.toJS,
        widget.channelName.toJS,
        token.toJS,
        (0).toJS,
      ).toDart;

      if (mounted) {
        setState(() {
          _joined = result.toDart;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Agora web init error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _jsLeave();
    super.dispose();
  }

  void _toggleAudio() {
    setState(() => _audioMuted = !_audioMuted);
    _jsMuteAudio(_audioMuted.toJS);
  }

  void _toggleVideo() {
    setState(() => _videoMuted = !_videoMuted);
    _jsMuteVideo(_videoMuted.toJS);
  }

  void _hangUp() async {
    await _jsLeave().toDart;
    widget.onLeave?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1a1a1a),
      child: Column(
        children: [
          // Video area
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text('Kobler til videomøte...',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: HtmlElementView(viewType: _viewId),
                  ),
          ),

          // Controls
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: const Color(0xFF111111),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _controlButton(
                  icon: _audioMuted ? Icons.mic_off : Icons.mic,
                  label: _audioMuted ? 'Lyd av' : 'Lyd',
                  active: !_audioMuted,
                  onPressed: _toggleAudio,
                ),
                const SizedBox(width: 16),
                _controlButton(
                  icon: _videoMuted ? Icons.videocam_off : Icons.videocam,
                  label: _videoMuted ? 'Video av' : 'Video',
                  active: !_videoMuted,
                  onPressed: _toggleVideo,
                ),
                const SizedBox(width: 16),
                _controlButton(
                  icon: Icons.call_end,
                  label: 'Legg på',
                  active: false,
                  isHangUp: true,
                  onPressed: _hangUp,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool active,
    bool isHangUp = false,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHangUp
                  ? Colors.red
                  : active
                      ? Colors.white24
                      : Colors.white10,
            ),
            child: Icon(icon,
                color: isHangUp
                    ? Colors.white
                    : active
                        ? Colors.white
                        : Colors.white54,
                size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: isHangUp ? Colors.red.shade200 : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
