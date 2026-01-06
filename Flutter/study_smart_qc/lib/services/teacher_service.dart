// lib/services/teacher_service.dart

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

// --- HELPER CLASS FOR PAGINATION ---
class PaginatedQuestions {
  final List<Question> questions;
  final DocumentSnapshot? lastDoc;
  PaginatedQuestions(this.questions, this.lastDoc);
}

class TeacherService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- 1. STATS DASHBOARD ---
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

  // --- 2. ADVANCED SEARCH (PAGINATED) ---

  Future<PaginatedQuestions> fetchQuestionsPaged({
    required String audienceType,
    int? studentId,
    String? smartFilter,
    String? subject,
    List<String>? chapterIds,
    List<String>? topicIds,
    int limit = 20, // Default reduced to 20
    DocumentSnapshot? startAfter, // Cursor for pagination
  }) async {
    // 1. Determine Source (Tracker vs General Pool)
    // Note: Tracker-based fetching (Smart Filter) is hard to paginate via Firestore query
    // because it reads a list of IDs. For now, we fetch the list and handle slicing manually
    // if needed, or just return all since tracker buckets usually aren't massive.
    // For 'General' search, we use true Firestore pagination.

    if (audienceType == 'Particular Student' && smartFilter != null && smartFilter != 'New Questions') {
      // Logic for Tracker (Pre-existing logic, simplified return)
      final allQuestions = await _fetchFromTracker(studentId!, smartFilter);
      // We simulate pagination or just return all for tracker buckets
      return PaginatedQuestions(allQuestions, null);
    }

    // 2. General Pool Query Construction
    Query query = _firestore.collection('questions');

    if (chapterIds != null && chapterIds.isNotEmpty) {
      // 'whereIn' limits to 10. If more, we might need multiple queries,
      // but assuming the UI restricts or we take first 10.
      query = query.where('chapterId', whereIn: chapterIds.take(10).toList());
    }

    // Apply Cursor
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    // Apply Limit
    final snap = await query.limit(limit).get();

    // Convert
    List<Question> questions = snap.docs.map((d) => Question.fromFirestore(d)).toList();

    // 3. Filter by Topic (Client-side)
    // Firestore can't do whereIn(chapters) AND whereIn(topics) easily.
    if (topicIds != null && topicIds.isNotEmpty) {
      questions = questions.where((q) => topicIds.contains(q.topicId)).toList();
    }

    // 4. Exclude History (Client-side)
    if (audienceType == 'Particular Student' && studentId != null) {
      final historyIds = await _getStudentHistory(studentId);
      questions = questions.where((q) => !historyIds.contains(q.id)).toList();
    }

    return PaginatedQuestions(
        questions,
        snap.docs.isNotEmpty ? snap.docs.last : null
    );
  }

  // --- 3. MANAGE CURATIONS ---
  Stream<QuerySnapshot> getTeacherCurations(String teacherUid) {
    return _firestore
        .collection('questions_curation')
        .where('teacherUid', isEqualTo: teacherUid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // --- 4. MANAGEMENT ---
  Future<void> cloneAssignment({
    required String originalDocId,
    required int targetStudentId,
    required String teacherUid,
  }) async {
    final docSnapshot = await _firestore.collection('questions_curation').doc(originalDocId).get();
    if (!docSnapshot.exists) throw Exception("Original assignment not found.");
    final data = docSnapshot.data()!;

    final newStudentUid = await _findUidByStudentId(targetStudentId);
    if (newStudentUid == null) throw Exception("Target student ID not found.");

    final newRef = _firestore.collection('questions_curation').doc();
    final newCode = _generateAssignmentCode();

    final newData = Map<String, dynamic>.from(data);
    newData['assignmentId'] = newRef.id;
    newData['assignmentCode'] = newCode;
    newData['studentUid'] = newStudentUid;
    newData['teacherUid'] = teacherUid;
    newData['createdAt'] = FieldValue.serverTimestamp();
    newData['status'] = 'assigned';

    final batch = _firestore.batch();
    batch.set(newRef, newData);

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
    int? timeLimitMinutes,
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
      'timeLimitMinutes': finalTimeLimit,
      'subjects': subjects,
      'meta_hierarchy': hierarchy,
    });

    batch.update(trackerRef, {
      'assigned_history': FieldValue.arrayUnion(questionIds),
      'buckets.unattempted': FieldValue.arrayUnion(questionIds),
    });

    await batch.commit();
  }

  // --- 6. PERFORMANCE MONITORING ---
  Future<AttemptModel?> getAttemptForCuration(String curationId) async {
    try {
      final query = await _firestore
          .collection('attempts')
          .where('sourceId', isEqualTo: curationId)
          .orderBy('completedAt', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        return AttemptModel.fromFirestore(query.docs.first);
      }
      return null;
    } catch (e) {
      print("Error fetching curation attempt: $e");
      return null;
    }
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

    final safeIds = ids.take(20).toList(); // Limit tracker fetch too
    final query = await _firestore.collection('questions').where(FieldPath.documentId, whereIn: safeIds).get();
    return query.docs.map((d) => Question.fromFirestore(d)).toList();
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
    return String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Map<String, dynamic> _buildHierarchy(List<Question> questions) {
    Map<String, dynamic> hierarchy = {};
    for (var q in questions) {
      final exam = q.exam.isEmpty ? 'Unknown Exam' : q.exam;
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