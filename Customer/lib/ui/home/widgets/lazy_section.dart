import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Reusable lazy-loading section that only builds content when visible.
/// Uses 200ms debounce to avoid rapid activate/deactivate during scroll.
class LazySection extends StatefulWidget {
  final Key sectionKey;
  final double visibilityThreshold;
  final Duration debounceDuration;
  final bool Function()? activateCondition;
  final Widget loadingPlaceholder;
  final Widget Function() contentBuilder;
  final void Function()? onActivated;

  const LazySection({
    super.key,
    required this.sectionKey,
    this.visibilityThreshold = 0.1,
    this.debounceDuration = const Duration(milliseconds: 200),
    this.activateCondition,
    required this.loadingPlaceholder,
    required this.contentBuilder,
    this.onActivated,
  });

  @override
  State<LazySection> createState() => _LazySectionState();
}

class _LazySectionState extends State<LazySection> {
  bool _isActivated = false;
  Widget? _cachedContent;
  Timer? _debounceTimer;
  bool _pendingActivation = false;

  bool get _conditionMet =>
      widget.activateCondition == null || widget.activateCondition!();

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final visible = info.visibleFraction >= widget.visibilityThreshold;
    if (!visible) {
      _debounceTimer?.cancel();
      _pendingActivation = false;
      return;
    }
    if (!_conditionMet) return;
    if (_isActivated) return;

    _pendingActivation = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (!mounted || !_pendingActivation) return;
      _pendingActivation = false;
      setState(() {
        _isActivated = true;
        _cachedContent ??= widget.contentBuilder();
      });
      widget.onActivated?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: widget.sectionKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: _isActivated && _cachedContent != null
          ? _cachedContent!
          : widget.loadingPlaceholder,
    );
  }
}
