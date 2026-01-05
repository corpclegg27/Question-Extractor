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

    // STRATEGY:
    // If Smart Filter is active (e.g., 'Incorrect'), source is the Tracker (Question IDs).
    // If General/New, source is the Questions Collection (filtered by Syllabus).

    if (audienceType == 'Particular Student' && smartFilter != null && smartFilter != 'New Questions') {
      // CASE A: Fetch from Tracker History (Incorrect, Unattempted, etc.)
      candidates = await _fetchFromTracker(studentId!, smartFilter);
    } else {
      // CASE B: Fetch from General Pool (and optionally filter out 'seen' questions)
      candidates = await _fetchFromGeneralPool(subject, chapterIds, limit);

      // If 'New Questions' for a student, exclude their history
      if (audienceType == 'Particular Student' && studentId != null) {
        final historyIds = await _getStudentHistory(studentId);
        candidates = candidates.where((q) => !historyIds.contains(q.id)).toList();
      }
    }

    // --- APPLY CLIENT-SIDE FILTERS ---
    // Firestore is limited, so we refine results here (Topic, Subject check)
    return candidates.where((q) {
      if (chapterIds != null && chapterIds.isNotEmpty && !chapterIds.contains(q.chapterId)) return false;
      if (topicIds != null && topicIds.isNotEmpty && !topicIds.contains(q.topicId)) return false;
      return true;
    }).take(limit).toList();
  }

  // --- INTERNAL HELPERS ---

  Future<List<Question>> _fetchFromTracker(int studentId, String bucketKey) async {
    final uid = await _findUidByStudentId(studentId);
    if (uid == null) return [];

    final doc = await _firestore.collection('student_question_tracker').doc(uid).get();
    if (!doc.exists) return [];

    final buckets = doc.data()!['buckets'] as Map<String, dynamic>;

    // Map UI string to DB key
    String dbKey = bucketKey.toLowerCase();
    if (bucketKey.contains('Incorrect')) dbKey = 'incorrect';
    if (bucketKey.contains('Unattempted')) dbKey = 'unattempted';
    if (bucketKey.contains('Correct')) dbKey = 'correct';
    if (bucketKey.contains('Skipped')) dbKey = 'skipped';

    final ids = List<String>.from(buckets[dbKey] ?? []);
    if (ids.isEmpty) return [];

    // Fetch actual docs (batched if > 10, but taking top 10 for MVP safety)
    final safeIds = ids.take(10).toList();
    final query = await _firestore.collection('questions').where(FieldPath.documentId, whereIn: safeIds).get();
    return query.docs.map((d) => Question.fromFirestore(d)).toList();
  }

  Future<List<Question>> _fetchFromGeneralPool(String? subject, List<String>? chapterIds, int limit) async {
    Query query = _firestore.collection('questions');

    // Optimization: If specific chapters selected, use them (max 10 for 'whereIn')
    if (chapterIds != null && chapterIds.isNotEmpty && chapterIds.length <= 10) {
      query = query.where('chapterId', whereIn: chapterIds);
    } else {
      // Fallback to purely limit-based if no chapters or too many chapters
      // In a real app, you'd filter by Subject string if it exists on the doc
    }

    final snap = await query.limit(limit * 2).get(); // Fetch extra to allow for local filtering
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

  /// UPDATED ASSIGNMENT LOGIC
  Future<void> assignQuestionsToStudent({
    required int studentId,
    required List<Question> questions, // Pass full objects for metadata
    required String teacherUid,
    required String targetAudience,
    String assignmentTitle = "Teacher Assignment",
    bool onlySingleAttempt = false,
  }) async {
    final studentUid = await _findUidByStudentId(studentId);
    if (studentUid == null) throw Exception("Student not found");

    final newAssignmentRef = _firestore.collection('questions_curation').doc();
    final trackerRef = _firestore.collection('student_question_tracker').doc(studentUid);
    final batch = _firestore.batch();

    // 1. Generate Metadata
    final assignmentCode = _generateAssignmentCode();
    final questionIds = questions.map((q) => q.id).toList();

    // Note: Assuming Question model implicitly has a subject via source or chapter,
    // otherwise we rely on what's available. We will aggregate subjects here.
    // Ideally add 'subjectId' to Question model if needed explicitly.
    // For now we will try to infer or group based on existing data.
    final subjects = questions.map((q) => q.chapterId.split('_').first).toSet().toList(); // Basic inference if subjectId missing

    final hierarchy = _buildHierarchy(questions);

    // 2. Create Assignment Document
    batch.set(newAssignmentRef, {
      'assignmentId': newAssignmentRef.id,
      'assignmentCode': assignmentCode, // Unique 4-digit code
      'targetAudience': targetAudience,
      'studentUid': studentUid,
      'teacherUid': teacherUid,
      'title': assignmentTitle,
      'questionIds': questionIds,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'assigned',
      'onlySingleAttempt': onlySingleAttempt,
      'subjects': subjects, // List of subjects involved
      'meta_hierarchy': hierarchy, // Detailed breakdown
    });

    // 3. Update Student Tracker
    batch.update(trackerRef, {
      'assigned_history': FieldValue.arrayUnion(questionIds),
      'buckets.unattempted': FieldValue.arrayUnion(questionIds),
    });

    await batch.commit();
  }

  // --- NEW HELPERS ---

  String _generateAssignmentCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Map<String, dynamic> _buildHierarchy(List<Question> questions) {
    // Structure: Exam -> Subject -> Chapter -> Topic -> Count
    Map<String, dynamic> hierarchy = {};

    for (var q in questions) {
      final exam = q.source.isEmpty ? 'Unknown Exam' : q.source;
      // If subjectId is missing in Question model, use placeholder or extract from chapter
      final subject = 'Physics'; // Hardcoded based on context, or q.subjectId if added
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