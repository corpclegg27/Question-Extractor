// lib/services/teacher_service.dart

import 'dart:math'; // For random code generation
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/question_model.dart';

class TeacherService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- 1. STATS DASHBOARD (For Step 1) ---

  Future<Map<String, int>> getStudentStats(int studentId) async {
    final uid = await _findUidByStudentId(studentId);
    if (uid == null) return {};

    final doc = await _firestore.collection('student_question_tracker').doc(uid).get();
    if (!doc.exists) return {};

    final data = doc.data()!;
    final buckets = data['buckets'] as Map<String, dynamic>;
    final assigned = (data['assigned_history'] as List?)?.length ?? 0;

    return {
      'Assigned': assigned,
      'Unattempted': (buckets['unattempted'] as List?)?.length ?? 0,
      'Incorrect': (buckets['incorrect'] as List?)?.length ?? 0,
      'Correct': (buckets['correct'] as List?)?.length ?? 0,
      'Skipped': (buckets['skipped'] as List?)?.length ?? 0,
    };
  }

  // --- 2. ADVANCED SEARCH (For Step 2) ---

  Future<List<Question>> fetchQuestions({
    required String audienceType, // 'General', 'Particular Student'
    int? studentId,
    String? smartFilter, // 'New Questions', 'Incorrect', etc.
    String? subject,
    List<String>? chapterIds,
    List<String>? topicIds,
    int limit = 50,
  }) async {
    List<Question> candidates = [];

    if (audienceType == 'Particular Student' && smartFilter != null && smartFilter != 'New Questions') {
      candidates = await _fetchFromTracker(studentId!, smartFilter);
    } else {
      candidates = await _fetchFromGeneralPool(subject, chapterIds, limit);

      if (audienceType == 'Particular Student' && studentId != null) {
        final historyIds = await _getStudentHistory(studentId);
        candidates = candidates.where((q) => !historyIds.contains(q.id)).toList();
      }
    }

    return candidates.where((q) {
      if (chapterIds != null && chapterIds.isNotEmpty && !chapterIds.contains(q.chapterId)) return false;
      if (topicIds != null && topicIds.isNotEmpty && !topicIds.contains(q.topicId)) return false;
      return true;
    }).take(limit).toList();
  }

  // --- 3. MANAGE CURATIONS (For TeacherHistoryScreen) ---

  Stream<QuerySnapshot> getTeacherCurations(String teacherUid) {
    return _firestore
        .collection('questions_curation')
        .where('teacherUid', isEqualTo: teacherUid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // --- 4. MANAGEMENT (Clone & Reorder) ---

  Future<void> cloneAssignment({
    required String originalDocId,
    required int targetStudentId,
    required String teacherUid,
  }) async {
    // 1. Get Original Data
    final docSnapshot = await _firestore.collection('questions_curation').doc(originalDocId).get();
    if (!docSnapshot.exists) throw Exception("Original assignment not found.");
    final data = docSnapshot.data()!;

    // 2. Validate Target Student
    final newStudentUid = await _findUidByStudentId(targetStudentId);
    if (newStudentUid == null) throw Exception("Target student ID not found.");

    // 3. Prepare New Data
    final newRef = _firestore.collection('questions_curation').doc();
    final newCode = _generateAssignmentCode();

    final newData = Map<String, dynamic>.from(data);
    newData['assignmentId'] = newRef.id;
    newData['assignmentCode'] = newCode;
    newData['studentUid'] = newStudentUid; // The new owner
    newData['teacherUid'] = teacherUid;
    newData['createdAt'] = FieldValue.serverTimestamp();
    newData['status'] = 'assigned'; // Reset status to assigned
    // We keep title, questionIds, timeLimit, isStrict, hierarchy exactly as is.

    // 4. Write to DB
    final batch = _firestore.batch();
    batch.set(newRef, newData);

    // Update new student's tracker
    final trackerRef = _firestore.collection('student_question_tracker').doc(newStudentUid);
    final List<dynamic> qIds = data['questionIds'] ?? [];

    batch.update(trackerRef, {
      'assigned_history': FieldValue.arrayUnion(qIds),
      'buckets.unattempted': FieldValue.arrayUnion(qIds),
    });

    await batch.commit();
  }

  Future<void> updateQuestionOrder(String docId, List<String> newOrder) async {
    await _firestore.collection('questions_curation').doc(docId).update({
      'questionIds': newOrder,
    });
  }

  // --- 5. ASSIGNMENT LOGIC ---

  Future<void> assignQuestionsToStudent({
    required int studentId,
    required List<Question> questions,
    required String teacherUid,
    required String targetAudience,
    String assignmentTitle = "Teacher Assignment",
    bool onlySingleAttempt = false,
    int? timeLimitMinutes, // <--- NEW PARAMETER ADDED HERE
  }) async {
    final studentUid = await _findUidByStudentId(studentId);
    if (studentUid == null) throw Exception("Student not found");

    final newAssignmentRef = _firestore.collection('questions_curation').doc();
    final trackerRef = _firestore.collection('student_question_tracker').doc(studentUid);
    final batch = _firestore.batch();

    final assignmentCode = _generateAssignmentCode();
    final questionIds = questions.map((q) => q.id).toList();
    final subjects = questions.map((q) => q.chapterId.split('_').first).toSet().toList();
    final hierarchy = _buildHierarchy(questions);

    // Calculate default time if none provided (2 mins per question)
    final int finalTimeLimit = timeLimitMinutes ?? (questions.length * 2);

    batch.set(newAssignmentRef, {
      'assignmentId': newAssignmentRef.id,
      'assignmentCode': assignmentCode,
      'targetAudience': targetAudience,
      'studentUid': studentUid,
      'teacherUid': teacherUid,
      'title': assignmentTitle,
      'questionIds': questionIds,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'assigned',
      'onlySingleAttempt': onlySingleAttempt,
      'timeLimitMinutes': finalTimeLimit, // <--- SAVED TO DB
      'subjects': subjects,
      'meta_hierarchy': hierarchy,
    });

    batch.update(trackerRef, {
      'assigned_history': FieldValue.arrayUnion(questionIds),
      'buckets.unattempted': FieldValue.arrayUnion(questionIds),
    });

    await batch.commit();
  }

  // --- INTERNAL HELPERS ---

  Future<List<Question>> _fetchFromTracker(int studentId, String bucketKey) async {
    final uid = await _findUidByStudentId(studentId);
    if (uid == null) return [];

    final doc = await _firestore.collection('student_question_tracker').doc(uid).get();
    if (!doc.exists) return [];

    final buckets = doc.data()!['buckets'] as Map<String, dynamic>;

    String dbKey = bucketKey.toLowerCase();
    if (bucketKey.contains('Incorrect')) dbKey = 'incorrect';
    if (bucketKey.contains('Unattempted')) dbKey = 'unattempted';
    if (bucketKey.contains('Correct')) dbKey = 'correct';
    if (bucketKey.contains('Skipped')) dbKey = 'skipped';

    final ids = List<String>.from(buckets[dbKey] ?? []);
    if (ids.isEmpty) return [];

    final safeIds = ids.take(10).toList();
    final query = await _firestore.collection('questions').where(FieldPath.documentId, whereIn: safeIds).get();
    return query.docs.map((d) => Question.fromFirestore(d)).toList();
  }

  Future<List<Question>> _fetchFromGeneralPool(String? subject, List<String>? chapterIds, int limit) async {
    Query query = _firestore.collection('questions');

    if (chapterIds != null && chapterIds.isNotEmpty && chapterIds.length <= 10) {
      query = query.where('chapterId', whereIn: chapterIds);
    }

    final snap = await query.limit(limit * 2).get();
    return snap.docs.map((d) => Question.fromFirestore(d)).toList();
  }

  Future<Set<String>> _getStudentHistory(int studentId) async {
    final uid = await _findUidByStudentId(studentId);
    if (uid == null) return {};
    final doc = await _firestore.collection('student_question_tracker').doc(uid).get();
    if (!doc.exists) return {};
    return Set<String>.from(doc.data()!['assigned_history'] ?? []);
  }

  Future<String?> _findUidByStudentId(int studentId) async {
    final query = await _firestore.collection('users').where('studentId', isEqualTo: studentId).limit(1).get();
    if (query.docs.isEmpty) return null;
    return query.docs.first.id;
  }

  String _generateAssignmentCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Map<String, dynamic> _buildHierarchy(List<Question> questions) {
    Map<String, dynamic> hierarchy = {};

    for (var q in questions) {
      final exam = q.source.isEmpty ? 'Unknown Exam' : q.source;
      final subject = 'Physics';
      final chapter = q.chapterId.isEmpty ? 'Unknown Chapter' : q.chapterId;
      final topic = q.topicId.isEmpty ? 'Unknown Topic' : q.topicId;

      hierarchy.putIfAbsent(exam, () => <String, dynamic>{});
      hierarchy[exam].putIfAbsent(subject, () => <String, dynamic>{});
      hierarchy[exam][subject].putIfAbsent(chapter, () => <String, dynamic>{});

      final currentCount = hierarchy[exam][subject][chapter][topic] ?? 0;
      hierarchy[exam][subject][chapter][topic] = currentCount + 1;
    }
    return hierarchy;
  }
}