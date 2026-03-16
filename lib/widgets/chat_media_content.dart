import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tourflow/widgets/mention_helpers.dart';
import 'package:tourflow/services/poll_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatMediaContent extends StatelessWidget {
  final String messageType;
  final String message;
  final String? attachmentUrl;
  final TextStyle textStyle;
  final bool isMine;

  const ChatMediaContent({
    super.key,
    required this.messageType,
    required this.message,
    this.attachmentUrl,
    required this.textStyle,
    this.isMine = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (messageType) {
      case 'image':
        return _buildImage();
      case 'file':
        return _buildFile();
      case 'gif':
        return _buildGif();
      case 'poll':
        return _buildPoll();
      default:
        return Text.rich(
          TextSpan(children: buildMentionSpans(message, textStyle)),
          style: textStyle,
        );
    }
  }

  Widget _buildImage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attachmentUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
              child: Image.network(
                attachmentUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    width: 200,
                    height: 150,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  width: 200,
                  height: 100,
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, size: 40),
                ),
              ),
            ),
          ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text.rich(
              TextSpan(children: buildMentionSpans(message, textStyle)),
              style: textStyle,
            ),
          ),
      ],
    );
  }

  Widget _buildFile() {
    final fileName = attachmentUrl != null
        ? Uri.parse(attachmentUrl!).pathSegments.last.replaceFirst(RegExp(r'^\d+_'), '')
        : 'Fil';
    return InkWell(
      onTap: () {
        if (attachmentUrl != null) {
          launchUrl(Uri.parse(attachmentUrl!));
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 20, color: isMine ? Colors.white70 : Colors.black54),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                fileName,
                style: textStyle.copyWith(decoration: TextDecoration.underline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download, size: 18, color: isMine ? Colors.white70 : Colors.black54),
          ],
        ),
      ),
    );
  }

  Widget _buildGif() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250),
        child: Image.network(
          attachmentUrl ?? '',
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              width: 200,
              height: 150,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 100,
            color: Colors.grey[300],
            child: const Icon(Icons.gif, size: 40),
          ),
        ),
      ),
    );
  }

  Widget _buildPoll() {
    // attachmentUrl contains the poll ID
    final pollId = attachmentUrl;
    if (pollId == null) {
      return Text('Ugyldig avstemming', style: textStyle);
    }
    return _PollBubbleContent(pollId: pollId, isMine: isMine);
  }
}

class _PollBubbleContent extends StatefulWidget {
  final String pollId;
  final bool isMine;
  const _PollBubbleContent({required this.pollId, required this.isMine});

  @override
  State<_PollBubbleContent> createState() => _PollBubbleContentState();
}

class _PollBubbleContentState extends State<_PollBubbleContent> {
  Map<String, dynamic>? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPoll();
  }

  Future<void> _loadPoll() async {
    try {
      final poll = await PollService.getPoll(widget.pollId);
      if (mounted) setState(() { _poll = poll; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 220,
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_poll == null) {
      return const Text('Kunne ikke laste avstemming');
    }

    final question = _poll!['question'] as String? ?? '';
    final options = (_poll!['options'] as List?) ?? [];
    final isClosed = _poll!['is_closed'] as bool? ?? false;
    final textColor = widget.isMine ? Colors.white : Colors.black;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PollService.streamVotes(widget.pollId),
      builder: (context, snap) {
        final votes = snap.data ?? (_poll!['votes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        final myVote = votes.where((v) => v['user_id'] == currentUserId).firstOrNull;
        final totalVotes = votes.length;

        return SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.poll, size: 18, color: textColor.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(question,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textColor)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...options.map((opt) {
                final optId = opt['id'] as String;
                final label = opt['label'] as String? ?? '';
                final optVotes = votes.where((v) => v['option_id'] == optId).length;
                final pct = totalVotes > 0 ? optVotes / totalVotes : 0.0;
                final isMyVote = myVote?['option_id'] == optId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    onTap: isClosed ? null : () async {
                      if (isMyVote) {
                        await PollService.removeVote(widget.pollId);
                      } else {
                        await PollService.vote(widget.pollId, optId);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMyVote
                              ? Colors.blue
                              : textColor.withValues(alpha: 0.2),
                          width: isMyVote ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: textColor))),
                          if (totalVotes > 0)
                            Text('${(pct * 100).round()}%',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor.withValues(alpha: 0.7))),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$totalVotes ${totalVotes == 1 ? 'stemme' : 'stemmer'}${isClosed ? ' · Avsluttet' : ''}',
                  style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
