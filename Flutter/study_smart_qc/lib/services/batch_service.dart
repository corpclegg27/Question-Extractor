// lib/services/batch_service.dart
// Description: Service layer for Batch operations.
// Handles fetching potential students and creating new batch documents.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/batch_model.dart';
import 'package:study_smart_qc/models/user_model.dart';

class BatchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetches all users with role 'student' to populate the selection list.
  /// Returns a list of [UserModel].
  Future<List<UserModel>> getAllStudents() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .orderBy('createdAt', descending: true) // Show newest students first
          .get();

      // [UPDATED] Use fromFirestore to ensure the UID is captured correctly from the doc ID.
      return snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print("Error fetching students for batch creation: $e");
      return [];
    }
  }

  /// Creates a new batch document in the 'batches' collection.
  Future<void> createBatch({
    required String batchName,
    required String createdByUserId,
    required List<String> selectedStudentIds,
  }) async {
    try {
      final docRef = _firestore.collection('batches').doc();

      final newBatch = BatchModel(
        id: docRef.id,
        createdAt: Timestamp.now(),
        createdBy: createdByUserId,
        batchName: batchName,
        // The creator is automatically added as the first teacher
        teacherIds: [createdByUserId],
        studentIds: selectedStudentIds,
        assignmentIds: [], // Initially empty
      );

      await docRef.set(newBatch.toFirestore());
    } catch (e) {
      print("Error creating batch: $e");
      rethrow;
    }
  }


  /// Fetches all batches where the specific teacher is listed in 'teacherRefs'.
  Future<List<BatchModel>> getBatchesForTeacher(String teacherId) async {
    try {
      final snapshot = await _firestore
          .collection('batches')
          .where('teacherRefs', arrayContains: teacherId)
          .orderBy('created_at', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => BatchModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print("Error fetching teacher batches: $e");
      return [];
    }
  }
}