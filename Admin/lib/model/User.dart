import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class User with ChangeNotifier {
  String email;
  String firstName;
  String lastName;
  String phoneNumber;
  bool active;
  Timestamp? lastOnlineTimestamp;
  Timestamp? createdAt;
  String userID;
  String profilePictureURL;
  String role;
  String? adminLevel;
  String? userLevel;

  User({
    this.email = '',
    this.userID = '',
    this.profilePictureURL = '',
    this.firstName = '',
    this.phoneNumber = '',
    this.lastName = '',
    this.active = true,
    Timestamp? lastOnlineTimestamp,
    Timestamp? createdAt,
    this.role = '',
    this.adminLevel,
    this.userLevel,
  })  : this.lastOnlineTimestamp = lastOnlineTimestamp ?? Timestamp.now(),
        this.createdAt = createdAt ?? Timestamp.now();

  String fullName() {
    return '$firstName $lastName';
  }

  factory User.fromJson(Map<String, dynamic> parsedJson) {
    return User(
      email: parsedJson['email'] ?? '',
      firstName: parsedJson['firstName'] ?? '',
      lastName: parsedJson['lastName'] ?? '',
      active: parsedJson['active'] ?? true,
      lastOnlineTimestamp: parsedJson['lastOnlineTimestamp'],
      phoneNumber: parsedJson['phoneNumber'] ?? '',
      userID: parsedJson['id'] ?? parsedJson['userID'] ?? '',
      profilePictureURL: parsedJson['profilePictureURL'] ?? '',
      role: parsedJson['role'] ?? parsedJson['userLevel'] ?? '',
      adminLevel: parsedJson['adminLevel'] as String?,
      userLevel: parsedJson['userLevel'] as String?,
      createdAt: parsedJson['createdAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': this.email,
      'firstName': this.firstName,
      'lastName': this.lastName,
      'phoneNumber': this.phoneNumber,
      'id': this.userID,
      'active': this.active,
      'lastOnlineTimestamp': this.lastOnlineTimestamp,
      'profilePictureURL': this.profilePictureURL,
      'role': this.role,
      'adminLevel': this.adminLevel,
      'userLevel': this.userLevel,
      'createdAt': this.createdAt,
    };
  }
}
