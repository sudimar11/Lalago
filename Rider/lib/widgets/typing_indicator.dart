import 'package:flutter/material.dart';
import 'package:foodie_driver/services/helper.dart';

class TypingIndicator extends StatefulWidget {
  final List<String> typingUserIds;
  final Function(String)? onUserTap;

  const TypingIndicator({
    Key? key,
    required this.typingUserIds,
    this.onUserTap,
  }) : super(key: key);

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typingUserIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Typing dots animation
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDot(0),
                  const SizedBox(width: 4),
                  _buildDot(1),
                  const SizedBox(width: 4),
                  _buildDot(2),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          // Typing text
          Text(
            widget.typingUserIds.length == 1
                ? 'Someone is typing...'
                : '${widget.typingUserIds.length} people are typing...',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: isDarkMode(context) ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final delay = index * 0.2;
    final value = ((_animation.value + delay) % 1.0);
    final opacity = value < 0.5 ? value * 2 : (1.0 - value) * 2;

    return Opacity(
      opacity: opacity.clamp(0.3, 1.0),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: isDarkMode(context) ? Colors.grey.shade400 : Colors.grey.shade600,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

