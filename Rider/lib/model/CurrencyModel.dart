class CurrencyModel {
  String code;

  int decimal;

  String id;

  bool isactive;

  int rounding;

  String name;

  String symbol;

  bool symbolatright;

  CurrencyModel({
    this.code = '',
    this.decimal = 0,
    this.isactive = false,
    this.id = '',
    this.name = '',
    this.rounding = 0,
    this.symbol = '',
    this.symbolatright = false,
  });

  factory CurrencyModel.fromJson(Map<String, dynamic> parsedJson) {
    return CurrencyModel(
      code: parsedJson['code']?.toString() ?? '',
      decimal: _parseInt(parsedJson['decimal_degits'], 0),
      isactive: _parseBool(parsedJson['isActive'], false),
      id: parsedJson['id']?.toString() ?? '',
      name: parsedJson['name']?.toString() ?? '',
      rounding: _parseInt(parsedJson['rounding'], 0),
      symbol: parsedJson['symbol']?.toString() ?? '',
      symbolatright: _parseBool(parsedJson['symbolAtRight'], false),
    );
  }

  static int _parseInt(dynamic v, int def) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final n = int.tryParse(v.toString());
    return n ?? def;
  }

  static bool _parseBool(dynamic v, bool def) {
    if (v == null) return def;
    if (v is bool) return v;
    if (v.toString().toLowerCase() == 'true') return true;
    if (v.toString().toLowerCase() == 'false') return false;
    return def;
  }

  Map<String, dynamic> toJson() {
    return {
      'code': this.code,
      'decimal_degits': this.decimal,
      'isActive': this.isactive,
      'rounding': this.rounding,
      'id': this.id,
      'name': this.name,
      'symbol': this.symbol,
      'symbolAtRight': this.symbolatright,
    };
  }
}
