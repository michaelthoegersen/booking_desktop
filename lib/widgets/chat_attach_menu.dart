import 'package:flutter/material.dart';

class ChatAttachMenu extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final VoidCallback onGif;
  final VoidCallback onPoll;

  const ChatAttachMenu({
    super.key,
    required this.onPickImage,
    required this.onPickFile,
    required this.onGif,
    required this.onPoll,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.add, size: 24),
      tooltip: 'Legg ved',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) {
        switch (value) {
          case 'image':
            onPickImage();
          case 'file':
            onPickFile();
          case 'gif':
            onGif();
          case 'poll':
            onPoll();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'image', child: ListTile(leading: Icon(Icons.image), title: Text('Bilde'), dense: true, contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.attach_file), title: Text('Fil'), dense: true, contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'gif', child: ListTile(leading: Icon(Icons.gif_box), title: Text('GIF'), dense: true, contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'poll', child: ListTile(leading: Icon(Icons.poll), title: Text('Avstemming'), dense: true, contentPadding: EdgeInsets.zero)),
      ],
    );
  }
}
