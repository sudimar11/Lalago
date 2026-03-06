import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/pre_validation_service.dart';

/// Single row for a validation step with icon, label, and optional message.
class PreValidationStepTile extends StatefulWidget {
  final ValidationStepResult result;

  const PreValidationStepTile({super.key, required this.result});

  @override
  State<PreValidationStepTile> createState() => _PreValidationStepTileState();
}

class _PreValidationStepTileState extends State<PreValidationStepTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final theme = Theme.of(context).textTheme;

    Widget iconWidget;
    if (widget.result.status == ValidationStatus.loading) {
      iconWidget = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Opacity(
          opacity: _pulseAnimation.value,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(COLOR_PRIMARY)),
            ),
          ),
        ),
      );
    } else {
      iconWidget = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildStatusIcon(dark),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconWidget,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.result.label,
                  style: theme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dark ? Colors.grey.shade200 : Colors.grey.shade900,
                  ),
                ),
                if (widget.result.message != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.result.message!,
                    style: theme.bodySmall?.copyWith(
                      color: dark ? Colors.grey.shade400 : Colors.grey.shade700,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (widget.result.actionHint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.result.actionHint!,
                    style: theme.bodySmall?.copyWith(
                      color: Color(COLOR_PRIMARY),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(bool dark) {
    final Color color;
    final IconData icon;

    switch (widget.result.status) {
      case ValidationStatus.success:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case ValidationStatus.warning:
        color = Colors.amber;
        icon = Icons.warning_amber_rounded;
        break;
      case ValidationStatus.error:
        color = Colors.red;
        icon = Icons.error;
        break;
      default:
        color = dark ? Colors.grey.shade600 : Colors.grey.shade400;
        icon = Icons.radio_button_unchecked;
    }

    return Icon(icon, color: color, size: 24, key: ValueKey(widget.result.status));
  }
}
