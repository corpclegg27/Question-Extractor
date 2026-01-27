// lib/models/batch_model.dart
// Description: Data model representing a Batch.
// Maps to the 'batches' collection in Firestore.

import 'package:cloud_firestore/cloud_firestore.dart';

class BatchModel {
  final String id;
  final Timestamp createdAt;
  final String createdBy;
  final String batchName;
  final List<String> teacherIds;   // Stored as 'teacherRefs' (UIDs)
  final List<String> studentIds;   // Stored as 'studentRefs' (UIDs)
  final List<String> assignmentIds;// Stored as 'assignments' (Curation IDs)

  BatchModel({
    required this.id,
    required this.createdAt,
    required this.createdBy,
    required this.batchName,
    required this.teacherIds,
    required this.studentIds,
    required this.assignmentIds,
  });

  // Factory to create a BatchModel from Firestore Document
  factory BatchModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BatchModel(
      id: doc.id,
      createdAt: data['created_at'] as Timestamp? ?? Timestamp.now(),
      createdBy: data['created_by'] ?? '',
      batchName: data['batchName'] ?? '',
      teacherIds: List<String>.from(data['teacherRefs'] ?? []),
      studentIds: List<String>.from(data['studentRefs'] ?? []),
      assignmentIds: List<String>.from(data['assignments'] ?? []),
    );
  }

  // Method to convert BatchModel to Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'created_at': createdAt,
      'created_by': createdBy,
      'batchName': batchName,
      'teacherRefs': teacherIds,
      'studentRefs': studentIds,
      'assignments': assignmentIds,
    };
  }
}