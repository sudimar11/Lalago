import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tracks whether any bottom banner (Happy Hour, Current Orders) is visible.
/// FABs use this to adjust their position and avoid overlap.
class BottomBannerVisibility {
  BottomBannerVisibility._();

  static final BottomBannerVisibility instance = BottomBannerVisibility._();

  static const double bannerHeight = 100.0;

  final ValueNotifier<double> offsetNotifier = ValueNotifier<double>(0);

  final Set<String> _visibleBanners = {};

  void showBanner(String key) {
    if (_visibleBanners.add(key)) {
      offsetNotifier.value = bannerHeight;
    }
  }

  void hideBanner(String key) {
    if (_visibleBanners.remove(key) && _visibleBanners.isEmpty) {
      offsetNotifier.value = 0;
    }
  }
}

/// Wraps a widget and reports visibility to [BottomBannerVisibility].
/// Use when showing the actual banner content.
class BottomBannerVisibilityReporter extends StatefulWidget {
  final String bannerKey;
  final bool visible;
  final Widget child;

  const BottomBannerVisibilityReporter({
    super.key,
    required this.bannerKey,
    required this.visible,
    required this.child,
  });

  @override
  State<BottomBannerVisibilityReporter> createState() =>
      _BottomBannerVisibilityReporterState();
}

class _BottomBannerVisibilityReporterState
    extends State<BottomBannerVisibilityReporter> {
  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      BottomBannerVisibility.instance.showBanner(widget.bannerKey);
    }
  }

  @override
  void didUpdateWidget(BottomBannerVisibilityReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        BottomBannerVisibility.instance.showBanner(widget.bannerKey);
      } else {
        BottomBannerVisibility.instance.hideBanner(widget.bannerKey);
      }
    }
  }

  @override
  void dispose() {
    if (widget.visible) {
      BottomBannerVisibility.instance.hideBanner(widget.bannerKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Positions FAB above the bottom banner when it's visible.
class BannerAwareFloatingActionButtonLocation
    extends FloatingActionButtonLocation {
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final base = FloatingActionButtonLocation.endFloat.getOffset(
      scaffoldGeometry,
    );
    final offset = BottomBannerVisibility.instance.offsetNotifier.value;
    return Offset(base.dx, base.dy - offset);
  }
}
