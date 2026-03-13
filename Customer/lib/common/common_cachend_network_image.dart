import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CommonNetworkImage extends StatelessWidget {
  const CommonNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.placeholder,
    this.error,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.cacheKey,
    this.httpHeaders,
    this.clipBehavior = Clip.antiAlias,
    this.enableGestures = false,
  });

  factory CommonNetworkImage.circle({
    Key? key,
    required String imageUrl,
    double size = 48,
    BoxFit fit = BoxFit.cover,
    Widget? placeholder,
    Widget? error,
    int? memCacheWidth,
    int? memCacheHeight,
    String? cacheKey,
    Map<String, String>? httpHeaders,
    bool enableGestures = false,
  }) {
    return CommonNetworkImage(
      key: key,
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: fit,
      borderRadius: BorderRadius.circular(size / 2),
      placeholder: placeholder,
      error: error,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      cacheKey: cacheKey,
      httpHeaders: httpHeaders,
      enableGestures: enableGestures,
    );
  }

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final Widget? placeholder;
  final Widget? error;
  final AlignmentGeometry alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final String? cacheKey;
  final Map<String, String>? httpHeaders;
  final Clip clipBehavior;
  final bool enableGestures;

  bool get _isEmpty => imageUrl.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius;
    final w = width;
    final h = height;

    Widget child;

    if (_isEmpty) {
      child = _errorBox();
    } else {
      child = CachedNetworkImage(
        imageUrl: imageUrl,
        cacheKey: cacheKey,
        httpHeaders: httpHeaders,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        imageBuilder: (_, ImageProvider imageProvider) => Container(
          width: w,
          height: h,
          alignment: alignment,
          decoration: BoxDecoration(
            borderRadius: radius,
            image: DecorationImage(
              image: imageProvider,
              fit: fit,
              alignment: alignment,
            ),
          ),
        ),
        placeholder: (_, __) => placeholder ?? _placeholderBox(w: w, h: h),
        errorWidget: (_, __, ___) => error ?? _errorBox(),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      clipBehavior: clipBehavior,
      child: SizedBox(
        width: w,
        height: h,
        child: enableGestures
        ? GestureDetector(
            onTap: () {},
            child: child,
          )
        : child,
      ),
    );
  }

  Widget _placeholderBox({double? w, double? h}) => Container(
    width: w ?? 120,
    height: h ?? 120,
    color: Colors.grey[300],
    alignment: Alignment.center,
    child: Icon(Icons.image, color: Colors.grey[400], size: 40),
  );

  Widget _errorBox() => Container(
    color: Colors.black12,
    alignment: Alignment.center,
    child: const Icon(Icons.broken_image_outlined),
  );
}
