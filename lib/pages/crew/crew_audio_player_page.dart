import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../state/active_company.dart';

/// Plays audio files from Dropbox via temporary link.
class CrewAudioPlayerPage extends StatefulWidget {
  final String filePath;
  final String fileName;

  const CrewAudioPlayerPage({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<CrewAudioPlayerPage> createState() => _CrewAudioPlayerPageState();
}

class _CrewAudioPlayerPageState extends State<CrewAudioPlayerPage> {
  final _sb = Supabase.instance.client;
  final _player = AudioPlayer();

  bool _loading = true;
  String? _error;

  String? get _companyId => activeCompanyNotifier.value?.id;

  @override
  void initState() {
    super.initState();
    _loadAndPlay();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadAndPlay() async {
    if (_companyId == null) {
      setState(() {
        _error = 'Ingen aktiv bedrift';
        _loading = false;
      });
      return;
    }

    try {
      // Get temporary link
      final res = await _sb.functions.invoke('dropbox-get-temp-link', body: {
        'company_id': _companyId!,
        'path': widget.filePath,
      });

      final data = res.data as Map<String, dynamic>?;
      final link = data?['link'] as String?;
      if (link == null) throw Exception('Ingen nedlastingslink');

      // Set audio source
      await _player.setUrl(link);
      await _player.play();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('AudioPlayer error: $e');
      if (mounted) {
        setState(() {
          _error = 'Kunne ikke laste lydfilen: $e';
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$mins:$secs';
    }
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + title
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _player.stop();
                  context.pop();
                },
                tooltip: 'Tilbake',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.fileName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Player
          Expanded(
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : _error != null
                      ? _buildError()
                      : _buildPlayer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text(
          _error!,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPlayer() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 500,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, size: 64, color: Colors.purple),
          const SizedBox(height: 20),
          Text(
            widget.fileName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const SizedBox(height: 28),

          // Seek bar
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration = _player.duration ?? Duration.zero;

              return Column(
                children: [
                  Slider(
                    min: 0,
                    max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    value: position.inMilliseconds
                        .toDouble()
                        .clamp(0, duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                    onChanged: (value) {
                      _player.seek(Duration(milliseconds: value.toInt()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // Controls
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final playing = state?.playing ?? false;
              final completed =
                  state?.processingState == ProcessingState.completed;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rewind 10s
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.replay_10),
                    onPressed: () {
                      final newPos = _player.position -
                          const Duration(seconds: 10);
                      _player.seek(
                          newPos < Duration.zero ? Duration.zero : newPos);
                    },
                  ),
                  const SizedBox(width: 16),

                  // Play/Pause
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 40,
                      color: Colors.white,
                      icon: Icon(
                        completed
                            ? Icons.replay
                            : playing
                                ? Icons.pause
                                : Icons.play_arrow,
                      ),
                      onPressed: () {
                        if (completed) {
                          _player.seek(Duration.zero);
                          _player.play();
                        } else if (playing) {
                          _player.pause();
                        } else {
                          _player.play();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Forward 10s
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.forward_10),
                    onPressed: () {
                      final duration =
                          _player.duration ?? Duration.zero;
                      final newPos = _player.position +
                          const Duration(seconds: 10);
                      _player
                          .seek(newPos > duration ? duration : newPos);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
