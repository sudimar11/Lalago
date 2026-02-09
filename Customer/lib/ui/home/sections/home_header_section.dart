import 'package:flutter/material.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/chat_read_service.dart';
import 'dart:async';
import 'dart:developer';

void _badgeLog(String message) => log('[BADGE] $message');

// Separate widget for rotating hint text
class RotatingHintText extends StatefulWidget {
  final List<String> hints;
  final Duration interval;
  final TextStyle? textStyle;

  const RotatingHintText({
    Key? key,
    required this.hints,
    this.interval = const Duration(seconds: 3),
    this.textStyle,
  }) : super(key: key);

  @override
  State<RotatingHintText> createState() => _RotatingHintTextState();
}

class _RotatingHintTextState extends State<RotatingHintText> {
  int currentIndex = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    timer = Timer.periodic(widget.interval, (timer) {
      if (mounted) {
        setState(() {
          currentIndex = (currentIndex + 1) % widget.hints.length;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: Text(
        widget.hints[currentIndex],
        key: ValueKey(currentIndex),
        style: widget.textStyle ??
            const TextStyle(
              color: Color(0xFF9CA3AF),
              fontFamily: 'Poppinsr',
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
      ),
    );
  }
}

class HomeHeaderSection extends StatelessWidget {
  final String? selctedOrderTypeValue;
  final List<String> rotatingHints;
  final Function(String?) onOrderTypeChanged;
  final VoidCallback onLocationTap;
  final VoidCallback onSearchTap;
  final VoidCallback onMessageTap;
  final VoidCallback onFavoriteTap;

  const HomeHeaderSection({
    Key? key,
    required this.selctedOrderTypeValue,
    required this.rotatingHints,
    required this.onOrderTypeChanged,
    required this.onLocationTap,
    required this.onSearchTap,
    required this.onMessageTap,
    required this.onFavoriteTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    _badgeLog('HomeHeader build - widget rebuilt');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/pis.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10.0),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/images/riderlogo.png',
                        width: 50,
                        height: 50,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 5),
                      Column(
                        children: [
                          Image.asset(
                            'assets/images/namewith.png',
                            width: 90,
                            height: 60,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                      const SizedBox(width: 140),
                      // Message icon
                      GestureDetector(
                        onTap: onMessageTap,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Builder(
                                builder: (context) {
                                  if (MyAppState.currentUser == null) {
                                    _badgeLog(
                                        'HomeHeader badge - User is null, hiding badge');
                                    return const SizedBox.shrink();
                                  }

                                  final userID = MyAppState.currentUser!.userID;
                                  if (userID.isEmpty) {
                                    _badgeLog(
                                        'HomeHeader badge - userID is empty, hiding badge');
                                    return const SizedBox.shrink();
                                  }

                                  _badgeLog(
                                      'HomeHeader badge - Initializing StreamBuilder for userID: $userID');
                                  return StreamBuilder<int>(
                                    stream: ChatReadService
                                        .getTotalUnreadCountStream(userID),
                                    builder: (context, snapshot) {
                                      _badgeLog(
                                          'HomeHeader badge - ConnectionState: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}, data: ${snapshot.data}');
                                      if (snapshot.hasError) {
                                        _badgeLog(
                                            'HomeHeader badge - Error: ${snapshot.error}');
                                      }

                                      final totalUnread = snapshot.data ?? 0;
                                      _badgeLog(
                                          'HomeHeader badge - Total unread: $totalUnread');

                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        _badgeLog(
                                            'HomeHeader badge - Waiting for unread count, hiding badge');
                                        return const SizedBox.shrink();
                                      }

                                      if (totalUnread <= 0) {
                                        _badgeLog(
                                            'HomeHeader badge - Count is 0 or negative, hiding badge');
                                        return const SizedBox.shrink();
                                      }

                                      _badgeLog(
                                          'HomeHeader badge - ✅ Showing badge with count: $totalUnread');

                                      final displayCount = totalUnread > 99
                                          ? '99+'
                                          : '$totalUnread';
                                      final badgeSize =
                                          totalUnread > 99 ? 24.0 : 18.0;

                                      return Container(
                                        width: badgeSize,
                                        height: badgeSize,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            displayCount,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Favorite icon
                      GestureDetector(
                        onTap: onFavoriteTap,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.favorite_border,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(
                    left: 10,
                    right: 10,
                    bottom: 5,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            "Search food or restaurants",
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontFamily: "Poppinssb",
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: selctedOrderTypeValue == null,
                        child: DropdownButton<String>(
                          value: selctedOrderTypeValue,
                          isDense: true,
                          dropdownColor: Colors.black,
                          onChanged: onOrderTypeChanged,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                          ),
                          items: const [
                            'Delivery',
                            'Takeaway',
                          ].map((location) {
                            return DropdownMenuItem<String>(
                              value: location,
                              child: Text(
                                location,
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onSearchTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Colors.white,
                            Color(0xFFF8FAFC),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(25.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.8),
                            blurRadius: 1,
                            offset: const Offset(0, 1),
                            spreadRadius: 0,
                          ),
                        ],
                        border: Border.all(
                          color: Colors.grey.shade100,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(left: 16, right: 12),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFF8C42),
                                  Color(0xFFFF6B35),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFFFF8C42).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                right: 16,
                                top: 16,
                                bottom: 16,
                              ),
                              child: RotatingHintText(
                                hints: rotatingHints,
                                interval: const Duration(seconds: 3),
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.mic_rounded,
                              color: Color(0xFF64748B),
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // User profile avatar
                      if (MyAppState.currentUser != null)
                        Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.orange,
                                width: 2.0,
                              ),
                            ),
                            child: ClipOval(
                              child: displayImage(
                                MyAppState.currentUser!.profilePictureURL,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: GestureDetector(
                          onTap: onLocationTap,
                          child: Text(
                            MyAppState.selectedPosotion
                                .getFullAddress()
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: "Poppinsr",
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
