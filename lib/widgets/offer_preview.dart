import 'package:flutter/material.dart';
import '../models/offer_draft.dart';

class OfferPreview extends StatelessWidget {
  final OfferDraft offer;

  const OfferPreview({
    super.key,
    required this.offer,
  });

  // --------------------------------------------------
  // STATUS COLOR
  // --------------------------------------------------
  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    switch (offer.status) {
     case "Inquiry":
        return cs.secondaryContainer;

      case "Confirmed":
        return Colors.green.shade200;

      case "Cancelled":
        return Colors.red.shade200;

      case "Draft":
      default:
        return cs.tertiaryContainer;
    }
  }

  // --------------------------------------------------
  // STATUS TEXT
  // --------------------------------------------------
  String _statusLabel() {
    switch (offer.status) {
      case "Inquiry":
        return "📤 SENT";

      case "Confirmed":
        return "✅ CONFIRMED";

      case "Cancelled":
        return "❌ CANCELLED";

      case "Draft":
      default:
        return "📝 DRAFT";
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // =================================================
        // HEADER
        // =================================================
        Row(
          children: [
            Text(
              "Live Preview",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),

            const Spacer(),

            // ================= STATUS CHIP =================
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: _statusColor(context),
              ),
              child: Text(
                _statusLabel(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // =================================================
        // MAIN CARD
        // =================================================
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // =================================================
              // TOP BAR
              // =================================================
              Row(
                children: [

                  // LOGO PLACEHOLDER
                  Container(
                    width: 110,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      "LOGO",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),

                  const Spacer(),

                  Text(
                    "Offer",
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // =================================================
              // BASIC INFO
              // =================================================
              _PreviewLine(label: "Company", value: offer.company),
              _PreviewLine(label: "Contact", value: offer.contact),
              _PreviewLine(label: "Production", value: offer.production),
              _PreviewLine(label: "Bus", value: offer.bus ?? ""),

              const SizedBox(height: 14),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 10),

              // =================================================
              // KPI
              // =================================================
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: "Rounds used",
                      value: "${offer.usedRounds} / 12",
                      icon: Icons.repeat,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: _KpiCard(
                      title: "Total days",
                      value: "${offer.totalDays}",
                      icon: Icons.calendar_month,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // =================================================
              // ROUNDS PREVIEW
              // =================================================
              Text(
                "Rounds preview",
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: List.generate(12, (i) {

                    final r = offer.rounds[i];

                    final has =
                        r.entries.isNotEmpty ||
                        r.startLocation.trim().isNotEmpty;

                    final title = "Round ${i + 1}";

                    final subtitle = has
                        ? "${r.startLocation.isEmpty ? "—" : r.startLocation} • ${r.entries.length} date(s)"
                        : "—";

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [

                          SizedBox(
                            width: 90,
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: has
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),

                          Expanded(
                            child: Text(
                              subtitle,
                              style: TextStyle(
                                color: has
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 10),
              Divider(color: cs.outlineVariant),
              const SizedBox(height: 8),

              // =================================================
              // TOTAL (PLACEHOLDER)
              // =================================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Estimated total",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "NOK 0",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =================================================
// PREVIEW LINE
// =================================================
class _PreviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [

          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),

          Expanded(
            child: Text(
              value.isEmpty ? "—" : value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================
// KPI CARD
// =================================================
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [

          CircleAvatar(
            radius: 18,
            backgroundColor: cs.surface,
            child: Icon(
              icon,
              color: cs.primary,
              size: 18,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}