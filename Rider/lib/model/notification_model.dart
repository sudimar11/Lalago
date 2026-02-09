enum NotificationType {
  order,
  earning,
  performance,
  reminder,
}

enum NotificationPriority {
  low,
  normal,
  high,
  critical,
}

class NotificationData {
  final NotificationType type;
  final String title;
  final String body;
  final NotificationPriority priority;
  final Map<String, dynamic>? payload;
  final int? notificationId;

  const NotificationData({
    required this.type,
    required this.title,
    required this.body,
    this.priority = NotificationPriority.normal,
    this.payload,
    this.notificationId,
  });
}

// Original NotificationModel class (used by FirebaseHelper)
class NotificationModel {
  String id;
  String message;
  String subject;
  String type;

  NotificationModel({
    required this.id,
    required this.message,
    required this.subject,
    required this.type,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] ?? '',
      message: json['message'] ?? '',
      subject: json['subject'] ?? '',
      type: json['type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'message': message,
      'subject': subject,
      'type': type,
    };
  }
}
