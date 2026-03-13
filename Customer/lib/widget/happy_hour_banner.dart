import 'dart:async';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/HappyHourConfig.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/bottom_banner_visibility.dart';
import 'package:foodie_customer/services/happy_hour_helper.dart';
import 'package:foodie_customer/services/happy_hour_service.dart';

class HappyHourBanner extends StatefulWidget {
  const HappyHourBanner({Key? key}) : super(key: key);

  @override
  _HappyHourBannerState createState() => _HappyHourBannerState();
}

// Flip-style timer module widget
class _FlipTimerModule extends StatelessWidget {
  final int value;

  const _FlipTimerModule({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 48,
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          // Centered number text
          Center(
            child: Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ),
          // Horizontal divider line
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              color: Colors.black.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }
}

// Separate widget for timer display to prevent flickering
class _TimerDisplay extends StatelessWidget {
  final Duration? timeRemaining;

  const _TimerDisplay({required this.timeRemaining});

  @override
  Widget build(BuildContext context) {
    if (timeRemaining == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Bonus ends in',
            style: TextStyle(
              fontFamily: 'Poppinsm',
              fontSize: 11,
              color: isDarkMode(context)
                  ? Colors.white70
                  : const Color(0xFF666666),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              color: Color(COLOR_PRIMARY).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Color(COLOR_PRIMARY).withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: const Text(
              '--',
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    final hours = timeRemaining!.inHours;
    final minutes = timeRemaining!.inMinutes.remainder(60);
    final seconds = timeRemaining!.inSeconds.remainder(60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bonus ends in',
          style: TextStyle(
            fontFamily: 'Poppinsm',
            fontSize: 11,
            color:
                isDarkMode(context) ? Colors.white70 : const Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hours > 0) ...[
              _FlipTimerModule(value: hours),
              const SizedBox(width: 4),
              Text(
                ':',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(COLOR_PRIMARY),
                ),
              ),
              const SizedBox(width: 4),
            ],
            _FlipTimerModule(value: minutes),
            const SizedBox(width: 4),
            Text(
              ':',
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(COLOR_PRIMARY),
              ),
            ),
            const SizedBox(width: 4),
            _FlipTimerModule(value: seconds),
          ],
        ),
      ],
    );
  }
}

class _HappyHourBannerState extends State<HappyHourBanner> {
  Timer? _countdownTimer;
  Timer? _serverTimeRefreshTimer;
  ValueNotifier<Duration?> _timeRemainingNotifier =
      ValueNotifier<Duration?>(null);
  HappyHourConfig? _activeConfig;
  bool _isBannerClosed = false;

  // Cache for server time offset and end time
  Duration? _serverTimeOffset;
  DateTime? _endTime;
  bool _isUpdatingServerTime = false;

  // Cache Future to prevent unnecessary rebuilds
  Future<HappyHourConfig?>? _cachedActiveConfigFuture;
  HappyHourSettings? _lastSettings;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _serverTimeRefreshTimer?.cancel();
    _timeRemainingNotifier.dispose();
    super.dispose();
  }

  // Initialize server time offset and calculate end time
  Future<void> _initializeTimer(HappyHourConfig config) async {
    // Cancel existing timers before starting new ones
    _countdownTimer?.cancel();
    _serverTimeRefreshTimer?.cancel();

    // Prevent concurrent initializations
    if (_isUpdatingServerTime) return;

    if (!mounted) return;

    _isUpdatingServerTime = true;
    try {
      // Get server time offset (cached in HappyHourHelper)
      final serverTime = await HappyHourHelper.getServerTime();

      if (!mounted) return;

      final localTime = DateTime.now();
      _serverTimeOffset = serverTime.difference(localTime);

      // Calculate end time using server time
      final endParts = config.endTime.split(':');
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);

      _endTime = DateTime(
        serverTime.year,
        serverTime.month,
        serverTime.day,
        endHour,
        endMinute,
      );

      // Start countdown with synchronous updates
      if (mounted) {
        _startCountdown();

        // Schedule periodic server time refresh (every 5 minutes)
        _serverTimeRefreshTimer = Timer.periodic(
          const Duration(minutes: 5),
          (timer) {
            if (!mounted) {
              timer.cancel();
              return;
            }
            _refreshServerTime(config);
          },
        );
      }
    } finally {
      _isUpdatingServerTime = false;
    }
  }

  // Refresh server time offset periodically
  Future<void> _refreshServerTime(HappyHourConfig config) async {
    if (_isUpdatingServerTime || !mounted) return;

    _isUpdatingServerTime = true;
    try {
      final serverTime = await HappyHourHelper.getServerTime();

      if (!mounted) return;

      final localTime = DateTime.now();
      _serverTimeOffset = serverTime.difference(localTime);

      // Recalculate end time
      final endParts = config.endTime.split(':');
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);

      _endTime = DateTime(
        serverTime.year,
        serverTime.month,
        serverTime.day,
        endHour,
        endMinute,
      );
    } finally {
      _isUpdatingServerTime = false;
    }
  }

  // Start countdown with synchronous time calculations
  void _startCountdown() {
    _countdownTimer?.cancel();

    // Initial update
    _updateTimeRemainingSync();

    // Update every second synchronously
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateTimeRemainingSync();
    });
  }

  // Synchronously calculate time remaining using cached offset
  void _updateTimeRemainingSync() {
    if (_endTime == null || _serverTimeOffset == null) {
      return;
    }

    // Calculate current server time using cached offset
    final estimatedServerTime = DateTime.now().add(_serverTimeOffset!);

    // Calculate remaining time
    final remaining = _endTime!.difference(estimatedServerTime);

    // Update ValueNotifier instead of setState to prevent full widget rebuild
    if (remaining.isNegative) {
      _timeRemainingNotifier.value = null;
      _countdownTimer?.cancel();
      // Trigger a rebuild to hide the banner when time expires
      if (mounted) {
        setState(() {});
      }
    } else {
      _timeRemainingNotifier.value = remaining;
    }
  }

  void _closeBanner() {
    // Cancel timers when banner is closed
    _countdownTimer?.cancel();
    _serverTimeRefreshTimer?.cancel();
    setState(() {
      _isBannerClosed = true;
    });
  }

  String _getDiscountText(HappyHourConfig config) {
    // Use currency symbol from database if available, fallback to hardcoded peso
    String currencySymbol = '₱'; // Default fallback
    if (currencyModel != null && currencyModel!.symbol.isNotEmpty) {
      currencySymbol = currencyModel!.symbol;
    }

    switch (config.promoType) {
      case 'fixed_amount':
        return '$currencySymbol ${config.promoValue.toStringAsFixed(0)} OFF';
      case 'percentage':
        return '${config.promoValue.toStringAsFixed(0)}% OFF';
      case 'free_delivery':
        return 'FREE DELIVERY';
      case 'reduced_delivery':
        return '$currencySymbol ${config.promoValue.toStringAsFixed(0)} OFF Delivery';
      default:
        return 'Special Offer';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Return empty widget if banner is closed
    if (_isBannerClosed) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<HappyHourSettings>(
      stream: HappyHourService.getHappyHourSettingsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final settings = snapshot.data!;

        if (!settings.enabled || settings.configs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Cache the Future to prevent unnecessary rebuilds
        // Only refresh if settings actually changed
        if (_lastSettings?.configs != settings.configs ||
            _lastSettings?.enabled != settings.enabled) {
          _cachedActiveConfigFuture =
              HappyHourHelper.getActiveHappyHour(settings);
          _lastSettings = settings;
        }

        // Check if Happy Hour is active
        return FutureBuilder<HappyHourConfig?>(
          future: _cachedActiveConfigFuture ??
              HappyHourHelper.getActiveHappyHour(settings),
          builder: (context, activeSnapshot) {
            if (activeSnapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }

            final activeConfig = activeSnapshot.data;

            if (activeConfig == null) {
              return const SizedBox.shrink();
            }

            // Initialize or update timer if config changed
            if (_activeConfig?.id != activeConfig.id) {
              _activeConfig = activeConfig;
              _initializeTimer(activeConfig);
            }

            // Don't show if timer is initialized and time expired
            // But show if timer hasn't been initialized yet (initialization is async)
            if (_endTime != null && _serverTimeOffset != null) {
              // Timer is initialized, check if time expired
              if (_timeRemainingNotifier.value == null ||
                  _timeRemainingNotifier.value!.isNegative) {
                return const SizedBox.shrink();
              }
            }
            // If timer not initialized yet, show banner (it will update once initialized)

            // Match CurrentOrdersBanner styling exactly
            final Color bgColor = isDarkMode(context)
                ? const Color(DarkContainerColor)
                : Colors.white;
            final Color borderColor = Color(COLOR_PRIMARY);

            return BottomBannerVisibilityReporter(
              bannerKey: 'happy_hour',
              visible: true,
              child: SafeArea(
                top: false,
              child: Container(
                margin: const EdgeInsets.all(12),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor, width: 2),
                        boxShadow: [
                          isDarkMode(context)
                              ? const BoxShadow()
                              : BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                        ],
                      ),
                      child: InkWell(
                        onTap: () {
                          // No navigation by default, or optional scroll
                        },
                        child: Row(
                          children: [
                            // Left icon/indicator
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 52,
                                height: 52,
                                color: Color(COLOR_PRIMARY).withOpacity(0.08),
                                child: Icon(
                                  Icons.timer,
                                  color: Color(COLOR_PRIMARY),
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Middle content (Expanded)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    activeConfig.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppinsm',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isDarkMode(context)
                                          ? Colors.white
                                          : const Color(0xFF000000),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  RichText(
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text:
                                              '${_getDiscountText(activeConfig)} • ',
                                          style: TextStyle(
                                            // Removed fontFamily to support peso sign character
                                            fontSize: 12,
                                            color: isDarkMode(context)
                                                ? Colors.white70
                                                : const Color(0xFF666666),
                                          ),
                                        ),
                                        TextSpan(
                                          text: 'Limited time only',
                                          style: TextStyle(
                                            fontFamily: 'Poppinsm',
                                            fontSize: 12,
                                            color: isDarkMode(context)
                                                ? Colors.white70
                                                : const Color(0xFF666666),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Right countdown - use ValueListenableBuilder to isolate updates
                            const SizedBox(width: 8),
                            ValueListenableBuilder<Duration?>(
                              valueListenable: _timeRemainingNotifier,
                              builder: (context, timeRemaining, child) {
                                return _TimerDisplay(
                                    timeRemaining: timeRemaining);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Close button in top-right corner (matching CurrentOrdersBanner)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _closeBanner,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isDarkMode(context)
                                ? Colors.black.withOpacity(0.6)
                                : Colors.white.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }
}
