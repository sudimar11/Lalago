import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'user_database.db');
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firestoreId TEXT,
        firstName TEXT,
        lastName TEXT,
        phoneNumber TEXT,
        email TEXT,
        active INTEGER,
        role TEXT,
        createdAt TEXT,
        lastOnlineTimestamp TEXT,
        profilePictureURL TEXT,
        fcmToken TEXT,
        appIdentifier TEXT,
        wallet_amount REAL,
        latitude REAL,
        longitude REAL,
        newArrivals INTEGER,
        orderUpdates INTEGER,
        promotions INTEGER,
        pushNewMessages INTEGER,
        sending_status TEXT DEFAULT 'To be sent'
      )
    ''');

    await db.execute('''
      CREATE TABLE financial_transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_balances(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        opening_balance REAL NOT NULL DEFAULT 0,
        closing_balance REAL NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add sending_status column if it doesn't exist
      try {
        await db.execute(
            'ALTER TABLE users ADD COLUMN sending_status TEXT DEFAULT "To be sent"');
      } catch (e) {
        // Column might already exist, ignore the error
        print('Column sending_status might already exist: $e');
      }
    }

    if (oldVersion < 3) {
      // Add financial tables
      try {
        await db.execute('''
          CREATE TABLE financial_transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            description TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE daily_balances(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL UNIQUE,
            opening_balance REAL NOT NULL DEFAULT 0,
            closing_balance REAL NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        print('Error creating financial tables: $e');
      }
    }
  }

  // Save user to local database
  Future<int> saveUser(Map<String, dynamic> userData) async {
    final db = await database;

    // Convert boolean to integer for SQLite
    Map<String, dynamic> data = {
      'firestoreId': userData['id'],
      'firstName': userData['firstName'] ?? '',
      'lastName': userData['lastName'] ?? '',
      'phoneNumber': userData['phoneNumber'] ?? '',
      'email': userData['email'] ?? '',
      'active': (userData['active'] ?? false) ? 1 : 0,
      'role': userData['role'] ?? '',
      'createdAt': userData['createdAt']?.toString() ?? '',
      'lastOnlineTimestamp': userData['lastOnlineTimestamp']?.toString() ?? '',
      'profilePictureURL': userData['profilePictureURL'] ?? '',
      'fcmToken': userData['fcmToken'] ?? '',
      'appIdentifier': userData['appIdentifier'] ?? '',
      'wallet_amount': userData['wallet_amount'] ?? 0.0,
      'latitude': userData['location']?['latitude'] ?? 0.0,
      'longitude': userData['location']?['longitude'] ?? 0.0,
      'newArrivals': (userData['settings']?['newArrivals'] ?? false) ? 1 : 0,
      'orderUpdates': (userData['settings']?['orderUpdates'] ?? false) ? 1 : 0,
      'promotions': (userData['settings']?['promotions'] ?? false) ? 1 : 0,
      'pushNewMessages':
          (userData['settings']?['pushNewMessages'] ?? false) ? 1 : 0,
      'sending_status': userData['sending_status'] ?? 'To be sent',
    };

    return await db.insert('users', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Save multiple users to local database
  Future<void> saveUsers(List<Map<String, dynamic>> users) async {
    final db = await database;

    await db.transaction((txn) async {
      for (Map<String, dynamic> userData in users) {
        Map<String, dynamic> data = {
          'firestoreId': userData['id'],
          'firstName': userData['firstName'] ?? '',
          'lastName': userData['lastName'] ?? '',
          'phoneNumber': userData['phoneNumber'] ?? '',
          'email': userData['email'] ?? '',
          'active': (userData['active'] ?? false) ? 1 : 0,
          'role': userData['role'] ?? '',
          'createdAt': userData['createdAt']?.toString() ?? '',
          'lastOnlineTimestamp':
              userData['lastOnlineTimestamp']?.toString() ?? '',
          'profilePictureURL': userData['profilePictureURL'] ?? '',
          'fcmToken': userData['fcmToken'] ?? '',
          'appIdentifier': userData['appIdentifier'] ?? '',
          'wallet_amount': userData['wallet_amount'] ?? 0.0,
          'latitude': userData['location']?['latitude'] ?? 0.0,
          'longitude': userData['location']?['longitude'] ?? 0.0,
          'newArrivals':
              (userData['settings']?['newArrivals'] ?? false) ? 1 : 0,
          'orderUpdates':
              (userData['settings']?['orderUpdates'] ?? false) ? 1 : 0,
          'promotions': (userData['settings']?['promotions'] ?? false) ? 1 : 0,
          'pushNewMessages':
              (userData['settings']?['pushNewMessages'] ?? false) ? 1 : 0,
          'sending_status': userData['sending_status'] ?? 'To be sent',
        };

        await txn.insert('users', data,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // Get all users from local database
  Future<List<Map<String, dynamic>>> getUsers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users');

    return maps.map((map) {
      return {
        'id': map['firestoreId'],
        'firstName': map['firstName'],
        'lastName': map['lastName'],
        'phoneNumber': map['phoneNumber'],
        'email': map['email'],
        'active': map['active'] == 1,
        'role': map['role'],
        'createdAt': map['createdAt'],
        'lastOnlineTimestamp': map['lastOnlineTimestamp'],
        'profilePictureURL': map['profilePictureURL'],
        'fcmToken': map['fcmToken'],
        'appIdentifier': map['appIdentifier'],
        'wallet_amount': map['wallet_amount'],
        'location': {
          'latitude': map['latitude'],
          'longitude': map['longitude'],
        },
        'settings': {
          'newArrivals': map['newArrivals'] == 1,
          'orderUpdates': map['orderUpdates'] == 1,
          'promotions': map['promotions'] == 1,
          'pushNewMessages': map['pushNewMessages'] == 1,
        },
        'sending_status': map['sending_status'] ?? 'To be sent',
      };
    }).toList();
  }

  // Get active users from local database
  Future<List<Map<String, dynamic>>> getActiveUsers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'active = ?',
      whereArgs: [1],
    );

    return maps.map((map) {
      return {
        'id': map['firestoreId'],
        'firstName': map['firstName'],
        'lastName': map['lastName'],
        'phoneNumber': map['phoneNumber'],
        'email': map['email'],
        'active': map['active'] == 1,
        'role': map['role'],
        'createdAt': map['createdAt'],
        'lastOnlineTimestamp': map['lastOnlineTimestamp'],
        'profilePictureURL': map['profilePictureURL'],
        'fcmToken': map['fcmToken'],
        'appIdentifier': map['appIdentifier'],
        'wallet_amount': map['wallet_amount'],
        'location': {
          'latitude': map['latitude'],
          'longitude': map['longitude'],
        },
        'settings': {
          'newArrivals': map['newArrivals'] == 1,
          'orderUpdates': map['orderUpdates'] == 1,
          'promotions': map['promotions'] == 1,
          'pushNewMessages': map['pushNewMessages'] == 1,
        },
        'sending_status': map['sending_status'] ?? 'To be sent',
      };
    }).toList();
  }

  // Clear all users from local database
  Future<void> clearUsers() async {
    final db = await database;
    await db.delete('users');
  }

  // Get user count
  Future<int> getUserCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM users')) ??
        0;
  }

  // Update sending status for a user (with race condition protection)
  Future<bool> updateSendingStatus(String firestoreId, String status) async {
    final db = await database;
    try {
      // Use a transaction to ensure atomic updates
      bool success = false;
      await db.transaction((txn) async {
        // First check current status to prevent invalid transitions
        final List<Map<String, dynamic>> currentUser = await txn.query(
          'users',
          where: 'firestoreId = ?',
          whereArgs: [firestoreId],
          limit: 1,
        );

        if (currentUser.isEmpty) {
          print('⚠️ User $firestoreId not found in database');
          return;
        }

        final currentStatus =
            currentUser.first['sending_status'] ?? 'To be sent';

        // Prevent invalid status transitions
        if (_isValidStatusTransition(currentStatus, status)) {
          final updateCount = await txn.update(
            'users',
            {
              'sending_status': status,
              'lastOnlineTimestamp':
                  DateTime.now().toIso8601String(), // Update timestamp
            },
            where: 'firestoreId = ?',
            whereArgs: [firestoreId],
          );

          success = updateCount > 0;
          if (success) {
            print(
                '✅ Updated user $firestoreId status: $currentStatus → $status');
          }
        } else {
          print(
              '⚠️ Invalid status transition for user $firestoreId: $currentStatus → $status');
        }
      });

      return success;
    } catch (e) {
      // If sending_status column doesn't exist, try to add it first
      if (e.toString().contains('no such column: sending_status')) {
        try {
          await db.execute(
              'ALTER TABLE users ADD COLUMN sending_status TEXT DEFAULT "To be sent"');
          // Retry the update
          return await updateSendingStatus(firestoreId, status);
        } catch (e2) {
          print('Error adding sending_status column: $e2');
          return false;
        }
      } else {
        print('Error updating sending status: $e');
        return false;
      }
    }
  }

  // Validate status transitions to prevent race conditions
  bool _isValidStatusTransition(String currentStatus, String newStatus) {
    // Define valid status transitions
    const validTransitions = {
      'To be sent': ['Sending', 'Cancelled'],
      // Allow retry by moving a record back to 'To be sent'
      'Sending': ['Sent', 'Failed', 'Cancelled', 'To be sent'],
      'Sent': [], // Sent is final, no transitions allowed
      'Failed': ['To be sent', 'Cancelled'], // Allow retry
      'Cancelled': ['To be sent'], // Allow reset
    };

    final allowedTransitions = validTransitions[currentStatus] ?? [];
    return allowedTransitions.contains(newStatus) || currentStatus == newStatus;
  }

  // Update sending status for multiple users
  Future<void> updateSendingStatusForUsers(
      List<String> firestoreIds, String status) async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        for (String firestoreId in firestoreIds) {
          await txn.update(
            'users',
            {'sending_status': status},
            where: 'firestoreId = ?',
            whereArgs: [firestoreId],
          );
        }
      });
    } catch (e) {
      // If sending_status column doesn't exist, try to add it first
      if (e.toString().contains('no such column: sending_status')) {
        try {
          await db.execute(
              'ALTER TABLE users ADD COLUMN sending_status TEXT DEFAULT "To be sent"');
          // Retry the transaction
          await db.transaction((txn) async {
            for (String firestoreId in firestoreIds) {
              await txn.update(
                'users',
                {'sending_status': status},
                where: 'firestoreId = ?',
                whereArgs: [firestoreId],
              );
            }
          });
        } catch (e2) {
          print('Error adding sending_status column: $e2');
        }
      } else {
        print('Error updating sending status for multiple users: $e');
      }
    }
  }

  // Reset all sending statuses to 'To be sent' (for testing purposes only)
  Future<void> resetAllSendingStatuses() async {
    final db = await database;
    try {
      await db.update(
        'users',
        {'sending_status': 'To be sent'},
      );
    } catch (e) {
      // If sending_status column doesn't exist, try to add it first
      if (e.toString().contains('no such column: sending_status')) {
        try {
          await db.execute(
              'ALTER TABLE users ADD COLUMN sending_status TEXT DEFAULT "To be sent"');
          // Retry the update
          await db.update(
            'users',
            {'sending_status': 'To be sent'},
          );
        } catch (e2) {
          print('Error adding sending_status column: $e2');
        }
      } else {
        print('Error resetting sending statuses: $e');
      }
    }
  }

  // Release stale 'Sending' rows back to 'To be sent' so campaigns don't get stuck
  Future<int> releaseStaleSendingRows({
    Duration staleAfter = const Duration(minutes: 2),
    bool resetAllIfNoTimestamps = true,
  }) async {
    final db = await database;
    try {
      int releasedCount = 0;
      await db.transaction((txn) async {
        final String cutoffIso =
            DateTime.now().subtract(staleAfter).toIso8601String();

        // Check if any Sending rows have timestamps
        int sendingCount = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM users WHERE sending_status = "Sending"')) ??
            0;
        int withTsCount = Sqflite.firstIntValue(await txn.rawQuery(
                'SELECT COUNT(*) FROM users WHERE sending_status = "Sending" AND lastOnlineTimestamp IS NOT NULL AND lastOnlineTimestamp != ""')) ??
            0;

        if (sendingCount == 0) {
          return; // Nothing to release
        }

        if (resetAllIfNoTimestamps && withTsCount == 0) {
          // Legacy data without timestamps: reset all Sending → To be sent
          releasedCount = await txn.update(
            'users',
            {
              'sending_status': 'To be sent',
              'lastOnlineTimestamp': DateTime.now().toIso8601String(),
            },
            where: 'sending_status = ?',
            whereArgs: ['Sending'],
          );
          print(
              '🔧 Reset $releasedCount rows with status "Sending" (no timestamps)');
          return;
        }

        // Normal case: release only stale or timestamp-missing rows
        releasedCount = await txn.update(
          'users',
          {
            'sending_status': 'To be sent',
            'lastOnlineTimestamp': DateTime.now().toIso8601String(),
          },
          where:
              'sending_status = ? AND (lastOnlineTimestamp IS NULL OR lastOnlineTimestamp = "" OR lastOnlineTimestamp < ?)',
          whereArgs: ['Sending', cutoffIso],
        );
        if (releasedCount > 0) {
          print(
              '🔓 Released $releasedCount stale "Sending" rows (cutoff: $cutoffIso)');
        }
      });

      return releasedCount;
    } catch (e) {
      print('Error releasing stale Sending rows: $e');
      return 0;
    }
  }

  // Get active users who haven't been sent SMS yet (status = 'To be sent')
  Future<List<Map<String, dynamic>>> getActiveUsersNotSent() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'active = ? AND (sending_status = ? OR sending_status IS NULL)',
      whereArgs: [1, 'To be sent'],
    );

    return maps.map((map) {
      return {
        'id': map['firestoreId'],
        'firstName': map['firstName'],
        'lastName': map['lastName'],
        'phoneNumber': map['phoneNumber'],
        'email': map['email'],
        'active': map['active'] == 1,
        'role': map['role'],
        'createdAt': map['createdAt'],
        'lastOnlineTimestamp': map['lastOnlineTimestamp'],
        'profilePictureURL': map['profilePictureURL'],
        'fcmToken': map['fcmToken'],
        'appIdentifier': map['appIdentifier'],
        'wallet_amount': map['wallet_amount'],
        'location': {
          'latitude': map['latitude'],
          'longitude': map['longitude'],
        },
        'settings': {
          'newArrivals': map['newArrivals'] == 1,
          'orderUpdates': map['orderUpdates'] == 1,
          'promotions': map['promotions'] == 1,
          'pushNewMessages': map['pushNewMessages'] == 1,
        },
        'sending_status': map['sending_status'] ?? 'To be sent',
      };
    }).toList();
  }

  // Get count of users who haven't been sent SMS yet
  Future<int> getCountOfUsersNotSent() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE active = 1 AND (sending_status = "To be sent" OR sending_status IS NULL)')) ??
        0;
  }

  // Get count of users who have been sent SMS
  Future<int> getCountOfUsersSent() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE active = 1 AND sending_status = "Sent"')) ??
        0;
  }

  // Get count of users who failed to receive SMS
  Future<int> getCountOfUsersFailed() async {
    final db = await database;
    return Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM users WHERE active = 1 AND sending_status = "Failed"')) ??
        0;
  }

  // Atomically claim the next user for sending (prevents race conditions)
  Future<Map<String, dynamic>?> claimNextUserForSending(Set<String> sentUserIds,
      {Duration staleAfter = const Duration(minutes: 2),
      bool resetAllIfNoTimestamps = true}) async {
    final db = await database;
    try {
      Map<String, dynamic>? claimedUser;

      await db.transaction((txn) async {
        // Find the next user to send to (including failed users for retry)
        String whereClause =
            'active = 1 AND (sending_status = ? OR sending_status = ? OR sending_status IS NULL)';
        List<dynamic> whereArgs = ['To be sent', 'Failed'];

        // Add exclusion for successfully sent users if any
        if (sentUserIds.isNotEmpty) {
          final placeholders = sentUserIds.map((_) => '?').join(',');
          whereClause += ' AND firestoreId NOT IN ($placeholders)';
          whereArgs.addAll(sentUserIds);
        }

        final List<Map<String, dynamic>> availableUsers = await txn.query(
          'users',
          where: whereClause,
          whereArgs: whereArgs,
          limit: 1,
          orderBy: 'id ASC', // Process in order
        );

        if (availableUsers.isNotEmpty) {
          final user = availableUsers.first;
          final firestoreId = user['firestoreId'];

          // Atomically update status to 'Sending'
          final updateCount = await txn.update(
            'users',
            {
              'sending_status': 'Sending',
              'lastOnlineTimestamp': DateTime.now().toIso8601String(),
            },
            where:
                'firestoreId = ? AND (sending_status = ? OR sending_status = ? OR sending_status IS NULL)',
            whereArgs: [firestoreId, 'To be sent', 'Failed'],
          );

          if (updateCount > 0) {
            // Successfully claimed the user
            claimedUser = {
              'id': firestoreId,
              'firstName': user['firstName'],
              'lastName': user['lastName'],
              'phoneNumber': user['phoneNumber'],
              'email': user['email'],
              'active': user['active'] == 1,
              'role': user['role'],
              'createdAt': user['createdAt'],
              'lastOnlineTimestamp': user['lastOnlineTimestamp'],
              'profilePictureURL': user['profilePictureURL'],
              'fcmToken': user['fcmToken'],
              'appIdentifier': user['appIdentifier'],
              'wallet_amount': user['wallet_amount'],
              'location': {
                'latitude': user['latitude'],
                'longitude': user['longitude'],
              },
              'settings': {
                'newArrivals': user['newArrivals'] == 1,
                'orderUpdates': user['orderUpdates'] == 1,
                'promotions': user['promotions'] == 1,
                'pushNewMessages': user['pushNewMessages'] == 1,
              },
              'sending_status': 'Sending',
            };

            print('✅ Claimed user $firestoreId for sending');
          }
        } else {
          // Nothing available. Try to unstick stale 'Sending' rows, then retry once.
          final String cutoffIso =
              DateTime.now().subtract(staleAfter).toIso8601String();

          // Identify stuck IDs we'll release so we can skip them on the immediate retry
          final List<Map<String, dynamic>> stuckRows = await txn.query(
            'users',
            columns: ['firestoreId'],
            where:
                'sending_status = ? AND (lastOnlineTimestamp IS NULL OR lastOnlineTimestamp = "" OR lastOnlineTimestamp < ?)',
            whereArgs: ['Sending', cutoffIso],
          );

          final Set<String> justReleasedIds =
              stuckRows.map((r) => (r['firestoreId'] ?? '').toString()).toSet();

          if (justReleasedIds.isEmpty && resetAllIfNoTimestamps) {
            int sendingCount = Sqflite.firstIntValue(await txn.rawQuery(
                    'SELECT COUNT(*) FROM users WHERE sending_status = "Sending"')) ??
                0;
            int withTsCount = Sqflite.firstIntValue(await txn.rawQuery(
                    'SELECT COUNT(*) FROM users WHERE sending_status = "Sending" AND lastOnlineTimestamp IS NOT NULL AND lastOnlineTimestamp != ""')) ??
                0;
            if (sendingCount > 0 && withTsCount == 0) {
              // Reset all current Sending rows and mark them as released
              final List<Map<String, dynamic>> allSending = await txn.query(
                'users',
                columns: ['firestoreId'],
                where: 'sending_status = "Sending"',
              );
              justReleasedIds.addAll(
                  allSending.map((r) => (r['firestoreId'] ?? '').toString()));
              await txn.update(
                'users',
                {
                  'sending_status': 'To be sent',
                  'lastOnlineTimestamp': DateTime.now().toIso8601String(),
                },
                where: 'sending_status = ?',
                whereArgs: ['Sending'],
              );
              print(
                  '🔧 Reset ${justReleasedIds.length} stuck "Sending" rows (no timestamps)');
            }
          }

          if (justReleasedIds.isNotEmpty) {
            // Retry selection, skipping the just-released IDs to keep the campaign moving
            String retryWhere =
                'active = 1 AND (sending_status = ? OR sending_status = ? OR sending_status IS NULL)';
            List<dynamic> retryArgs = ['To be sent', 'Failed'];

            final Set<String> combinedExcludes = {
              ...sentUserIds,
              ...justReleasedIds,
            };
            if (combinedExcludes.isNotEmpty) {
              final placeholders = combinedExcludes.map((_) => '?').join(',');
              retryWhere += ' AND firestoreId NOT IN ($placeholders)';
              retryArgs.addAll(combinedExcludes);
            }

            final List<Map<String, dynamic>> retryUsers = await txn.query(
              'users',
              where: retryWhere,
              whereArgs: retryArgs,
              limit: 1,
              orderBy: 'id ASC',
            );

            if (retryUsers.isNotEmpty) {
              final user = retryUsers.first;
              final firestoreId = user['firestoreId'];
              final updateCount = await txn.update(
                'users',
                {
                  'sending_status': 'Sending',
                  'lastOnlineTimestamp': DateTime.now().toIso8601String(),
                },
                where:
                    'firestoreId = ? AND (sending_status = ? OR sending_status = ? OR sending_status IS NULL)',
                whereArgs: [firestoreId, 'To be sent', 'Failed'],
              );
              if (updateCount > 0) {
                claimedUser = {
                  'id': firestoreId,
                  'firstName': user['firstName'],
                  'lastName': user['lastName'],
                  'phoneNumber': user['phoneNumber'],
                  'email': user['email'],
                  'active': user['active'] == 1,
                  'role': user['role'],
                  'createdAt': user['createdAt'],
                  'lastOnlineTimestamp': user['lastOnlineTimestamp'],
                  'profilePictureURL': user['profilePictureURL'],
                  'fcmToken': user['fcmToken'],
                  'appIdentifier': user['appIdentifier'],
                  'wallet_amount': user['wallet_amount'],
                  'location': {
                    'latitude': user['latitude'],
                    'longitude': user['longitude'],
                  },
                  'settings': {
                    'newArrivals': user['newArrivals'] == 1,
                    'orderUpdates': user['orderUpdates'] == 1,
                    'promotions': user['promotions'] == 1,
                    'pushNewMessages': user['pushNewMessages'] == 1,
                  },
                  'sending_status': 'Sending',
                };
                print(
                    '✅ Claimed user $firestoreId after releasing stale stuck rows');
              }
            }
          }
        }
      });

      return claimedUser;
    } catch (e) {
      print('Error claiming next user for sending: $e');
      return null;
    }
  }

  // Reset all database records (clear all data)
  Future<void> resetAllDatabaseRecords() async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        // Delete all records from users table
        await txn.delete('users');

        // Reset auto-increment counter
        await txn.execute('DELETE FROM sqlite_sequence WHERE name="users"');
      });
      print('Database reset completed successfully');
    } catch (e) {
      print('Error resetting database records: $e');
      throw e;
    }
  }

  // Check if database needs migration
  Future<bool> needsMigration() async {
    final db = await database;
    try {
      // Try to query the sending_status column
      await db.rawQuery('SELECT sending_status FROM users LIMIT 1');
      return false; // Column exists, no migration needed
    } catch (e) {
      if (e.toString().contains('no such column: sending_status')) {
        return true; // Migration needed
      }
      return false; // Other error, assume no migration needed
    }
  }

  // Force database migration
  Future<void> forceMigration() async {
    final db = await database;
    try {
      await db.execute(
          'ALTER TABLE users ADD COLUMN sending_status TEXT DEFAULT "To be sent"');
      print('Database migration completed successfully');
    } catch (e) {
      print('Database migration failed or not needed: $e');
    }
  }

  // Delete users by their firestore IDs (for batch deletion)
  Future<int> deleteUsersByIds(List<String> firestoreIds) async {
    if (firestoreIds.isEmpty) return 0;

    final db = await database;
    try {
      // Create placeholders for the IN clause
      String placeholders = firestoreIds.map((_) => '?').join(',');

      // Delete users with the specified firestore IDs
      int deletedCount = await db.delete(
        'users',
        where: 'firestoreId IN ($placeholders)',
        whereArgs: firestoreIds,
      );

      print('Deleted $deletedCount users from batch');
      return deletedCount;
    } catch (e) {
      print('Error deleting users by IDs: $e');
      throw e;
    }
  }

  // Delete users by their database IDs (for batch deletion)
  Future<int> deleteUsersByDatabaseIds(List<int> databaseIds) async {
    if (databaseIds.isEmpty) return 0;

    final db = await database;
    try {
      // Create placeholders for the IN clause
      String placeholders = databaseIds.map((_) => '?').join(',');

      // Delete users with the specified database IDs
      int deletedCount = await db.delete(
        'users',
        where: 'id IN ($placeholders)',
        whereArgs: databaseIds,
      );

      print('Deleted $deletedCount users from batch');
      return deletedCount;
    } catch (e) {
      print('Error deleting users by database IDs: $e');
      throw e;
    }
  }

  // Financial Transaction Methods

  // Add a financial transaction
  Future<int> addTransaction(
      String date, String type, double amount, String description) async {
    final db = await database;
    return await db.insert('financial_transactions', {
      'date': date,
      'type': type,
      'amount': amount,
      'description': description,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Get transactions for a specific date
  Future<List<Map<String, dynamic>>> getTransactionsByDate(String date) async {
    final db = await database;
    return await db.query(
      'financial_transactions',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'created_at DESC',
    );
  }

  // Get all transactions
  Future<List<Map<String, dynamic>>> getAllTransactions() async {
    final db = await database;
    return await db.query(
      'financial_transactions',
      orderBy: 'date DESC, created_at DESC',
    );
  }

  // Get daily summary for a specific date
  Future<Map<String, double>> getDailySummary(String date) async {
    final db = await database;

    // Get opening balance
    double openingBalance = 0.0;
    final balanceResult = await db.query(
      'daily_balances',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (balanceResult.isNotEmpty) {
      openingBalance = balanceResult.first['opening_balance'] as double;
    }

    // Get transactions for the day
    final transactions = await getTransactionsByDate(date);

    double walletTopups = 0.0;
    double otherIncome = 0.0;
    double creditSales = 0.0;
    double totalExpenses = 0.0;

    for (var transaction in transactions) {
      final amount = transaction['amount'] as double;
      final type = transaction['type'] as String;

      switch (type) {
        case 'wallet_topup':
          walletTopups += amount;
          break;
        case 'other_income':
          otherIncome += amount;
          break;
        case 'credit_sale':
          creditSales += amount;
          break;
        case 'expense':
          totalExpenses += amount;
          break;
      }
    }

    final netBalance = (walletTopups + otherIncome + creditSales) - totalExpenses;
    final closingBalance = openingBalance + netBalance;

    return {
      'opening_balance': openingBalance,
      'wallet_topups': walletTopups,
      'other_income': otherIncome,
      'credit_sales': creditSales,
      'total_expenses': totalExpenses,
      'net_balance': netBalance,
      'closing_balance': closingBalance,
    };
  }

  // Update daily balance
  Future<void> updateDailyBalance(
      String date, double openingBalance, double closingBalance) async {
    final db = await database;
    await db.insert(
      'daily_balances',
      {
        'date': date,
        'opening_balance': openingBalance,
        'closing_balance': closingBalance,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Get the closing balance for the previous day
  Future<double> getPreviousDayClosingBalance(String currentDate) async {
    final db = await database;
    final DateTime current = DateTime.parse(currentDate);
    final DateTime previous = current.subtract(Duration(days: 1));
    final String previousDate = previous.toIso8601String().split('T')[0];

    final result = await db.query(
      'daily_balances',
      where: 'date = ?',
      whereArgs: [previousDate],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['closing_balance'] as double;
    }
    return 0.0;
  }

  // Automatically carry over balance from previous day
  Future<void> carryOverBalance(String date) async {
    final previousBalance = await getPreviousDayClosingBalance(date);
    final summary = await getDailySummary(date);

    // Update opening balance to previous day's closing balance
    await updateDailyBalance(
        date, previousBalance, summary['closing_balance']!);
  }

  // Update rider wallet balance
  Future<bool> updateRiderWallet(String riderId, double amount) async {
    final db = await database;
    try {
      // Get current wallet amount
      final result = await db.query(
        'users',
        columns: ['wallet_amount'],
        where: 'firestoreId = ?',
        whereArgs: [riderId],
        limit: 1,
      );

      if (result.isEmpty) {
        print('Rider not found: $riderId');
        return false;
      }

      final currentAmount = (result.first['wallet_amount'] as double?) ?? 0.0;
      final newAmount = currentAmount + amount;

      // Update wallet amount
      final updateCount = await db.update(
        'users',
        {'wallet_amount': newAmount},
        where: 'firestoreId = ?',
        whereArgs: [riderId],
      );

      if (updateCount > 0) {
        print(
            '✅ Updated rider $riderId wallet: ₱${currentAmount.toStringAsFixed(2)} → ₱${newAmount.toStringAsFixed(2)}');
        return true;
      }

      return false;
    } catch (e) {
      print('Error updating rider wallet: $e');
      return false;
    }
  }

  // Get rider current wallet balance
  Future<double> getRiderWalletBalance(String riderId) async {
    final db = await database;
    try {
      final result = await db.query(
        'users',
        columns: ['wallet_amount'],
        where: 'firestoreId = ?',
        whereArgs: [riderId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return (result.first['wallet_amount'] as double?) ?? 0.0;
      }

      return 0.0;
    } catch (e) {
      print('Error getting rider wallet balance: $e');
      return 0.0;
    }
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
