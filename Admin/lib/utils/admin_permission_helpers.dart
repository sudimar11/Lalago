import 'package:brgy/constants.dart';
import 'package:brgy/model/User.dart';

/// Returns true if the user is an admin (role or userLevel).
bool isAdmin(User? user) {
  if (user == null) return false;
  return user.role == USER_ROLE_ADMIN ||
      user.userLevel == USER_ROLE_ADMIN;
}

/// Returns true if the user has super admin access (can edit roles, batch ops).
bool isSuperAdmin(User? user) {
  if (user == null || !isAdmin(user)) return false;
  if (user.adminLevel == ADMIN_LEVEL_LIMITED) return false;
  return user.adminLevel == ADMIN_LEVEL_SUPER ||
      user.role == USER_ROLE_ADMIN ||
      user.userLevel == USER_ROLE_ADMIN;
}

/// Returns true if the user can edit roles and perform batch operations.
bool canEditRoles(User? user) => isSuperAdmin(user);
