import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _agoraAppId = '4fe1ae5ea7454ba9adc19030d559ce74';
const _tokenUrl = 'https://fqefvgqlrntwgschkugf.supabase.co/functions/v1/agora-token';

class AgoraMeetingView extends StatefulWidget {
  final String channelName;
  final String displayName;
  final VoidCallback? onLeave;

  const AgoraMeetingView({
    super.key,
    required this.channelName,
    required this.displayName,
    this.onLeave,
  });

  @override
  State<AgoraMeetingView> createState() => _AgoraMeetingViewState();
}

class _AgoraMeetingViewState extends State<AgoraMeetingView> {
  late RtcEngine _engine;
  bool _joined = false;
  bool _loading = true;
  bool _audioMuted = false;
  bool _videoMuted = false;
  final Set<int> _remoteUids = {};

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  Future<String> _fetchToken() async {
    final resp = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channelName': widget.channelName, 'uid': 0}),
    );
    if (resp.statusCode != 200) {
      throw Exception('Token fetch failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    return data['token'] as String;
  }

  Future<void> _initAgora() async {
    try {
      debugPrint('Agora: fetching token for channel ${widget.channelName}...');
      final token = await _fetchToken();
      debugPrint('Agora: token received');

      _engine = createAgoraRtcEngine();
      await _engine.initialize(const RtcEngineContext(
        appId: _agoraAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      _engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          debugPrint('Agora: joined channel ${connection.channelId} in ${elapsed}ms');
          if (mounted) setState(() {
            _joined = true;
            _loading = false;
          });
        },
        onConnectionStateChanged: (connection, state, reason) {
          debugPrint('Agora connection: state=$state reason=$reason');
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted) setState(() => _remoteUids.add(remoteUid));
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted) setState(() => _remoteUids.remove(remoteUid));
        },
        onError: (err, msg) {
          debugPrint('Agora error: $err — $msg');
          if (mounted) setState(() => _loading = false);
        },
      ));

      await _engine.enableVideo();
      await _engine.startPreview();

      await _engine.joinChannel(
        token: token,
        channelId: widget.channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } catch (e, stack) {
      debugPrint('Agora init error: $e');
      debugPrint('Stack: $stack');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  Future<void> _leave() async {
    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (_) {}
  }

  void _toggleAudio() {
    setState(() => _audioMuted = !_audioMuted);
    _engine.muteLocalAudioStream(_audioMuted);
  }

  void _toggleVideo() {
    setState(() => _videoMuted = !_videoMuted);
    _engine.muteLocalVideoStream(_videoMuted);
  }

  void _hangUp() async {
    await _leave();
    widget.onLeave?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: const Color(0xFF1a1a1a),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Kobler til videomøte...',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1a1a1a),
      child: Column(
        children: [
          // Video grid
          Expanded(
            child: _buildVideoGrid(),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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

  Widget _buildVideoGrid() {
    final views = <Widget>[];

    // Local video
    if (_joined) {
      views.add(_videoTile(
        child: _videoMuted
            ? _avatarPlaceholder(widget.displayName)
            : AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _engine,
                  canvas: const VideoCanvas(uid: 0),
                ),
              ),
        label: '${widget.displayName} (deg)',
      ));
    }

    // Remote videos
    for (final uid in _remoteUids) {
      views.add(_videoTile(
        child: AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _engine,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: widget.channelName),
          ),
        ),
        label: 'Deltaker',
      ));
    }

    if (views.isEmpty) {
      return const Center(
        child: Text('Venter på tilkobling...',
            style: TextStyle(color: Colors.white54)),
      );
    }

    if (views.length == 1) {
      return views.first;
    }

    // Grid layout for multiple participants
    return GridView.count(
      crossAxisCount: views.length <= 2 ? 2 : (views.length <= 4 ? 2 : 3),
      childAspectRatio: 16 / 9,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      padding: const EdgeInsets.all(4),
      children: views,
    );
  }

  Widget _videoTile({required Widget child, required String label}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder(String name) {
    final initials = name.isNotEmpty
        ? name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : '?';
    return Container(
      color: const Color(0xFF2a2a2a),
      child: Center(
        child: CircleAvatar(
          radius: 36,
          backgroundColor: Colors.blueGrey,
          child: Text(initials,
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        ),
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
