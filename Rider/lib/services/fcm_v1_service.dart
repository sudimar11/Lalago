import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FcmV1Service {
  static const String projectId = "lalago-v2";
  static const String fcmUrl =
      "https://fcm.googleapis.com/v1/projects/$projectId/messages:send";

  // ⚠️ WARNING: Service account credentials stored in app code is INSECURE!
  // This should only be used for development/testing.
  // For production, use a backend server to send FCM notifications.
  static const String serviceAccountJson = '''
{
  "type": "service_account",
  "project_id": "lalago-v2",
  "private_key_id": "b98c6f62158a725864dab59b77fff82b900b5d3b",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDmNmr1amFxoAtv\\nOC3JQMbqOlGCRAEt3gqten6dvN/q4e4ETYuJ6XoyTFv1i5YIAcP8RE4XhWhXFGzw\\n9bjSmrExH4JQ8MFc/H4820Jb3iWjqdScrMcK58Nzq5Gkl40SMJks9Bj2RV6gao9S\\nTTQC7btJl+hWSKV2B691fqqu/GjO7YIFI67bIzINfAw6KOgQqSbi8UZVc/FpgOAa\\nH5Be2734CMxs1dQFBnRk8DGYmei0i3RXL18wWqGKjVkud4ZbfgF8S1a/2jbRMkkB\\nJ7msWBNW6wt77n/1Ql6BBFjiA+imadJNCoRKkHzaPUlWNH3CduuTB6MHTXD0vTQk\\nNDZR+mj1AgMBAAECggEAAfz6U4BFsyuErcM4cgKDNUanqY5YzEKcqP7j1QzqiibF\\nXXgl+lzv1ztdl/NKqmsJfEZCvmVCj233uuUEYZ1AZoI1J+nMYbc0h+YE3rI+dPlk\\ngq3jUi7KO1eB/H/qkfuldwPsq0PSG2SQNE/CYTwYX/xV31jlRO2wED21z6kSZqcW\\nREY8OreW4PsJ/Mf99h8Z/x0hCDEv5Efwv0cvuycMVLCD2b0kxTDYeIp8pSAHxfWu\\n1ANoUSvyoHhxbLRzKayZjRmLbXZ4NhYLXga/cMF4dXcnXBvm9Hhw6pKdTQFIYM4G\\nwrv2R6U07a51gaYBhvlJ/dp7Tf0UUU5W/Gzq54aFQQKBgQD7PaqEV5oJw3ZOLcRu\\nZMptAXdUraBMg+5i1CrjasuEN8l9N6utFFZRHd8mTxJwsnlFQxvZhGTmKaYtktqy\\n9cdRe+Cht92y5wCrINthfMruYsl0PneSQhkLUU7GjOCEYRN6qMw2Rp1sXnuNCuGJ\\nOVd/p2/lJPN4I0piBQqEzByHaQKBgQDqksejTHAC8WjPUSaghH3hleLPlopViHmZ\\nq0zejX3qQ+91/Yjnd6VvinpYWmk1+iz3IYnf3n9SQam0lj3nPgTVOdCwDXXg1i1X\\nSS3UVvEBQErULmuXmEv6E+EMn/Shvl6uI3bV4c6fAennqobjz0/VPbJbEh8I7TGO\\n1e8yre3PrQKBgBpf/ualy6X6vxC1/UkZi6al4MEi+REPSJdXbqkxLOxUbvKWRY+F\\n8wnQ+PwskOMD2XdL9ECBhZYkCS3/nLXs11/WgV54zu1ZEtjkOiOh1ivwcvWhGSxh\\ng/+MKZjucSN0jXbzAX0xLJWT1aSY39RoEKd2DGkh1+1kxwpDPTdztgsBAoGANR6i\\nGOfBYdk7S99rqOP4AbLIlwvXLcFnEBaLpMZT4k4aFxUgAJLGoviv9fwbYT7TGe+9\\nYjXnjUATZzKyuAACZireiE+0BwNZZy/KMhCyKP9fMqeEc+LoKayAxTQf2NTcagDb\\n81lcSgPL7Utfmo0i3f5HunnjD0lvdJIbxdU/Sk0CgYBImS1hS1L14glJJ58cClKt\\nKpYy8oc21oFRpsRwY5Y42fFtfyusIK6NaZJC12z2A/RoOMjBIUQcKHoUnCWb23Lx\\nwowU4wvrRBxf+agVPk3kSg95mxqzvFebe6TNjf++9v0U31mWtzItpYh4FvOhfsly\\nLACo5DavMGNTFtk3o80csA==\\n-----END PRIVATE KEY-----\\n",
  "client_email": "firebase-adminsdk-fbsvc@lalago-v2.iam.gserviceaccount.com",
  "client_id": "101067610325350325339",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40lalago-v2.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
''';

  /// Gets OAuth 2.0 access token from service account credentials
  static Future<String> getAccessToken() async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(
        json.decode(serviceAccountJson),
      );

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(accountCredentials, scopes);

      final accessToken = client.credentials.accessToken.data;
      client.close();

      return accessToken;
    } catch (e) {
      debugPrint('Error getting access token: $e');
      rethrow;
    }
  }

  /// Sends FCM message using Firebase Cloud Messaging v1 API
  static Future<void> sendFcmMessage({
    required String title,
    required String body,
    required String fcmToken,
  }) async {
    if (fcmToken.isEmpty) {
      debugPrint("Error: FCM Token is empty. Cannot send notification.");
      return;
    }

    try {
      // Get fresh OAuth 2.0 access token
      final accessToken = await getAccessToken();

      final headers = {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

      final payload = {
        "message": {
          "token": fcmToken,
          "notification": {
            "title": title,
            "body": body,
          },
          "android": {
            "priority": "high",
            "notification": {
              "sound": "default",
            },
          },
          "apns": {
            "payload": {
              "aps": {
                "sound": "default",
              },
            },
          },
        },
      };

      final response = await http.post(
        Uri.parse(fcmUrl),
        headers: headers,
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM message sent successfully: ${response.body}');
      } else {
        debugPrint(
          'Failed to send FCM message: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint("Error sending FCM: $e");
    }
  }
}

