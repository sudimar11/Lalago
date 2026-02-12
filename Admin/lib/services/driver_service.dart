import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/models/driver.dart';

class DriverService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Driver>> streamDrivers() {
    return _db
        .collection(USERS)
        .where('role', isEqualTo: 'driver')
        .snapshots()
        .map((QuerySnapshot snapshot) => snapshot.docs
            .map((doc) =>
                Driver.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  Future<void> setActive(String driverId, bool active) async {
    await _db.collection(USERS).doc(driverId).update({'isActive': active});
  }
}
