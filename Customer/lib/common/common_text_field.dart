import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../resources/colors.dart';

class CommonTextField extends StatefulWidget {
  const CommonTextField({
    super.key,
    this.label,
    this.labelText,
    this.labelStyle,
    this.helperText,
    this.helperTextStyle,
    this.helperPadding,
    this.hintText,
    this.hintTextStyle,
    this.textStyle,
    this.controller,
    this.focusNode,
    this.prefixIcon,
    this.suffixIcon,
    this.readOnly = false,
    this.textInputAction = TextInputAction.next,
    this.onTap,
    this.keyboardType = TextInputType.text,
    this.inputBorder,
    this.isEnabled = true,
    this.validator,
    this.onChanged,
    this.errorText,
    this.isSecure = false,
    this.maxLines = 2,
    this.minLines = 1,
    this.onFieldSubmitted,
    this.hasShowHideTextIcon = false,
    this.onFocusChange,
    this.inputFormatters,
    this.maxLength,
    this.fillColor,
    this.filled,
    this.contentPadding,
    this.isDense,
    this.prefixText,
    this.prefixStyle,
    this.prefixIconConstraints,
    this.fontFamily,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.onEditingComplete,
    this.isLoading = false
  });

  final String? helperText;
  final TextStyle? helperTextStyle;
  final EdgeInsetsGeometry? helperPadding;
  final EdgeInsetsGeometry? contentPadding;
  final String? labelText;
  final TextStyle? labelStyle;
  final String? hintText;
  final TextStyle? hintTextStyle;
  final TextStyle? textStyle;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextInputAction textInputAction;
  final TextInputType keyboardType;
  final InputBorder? inputBorder;
  final bool isEnabled;
  final String? errorText;
  final Function(String)? onChanged;
  final String? Function(String?)? validator;
  final bool isSecure;
  final bool hasShowHideTextIcon;
  final int? maxLines;
  final int? minLines;
  final Function(String)? onFieldSubmitted;
  final Function(bool)? onFocusChange;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool? filled;
  final Color? fillColor;
  final Widget? label;
  final bool? isDense;
  final String? prefixText;
  final TextStyle? prefixStyle;
  final BoxConstraints? prefixIconConstraints;
  final String? fontFamily;
  final bool autofocus;
  final TextAlign textAlign;
  final void Function()? onEditingComplete;
  final bool isLoading;

  @override
  CommonTextFieldState createState() => CommonTextFieldState();
}

class CommonTextFieldState extends State<CommonTextField> {

  bool _isTextShown = false;
  bool _isFocus = false;

  final _textEditingController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    _focusNode.addListener(_focusListener);
    super.initState();
  }

  void _focusListener() {
    setState(() {
      _isFocus =  _focusNode.hasFocus;
    });
    widget.onFocusChange?.call(_isFocus);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.helperText != null
        ? Padding(
          padding: widget.helperPadding ?? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 12.0),
          child: Text(
              widget.helperText!,
              style: widget.helperTextStyle ??
                  const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
            ),
        )
        : const SizedBox.shrink(),
        Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.blue,
              selectionColor: Colors.blue.shade200,
              selectionHandleColor: Colors.blue.shade200,
            ),
            colorScheme: const ColorScheme.light(
              primary: CustomColors.primary,
            ),
          ),
          child: TextFormField(
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            enabled: widget.isEnabled,
            readOnly: widget.readOnly,
            obscureText: widget.hasShowHideTextIcon ? !_isTextShown : widget.isSecure,
            controller: widget.controller ?? _textEditingController,
            focusNode: widget.focusNode ?? _focusNode,
            textInputAction: widget.textInputAction,
            keyboardType: widget.keyboardType,
            style: widget.textStyle ?? TextStyle(
              color: Colors.black87,
              fontSize: 14.0,
              fontWeight: FontWeight.w400,
              fontFamily: widget.fontFamily
            ),
            textAlign: widget.textAlign,
            inputFormatters: widget.inputFormatters,
            onFieldSubmitted: widget.onFieldSubmitted,
            maxLength: widget.maxLength,
            onChanged: widget.onChanged,
            onEditingComplete: widget.onEditingComplete,
            validator: widget.validator,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            decoration: InputDecoration(
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: widget.isDense,
              labelText: widget.labelText,
              labelStyle: widget.labelStyle,
              label: widget.label,
              filled: widget.filled,
              fillColor: (widget.isLoading) ? CustomColors.lightGray300 : widget.fillColor,
              counterText: "",
              contentPadding: widget.contentPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: widget.hintText,
              hintStyle: widget.hintTextStyle ?? const TextStyle(
                color: Colors.black38,
                fontSize: 14.0,
                fontWeight: FontWeight.w400,
              ),
              errorText: widget.errorText,
              errorStyle: const TextStyle(fontSize: 12.0, color: Colors.red, fontWeight: FontWeight.w500,),
              errorMaxLines: 5,
              border: widget.inputBorder,
              focusedBorder: widget.inputBorder,
              disabledBorder: widget.inputBorder,
              enabledBorder: widget.inputBorder,
              prefixIconConstraints: widget.prefixIconConstraints,
              prefixIcon: widget.prefixIcon != null ? Padding(
                padding: const EdgeInsets.only(
                  bottom: 2.0
                ),
                child: widget.prefixIcon,
              ) : null,
              prefixText: widget.prefixText,
              prefixStyle: widget.prefixStyle,
              suffixIcon: widget.suffixIcon ?? (widget.hasShowHideTextIcon
                ? _isTextShown
                    ? IconButton(
                      splashRadius: 20,
                        icon: const Icon(Icons.visibility_outlined, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _isTextShown = !_isTextShown;
                          });
                        },
                      )
                    : IconButton(
                      splashRadius: 20,
                        icon: const Icon(Icons.visibility_off_outlined, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _isTextShown = !_isTextShown;
                          });
                        },
                      )
                : null),
            ),
          ),
        ),
      ],
    );
  }
}