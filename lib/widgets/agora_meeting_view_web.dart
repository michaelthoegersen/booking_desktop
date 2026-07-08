import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

const _agoraAppId = '4fe1ae5ea7454ba9adc19030d559ce74';
const _tokenUrl =
    'https://fqefvgqlrntwgschkugf.supabase.co/functions/v1/agora-token';

const _prefVideoDevice = 'agora_video_device_id';
const _prefRecordingDevice = 'agora_recording_device_id';
const _prefPlaybackDevice = 'agora_playback_device_id';

@JS('agoraWeb.init')
external JSPromise<JSBoolean> _jsInit(
    JSString appId, JSString channel, JSString token, JSNumber uid);

@JS('agoraWeb.leave')
external JSPromise _jsLeave();

@JS('agoraWeb.muteAudio')
external void _jsMuteAudio(JSBoolean muted);

@JS('agoraWeb.muteVideo')
external void _jsMuteVideo(JSBoolean muted);

@JS('agoraWeb.listDevices')
external JSPromise<JSString> _jsListDevices();

@JS('agoraWeb.setMicrophone')
external JSPromise<JSBoolean> _jsSetMicrophone(JSString deviceId);

@JS('agoraWeb.setCamera')
external JSPromise<JSBoolean> _jsSetCamera(JSString deviceId);

@JS('agoraWeb.setSpeaker')
external JSPromise<JSBoolean> _jsSetSpeaker(JSString deviceId);

@JS('agoraWeb.selectedMicId')
external set _jsSelectedMicId(JSString? id);

@JS('agoraWeb.selectedCameraId')
external set _jsSelectedCameraId(JSString? id);

@JS('agoraWeb.selectedSpeakerId')
external set _jsSelectedSpeakerId(JSString? id);

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

  List<MapEntry<String, String>> _cameras = [];
  List<MapEntry<String, String>> _microphones = [];
  List<MapEntry<String, String>> _speakers = [];
  String? _selectedCameraId;
  String? _selectedMicId;
  String? _selectedSpeakerId;

  @override
  void initState() {
    super.initState();
    _viewId = 'agora-container-${widget.channelName.hashCode}';
    _registerView();
    _restoreSavedDevices().then((_) => _initAgora());
  }

  Future<void> _restoreSavedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedCameraId = prefs.getString(_prefVideoDevice);
    _selectedMicId = prefs.getString(_prefRecordingDevice);
    _selectedSpeakerId = prefs.getString(_prefPlaybackDevice);
    if (_selectedCameraId != null) _jsSelectedCameraId = _selectedCameraId!.toJS;
    if (_selectedMicId != null) _jsSelectedMicId = _selectedMicId!.toJS;
    if (_selectedSpeakerId != null) {
      _jsSelectedSpeakerId = _selectedSpeakerId!.toJS;
    }
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

  Future<void> _loadDevices() async {
    try {
      final jsonStr = (await _jsListDevices().toDart).toDart;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      List<MapEntry<String, String>> parse(String key) {
        final list = (data[key] as List?) ?? const [];
        return list
            .map((e) {
              final m = e as Map<String, dynamic>;
              return MapEntry(
                  (m['id'] as String?) ?? '', (m['name'] as String?) ?? 'Ukjent');
            })
            .where((e) => e.key.isNotEmpty)
            .toList();
      }

      if (mounted) {
        setState(() {
          _cameras = parse('cameras');
          _microphones = parse('microphones');
          _speakers = parse('speakers');
        });
      }
    } catch (e) {
      debugPrint('Agora web listDevices error: $e');
    }
  }

  Future<void> _setCamera(String id) async {
    await _jsSetCamera(id.toJS).toDart;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVideoDevice, id);
    if (mounted) setState(() => _selectedCameraId = id);
  }

  Future<void> _setMicrophone(String id) async {
    await _jsSetMicrophone(id.toJS).toDart;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefRecordingDevice, id);
    if (mounted) setState(() => _selectedMicId = id);
  }

  Future<void> _setSpeaker(String id) async {
    await _jsSetSpeaker(id.toJS).toDart;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPlaybackDevice, id);
    if (mounted) setState(() => _selectedSpeakerId = id);
  }

  Future<void> _showDeviceSettings() async {
    await _loadDevices();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1f1f1f),
              title:
                  const Text('Enheter', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _deviceDropdown(
                      label: 'Kamera',
                      icon: Icons.videocam,
                      value: _selectedCameraId,
                      items: _cameras,
                      onChanged: (id) async {
                        if (id == null) return;
                        await _setCamera(id);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    _deviceDropdown(
                      label: 'Mikrofon',
                      icon: Icons.mic,
                      value: _selectedMicId,
                      items: _microphones,
                      onChanged: (id) async {
                        if (id == null) return;
                        await _setMicrophone(id);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 16),
                    _deviceDropdown(
                      label: 'Høyttaler',
                      icon: Icons.volume_up,
                      value: _selectedSpeakerId,
                      items: _speakers,
                      onChanged: (id) async {
                        if (id == null) return;
                        await _setSpeaker(id);
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Lukk',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _deviceDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<MapEntry<String, String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final hasValue = value != null && items.any((e) => e.key == value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF2a2a2a),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: const Color(0xFF2a2a2a),
              value: hasValue ? value : null,
              hint: Text(
                items.isEmpty ? 'Ingen enheter funnet' : 'Velg enhet',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: items
                  .map((e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(
                          e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: items.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
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
                  icon: Icons.tune,
                  label: 'Enheter',
                  active: true,
                  onPressed: _showDeviceSettings,
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
