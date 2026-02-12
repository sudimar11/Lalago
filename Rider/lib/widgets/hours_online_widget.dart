import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:http/http.dart' as http;

class HoursOnlineWidget extends StatefulWidget {
  final User user;

  const HoursOnlineWidget({
    Key? key,
    required this.user,
  }) : super(key: key);

  @override
  State<HoursOnlineWidget> createState() => _HoursOnlineWidgetState();
}

class _HoursOnlineWidgetState extends State<HoursOnlineWidget> {
  Timer? _timer;
  String _hoursText = 'Offline';
  bool _isOnline = false;

  Duration _getUpdateInterval() {
    final hasActiveOrder = widget.user.inProgressOrderID != null &&
        widget.user.inProgressOrderID!.isNotEmpty;
    return hasActiveOrder
        ? const Duration(minutes: 1)
        : const Duration(minutes: 5);
  }

  @override
  void initState() {
    super.initState();
    _updateHoursOnline();
    // Update interval based on active order status
    _timer = Timer.periodic(_getUpdateInterval(), (_) {
      if (mounted) {
        _updateHoursOnline();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _updateHoursOnline();
    _timer = Timer.periodic(_getUpdateInterval(), (_) {
      if (mounted) {
        _updateHoursOnline();
      }
    });
  }

  @override
  void didUpdateWidget(HoursOnlineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // #region agent log
    http
        .post(
            Uri.parse(
                'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'location': 'hours_online_widget.dart:42',
              'message': 'didUpdateWidget called',
              'data': {
                'oldCheckedInToday': oldWidget.user.checkedInToday,
                'newCheckedInToday': widget.user.checkedInToday,
                'oldCheckedOutToday': oldWidget.user.checkedOutToday,
                'newCheckedOutToday': widget.user.checkedOutToday
              },
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'sessionId': 'debug-session',
              'runId': 'checkout-test',
              'hypothesisId': 'D'
            }))
        .catchError((_) => http.Response('', 500));
    // #endregion
    // Update when user object changes
    if (oldWidget.user.todayCheckInTime != widget.user.todayCheckInTime ||
        oldWidget.user.checkedInToday != widget.user.checkedInToday) {
      // #region agent log
      http
          .post(
              Uri.parse(
                  'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'location': 'hours_online_widget.dart:47',
                'message': 'didUpdateWidget triggered _updateHoursOnline',
                'data': {
                  'checkedInTodayChanged': oldWidget.user.checkedInToday !=
                      widget.user.checkedInToday,
                  'todayCheckInTimeChanged': oldWidget.user.todayCheckInTime !=
                      widget.user.todayCheckInTime
                },
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'sessionId': 'debug-session',
                'runId': 'checkout-test',
                'hypothesisId': 'D'
              }))
          .catchError((_) => http.Response('', 500));
      // #endregion
      _updateHoursOnline();
    }

    // Check if order status changed and restart timer with new interval
    final oldHasOrder = oldWidget.user.inProgressOrderID != null &&
        oldWidget.user.inProgressOrderID!.isNotEmpty;
    final newHasOrder = widget.user.inProgressOrderID != null &&
        widget.user.inProgressOrderID!.isNotEmpty;
    if (oldHasOrder != newHasOrder) {
      _restartTimer();
    }
  }

  void _updateHoursOnline() {
    // #region agent log
    http
        .post(
            Uri.parse(
                'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'location': 'hours_online_widget.dart:51',
              'message': '_updateHoursOnline called',
              'data': {
                'checkedInToday': widget.user.checkedInToday,
                'checkedOutToday': widget.user.checkedOutToday,
                'isOnline': widget.user.isOnline
              },
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'sessionId': 'debug-session',
              'runId': 'checkout-test',
              'hypothesisId': 'B'
            }))
        .catchError((_) => http.Response('', 500));
    // #endregion
    final now = DateTime.now();
    Duration onlineDuration = Duration.zero;
    String hoursText = 'Offline';
    bool isOnline = false;

    // Check if user is checked in today
    if (widget.user.checkedInToday == true) {
      // #region agent log
      http
          .post(
              Uri.parse(
                  'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'location': 'hours_online_widget.dart:58',
                'message': 'User marked as online (checkedInToday==true)',
                'data': {
                  'checkedInToday': widget.user.checkedInToday,
                  'checkedOutToday': widget.user.checkedOutToday,
                  'isOnline': widget.user.isOnline
                },
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'sessionId': 'debug-session',
                'runId': 'checkout-test',
                'hypothesisId': 'A-B'
              }))
          .catchError((_) => http.Response('', 500));
      // #endregion
      isOnline = true;
      // Use todayCheckInTime if available, otherwise fallback to checkInTime
      String? checkInTimeString =
          widget.user.todayCheckInTime?.isNotEmpty == true
              ? widget.user.todayCheckInTime
              : widget.user.checkInTime;

      if (checkInTimeString != null && checkInTimeString.isNotEmpty) {
        try {
          final checkInDateTime = _parseTimeString(checkInTimeString);
          // Calculate duration from check-in to now
          onlineDuration = now.difference(checkInDateTime);

          // Only show positive duration (if check-in was today and before now)
          if (onlineDuration.isNegative) {
            onlineDuration = Duration.zero;
          }
        } catch (e) {
          // If parsing fails, fallback to lastOnlineTimestamp
          final lastOnline = widget.user.lastOnlineTimestamp?.toDate() ?? now;
          onlineDuration = now.difference(lastOnline);
          if (onlineDuration.isNegative) {
            onlineDuration = Duration.zero;
          }
        }
      } else {
        // Fallback to lastOnlineTimestamp if no check-in time
        final lastOnline = widget.user.lastOnlineTimestamp?.toDate() ?? now;
        onlineDuration = now.difference(lastOnline);
        if (onlineDuration.isNegative) {
          onlineDuration = Duration.zero;
        }
      }

      // Format hours display
      if (onlineDuration.inSeconds > 0) {
        final totalMinutes = onlineDuration.inMinutes;
        final hours = totalMinutes ~/ 60;
        final minutes = totalMinutes % 60;

        if (hours < 1) {
          hoursText = '${minutes}m';
        } else if (hours < 24) {
          if (minutes > 0) {
            hoursText = '${hours}h ${minutes}m';
          } else {
            hoursText = '${hours}h';
          }
        } else {
          final days = hours ~/ 24;
          final remainingHours = hours % 24;
          if (remainingHours > 0) {
            hoursText = '${days}d ${remainingHours}h';
          } else {
            hoursText = '${days}d';
          }
        }
      } else {
        // User is checked in but duration is zero (just checked in)
        hoursText = 'Just checked in';
      }
    } else {
      // User is not checked in today, show offline
      // #region agent log
      http
          .post(
              Uri.parse(
                  'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'location': 'hours_online_widget.dart:121',
                'message': 'User marked as offline (checkedInToday!=true)',
                'data': {
                  'checkedInToday': widget.user.checkedInToday,
                  'checkedOutToday': widget.user.checkedOutToday,
                  'isOnline': widget.user.isOnline
                },
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'sessionId': 'debug-session',
                'runId': 'checkout-test',
                'hypothesisId': 'B'
              }))
          .catchError((_) => http.Response('', 500));
      // #endregion
      hoursText = 'Offline';
      isOnline = false;
    }

    if (mounted) {
      // #region agent log
      http
          .post(
              Uri.parse(
                  'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'location': 'hours_online_widget.dart:126',
                'message': 'Setting state in widget',
                'data': {
                  'hoursText': hoursText,
                  'isOnline': isOnline,
                  'checkedInToday': widget.user.checkedInToday
                },
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'sessionId': 'debug-session',
                'runId': 'checkout-test',
                'hypothesisId': 'C'
              }))
          .catchError((_) => http.Response('', 500));
      // #endregion
      setState(() {
        _hoursText = hoursText;
        _isOnline = isOnline;
      });
    }
  }

  /// Parse time string in "h:mm a" format (e.g., "10:57 AM")
  DateTime _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(' ');
      if (parts.length == 2) {
        final timePart = parts[0];
        final period = parts[1];
        final timeParts = timePart.split(':');
        if (timeParts.length == 2) {
          int hour = int.parse(timeParts[0]);
          int minute = int.parse(timeParts[1]);

          if (period.toLowerCase() == 'pm' && hour != 12) {
            hour += 12;
          } else if (period.toLowerCase() == 'am' && hour == 12) {
            hour = 0;
          }

          // Create DateTime for today with the parsed time
          final now = DateTime.now();
          return DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
    } catch (e) {
      // If parsing fails, return current time
    }
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Clock or status icon
          Icon(
            _isOnline ? Icons.access_time : Icons.offline_bolt,
            color: isDarkMode(context) ? Colors.white : Colors.black,
            size: 14,
          ),
          const SizedBox(width: 4),
          // Hours online text
          Text(
            _hoursText,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
