/// Model for restaurant working hours.
/// Matches Firestore structure used by Customer/Rider/Restaurant apps.
class WorkingHoursModel {
  WorkingHoursModel({this.day, List<Timeslot>? timeslot})
      : timeslot = timeslot ?? [];

  String? day;
  List<Timeslot> timeslot;

  factory WorkingHoursModel.fromJson(Map<String, dynamic> json) {
    final day = json['day']?.toString();
    List<Timeslot> slots = [];
    if (json['timeslot'] != null && json['timeslot'] is List) {
      for (final v in json['timeslot'] as List) {
        if (v is Map<String, dynamic>) {
          try {
            slots.add(Timeslot.fromJson(v));
          } catch (_) {
            // skip malformed slot
          }
        }
      }
    }
    return WorkingHoursModel(day: day, timeslot: slots);
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'timeslot': timeslot.map((v) => v.toJson()).toList(),
    };
  }
}

class Timeslot {
  Timeslot({this.from, this.to});

  String? from;
  String? to;

  factory Timeslot.fromJson(Map<String, dynamic> json) {
    return Timeslot(
      from: json['from']?.toString(),
      to: json['to']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from ?? '',
      'to': to ?? '',
    };
  }
}
