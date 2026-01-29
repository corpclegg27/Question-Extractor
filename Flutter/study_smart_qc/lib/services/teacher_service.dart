// lib/services/teacher_service.dart
// Description: Handles teacher operations.
// UPDATED: Added 'assignQuestionsToBatch' to handle Batch assignment creation.

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/marking_configuration.dart';
import 'package:study_smart_qc/services/teacher_service.dart'; // Self-import if needed for enums, usually not required if defined here.

// Enum for Cloning Targets
enum TargetAudienceType { individual, batch, general }

class PaginatedQuestions {
  final List<Question> questions;
  final DocumentSnapshot? lastDoc;
  PaginatedQuestions(this.questions, this.lastDoc);
}

class TeacherService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _currentTeacherId => _auth.currentUser?.uid;

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
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    if (audienceType == 'Particular Student' && smartFilter != null && smartFilter != 'New Questions') {
      final allQuestions = await _fetchFromTracker(studentId!, smartFilter);
      return PaginatedQuestions(allQuestions, null);
    }

    Query query = _firestore.collection('questions');

    if (chapterIds != null && chapterIds.isNotEmpty) {
      query = query.where('chapterId', whereIn: chapterIds.take(10).toList());
    }

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.limit(limit).get();
    List<Question> questions = snap.docs.map((d) => Question.fromFirestore(d)).toList();

    if (topicIds != null && topicIds.isNotEmpty) {
      questions = questions.where((q) => topicIds.contains(q.topicId)).toList();
    }

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

  // --- 4. CLONING ---
  Future<void> cloneAssignment({
    required DocumentSnapshot sourceDoc,
    required TargetAudienceType targetType,
    required String targetId,
    required String targetName,
    DateTime? newDeadline,
  }) async {
    if (_currentTeacherId == null) throw Exception("User not logged in");

    try {
      final data = sourceDoc.data() as Map<String, dynamic>;
      final String newCode = _generateAssignmentCode();

      Map<String, dynamic> newCuration = {
        'title': data['title'] ?? 'Cloned Assignment',
        'assignmentCode': newCode,
        'assignmentId': data['assignmentId'],
        'createdAt': FieldValue.serverTimestamp(),
        'teacherUid': _currentTeacherId,
        'status': 'Assigned',

        'questionIds': data['questionIds'] ?? [],
        'markingSchemes': data['markingSchemes'] ?? {},
        'marksBreakdownMap': data['marksBreakdownMap'] ?? {},
        'meta_hierarchy': data['meta_hierarchy'] ?? {},
        'onlySingleAttempt': data['onlySingleAttempt'] ?? false,
        'timeLimitMinutes': data['timeLimitMinutes'],
        'subjects': data['subjects'] ?? [],
        'questionIdsGrouped': data['questionIdsGrouped'] ?? {},
      };

      if (newDeadline != null) {
        newCuration['deadline'] = Timestamp.fromDate(newDeadline);
      }

      switch (targetType) {
        case TargetAudienceType.individual:
          newCuration['targetAudience'] = 'Particular Student';
          newCuration['studentUid'] = targetId;
          newCuration['studentName'] = targetName;
          break;

        case TargetAudienceType.batch:
          newCuration['targetAudience'] = 'Batch';
          newCuration['batchId'] = targetId;
          newCuration['batchName'] = targetName;
          newCuration['studentUid'] = null;
          newCuration['studentId'] = null;
          break;

        case TargetAudienceType.general:
          newCuration['targetAudience'] = 'General';
          newCuration['assignedToName'] = "General Audience";
          newCuration['studentUid'] = null;
          newCuration['batchId'] = null;
          break;
      }

      final newRef = _firestore.collection('questions_curation').doc();
      final batch = _firestore.batch();
      batch.set(newRef, newCuration);

      if (targetType == TargetAudienceType.individual) {
        final trackerRef = _firestore.collection('student_question_tracker').doc(targetId);
        final List<dynamic> qIds = data['questionIds'] ?? [];
        batch.update(trackerRef, {
          'assigned_history': FieldValue.arrayUnion(qIds),
          'buckets.unattempted': FieldValue.arrayUnion(qIds),
        });
      }

      await batch.commit();

    } catch (e) {
      print("Error cloning assignment: $e");
      rethrow;
    }
  }

  Future<void> updateQuestionOrder(String docId, List<String> newOrder) async {
    await _firestore.collection('questions_curation').doc(docId).update({
      'questionIds': newOrder,
    });
  }

  // --- 5. ASSIGNMENT LOGIC ---

  // A. ASSIGN TO STUDENT (Updates Tracker)
  Future<void> assignQuestionsToStudent({
    required int studentId,
    required List<Question> questions,
    required String teacherUid,
    required String targetAudience,
    String assignmentTitle = "",
    bool onlySingleAttempt = false,
    int? timeLimitMinutes,
    DateTime? deadline,
    Map<QuestionType, MarkingConfiguration>? markingSchemes,
  }) async {
    final studentUid = await _findUidByStudentId(studentId);
    if (studentUid == null) throw Exception("Student not found");

    final newAssignmentRef = _firestore.collection('questions_curation').doc();
    final trackerRef = _firestore.collection('student_question_tracker').doc(studentUid);
    final batch = _firestore.batch();

    final data = _prepareAssignmentData(
        refId: newAssignmentRef.id,
        questions: questions,
        teacherUid: teacherUid,
        targetAudience: targetAudience,
        title: assignmentTitle,
        onlySingleAttempt: onlySingleAttempt,
        timeLimitMinutes: timeLimitMinutes,
        deadline: deadline,
        markingSchemes: markingSchemes
    );

    // Specific Fields for Student
    data['studentId'] = studentId;
    data['studentUid'] = studentUid;

    batch.set(newAssignmentRef, data);

    final questionIds = questions.map((q) => q.customId).toList();
    batch.update(trackerRef, {
      'assigned_history': FieldValue.arrayUnion(questionIds),
      'buckets.unattempted': FieldValue.arrayUnion(questionIds),
    });

    await batch.commit();
  }

  // B. [NEW] ASSIGN TO BATCH (No Tracker Update)
  Future<void> assignQuestionsToBatch({
    required String batchId,
    required String batchName,
    required List<Question> questions,
    required String teacherUid,
    String assignmentTitle = "",
    bool onlySingleAttempt = false,
    int? timeLimitMinutes,
    DateTime? deadline,
    Map<QuestionType, MarkingConfiguration>? markingSchemes,
  }) async {
    final newAssignmentRef = _firestore.collection('questions_curation').doc();

    final data = _prepareAssignmentData(
        refId: newAssignmentRef.id,
        questions: questions,
        teacherUid: teacherUid,
        targetAudience: 'Batch',
        title: assignmentTitle,
        onlySingleAttempt: onlySingleAttempt,
        timeLimitMinutes: timeLimitMinutes,
        deadline: deadline,
        markingSchemes: markingSchemes
    );

    // Specific Fields for Batch
    data['batchId'] = batchId;
    data['batchName'] = batchName;
    // Explicitly nullify student fields to prevent index issues
    data['studentId'] = null;
    data['studentUid'] = null;

    await newAssignmentRef.set(data);
  }

  // --- HELPERS ---

  // Shared Data Builder
  Map<String, dynamic> _prepareAssignmentData({
    required String refId,
    required List<Question> questions,
    required String teacherUid,
    required String targetAudience,
    required String title,
    required bool onlySingleAttempt,
    int? timeLimitMinutes,
    DateTime? deadline,
    Map<QuestionType, MarkingConfiguration>? markingSchemes,
  }) {
    final assignmentCode = _generateAssignmentCode();
    final questionIds = questions.map((q) => q.customId).toList();

    // Subjects
    final subjects = questions
        .map((q) => q.subject.isNotEmpty ? q.subject : (q.chapterId.split('_').first))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    // Hierarchy
    final hierarchy = _buildHierarchy(questions);

    // Grouped IDs & Marks
    Map<String, dynamic> questionIdsGrouped = {};
    Map<String, dynamic> marksBreakdownMap = { "Overall": 0.0 };

    for (var q in questions) {
      String subject = q.subject.isEmpty ? "General" : q.subject;
      String typeStr = _mapTypeToString(q.type);

      questionIdsGrouped.putIfAbsent(subject, () => <String, dynamic>{});
      questionIdsGrouped[subject].putIfAbsent(typeStr, () => <String>[]);
      (questionIdsGrouped[subject][typeStr] as List).add(q.customId);

      double score = 4.0;
      if (markingSchemes != null && markingSchemes.containsKey(q.type)) {
        score = markingSchemes[q.type]!.correctScore;
      }

      marksBreakdownMap.putIfAbsent(subject, () => <String, dynamic>{});
      double currentSubjTypeTotal = (marksBreakdownMap[subject][typeStr] ?? 0.0);
      marksBreakdownMap[subject][typeStr] = currentSubjTypeTotal + score;
      marksBreakdownMap["Overall"] = (marksBreakdownMap["Overall"] ?? 0.0) + score;
    }

    // Marking Schemes Serialization
    Map<String, dynamic> schemesMap = {};
    if (markingSchemes != null) {
      markingSchemes.forEach((type, config) {
        schemesMap[_mapTypeToString(type)] = config.toMap();
      });
    }

    final int finalTimeLimit = timeLimitMinutes ?? (questions.length * 2);
    final String finalTitle = title.isEmpty ? "New Assignment" : title;

    Map<String, dynamic> data = {
      'assignmentId': refId,
      'assignmentCode': assignmentCode,
      'targetAudience': targetAudience,
      'teacherUid': teacherUid,
      'title': finalTitle,
      'questionIds': questionIds,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'assigned',
      'onlySingleAttempt': onlySingleAttempt,
      'timeLimitMinutes': finalTimeLimit,
      'subjects': subjects,
      'meta_hierarchy': hierarchy,
      'markingSchemes': schemesMap,
      'questionIdsGrouped': questionIdsGrouped,
      'marksBreakdownMap': marksBreakdownMap,
    };

    if (deadline != null) {
      data['deadline'] = Timestamp.fromDate(deadline);
    }

    return data;
  }

  String _mapTypeToString(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return 'Single Correct';
      case QuestionType.numerical: return 'Numerical type';
      case QuestionType.oneOrMoreOptionsCorrect: return 'One or more options correct';
      case QuestionType.matrixSingle: return 'Single Matrix Match';
      case QuestionType.matrixMulti: return 'Multi Matrix Match';
      default: return 'Unknown';
    }
  }

  Future<AttemptModel?> getAttemptForCuration(String curationId) async {
    try {
      final query = await _firestore.collection('attempts').where('sourceId', isEqualTo: curationId).orderBy('completedAt', descending: true).limit(1).get();
      if (query.docs.isNotEmpty) return AttemptModel.fromFirestore(query.docs.first);
      return null;
    } catch (e) { return null; }
  }

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
    final safeIds = ids.take(20).toList();
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
      final exam = q.exam.isEmpty ? 'General' : q.exam;
      final subject = q.subject.isEmpty ? 'General' : q.subject;
      String chapter = q.chapter.isNotEmpty ? q.chapter : (q.chapterId.isNotEmpty ? q.chapterId : 'Unknown Chapter');
      String topic = q.topic.isNotEmpty ? q.topic : (q.topicId.isNotEmpty ? q.topicId : 'Unknown Topic');
      hierarchy.putIfAbsent(exam, () => <String, dynamic>{});
      hierarchy[exam].putIfAbsent(subject, () => <String, dynamic>{});
      hierarchy[exam][subject].putIfAbsent(chapter, () => <String, dynamic>{});
      final currentCount = hierarchy[exam][subject][chapter][topic] ?? 0;
      hierarchy[exam][subject][chapter][topic] = currentCount + 1;
    }
    return hierarchy;
  }
}