import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:study_smart_qc/models/custom_test_model.dart';

class CustomTestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get the current user's ID
  String? get _userId => _auth.currentUser?.uid;

  // Save a generated test to Firestore
  Future<void> saveTest(CustomTest test) async {
    if (_userId == null) return;

    final docRef = _firestore
        .collection('users')
        .doc(_userId)
        .collection('custom_tests')
        .doc(); // Auto-generate ID

    await docRef.set(test.toFirestore());
  }

  // Retrieve all tests for the current user
  Stream<List<CustomTest>> getCustomTests() {
    if (_userId == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('custom_tests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => CustomTest.fromFirestore(doc))
              .toList();
        });
  }

  // Fetch the full Question objects for a saved test
  Future<List<Map<String, dynamic>>> getQuestionsForTest(
    List<String> questionIds,
  ) async {
    if (questionIds.isEmpty) return [];

    final querySnapshot = await _firestore
        .collection('questions')
        .where(FieldPath.documentId, whereIn: questionIds)
        .get();

    return querySnapshot.docs.map((doc) => doc.data()).toList();
  }
}
