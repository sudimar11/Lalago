import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/pre_validation_service.dart';
import 'package:foodie_customer/widgets/pre_validation/pre_validation_step_tile.dart';

/// Main pre-validation UI shown in a modal.
class PreValidationWidget extends StatefulWidget {
  final List<ValidationStepResult> steps;
  final bool canProceed;
  final bool hasErrors;
  final bool hasWarnings;
  final bool isComplete;
  final VoidCallback? onRetry;
  final VoidCallback? onProceed;
  final VoidCallback? onCancel;

  const PreValidationWidget({
    super.key,
    required this.steps,
    required this.canProceed,
    required this.hasErrors,
    required this.hasWarnings,
    required this.isComplete,
    this.onRetry,
    this.onProceed,
    this.onCancel,
  });

  @override
  State<PreValidationWidget> createState() => _PreValidationWidgetState();
}

class _PreValidationWidgetState extends State<PreValidationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _successController;
  late Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );
  }

  @override
  void didUpdateWidget(PreValidationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isComplete &&
        widget.canProceed &&
        !oldWidget.isComplete &&
        _successController.status != AnimationStatus.completed) {
      _successController.forward();
    }
  }

  @override
  void dispose() {
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final theme = Theme.of(context).textTheme;
    final backgroundColor = dark ? Colors.grey.shade900 : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(dark, theme),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.isComplete && widget.canProceed)
                    _buildSuccessBanner(dark),
                  ...widget.steps.map(
                    (s) => PreValidationStepTile(key: ValueKey(s.id), result: s),
                  ),
                ],
              ),
            ),
          ),
          _buildActions(dark, theme),
        ],
      ),
    );
  }

  Widget _buildHeader(bool dark, TextTheme theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Text(
            widget.isComplete
                ? (widget.canProceed ? 'Ready to order' : 'Validation complete')
                : 'Validating your order',
            style: theme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: dark ? Colors.grey.shade100 : Colors.grey.shade900,
            ),
          ),
          const Spacer(),
          if (widget.onCancel != null)
            IconButton(
              icon: Icon(
                Icons.close,
                color: dark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              onPressed: widget.onCancel,
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner(bool dark) {
    return AnimatedBuilder(
      animation: _successScale,
      builder: (context, child) => Transform.scale(
        scale: _successScale.value,
        child: child,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'All checks passed! You can proceed with your order.',
                style: TextStyle(
                  color: dark ? Colors.grey.shade200 : Colors.grey.shade800,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(bool dark, TextTheme theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: dark ? Colors.grey.shade900 : Colors.white,
        border: Border(
          top: BorderSide(
            color: dark ? Colors.grey.shade700 : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.onCancel != null)
            TextButton(
              onPressed: widget.onCancel,
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          const Spacer(),
          if (widget.hasErrors && widget.onRetry != null)
            OutlinedButton(
              onPressed: widget.onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(COLOR_PRIMARY),
                side: BorderSide(color: Color(COLOR_PRIMARY)),
              ),
              child: const Text('Retry'),
            ),
          if (widget.hasErrors && widget.onRetry != null) const SizedBox(width: 12),
          if (widget.canProceed && widget.onProceed != null)
            ElevatedButton(
              onPressed: widget.onProceed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(COLOR_PRIMARY),
                foregroundColor: isDarkMode(context) ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Proceed'),
            ),
        ],
      ),
    );
  }
}
