import 'package:flutter/material.dart';

/// Stub for non-web platforms. Never actually used — the conditional import
/// picks the real web implementation on web.
class AgoraMeetingViewWeb extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return const Center(child: Text('Not supported on this platform'));
  }
}
