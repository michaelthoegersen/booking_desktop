import 'package:flutter/material.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Calendar",
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),

          const SizedBox(height: 12),

          const Expanded(
            child: Center(
              child: Text("Calendar view coming soon"),
            ),
          ),
        ],
      ),
    );
  }
}