import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/google_routes_service.dart';
import '../services/route_analyzer.dart';

class GoogleTestPage extends StatefulWidget {
  const GoogleTestPage({super.key});

  @override
  State<GoogleTestPage> createState() => _GoogleTestPageState();
}

class _GoogleTestPageState extends State<GoogleTestPage> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  bool _loading = false;
  String? _result;

  final _service = GoogleRoutesService();
  final _analyzer = RouteAnalyzer();

  // ------------------------------------------------------------
  // TEST ROUTE
  // ------------------------------------------------------------
  Future<void> _test() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();

    if (from.isEmpty || to.isEmpty) {
      debugPrint("❌ Empty input");
      return;
    }

    debugPrint("▶️ TEST ROUTE: $from → $to");

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      // --------------------------------
      // CALL GOOGLE
      // --------------------------------
      debugPrint("📡 Calling Google API...");

      final data = await _service.getRoute(
        from: from,
        to: to,
      );

      debugPrint("✅ Google response OK");

      final distance = data['distanceMeters'] as int;
      final polyline = data['polyline'] as String;

      debugPrint("📏 Distance: $distance m");
      debugPrint("📐 Polyline chars: ${polyline.length}");

      // --------------------------------
      // ANALYZE
      // --------------------------------
      debugPrint("🌍 Analyzing route countries...");

      final analysis =
  await _analyzer.kmPerCountry(
    polyline,
    googleKm: distance / 1000,
  );

      debugPrint("✅ Country analysis done");

      // --------------------------------
      // BUILD RESULT
      // --------------------------------
      final buffer = StringBuffer();

      buffer.writeln("ROUTE ANALYSIS");
      buffer.writeln("======================");
      buffer.writeln("");

      buffer.writeln("FROM: $from");
      buffer.writeln("TO:   $to");
      buffer.writeln("");

      buffer.writeln(
        "TOTAL: ${(analysis.totalKm).toStringAsFixed(1)} km",
      );

      buffer.writeln("POINTS: ${analysis.points}");
      buffer.writeln("");

      buffer.writeln("PER COUNTRY:");
      buffer.writeln("");

      analysis.perCountry.forEach((c, km) {
        buffer.writeln(
          "• $c: ${km.toStringAsFixed(1)} km",
        );
      });

      buffer.writeln("");
      buffer.writeln("RAW DISTANCE: $distance m");

      setState(() {
        _result = buffer.toString();
      });
    } catch (e, st) {
      // --------------------------------
      // ERROR
      // --------------------------------
      debugPrint("🔥 ERROR");
      debugPrint(e.toString());
      debugPrint(st.toString());

      setState(() {
        _result = '''
ERROR
=====

$e

STACKTRACE
----------

$st
''';
      });
    } finally {
      setState(() {
        _loading = false;
      });

      debugPrint("⏹ Test finished");
    }
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------
  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Google Route Test"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --------------------------------
            // FROM
            // --------------------------------
            TextField(
              controller: _fromCtrl,
              decoration: const InputDecoration(
                labelText: "From",
                hintText: "Oslo",
              ),
            ),

            const SizedBox(height: 12),

            // --------------------------------
            // TO
            // --------------------------------
            TextField(
              controller: _toCtrl,
              decoration: const InputDecoration(
                labelText: "To",
                hintText: "Berlin",
              ),
            ),

            const SizedBox(height: 20),

            // --------------------------------
            // BUTTON
            // --------------------------------
            FilledButton.icon(
              onPressed: _loading ? null : _test,
              icon: const Icon(Icons.play_arrow),
              label: const Text("Test route"),
            ),

            const SizedBox(height: 20),

            // --------------------------------
            // LOADING
            // --------------------------------
            if (_loading)
              const Center(
                child: CircularProgressIndicator(),
              ),

            // --------------------------------
            // RESULT
            // --------------------------------
            if (_result != null) ...[
              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    _result!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}