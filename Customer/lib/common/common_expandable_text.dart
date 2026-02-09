import 'package:flutter/material.dart';

class CommonExpandableText extends StatefulWidget {
  final String text;
  final int trimLines;
  final TextStyle? textStyle;
  final TextStyle? toggleTextStyle;
  final String expandText;
  final String collapseText;

  const CommonExpandableText({
    super.key,
    required this.text,
    this.trimLines = 5,
    this.textStyle,
    this.toggleTextStyle,
    this.expandText = "See all",
    this.collapseText = "Hide",
  });

  @override
  State<CommonExpandableText> createState() => _CommonExpandableTextState();
}

class _CommonExpandableTextState extends State<CommonExpandableText>
    with SingleTickerProviderStateMixin {
  bool isExpanded = false;
  bool isOverflowing = false;

  @override
  Widget build(BuildContext context) {
    final defaultTextStyle = widget.textStyle ??
    const TextStyle(
      color: Colors.black87,
      fontSize: 14.0,
      fontWeight: FontWeight.w400,
      fontFamily: "Poppinsl",
    );

    final defaultToggleStyle = widget.toggleTextStyle ??
    const TextStyle(
      color: Colors.blue,
      fontWeight: FontWeight.w600,
      fontFamily: "Poppinsm",
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: defaultTextStyle),
          textDirection: TextDirection.ltr,
          maxLines: widget.trimLines,
        )..layout(maxWidth: constraints.maxWidth);

        final newIsOverflowing = textPainter.didExceedMaxLines;
        if (newIsOverflowing != isOverflowing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => isOverflowing = newIsOverflowing);
          });
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: isExpanded
                      ? widget.text
                      : _trimText(widget.text, widget.trimLines, constraints, defaultTextStyle),
                  style: defaultTextStyle,
                ),
                if (isOverflowing)
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () => setState(() => isExpanded = !isExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          isExpanded ? widget.collapseText : widget.expandText,
                          style: defaultToggleStyle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _trimText(String text, int maxLines, BoxConstraints constraints, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: "...",
    )..layout(maxWidth: constraints.maxWidth);

    if (textPainter.didExceedMaxLines) {
      int endIndex = textPainter.getPositionForOffset(
        Offset(constraints.maxWidth, textPainter.height),
      ).offset;
      return text.substring(0, endIndex).trim();
    } else {
      return text;
    }
  }
}
