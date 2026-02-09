extension StringExt on String? {
  String removeNullWord() {
    if (this == null) return '';
    return this!
    .replaceAll(RegExp(r'\bnull,\b', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
  }

  String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Email is empty";
    }

    String pattern =
        r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$';
    RegExp regex = RegExp(pattern);

    if (!regex.hasMatch(value)) {
      return "Please enter a valid email address";
    }

    final allowedDomains = ['gmail.com', 'yahoo.com', 'outlook.com'];
    final domain = value.split('@').last.toLowerCase();

    if (!allowedDomains.contains(domain)) {
      return "Only Gmail, Yahoo, or Outlook emails are allowed";
    }

    return null;
  }
}
