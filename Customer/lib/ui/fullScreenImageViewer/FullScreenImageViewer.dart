import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final File? imageFile;
  final String? heroTag;

  const FullScreenImageViewer({
    Key? key,
    required this.imageUrl,
    this.imageFile,
    this.heroTag,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tag = heroTag ?? imageUrl;
    return Scaffold(
        appBar: AppBar(
          elevation: 0.0,
          backgroundColor: Colors.black,
          iconTheme: IconThemeData(color: Colors.white),
        ),
        body: Container(
          color: Colors.black,
          child: Hero(
            tag: tag,
            child: PhotoView(
              imageProvider: imageFile == null
                  ? NetworkImage(imageUrl)
                  : Image.file(imageFile!).image,
            ),
          ),
        ));
  }
}
