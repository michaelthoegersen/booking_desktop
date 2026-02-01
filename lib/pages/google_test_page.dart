import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/google_routes_service.dart';
import '../services/polyline_decoder.dart';

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
      // CALL API
      // --------------------------------
      debugPrint("📡 Calling GoogleRoutesService...");

      final data = await _service.getRoute(
        from: from,
        to: to,
      );

      debugPrint("✅ Google response received");

      // --------------------------------
      // EXTRACT
      // --------------------------------
      final distance = data['distanceMeters'];
      final polyline = data['polyline'];

      if (polyline == null || polyline is! String) {
        throw Exception("Polyline is null or invalid");
      }

      debugPrint("📏 Distance: $distance m");
      debugPrint("📐 Polyline length: ${polyline.length}");

      // --------------------------------
      // DECODE
      // --------------------------------
      debugPrint("🧩 Decoding polyline...");

      final points = PolylineDecoder.decode(polyline);

      debugPrint("✅ Decoded ${points.length} points");

      if (points.isEmpty) {
        throw Exception("No points decoded");
      }

      final first = points.first;
      final last = points.last;

      debugPrint(
        "📍 First: ${first.lat}, ${first.lng}",
      );

      debugPrint(
        "🏁 Last: ${last.lat}, ${last.lng}",
      );

      // --------------------------------
      // RESULT TEXT
      // --------------------------------
      final text = '''
ROUTE TEST RESULT
=================

FROM: $from
TO:   $to

DISTANCE:
$distance m
${(distance / 1000).toStringAsFixed(1)} km

POLYLINE:
Length: ${polyline.length} chars

POINTS:
${points.length}

FIRST POINT:
${first.lat}, ${first.lng}

LAST POINT:
${last.lat}, ${last.lng}

RAW POLYLINE (first 500 chars):
${polyline.substring(0, polyline.length > 500 ? 500 : polyline.length)}
...
''';

      setState(() {
        _result = text;
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

STACKTRACE:
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