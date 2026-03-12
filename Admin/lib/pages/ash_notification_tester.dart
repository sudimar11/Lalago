import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase, FirebaseException;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Test dashboard for Ash notifications. Allows triggering notifications
/// on-demand for specific users with configurable context.
class AshNotificationTesterPage extends StatefulWidget {
  const AshNotificationTesterPage({super.key});

  @override
  State<AshNotificationTesterPage> createState() =>
      _AshNotificationTesterPageState();
}

class _AshNotificationTesterPageState extends State<AshNotificationTesterPage> {
  List<Map<String, dynamic>> _allUsersWithTokens = [];
  bool _isLoadingUsers = false;
  Map<String, List<Map<String, dynamic>>> _usersByLetter = {};
  final ScrollController _listScrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};
  Map<String, dynamic>? _selectedSearchResult;
  String _selectedType = 'reorder';
  final Map<String, TextEditingController> _controllers = {};
  bool _isSending = false;
  _TestResult? _lastResult;
  bool _overrideContent = false;
  final TextEditingController _overrideTitleController = TextEditingController();
  final TextEditingController _overrideBodyController = TextEditingController();
  final TextEditingController _manualUserIdController = TextEditingController();
  String? _lastSearchError;
  String? _searchErrorSuggestion;
  List<Map<String, dynamic>>? _diagnosticResults;
  bool _isDiagnosing = false;
  Map<String, dynamic>? _detailedErrorInfo;
  String? _fullErrorLog;
  bool _showFullErrorLog = false;
  String? _authTestResult;
  String? _networkTestResult;
  String? _functionTestResult;
  List<Map<String, dynamic>>? _analyticsHistory;
  bool _isLoadingAnalytics = false;
  String? _lastResponseTime;

  static const List<String> _notificationTypes = [
    'reorder',
    'cart',
    'hunger',
    'recommendation',
    'recovery',
    'payment_failed',
    'order_accepted',
    'order_ready',
  ];

  static const Map<String, List<_FieldDef>> _typeFields = {
    'reorder': [
      _FieldDef('restaurantName', 'Restaurant name', 'Pizza Palace'),
      _FieldDef('daysSinceLastOrder', 'Days since last order', '3'),
      _FieldDef('productName', 'Product name', 'Pasta Carbonara'),
    ],
    'cart': [
      _FieldDef('restaurantName', 'Restaurant name', 'Burger Joint'),
      _FieldDef('itemCount', 'Item count', '2'),
      _FieldDef(
        'productNames',
        'Product names (comma-separated)',
        'Chickenjoy, Spaghetti, Peach Mango Pie',
      ),
    ],
    'hunger': [
      _FieldDef('restaurantName', 'Restaurant name', 'Noodle House'),
      _FieldDef('suggestion', 'Suggestion / product', 'Pad Thai'),
    ],
    'recommendation': [
      _FieldDef('restaurantName', 'Restaurant name', 'Sushi Bar'),
      _FieldDef('productName', 'Product name', 'Salmon Roll'),
    ],
    'recovery': [
      _FieldDef('restaurantName', 'Restaurant name', 'Taco Shack'),
      _FieldDef('orderId', 'Order ID', 'test_order_123'),
    ],
    'payment_failed': [
      _FieldDef('amount', 'Amount', '500'),
    ],
    'order_accepted': [
      _FieldDef('restaurantName', 'Restaurant name', 'Pizza Palace'),
      _FieldDef('orderId', 'Order ID', 'test_order_456'),
    ],
    'order_ready': [
      _FieldDef('restaurantName', 'Restaurant name', 'Pizza Palace'),
      _FieldDef('orderId', 'Order ID', 'test_order_789'),
    ],
  };

  @override
  void initState() {
    super.initState();
    _ensureControllersForType(_selectedType);
    _loadAllUsersWithTokens();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _overrideTitleController.dispose();
    _overrideBodyController.dispose();
    _manualUserIdController.dispose();
    super.dispose();
  }

  void _clearSearchError() {
    _lastSearchError = null;
    _searchErrorSuggestion = null;
    _detailedErrorInfo = null;
    _fullErrorLog = null;
    _showFullErrorLog = false;
  }

  static bool _hasFcmToken(Map<String, dynamic> d) {
    final arr = d['fcmTokens'];
    if (arr is List && arr.isNotEmpty) {
      return arr.any(
        (t) => t is String && t.trim().isNotEmpty,
      );
    }
    final single = d['fcmToken'];
    return single is String && single.trim().isNotEmpty;
  }

  Future<void> _checkUserQueryDiagnostic() async {
    if (!mounted) return;
    setState(() {
      _detailedErrorInfo = null;
      _fullErrorLog = null;
      _clearSearchError();
    });
    try {
      developer.log(
        '🔍 Running user query diagnostic...',
        name: 'AshNotificationTester',
      );

      QuerySnapshot<Map<String, dynamic>> allUsers;
      try {
        allUsers = await FirebaseFirestore.instance
            .collection('users')
            .limit(1)
            .get();
        developer.log(
          '📊 Basic users query OK, size: ${allUsers.size}',
          name: 'AshNotificationTester',
        );
      } catch (e) {
        final code = e is FirebaseException ? e.code : null;
        final msg = e.toString();
        developer.log('❌ Basic query failed: $msg', name: 'AshNotificationTester');
        if (mounted) {
          _storeAndShowError(
            errorType: 'firestore',
            code: code,
            message: msg,
            suggestion: _suggestFix(msg),
            stackTrace: null,
            rawError: msg,
            authUid: auth.FirebaseAuth.instance.currentUser?.uid,
          );
        }
        return;
      }

      QuerySnapshot<Map<String, dynamic>> customers;
      try {
        customers = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'customer')
            .limit(500)
            .get();
        developer.log(
          '📊 Customer users: ${customers.size}',
          name: 'AshNotificationTester',
        );
      } catch (e) {
        final code = e is FirebaseException ? e.code : null;
        final msg = e.toString();
        developer.log('❌ Role=customer query failed: $msg', name: 'AshNotificationTester');
        if (mounted) {
          _storeAndShowError(
            errorType: code == 'failed-precondition' ? 'index' : 'firestore',
            code: code,
            message: msg,
            suggestion: _suggestFix(msg),
            stackTrace: null,
            rawError: msg,
            authUid: auth.FirebaseAuth.instance.currentUser?.uid,
          );
        }
        return;
      }

      int withTokens = 0;
      for (final doc in customers.docs) {
        if (_hasFcmToken(doc.data())) withTokens++;
      }

      if (mounted) {
        setState(() {
          _lastSearchError = null;
          _searchErrorSuggestion = null;
          _detailedErrorInfo = {
            'errorType': 'success',
            'message': 'Diagnostic passed',
            'totalCustomers': customers.size,
            'withFcmTokens': withTokens,
            'note': 'A-Z list uses role=customer only (no composite index). '
                'Search needs role+email, role+firstName, role+lastName indexes.',
          };
        });
        _showSnackBar(
          'OK: ${customers.size} customers, $withTokens with FCM tokens',
        );
      }
    } catch (e, st) {
      developer.log('❌ Diagnostic error: $e', name: 'AshNotificationTester');
      if (mounted) {
        _storeAndShowError(
          errorType: 'unknown',
          message: e.toString(),
          stackTrace: st?.toString(),
          rawError: e.toString(),
          authUid: auth.FirebaseAuth.instance.currentUser?.uid,
        );
        _showSnackBar('Diagnostic failed: $e', isError: true);
      }
    }
  }

  void _debugLog(String location, String message, Map<String, dynamic> data) {
    developer.log(
      data.isEmpty ? message : '$message $data',
      name: location,
    );
  }

  Future<void> _loadAllUsersWithTokens() async {
    if (_isLoadingUsers) return;
    setState(() {
      _isLoadingUsers = true;
      _allUsersWithTokens = [];
      _usersByLetter = {};
      _clearSearchError();
    });

    // #region agent log
    _debugLog('ash_notification_tester.dart:_loadAllUsersWithTokens', 'start', {});
    // #endregion

    try {
      developer.log(
        '🔵 Loading all users with FCM tokens...',
        name: 'AshNotificationTester',
      );

      try {
        await FirebaseFirestore.instance
            .collection('users')
            .limit(1)
            .get();
        // #region agent log
        _debugLog('ash_notification_tester.dart:_loadAllUsersWithTokens', 'basic_query_ok', {});
        // #endregion
      } catch (e) {
        // #region agent log
        _debugLog('ash_notification_tester.dart:_loadAllUsersWithTokens', 'basic_query_failed', {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
          'hypothesisId': 'h1',
        });
        // #endregion
        developer.log(
          '❌ Cannot connect to Firestore: $e',
          name: 'AshNotificationTester',
        );
        throw Exception('Firestore connection failed');
      }

      final List<Map<String, dynamic>> users = [];
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;

      do {
        Query<Map<String, dynamic>> query = FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'customer')
            .limit(500);
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }
        snapshot = await query.get();

        developer.log(
          '✅ Found ${snapshot.size} customer users in batch',
          name: 'AshNotificationTester',
        );

        if (snapshot.docs.isEmpty && users.isEmpty) {
          developer.log(
            '⚠️ No customer users found in database',
            name: 'AshNotificationTester',
          );
          if (mounted) {
            setState(() => _isLoadingUsers = false);
          }
          return;
        }

        for (final doc in snapshot.docs) {
          final d = doc.data();
          if (!_hasFcmToken(d)) continue;

          final firstName = (d['firstName'] as String?) ?? '';
          final lastName = (d['lastName'] as String?) ?? '';
          final email = (d['email'] as String?) ?? '';
          var displayName =
              '${firstName.trim()} ${lastName.trim()}'.trim();
          if (displayName.isEmpty) {
            if (email.trim().isNotEmpty) {
              displayName = email;
            } else {
              displayName = doc.id;
            }
          }
          if (displayName.isEmpty) displayName = 'Unknown';

          users.add({
            'id': doc.id,
            'name': displayName,
            'displayName': displayName,
            'email': email,
            'hasToken': true,
          });
        }

        if (snapshot.docs.isNotEmpty) {
          lastDoc = snapshot.docs.last;
        } else {
          lastDoc = null;
        }
      } while (snapshot.docs.length == 500);

      developer.log(
        '✅ Found ${users.length} users with FCM tokens',
        name: 'AshNotificationTester',
      );

      if (users.isEmpty) {
        developer.log(
          '⚠️ No users have FCM tokens',
          name: 'AshNotificationTester',
        );
        if (mounted) {
          setState(() => _isLoadingUsers = false);
        }
        return;
      }

      users.sort(
        (a, b) =>
            ((a['displayName'] ?? '') as String).toLowerCase().compareTo(
                  ((b['displayName'] ?? '') as String).toLowerCase(),
                ),
      );

      final byLetter = <String, List<Map<String, dynamic>>>{};
      for (final u in users) {
        final name = (u['displayName'] ?? '') as String;
        final first = name.isNotEmpty ? name[0].toUpperCase() : '#';
        final key = first.codeUnitAt(0) >= 65 && first.codeUnitAt(0) <= 90
            ? first
            : '#';
        byLetter.putIfAbsent(key, () => []).add(u);
      }

      final sortedKeys = byLetter.keys.toList()..sort();
      _sectionKeys.clear();
      for (final k in sortedKeys) {
        _sectionKeys[k] = GlobalKey();
      }

      developer.log(
        '[Ash Tester] Loaded ${users.length} users with FCM tokens',
        name: 'AshNotificationTester',
      );

      if (mounted) {
        setState(() {
          _allUsersWithTokens = users;
          _usersByLetter = byLetter;
          _isLoadingUsers = false;
          _lastResponseTime = 'Load: ${users.length} users';
        });
      }
    } catch (e, st) {
      // #region agent log
      String? firestoreCode;
      if (e is FirebaseException) {
        firestoreCode = e.code;
      }
      _debugLog('ash_notification_tester.dart:_loadAllUsersWithTokens', 'catch', {
        'error': e.toString(),
        'errorType': e.runtimeType.toString(),
        'firestoreCode': firestoreCode,
        'stackTrace': st?.toString() ?? '',
        'hypothesisId': firestoreCode != null ? 'h1' : 'h2',
      });
      // #endregion
      developer.log('❌ Load users error: $e', name: 'AshNotificationTester');
      developer.log('Stack: $st', name: 'AshNotificationTester', level: 1000);
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
          _allUsersWithTokens = [];
          _usersByLetter = {};
        });
        final errMsg = e is FirebaseException
            ? '${e.code}: ${e.message}'
            : e.toString();
        _storeAndShowError(
          errorType: 'unknown',
          code: e is FirebaseException ? e.code : null,
          message: errMsg,
          suggestion: _suggestFix(e.toString()),
          stackTrace: st.toString(),
          rawError: e.toString(),
          authUid: auth.FirebaseAuth.instance.currentUser?.uid,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $errMsg'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String? _suggestFix(String errorStr) {
    final lower = errorStr.toLowerCase();
    if (lower.contains('index') || lower.contains('failed-precondition')) {
      return 'Create composite indexes in Firestore. See instructions below.';
    }
    if (lower.contains('permission') || lower.contains('permission-denied')) {
      return 'Check Firestore security rules and that you are signed in as admin.';
    }
    if (lower.contains('network') || lower.contains('unavailable')) {
      return 'Check network connectivity and try again.';
    }
    if (lower.contains('unauthenticated')) {
      return 'Sign in as an admin user.';
    }
    return null;
  }

  void _storeAndShowError({
    required String errorType,
    String? code,
    String? message,
    dynamic details,
    String? suggestion,
    String? stackTrace,
    required String rawError,
    String? authUid,
  }) {
    if (!mounted) return;
    final info = <String, dynamic>{
      'errorType': errorType,
      'code': code,
      'message': message ?? rawError,
      'details': details,
      'suggestion': suggestion,
      'stackTrace': stackTrace,
      'rawError': rawError,
      'authUid': authUid ?? 'null',
      'timestamp': DateTime.now().toIso8601String(),
    };
    final fullLog = StringBuffer()
      ..writeln('Error type: $errorType')
      ..writeln('Code: ${code ?? "N/A"}')
      ..writeln('Message: ${message ?? rawError}')
      ..writeln('Details: $details')
      ..writeln('Auth UID: ${authUid ?? "null"}')
      ..writeln('---')
      ..writeln('Raw: $rawError')
      ..writeln('---')
      ..writeln('Stack: ${stackTrace ?? "N/A"}');

    setState(() {
      _isLoadingUsers = false;
      _lastSearchError = rawError;
      _searchErrorSuggestion = suggestion;
      _detailedErrorInfo = info;
      _fullErrorLog = fullLog.toString();
    });
    _showSnackBar('Search failed: ${message ?? rawError}', isError: true);
  }

  Future<void> _runDiagnostics() async {
    if (_isDiagnosing) return;
    setState(() {
      _isDiagnosing = true;
      _diagnosticResults = null;
      _clearSearchError();
    });
    try {
      developer.log(
        '[CONNECTIVITY] Ash Tester diagnostics starting',
        name: 'AshNotificationTester',
      );
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('diagnoseAshTesterSearch');
      final result = await callable.call(<String, dynamic>{});
      final data = result.data as Map<String, dynamic>? ?? {};
      final raw = data['results'] as List<dynamic>? ?? [];
      final results = raw
          .map((e) => (e as Map<String, dynamic>).cast<String, dynamic>())
          .toList();

      developer.log(
        '[CONNECTIVITY] Ash Tester diagnostics: ${results.length} tests',
        name: 'AshNotificationTester',
      );
      if (mounted) {
        setState(() {
          _diagnosticResults = results;
          _isDiagnosing = false;
        });
      }
    } on FirebaseFunctionsException catch (e, st) {
      developer.log(
        '❌ DIAGNOSTIC FirebaseFunctionsException: ${e.code} ${e.message}',
        name: 'AshNotificationTester',
      );
      if (mounted) {
        setState(() => _isDiagnosing = false);
        _storeAndShowError(
          errorType: e.code == 'unauthenticated' ? 'auth' : 'function',
          code: e.code,
          message: e.message,
          details: e.details,
          suggestion: _suggestFix(e.toString()),
          stackTrace: st?.toString(),
          rawError: e.toString(),
          authUid: auth.FirebaseAuth.instance.currentUser?.uid,
        );
        _showSnackBar('Diagnostic failed: ${e.message}', isError: true);
      }
    } catch (e, st) {
      developer.log('❌ DIAGNOSTIC ERROR: $e', name: 'AshNotificationTester');
      developer.log('📚 STACK: $st', name: 'AshNotificationTester', level: 1000);
      if (mounted) {
        setState(() => _isDiagnosing = false);
        _storeAndShowError(
          errorType: 'unknown',
          message: e.toString(),
          suggestion: _suggestFix(e.toString()),
          stackTrace: st?.toString(),
          rawError: e.toString(),
          authUid: auth.FirebaseAuth.instance.currentUser?.uid,
        );
        _showSnackBar('Diagnostic failed: $e', isError: true);
      }
    }
  }

  String get _functionLogsUrl {
    try {
      final pid = Firebase.app().options.projectId;
      return 'https://console.firebase.google.com/project/$pid/functions/logs';
    } catch (_) {
      return 'https://console.firebase.google.com';
    }
  }

  Future<void> _testAuthentication() async {
    setState(() => _authTestResult = null);
    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _authTestResult = '❌ Not signed in');
      return;
    }
    String result = '✅ Signed in\nUID: ${user.uid}\nEmail: ${user.email ?? "N/A"}';
    if (user.refreshToken != null) {
      result += '\nToken: present';
    }
    setState(() => _authTestResult = result);
  }

  Future<void> _testNetwork() async {
    setState(() => _networkTestResult = null);
    try {
      final results = await Connectivity().checkConnectivity();
      final hasConnectivity = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnectivity) {
        setState(() => _networkTestResult = '❌ No connectivity: $results');
        return;
      }
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      setState(() => _networkTestResult =
          '✅ Network OK\nConnectivity: $results\nGoogle: ${response.statusCode}');
    } catch (e) {
      setState(() => _networkTestResult = '❌ Network failed: $e');
    }
  }

  Future<void> _test1BasicCall() async {
    developer.log('🔵 TEST 1: Basic Function Call', name: 'AshNotificationTester');
    final start = DateTime.now();
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('searchUsersForAshTester')
          .call(<String, dynamic>{'query': 'test'});
      final ms = DateTime.now().difference(start).inMilliseconds;
      developer.log('✅ SUCCESS: $result', name: 'AshNotificationTester');
      if (mounted) {
        setState(() => _lastResponseTime = 'Search: ${ms}ms');
        _showSnackBar('Test 1 passed (${ms}ms)');
      }
    } catch (e) {
      developer.log('❌ FAILED: $e', name: 'AshNotificationTester');
      if (mounted) {
        _showSnackBar('Test 1 failed: $e', isError: true);
      }
    }
  }

  Future<void> _checkAnalytics() async {
    if (_selectedSearchResult == null) {
      _showSnackBar('Please select a user first', isWarning: true);
      return;
    }
    final userId = _selectedSearchResult!['id'] as String?;
    if (userId == null) return;
    setState(() {
      _isLoadingAnalytics = true;
      _analyticsHistory = null;
    });
    final start = DateTime.now();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getNotificationHistory');
      final result = await callable
          .call(<String, dynamic>{'userId': userId, 'limit': 20});
      final ms = DateTime.now().difference(start).inMilliseconds;
      final data = result.data as Map<String, dynamic>? ?? {};
      final raw = data['notifications'] as List<dynamic>? ?? [];
      final notifications = raw
          .map((e) => (e as Map<String, dynamic>).cast<String, dynamic>())
          .toList();
      if (mounted) {
        setState(() {
          _analyticsHistory = notifications;
          _isLoadingAnalytics = false;
          _lastResponseTime = 'Analytics: ${ms}ms';
        });
        _showSnackBar('Loaded ${notifications.length} notifications');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() => _isLoadingAnalytics = false);
        _showSnackBar('Analytics failed: ${e.message}', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAnalytics = false);
        _showSnackBar('Analytics failed: $e', isError: true);
      }
    }
  }

  Future<void> _testSearchSimple() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final result = await functions.httpsCallable('testSearchSimple').call({});
      developer.log('✅ SIMPLE TEST SUCCESS: $result', name: 'AshNotificationTester');
      if (mounted) {
        final data = result.data as Map<String, dynamic>? ?? {};
        _showSnackBar(
          'Function works! ${data['message'] ?? data['success']}',
        );
      }
    } catch (e, stack) {
      developer.log('❌ SIMPLE TEST FAILED: $e', name: 'AshNotificationTester');
      developer.log('Stack: $stack', name: 'AshNotificationTester', level: 1000);
      if (mounted) {
        _showSnackBar('Error: $e', isError: true);
      }
    }
  }

  Future<void> _testSearchBasic() async {
    setState(() => _functionTestResult = null);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('testSearchBasic');
      final result = await callable.call<Map<String, dynamic>>({});
      final data = result.data ?? <String, dynamic>{};
      final success = data['success'] as bool? ?? false;
      final test1 = data['test1'];
      final test2 = data['test2'];
      final auth = data['auth'];
      setState(() => _functionTestResult =
          success
              ? '✅ Basic test OK\n'
                'test1 (users limit 1): $test1\n'
                'test2 (role=customer): $test2\n'
                'auth: $auth'
              : '❌ Basic test returned success=false');
      if (success) {
        _showSnackBar('Basic test succeeded');
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _functionTestResult =
          '❌ Basic test failed\nCode: ${e.code}\nMessage: ${e.message}');
      _showSnackBar('Basic test failed: ${e.message}', isError: true);
    } catch (e) {
      setState(() => _functionTestResult = '❌ Basic test failed: $e');
      _showSnackBar('Basic test failed: $e', isError: true);
    }
  }

  Future<void> _testMinimalPing() async {
    setState(() => _functionTestResult = null);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('pingTestMinimal');
      final result = await callable.call<Map<String, dynamic>>({});
      final data = result.data ?? {};
      setState(() => _functionTestResult =
          '✅ Minimal OK\nt=${data['t'] ?? 'N/A'}');
      _showSnackBar('Minimal ping succeeded');
    } on FirebaseFunctionsException catch (e) {
      setState(() => _functionTestResult =
          '❌ Minimal failed\nCode: ${e.code}\nMessage: ${e.message}');
      _showSnackBar('Minimal failed: ${e.code}', isError: true);
    } catch (e) {
      setState(() => _functionTestResult = '❌ Minimal failed: $e');
      _showSnackBar('Minimal failed: $e', isError: true);
    }
  }

  Future<void> _testFunctionConnectivity() async {
    setState(() => _functionTestResult = null);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('pingAshTester');
      final result = await callable.call<Map<String, dynamic>>({});
      final ts = result.data?['timestamp'];
      setState(() => _functionTestResult =
          '✅ Function OK\nTimestamp: ${ts ?? 'N/A'}');
    } on FirebaseFunctionsException catch (e) {
      setState(() => _functionTestResult =
          '❌ Function failed\nCode: ${e.code}\nMessage: ${e.message}');
    } catch (e) {
      setState(() => _functionTestResult = '❌ Function failed: $e');
    }
  }

  Future<void> _copyErrorDetails() async {
    if (_fullErrorLog == null) return;
    await Clipboard.setData(ClipboardData(text: _fullErrorLog!));
    if (mounted) _showSnackBar('Error details copied to clipboard');
  }

  Future<void> _openFunctionLogs() async {
    final uri = Uri.parse(_functionLogsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _testUserQuery() async {
    developer.log('🔍 Testing user query...', name: 'AshTester');
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .limit(5)
          .get();
      developer.log('✅ Found ${snapshot.docs.length} customers', name: 'AshTester');
      for (final doc in snapshot.docs) {
        developer.log('  - ${doc.id}: ${doc.data()}', name: 'AshTester');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${snapshot.docs.length} customers (see console)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      developer.log('❌ Query failed: $e', name: 'AshTester');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Query failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    developer.log('🔄 Testing function connectivity...', name: 'AshTester');
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('pingAshTester')
          .call<Map<String, dynamic>>({});
      developer.log('✅ Success: $result', name: 'AshTester');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection OK: ${result.data}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      developer.log('❌ Failed: $e', name: 'AshTester');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _runQuickDiagnostic() async {
    if (!mounted) return;
    setState(() {
      _detailedErrorInfo = null;
      _fullErrorLog = null;
      _clearSearchError();
    });
    try {
      final simpleQuery = await FirebaseFirestore.instance
          .collection('users')
          .limit(1)
          .get();
      developer.log(
        '✅ Quick Diagnostic: Simple query works: ${simpleQuery.size}',
        name: 'AshNotificationTester',
      );

      final roleQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .limit(1)
          .get();
      developer.log(
        '✅ Quick Diagnostic: Role filter works: ${roleQuery.size}',
        name: 'AshNotificationTester',
      );

      if (mounted) {
        setState(() {
          _detailedErrorInfo = {
            'errorType': 'success',
            'message': 'Direct Firestore OK',
            'totalCustomers': roleQuery.size,
            'withFcmTokens': null,
            'note': 'Simple query and role=customer query both succeeded. '
                'User list should load. Indexes needed only for search feature.',
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Direct Firestore OK: simple=${simpleQuery.size}, '
              'roleFilter=${roleQuery.size}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      developer.log('❌ Quick Diagnostic failed: $e', name: 'AshNotificationTester');
      if (mounted) {
        final code = e is FirebaseException ? e.code : null;
        _storeAndShowError(
          errorType: code == 'failed-precondition' ? 'index' : 'firestore',
          code: code,
          message: e.toString(),
          suggestion: _suggestFix(e.toString()),
          rawError: e.toString(),
          authUid: auth.FirebaseAuth.instance.currentUser?.uid,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direct Firestore failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _ensureControllersForType(String type) {
    final fields = _typeFields[type] ?? [];
    for (final f in fields) {
      if (!_controllers.containsKey(f.key)) {
        _controllers[f.key] = TextEditingController(text: f.defaultValue);
      }
    }
  }

  Map<String, dynamic> _getContextData() {
    final fields = _typeFields[_selectedType] ?? [];
    final map = <String, dynamic>{};
      for (final f in fields) {
      final c = _controllers[f.key];
      final v = c?.text.trim();
      if (v != null && v.isNotEmpty) {
        if (f.key == 'daysSinceLastOrder' ||
            f.key == 'itemCount' ||
            f.key == 'amount') {
          map[f.key] = int.tryParse(v) ?? v;
        } else if (f.key == 'productNames') {
          map['productName'] = v.split(',').map((s) => s.trim()).join(', ');
        } else {
          map[f.key] = v;
        }
      }
    }
    if (_overrideContent) {
      final t = _overrideTitleController.text.trim();
      final b = _overrideBodyController.text.trim();
      if (t.isNotEmpty) map['overrideTitle'] = t;
      if (b.isNotEmpty) map['overrideBody'] = b;
    }
    return map;
  }

  Future<void> _sendTestNotification() async {
    const _logName = 'AshTester';

    developer.log('[SEND] Button pressed', name: _logName);
    if (_selectedSearchResult == null) {
      developer.log('[SEND] Abort: no user selected', name: _logName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a user first'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final currentUser = auth.FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      developer.log('[SEND] Abort: not signed in', name: _logName);
      _showSnackBar('You must be signed in', isError: true);
      return;
    }

    final selectedUserId = _selectedSearchResult!['id'] as String;
    final contextData = _getContextData();
    developer.log('📤 Sending notification to user: $selectedUserId', name: _logName);
    developer.log('📤 Type: $_selectedType', name: _logName);
    developer.log('📤 Context: $contextData', name: _logName);
    developer.log(
      '[SEND] Selected user ID: $selectedUserId',
      name: _logName,
    );
    developer.log(
      '[SEND] Notification type: $_selectedType',
      name: _logName,
    );
    developer.log(
      '[SEND] Context params: $contextData',
      name: _logName,
    );

    setState(() {
      _isSending = true;
      _lastResult = null;
    });

    final payload = <String, dynamic>{
      'userId': selectedUserId,
      'notificationType': _selectedType,
      'contextData': contextData,
    };
    developer.log('[SEND] Payload assembled: $payload', name: _logName);
    // #region agent log
    _debugLog('ash_notification_tester.dart:_sendTestNotification', 'before_call', {
      'userId': payload['userId'],
      'notificationType': payload['notificationType'],
      'contextDataKeys': (payload['contextData'] as Map).keys.toList(),
      'callerUid': currentUser.uid,
      'hypothesisId': 'h4',
    });
    // #endregion

    developer.log(
      '[SEND] About to call testAshNotification (us-central1)',
      name: _logName,
    );
    final sendStart = DateTime.now();

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('testAshNotification');
      final result = await callable.call(payload);

      final sendMs = DateTime.now().difference(sendStart).inMilliseconds;
      developer.log(
        '[SEND] Cloud Function returned in ${sendMs}ms: $result',
        name: _logName,
      );

      final data = result.data as Map<String, dynamic>? ?? {};
      final success = data['success'] as bool? ?? false;
      final message = data['message'] as String? ?? '';
      final preview = data['preview'] as Map<String, dynamic>?;
      developer.log(
        '[SEND] Parsed response: success=$success, message=$message',
        name: _logName,
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          _lastResult = _TestResult(
            success: success,
            message: message,
            preview: preview,
          );
          _lastResponseTime = 'Send: ${sendMs}ms';
        });
        if (success) {
          developer.log('[SEND] Success', name: _logName);
          _showSnackBar('Notification sent successfully (${sendMs}ms)');
        } else {
          developer.log('[SEND] Function returned success=false: $message', name: _logName);
        }
      }
    } on FirebaseFunctionsException catch (e) {
      developer.log(
        '[SEND] FirebaseFunctionsException: code=${e.code}, message=${e.message}, '
        'details=${e.details}',
        name: _logName,
      );
      // #region agent log
      _debugLog('ash_notification_tester.dart:_sendTestNotification', 'FirebaseFunctionsException', {
        'code': e.code,
        'message': e.message,
        'details': e.details?.toString(),
        'hypothesisId': 'h3',
      });
      // #endregion
      if (mounted) {
        String msg = '${e.code}: ${e.message}';
        if (e.details != null && e.details is Map) {
          final d = e.details as Map;
          if (d['cause'] != null) {
            msg += ' (cause: ${d['cause']})';
          }
        }
        setState(() {
          _isSending = false;
          _lastResult = _TestResult(
            success: false,
            message: msg,
            preview: null,
          );
        });
        _showSnackBar('Failed: $msg', isError: true);
      }
    } catch (e, st) {
      developer.log(
        '[SEND] Generic catch: $e\nStack: $st',
        name: _logName,
      );
      // #region agent log
      _debugLog('ash_notification_tester.dart:_sendTestNotification', 'catch', {
        'error': e.toString(),
        'errorType': e.runtimeType.toString(),
        'stackTrace': st?.toString() ?? '',
        'hypothesisId': 'h5',
      });
      // #endregion
      if (mounted) {
        setState(() {
          _isSending = false;
          _lastResult = _TestResult(
            success: false,
            message: e.toString(),
            preview: null,
          );
        });
        _showSnackBar('Failed: $e', isError: true);
      }
    }
  }

  void _showSnackBar(String text, {bool isError = false, bool isWarning = false}) {
    if (!mounted) return;
    Color? bg;
    if (isError) bg = Colors.red;
    else if (isWarning) bg = Colors.orange;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bg),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ash Notification Tester'),
        actions: [
          TextButton.icon(
            onPressed: _isDiagnosing ? null : _runDiagnostics,
            icon: _isDiagnosing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bug_report, size: 20),
            label: const Text('Diagnose'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh users',
            onPressed: _isLoadingUsers ? null : _loadAllUsersWithTokens,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUserSection(),
            if (_lastSearchError != null) ...[
              const SizedBox(height: 16),
              _buildDiagnosticErrorSection(),
            ],
            const SizedBox(height: 16),
            _buildDiagnosticsSection(),
            if (_diagnosticResults != null) ...[
              const SizedBox(height: 16),
              _buildDiagnosticResultsSection(),
            ],
            const SizedBox(height: 16),
            _buildIndexInstructionsSection(),
            const SizedBox(height: 24),
            _buildNotificationTypeSection(),
            const SizedBox(height: 24),
            _buildContextParamsSection(),
            const SizedBox(height: 24),
            _buildOverrideSection(),
            const SizedBox(height: 24),
            _buildSendButton(),
            if (_analyticsHistory != null) ...[
              const SizedBox(height: 24),
              _buildAnalyticsSection(),
            ],
            if (_lastResult != null) ...[
              const SizedBox(height: 24),
              _buildResultSection(),
            ],
          ],
        ),
      ),
    );
  }

  void _scrollToLetter(String letter) {
    final key = _sectionKeys[letter];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      alignment: 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  String _userInitial(Map<String, dynamic> u) {
    final name = (u['displayName'] ?? u['name'] ?? '') as String;
    if (name.isNotEmpty) return name[0].toUpperCase();
    final email = (u['email'] ?? '') as String;
    if (email.isNotEmpty) return email[0].toUpperCase();
    return '?';
  }

  Widget _buildUserSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Test user',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: _isLoadingUsers
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _isLoadingUsers ? null : _loadAllUsersWithTokens,
                  tooltip: 'Refresh user list',
                ),
              ],
            ),
            if (_isLoadingUsers)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_allUsersWithTokens.isEmpty) ...[
              const SizedBox(height: 16),
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
              const SizedBox(height: 16),
              Text(
                'No users with FCM tokens found',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'This could mean:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const SizedBox(height: 4),
              const Text('• No customer users exist in the database'),
              const Text('• Users exist but have no FCM tokens'),
              const Text('• Firestore query is failing'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAllUsersWithTokens,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry Loading Users'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _checkUserQueryDiagnostic,
                icon: const Icon(Icons.bug_report, size: 18),
                label: const Text('Run Diagnostic'),
              ),
              const SizedBox(height: 16),
              Text(
                'Or enter User ID manually:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _manualUserIdController,
                decoration: const InputDecoration(
                  labelText: 'User ID',
                  hintText: 'Enter Firestore user document ID',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  final trimmed = value.trim();
                  if (trimmed.isNotEmpty) {
                    setState(() {
                      _selectedSearchResult = {
                        'id': trimmed,
                        'name': 'Manual: $trimmed',
                        'displayName': 'Manual: $trimmed',
                        'email': '',
                        'hasToken': true,
                      };
                    });
                  } else {
                    setState(() => _selectedSearchResult = null);
                  }
                },
              ),
            ]
            else ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final letter in _sectionKeys.keys.toList()..sort())
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap: () => _scrollToLetter(letter),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              letter,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  controller: _listScrollController,
                  shrinkWrap: true,
                  itemCount: _sectionKeys.keys.toList().fold<int>(
                    0,
                    (acc, k) => acc + 1 + _usersByLetter[k]!.length,
                  ),
                  itemBuilder: (context, idx) {
                    int i = 0;
                    for (final letter in _sectionKeys.keys.toList()..sort()) {
                      final users = _usersByLetter[letter]!;
                      if (idx == i) {
                        return _SectionHeader(
                          key: _sectionKeys[letter],
                          letter: letter,
                        );
                      }
                      i++;
                      for (var j = 0; j < users.length; j++) {
                        if (idx == i) {
                          final u = users[j];
                          final selected =
                              _selectedSearchResult?['id'] == u['id'];
                          return _UserTile(
                            user: u,
                            initial: _userInitial(u),
                            selected: selected,
                            onTap: () {
                              _manualUserIdController.clear();
                              setState(() => _selectedSearchResult = u);
                            },
                          );
                        }
                        i++;
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_allUsersWithTokens.length} users with FCM tokens',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Or enter User ID manually:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _manualUserIdController,
              decoration: const InputDecoration(
                labelText: 'User ID',
                hintText: 'Enter Firestore user document ID',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final trimmed = value.trim();
                if (trimmed.isNotEmpty) {
                  setState(() {
                    _selectedSearchResult = {
                      'id': trimmed,
                      'name': 'Manual: $trimmed',
                      'displayName': 'Manual: $trimmed',
                      'email': '',
                      'hasToken': true,
                    };
                  });
                } else {
                  setState(() => _selectedSearchResult = null);
                }
              },
            ),
            if (_selectedSearchResult != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Chip(
                      avatar: CircleAvatar(
                        radius: 12,
                        child: Text(_userInitial(_selectedSearchResult!)),
                      ),
                      label: Text(
                        (_selectedSearchResult!['email'] as String?)
                                    ?.isNotEmpty ==
                                true
                            ? _selectedSearchResult!['email'] as String
                            : _selectedSearchResult!['name'] as String? ??
                                _selectedSearchResult!['id'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onDeleted: () {
                        _manualUserIdController.clear();
                        setState(() => _selectedSearchResult = null);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isLoadingAnalytics ? null : _checkAnalytics,
                    icon: _isLoadingAnalytics
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.analytics, size: 18),
                    label: const Text('Check Analytics'),
                  ),
                ],
              ),
            ],
            if (_lastResponseTime != null) ...[
              const SizedBox(height: 8),
              Text(
                '⏱️ $_lastResponseTime',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _firestoreIndexesUrl {
    try {
      final pid = Firebase.app().options.projectId;
      return 'https://console.firebase.google.com/project/$pid/firestore/indexes';
    } catch (_) {
      return 'https://console.firebase.google.com';
    }
  }

  Color _errorTypeColor(String? type) {
    switch (type) {
      case 'success':
        return Colors.green.shade800;
      case 'auth':
        return Colors.orange.shade800;
      case 'network':
        return Colors.blue.shade800;
      case 'index':
        return Colors.purple.shade800;
      case 'function':
      case 'firestore':
        return Colors.red.shade800;
      default:
        return Colors.red.shade900;
    }
  }

  Widget _buildDiagnosticErrorSection() {
    final info = _detailedErrorInfo;
    final errorType = info?['errorType'] as String? ?? 'unknown';
    final isSuccess = errorType == 'success';

    return Card(
      color: Color.lerp(
        _errorTypeColor(errorType),
        Colors.white,
        0.9,
      )!,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                  color: _errorTypeColor(errorType),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  isSuccess
                      ? 'Diagnostic Result'
                      : 'Search Error (${errorType.toUpperCase()})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _errorTypeColor(errorType),
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (_fullErrorLog != null)
                  TextButton.icon(
                    onPressed: _copyErrorDetails,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                TextButton.icon(
                  onPressed: _openFunctionLogs,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('View Logs'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_clearSearchError),
                ),
              ],
            ),
            if (info != null) ...[
              if (info['code'] != null && !isSuccess) ...[
                const SizedBox(height: 8),
                _buildErrorRow('Code', info['code'] as String, errorType),
              ],
              const SizedBox(height: 4),
              _buildErrorRow(
                isSuccess ? 'Result' : 'Message',
                info['message'] as String? ?? _lastSearchError ?? '',
                errorType,
              ),
              if (isSuccess && info['totalCustomers'] != null) ...[
                const SizedBox(height: 4),
                _buildErrorRow(
                  'Customers',
                  '${info['totalCustomers']} total, '
                  '${info['withFcmTokens'] ?? 0} with FCM tokens',
                  errorType,
                ),
              ],
              if (isSuccess && info['note'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  info['note'] as String,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
              ],
              if (info['details'] != null) ...[
                const SizedBox(height: 4),
                _buildErrorRow('Details', info['details'].toString(), errorType),
              ],
              if (info['authUid'] != null) ...[
                const SizedBox(height: 4),
                _buildErrorRow('Auth UID', info['authUid'] as String, errorType),
              ],
            ] else ...[
              const SizedBox(height: 8),
              SelectableText(
                _lastSearchError ?? '',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: _errorTypeColor(errorType),
                ),
              ),
            ],
            if (_searchErrorSuggestion != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _searchErrorSuggestion!,
                        style: TextStyle(color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_fullErrorLog != null) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() => _showFullErrorLog = !_showFullErrorLog),
                child: Row(
                  children: [
                    Icon(
                      _showFullErrorLog ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showFullErrorLog
                          ? 'Hide full error log'
                          : 'View full error log',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_showFullErrorLog) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _fullErrorLog!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorRow(String label, String value, String errorType) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _errorTypeColor(errorType),
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: _errorTypeColor(errorType),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostics',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Isolate authentication, network, and function connectivity.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _testAuthentication,
                  icon: const Icon(Icons.person, size: 18),
                  label: const Text('Test Auth'),
                ),
                OutlinedButton.icon(
                  onPressed: _testNetwork,
                  icon: const Icon(Icons.wifi, size: 18),
                  label: const Text('Test Network'),
                ),
                OutlinedButton.icon(
                  onPressed: _testMinimalPing,
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text('Test Minimal'),
                ),
                OutlinedButton.icon(
                  onPressed: _testFunctionConnectivity,
                  icon: const Icon(Icons.cable, size: 18),
                  label: const Text('Test Function'),
                ),
                OutlinedButton.icon(
                  onPressed: _testSearchBasic,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Test Basic'),
                ),
                OutlinedButton.icon(
                  onPressed: _testSearchSimple,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Test Simple'),
                ),
                OutlinedButton.icon(
                  onPressed: _test1BasicCall,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Test 1: Basic Call'),
                ),
              ],
            ),
            if (_authTestResult != null ||
                _networkTestResult != null ||
                _functionTestResult != null) ...[
              const SizedBox(height: 12),
              if (_authTestResult != null)
                _buildDiagnosticResult('Auth', _authTestResult!),
              if (_networkTestResult != null)
                _buildDiagnosticResult('Network', _networkTestResult!),
              if (_functionTestResult != null)
                _buildDiagnosticResult('Function', _functionTestResult!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticResult(String label, String result) {
    final isOk = result.startsWith('✅');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              result,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: isOk ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticResultsSection() {
    final results = _diagnosticResults ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostic Results',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...results.map((r) {
              final passed = r['passed'] as bool? ?? false;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      passed ? Icons.check_circle : Icons.cancel,
                      color: passed ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r['name'] as String? ?? 'Unknown',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (!passed && r['error'] != null)
                      Expanded(
                        child: Text(
                          r['error'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade700,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildIndexInstructionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Firestore Indexes',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A-Z user list uses role=customer only (no composite index).\n'
              'Search feature needs composite indexes:\n'
              '1. (role, email) 2. (role, firstName) 3. (role, lastName)\n'
              'They are in firestore.indexes.json. Deploy with:\n'
              'firebase deploy --only firestore:indexes',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _testUserQuery,
                  icon: const Icon(Icons.people, size: 18),
                  label: const Text('Test User Query'),
                ),
                ElevatedButton.icon(
                  onPressed: _testConnection,
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Test Connection'),
                ),
                OutlinedButton.icon(
                  onPressed: _runQuickDiagnostic,
                  icon: const Icon(Icons.science, size: 18),
                  label: const Text('Quick Diagnostic'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(_firestoreIndexesUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open Firestore Indexes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTypeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification type',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _notificationTypes.map((t) {
                final selected = _selectedType == t;
                return FilterChip(
                  label: Text(t),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      _selectedType = t;
                      _ensureControllersForType(t);
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextParamsSection() {
    final fields = _typeFields[_selectedType] ?? [];
    if (fields.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Context parameters',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ...fields.map((f) {
              final isNumeric = f.key == 'daysSinceLastOrder' ||
                  f.key == 'itemCount' ||
                  f.key == 'amount';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _controllers[f.key],
                  decoration: InputDecoration(
                    labelText: f.label,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      isNumeric ? TextInputType.number : TextInputType.text,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOverrideSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Override title & body'),
              subtitle: const Text(
                'Bypass Ash voice and send custom content',
              ),
              value: _overrideContent,
              onChanged: (v) => setState(() => _overrideContent = v),
            ),
            if (_overrideContent) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _overrideTitleController,
                decoration: const InputDecoration(
                  labelText: 'Custom title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _overrideBodyController,
                decoration: const InputDecoration(
                  labelText: 'Custom body',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return FilledButton.icon(
      onPressed: _isSending ? null : _sendTestNotification,
      icon: _isSending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send),
      label: Text(_isSending ? 'Sending...' : 'Send test notification'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _buildAnalyticsSection() {
    final history = _analyticsHistory ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Notification History',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _analyticsHistory = null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text(
                'No notifications found for this user.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...history.take(10).map((n) {
                final type = n['type'] as String? ?? 'unknown';
                final title = n['title'] as String? ?? '';
                final sentAt = n['sentAt'];
                final openedAt = n['openedAt'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        openedAt != null ? Icons.done_all : Icons.circle_outlined,
                        size: 16,
                        color: openedAt != null ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$type: $title',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (sentAt != null)
                              Text(
                                'Sent: $sentAt',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    final r = _lastResult!;
    return Card(
      color: r.success ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.success ? Icons.check_circle : Icons.error,
                  color: r.success ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    r.success ? 'Success' : 'Error',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: r.success ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            if (r.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                r.message,
                style: TextStyle(
                  color: r.success ? Colors.green.shade900 : Colors.red.shade900,
                ),
              ),
            ],
            if (r.preview != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              Text(
                'Preview',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.preview!['title'] != null)
                      Text(
                        r.preview!['title'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    if (r.preview!['body'] != null) ...[
                      if (r.preview!['title'] != null) const SizedBox(height: 4),
                      Text(r.preview!['body'] as String),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.initial,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> user;
  final String initial;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (user['name'] ?? user['displayName'] ?? '') as String;
    final email = (user['email'] ?? '') as String;
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        child: Text(initial),
      ),
      title: Text(
        name.isNotEmpty ? name : email,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: email.isNotEmpty && name != email
          ? Text(email, overflow: TextOverflow.ellipsis)
          : null,
      tileColor: selected ? Colors.blue.shade50 : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _FieldDef {
  final String key;
  final String label;
  final String defaultValue;

  const _FieldDef(this.key, this.label, this.defaultValue);
}

class _TestResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? preview;

  _TestResult({
    required this.success,
    required this.message,
    this.preview,
  });
}
