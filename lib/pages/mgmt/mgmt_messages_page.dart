import 'package:flutter/material.dart';

import '../../ui/css_theme.dart';

class MgmtMessagesPage extends StatelessWidget {
  const MgmtMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Messages',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Messages coming soon',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: CssTheme.textMuted,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You\'ll be able to communicate with CSS directly here.',
                    style: TextStyle(color: CssTheme.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
