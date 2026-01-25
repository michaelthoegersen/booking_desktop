import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RouteMapPage extends StatefulWidget {
  final String from;
  final String to;

  const RouteMapPage({
    super.key,
    required this.from,
    required this.to,
  });

  @override
  State<RouteMapPage> createState() => _RouteMapPageState();
}

class _RouteMapPageState extends State<RouteMapPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception("GOOGLE_MAPS_API_KEY mangler");
    }

    final origin = Uri.encodeComponent(widget.from);
    final destination = Uri.encodeComponent(widget.to);

    final embedUrl =
        "https://www.google.com/maps/embed/v1/directions"
        "?key=$apiKey"
        "&origin=$origin"
        "&destination=$destination"
        "&mode=driving";

    final html = """
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
      html, body {
        margin: 0;
        padding: 0;
        height: 100%;
      }
      iframe {
        border: 0;
        width: 100%;
        height: 100%;
      }
    </style>
  </head>
  <body>
    <iframe
      src="$embedUrl"
      allowfullscreen
      loading="lazy">
    </iframe>
  </body>
</html>
""";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.from} → ${widget.to}"),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}