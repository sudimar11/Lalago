class CodModel {
  bool cod;

  CodModel({
    this.cod = false,
  });

  factory CodModel.fromJson(Map<String, dynamic> parsedJson) {
    final v = parsedJson['isEnabled'];
    return CodModel(
      cod: v == true || v == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': this.cod,
    };
  }
}
