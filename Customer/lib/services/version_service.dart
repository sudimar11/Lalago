import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';

class VersionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static bool _updateDialogShownThisSession = false;

  /// Fetches the latest version from Firestore
  static Future<String?> getLatestVersion() async {
    try {
      final doc = await _firestore.collection(Setting).doc('Version').get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['latest_version']?.toString();
      }
    } catch (e) {
      debugPrint('Error fetching latest version: $e');
    }
    return null;
  }

  /// Gets the current app version
  static Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      debugPrint('Error getting current version: $e');
      return '0.0.0';
    }
  }

  /// Compares two version strings (e.g., "3.2.6" vs "3.2.7")
  /// Returns:
  /// - negative if current < latest
  /// - 0 if current == latest
  /// - positive if current > latest
  static int compareVersions(String current, String latest) {
    try {
      List<int> currentParts = current.split('.').map(int.parse).toList();
      List<int> latestParts = latest.split('.').map(int.parse).toList();

      // Pad shorter version with zeros
      while (currentParts.length < latestParts.length) {
        currentParts.add(0);
      }
      while (latestParts.length < currentParts.length) {
        latestParts.add(0);
      }

      for (int i = 0; i < currentParts.length; i++) {
        if (currentParts[i] < latestParts[i]) return -1;
        if (currentParts[i] > latestParts[i]) return 1;
      }
      return 0;
    } catch (e) {
      debugPrint('Error comparing versions: $e');
      return 0; // Assume equal if comparison fails
    }
  }

  /// Checks if an update is available and shows dialog if needed
  static Future<void> checkForUpdate(BuildContext context) async {
    // Skip if already shown this session
    if (_updateDialogShownThisSession) {
      return;
    }

    try {
      final currentVersion = await getCurrentVersion();
      final latestVersion = await getLatestVersion();

      if (latestVersion != null) {
        final comparison = compareVersions(currentVersion, latestVersion);

        if (comparison < 0) {
          // Mark as shown before displaying
          _updateDialogShownThisSession = true;
          _showUpdateDialog(context, currentVersion, latestVersion);
        }
      }
    } catch (e) {
      debugPrint('Error checking for update: $e');
    }
  }

  /// Shows the update dialog with Update Now and Later options
  static void _showUpdateDialog(
      BuildContext context, String currentVersion, String latestVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(
                Icons.system_update,
                color: Color(COLOR_PRIMARY),
                size: 30,
              ),
              SizedBox(width: 10),
              Text(
                'Update Available',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(COLOR_PRIMARY),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version of the app is available.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                'Current Version: $currentVersion',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                'Latest Version: $latestVersion',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(COLOR_PRIMARY),
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 15),
              Text(
                'Update now to enjoy the latest features and improvements.',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Later',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _launchPlayStore();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(COLOR_PRIMARY),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Update Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Launches the Play Store to update the app
  static Future<void> _launchPlayStore() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final packageName = packageInfo.packageName;

      // Try to open in Play Store app first
      final playStoreUri = Uri.parse('market://details?id=$packageName');
      if (await canLaunchUrl(playStoreUri)) {
        await launchUrl(playStoreUri);
      } else {
        // Fallback to web browser
        final webUri = Uri.parse(
            'https://play.google.com/store/apps/details?id=$packageName');
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      debugPrint('Error launching Play Store: $e');
    }
  }
}
