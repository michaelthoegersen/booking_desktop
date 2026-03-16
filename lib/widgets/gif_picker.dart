import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GifPicker extends StatefulWidget {
  final void Function(String gifUrl) onGifSelected;
  const GifPicker({super.key, required this.onGifSelected});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _gifs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    final apiKey = dotenv.env['GIPHY_API_KEY'] ?? '';
    if (apiKey.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse(
          'https://api.giphy.com/v1/gifs/trending?api_key=$apiKey&limit=20&rating=g'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _gifs = List<Map<String, dynamic>>.from(data['data']));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadTrending();
      return;
    }
    final apiKey = dotenv.env['GIPHY_API_KEY'] ?? '';
    if (apiKey.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse(
          'https://api.giphy.com/v1/gifs/search?api_key=$apiKey&q=${Uri.encodeComponent(query)}&limit=20&rating=g'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _gifs = List<Map<String, dynamic>>.from(data['data']));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  String? _getGifUrl(Map<String, dynamic> gif) {
    try {
      return gif['images']['fixed_height']['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Sok GIF...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: _search,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (_, i) {
                        final url = _getGifUrl(_gifs[i]);
                        if (url == null) return const SizedBox.shrink();
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onGifSelected(url);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(url, fit: BoxFit.cover),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Image.network(
                'https://giphy.com/static/img/poweredby_giphy.png',
                height: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
