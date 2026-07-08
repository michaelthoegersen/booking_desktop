import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
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
        return SelectableText.rich(
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
          Builder(
            builder: (context) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openImageViewer(context, attachmentUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: 300, maxHeight: 300),
                    child: Image.network(
                      attachmentUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox(
                          width: 200,
                          height: 150,
                          child: Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
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

  void _openImageViewer(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx),
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.white));
                  },
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    size: 80,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.5),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                  tooltip: 'Lukk',
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 56,
              child: Material(
                color: Colors.black.withValues(alpha: 0.5),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.open_in_new, color: Colors.white),
                  onPressed: () => launchUrl(Uri.parse(url)),
                  tooltip: 'Åpne eksternt',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFile() {
    final fileName = attachmentUrl != null
        ? Uri.parse(attachmentUrl!).pathSegments.last.replaceFirst(RegExp(r'^\d+_'), '')
        : 'Fil';
    final isPdf = fileName.toLowerCase().endsWith('.pdf') ||
        (attachmentUrl?.toLowerCase().contains('.pdf') ?? false);

    if (isPdf && attachmentUrl != null) {
      return Builder(builder: (context) => GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SizedBox(
                width: 700,
                height: 800,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(message.isNotEmpty ? message : fileName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          IconButton(icon: const Icon(Icons.open_in_new, color: Colors.white70, size: 18), onPressed: () => launchUrl(Uri.parse(attachmentUrl!)), tooltip: 'Åpne eksternt'),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 18), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                    Expanded(child: SfPdfViewer.network(attachmentUrl!)),
                  ],
                ),
              ),
            ),
          );
        },
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isMine ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isMine ? Colors.white24 : Colors.black12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, size: 28, color: Colors.red.shade400),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message.isNotEmpty ? message : fileName,
                  style: textStyle.copyWith(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ));
    }

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
