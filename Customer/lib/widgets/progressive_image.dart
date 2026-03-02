import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Image widget with placeholder and memory limits for list/card usage.
/// Uses CachedNetworkImage with memCacheWidth/Height for low-memory devices.
class ProgressiveImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final int memCacheWidth;
  final int memCacheHeight;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const ProgressiveImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.memCacheWidth = 280,
    this.memCacheHeight = 280,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 300),
      placeholder: (context, url) =>
          placeholder ??
          Center(
            child: CircularProgressIndicator.adaptive(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      errorWidget: (context, url, error) =>
          errorWidget ??
          Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
    );
  }
}
