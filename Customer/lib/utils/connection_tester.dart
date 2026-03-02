/// Connectivity verification utility with layered checks.
///
/// Uses conditional imports: Socket-based checks on mobile/desktop,
/// http-based checks on web.
import 'connection_tester_stub.dart'
    if (dart.library.io) 'connection_tester_io.dart' as impl;

/// Performs layered connectivity checks: quick (Connectivity API),
/// medium (Socket to 8.8.8.8 / 1.1.1.1 or http on web), heavy (Firebase).
/// Returns true if any check succeeds.
Future<bool> isConnected() => impl.isConnectedImpl();
