import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class RouteMapView extends StatefulWidget {
  final String from;
  final String to;

  const RouteMapView({
    super.key,
    required this.from,
    required this.to,
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    final url =
        "https://www.google.com/maps/dir/?api=1"
        "&origin=${Uri.encodeComponent(widget.from)}"
        "&destination=${Uri.encodeComponent(widget.to)}"
        "&travelmode=driving";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}