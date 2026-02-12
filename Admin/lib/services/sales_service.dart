import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class SalesService {
  static Future<List<Map<String, dynamic>>> getOutstandingCreditEntries() async {
    try {
      final firestore = FirebaseFirestore.instance;
      // Try with orderBy first, if it fails due to missing index, try without
      QuerySnapshot snapshot;
      try {
        snapshot = await firestore
            .collection(CREDIT_ENTRIES)
            .where('is_paid', isEqualTo: false)
            .where('outstanding_balance', isGreaterThan: 0)
            .orderBy('outstanding_balance')
            .get();
      } catch (e) {
        // If orderBy fails (missing index), try without orderBy
        snapshot = await firestore
            .collection(CREDIT_ENTRIES)
            .where('is_paid', isEqualTo: false)
            .where('outstanding_balance', isGreaterThan: 0)
            .get();
      }

      final entries = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'date': data['date'] ?? '',
          'description': data['description'] ?? '',
          'initial_amount': (data['initial_amount'] ?? 0).toDouble(),
          'outstanding_balance': (data['outstanding_balance'] ?? 0).toDouble(),
          'is_paid': data['is_paid'] ?? false,
          'created_at': data['created_at'],
        };
      }).toList();

      // Sort manually if we couldn't use orderBy
      entries.sort((a, b) {
        final aBalance = a['outstanding_balance'] as double;
        final bBalance = b['outstanding_balance'] as double;
        return aBalance.compareTo(bBalance);
      });

      return entries;
    } catch (e) {
      // Re-throw with more context
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('permission')) {
        throw Exception(
            'Permission denied. Please check Firestore security rules for the credit_entries collection.');
      }
      rethrow;
    }
  }

  static Future<void> addTransactionAtomic({
    required String dateKey,
    required String type,
    required double amount,
    required String description,
    String? riderId,
    required String txId,
    String? creditEntryId,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final dayRef = firestore.collection(DAILY_SUMMARIES).doc(dateKey);
    final txRef = dayRef.collection('transactions').doc(txId);
    final riderRef =
        riderId != null ? firestore.collection(USERS).doc(riderId) : null;

    await firestore.runTransaction((t) async {
      // Idempotency: if tx already exists, no-op
      final existingTx = await t.get(txRef);
      if (existingTx.exists) return;

      // READS MUST COME BEFORE WRITES IN A TRANSACTION
      // Read daily summary and (if needed) previous day's closing balance
      final daySnap = await t.get(dayRef);
      final current = daySnap.data() ?? {};

      double openingBalance = (current['opening_balance'] ?? 0).toDouble();

      if (current['opening_balance'] == null) {
        try {
          final prevDate = DateTime.parse(dateKey).subtract(Duration(days: 1));
          final prevKey = prevDate.toIso8601String().split('T')[0];
          final prevSnap =
              await t.get(firestore.collection(DAILY_SUMMARIES).doc(prevKey));
          final prevData = prevSnap.data() ?? {};
          openingBalance = (prevData['closing_balance'] ?? 0).toDouble();
        } catch (_) {}
      }

      double walletTopups = (current['wallet_topups'] ?? 0).toDouble();
      double otherIncome = (current['other_income'] ?? 0).toDouble();
      double creditSales = (current['credit_sales'] ?? 0).toDouble();
      double totalExpenses = (current['total_expenses'] ?? 0).toDouble();
      double totalPaymentsReceived =
          (current['total_payments_received'] ?? 0).toDouble();

      // Read credit entry if this is a credit payment
      DocumentReference? creditEntryRef;
      Map<String, dynamic>? creditEntryData;
      if (type == 'credit_payment' && creditEntryId != null) {
        creditEntryRef =
            firestore.collection(CREDIT_ENTRIES).doc(creditEntryId);
        final creditEntrySnap = await t.get(creditEntryRef);
        if (creditEntrySnap.exists) {
          creditEntryData = creditEntrySnap.data() as Map<String, dynamic>?;
        }
      }

      // APPLY MUTATIONS (WRITES) ONLY AFTER ALL READS
      if (type == 'wallet_topup') walletTopups += amount;
      if (type == 'other_income') otherIncome += amount;
      if (type == 'credit_sale') creditSales += amount;
      if (type == 'expense') totalExpenses += amount;
      if (type == 'credit_payment') totalPaymentsReceived += amount;

      final netBalance = (walletTopups +
              otherIncome +
              totalPaymentsReceived) -
          totalExpenses -
          creditSales;
      final closingBalance = openingBalance + netBalance;

      // 1) Increment wallet only for wallet_topup
      if (type == 'wallet_topup' && riderRef != null) {
        t.update(riderRef, {'wallet_amount': FieldValue.increment(amount)});
      }

      // 2) Create credit entry when a credit sale is made
      DocumentReference? newCreditEntryRef;
      if (type == 'credit_sale') {
        newCreditEntryRef = firestore.collection(CREDIT_ENTRIES).doc();
        t.set(newCreditEntryRef, {
          'date': dateKey,
          'description': description,
          'initial_amount': amount,
          'outstanding_balance': amount,
          'is_paid': false,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      // 3) Handle credit payment - atomically update credit entry
      if (type == 'credit_payment' &&
          creditEntryRef != null &&
          creditEntryData != null) {
        final currentOutstanding =
            (creditEntryData['outstanding_balance'] ?? 0).toDouble();
        final newOutstanding = (currentOutstanding - amount).clamp(0.0, double.infinity);
        final isFullyPaid = newOutstanding <= 0.001; // Use small epsilon for float comparison

        t.update(creditEntryRef, {
          'outstanding_balance': newOutstanding,
          'is_paid': isFullyPaid,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      // 4) Write the transaction (with known id)
      t.set(txRef, {
        'date': dateKey,
        'type': type,
        'amount': amount,
        'description': description,
        'riderId': riderId,
        'creditEntryId': creditEntryId ?? newCreditEntryRef?.id,
        'created_at': FieldValue.serverTimestamp(),
        'txId': txId,
      });

      // 5) Update daily summary totals
      t.set(
        dayRef,
        {
          'date': dateKey,
          'opening_balance': openingBalance,
          'wallet_topups': walletTopups,
          'other_income': otherIncome,
          'credit_sales': creditSales,
          'total_payments_received': totalPaymentsReceived,
          'total_expenses': totalExpenses,
          'net_balance': netBalance,
          'closing_balance': closingBalance,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> deleteCreditSale({
    required String dateKey,
    required String transactionId,
    required double amount,
    String? creditEntryId,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final dayRef = firestore.collection(DAILY_SUMMARIES).doc(dateKey);
    final txRef = dayRef.collection('transactions').doc(transactionId);
    final creditEntryRef = creditEntryId != null
        ? firestore.collection(CREDIT_ENTRIES).doc(creditEntryId)
        : null;

    await firestore.runTransaction((t) async {
      // Read daily summary
      final daySnap = await t.get(dayRef);
      final current = daySnap.data() ?? {};

      double openingBalance = (current['opening_balance'] ?? 0).toDouble();
      double creditSales = (current['credit_sales'] ?? 0).toDouble();

      // Check if credit entry exists and read it
      Map<String, dynamic>? creditEntryData;
      if (creditEntryRef != null) {
        final creditEntrySnap = await t.get(creditEntryRef);
        if (creditEntrySnap.exists) {
          creditEntryData = creditEntrySnap.data();
        }
      }

      // Verify transaction exists
      final txSnap = await t.get(txRef);
      if (!txSnap.exists) {
        throw Exception('Transaction not found');
      }

      // Update credit sales (subtract the amount)
      creditSales = (creditSales - amount).clamp(0.0, double.infinity);

      double walletTopups = (current['wallet_topups'] ?? 0).toDouble();
      double otherIncome = (current['other_income'] ?? 0).toDouble();
      double totalExpenses = (current['total_expenses'] ?? 0).toDouble();
      double totalPaymentsReceived =
          (current['total_payments_received'] ?? 0).toDouble();

      final netBalance = (walletTopups +
              otherIncome +
              totalPaymentsReceived) -
          totalExpenses -
          creditSales;
      final closingBalance = openingBalance + netBalance;

      // Delete credit entry if it exists
      if (creditEntryRef != null && creditEntryData != null) {
        t.delete(creditEntryRef);
      }

      // Delete transaction
      t.delete(txRef);

      // Update daily summary
      t.set(
        dayRef,
        {
          'date': dateKey,
          'opening_balance': openingBalance,
          'wallet_topups': walletTopups,
          'other_income': otherIncome,
          'credit_sales': creditSales,
          'total_payments_received': totalPaymentsReceived,
          'total_expenses': totalExpenses,
          'net_balance': netBalance,
          'closing_balance': closingBalance,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
