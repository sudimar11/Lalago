import 'package:flutter/material.dart';

class CommonTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final TextStyle? helperTextStyle;
  final TextStyle? hintTextStyle;
  final InputBorder? inputBorder;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool hasShowHideTextIcon;
  final int? maxLines;
  final Function(String)? onFieldSubmitted;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  const CommonTextField({
    Key? key,
    this.controller,
    this.hintText,
    this.helperText,
    this.helperTextStyle,
    this.hintTextStyle,
    this.inputBorder,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.hasShowHideTextIcon = false,
    this.maxLines = 1,
    this.onFieldSubmitted,
    this.focusNode,
    this.onChanged,
  }) : super(key: key);

  @override
  State<CommonTextField> createState() => _CommonTextFieldState();
}

class _CommonTextFieldState extends State<CommonTextField> {
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              widget.helperText!,
              style: widget.helperTextStyle ??
                  const TextStyle(
                    color: Colors.black,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          validator: widget.validator,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction ?? TextInputAction.next,
          obscureText: widget.hasShowHideTextIcon ? _obscureText : widget.obscureText,
          maxLines: widget.maxLines,
          onFieldSubmitted: widget.onFieldSubmitted,
          onChanged: widget.onChanged,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w400,
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: widget.hintTextStyle ??
                TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w400,
                ),
            border: widget.inputBorder,
            enabledBorder: widget.inputBorder,
            focusedBorder: widget.inputBorder,
            errorBorder: widget.inputBorder,
            focusedErrorBorder: widget.inputBorder,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
            suffixIcon: widget.hasShowHideTextIcon
                ? IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: _togglePasswordVisibility,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}
