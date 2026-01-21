import 'package:flutter/material.dart';

class ExpandableImage extends StatelessWidget {
  final String imageUrl;

  const ExpandableImage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              body: Center(
                // This widget allows pinch-to-zoom
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.network(imageUrl), // Switch to Image.asset if local
                ),
              ),
            ),
          ),
        );
      },
      child: Image.network(imageUrl), // The thumbnail view in the question
    );
  }
}