import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:study_smart_qc/models/attempt_item_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_model.dart';
import 'package:study_smart_qc/models/attempt_model.dart';

class TestOrchestrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? get _userId => _auth.currentUser?.uid;

  // ===========================================================================
  // 1. NEW UNIVERSAL SUBMISSION LOGIC (For Assignments & Practice)
  // ===========================================================================

  Future<void> submitAttempt({
    required String sourceId, // Doc ID (assignmentId or testId)
    required String assignmentCode, // Readable Code (e.g., A7X2)
    required String mode, // 'Test' or 'Practice'
    required List<Question> questions,
    required int score,
    required int timeTakenSeconds,
    required Map<String, ResponseObject> responses,
  }) async {
    if (_userId == null) return;

    final batch = _firestore.batch();
    final timestamp = Timestamp.now();

    // A. Create Attempt Record (The "Session" summary)
    final attemptRef = _firestore.collection('attempts').doc();
    final newAttempt = AttemptModel(
      id: attemptRef.id,
      sourceId: sourceId,
      assignmentCode: assignmentCode,
      mode: mode,
      userId: _userId!,
      startedAt: timestamp,
      completedAt: timestamp,
      score: score,
      timeTakenSeconds: timeTakenSeconds,
      responses: responses,
    );
    batch.set(attemptRef, newAttempt.toFirestore());

    // B. Create Attempt Items (Question-level history)
    for (final question in questions) {
      final response = responses[question.id];
      if (response != null) {
        final attemptItemRef = _firestore.collection('attempt_items').doc();
        final attemptItem = AttemptItemModel(
          userId: _userId!,
          questionId: question.id,
          chapterId: question.chapterId,
          topicId: question.topicId,
          status: response.status,
          timeSpent: response.timeSpent,
          attemptedAt: timestamp,
          assignmentCode: assignmentCode,
          mode: mode,
        );
        batch.set(attemptItemRef, attemptItem.toFirestore());
      }
    }

    // C. Update Student Tracker (The "Brain" - Latest Status Logic)
    final trackerRef = _firestore.collection('student_question_tracker').doc(_userId);
    final trackerDoc = await trackerRef.get();

    if (trackerDoc.exists) {
      final data = trackerDoc.data()!;
      final buckets = data['buckets'] as Map<String, dynamic>;

      // Load current sets
      List<String> unattempted = List<String>.from(buckets['unattempted'] ?? []);
      List<String> correct = List<String>.from(buckets['correct'] ?? []);
      List<String> incorrect = List<String>.from(buckets['incorrect'] ?? []);
      List<String> skipped = List<String>.from(buckets['skipped'] ?? []);
      List<String> history = List<String>.from(data['attempted_history'] ?? []);

      // Update buckets based on NEW responses
      responses.forEach((qid, response) {
        // Remove from ALL buckets first (Clean slate)
        unattempted.remove(qid);
        correct.remove(qid);
        incorrect.remove(qid);
        skipped.remove(qid);

        // Add to the NEW bucket
        if (response.status == 'CORRECT') correct.add(qid);
        else if (response.status == 'INCORRECT') incorrect.add(qid);
        else skipped.add(qid);

        // Add to history
        if (!history.contains(qid)) history.add(qid);
      });

      // Write back
      batch.update(trackerRef, {
        'buckets.unattempted': unattempted,
        'buckets.correct': correct,
        'buckets.incorrect': incorrect,
        'buckets.skipped': skipped,
        'attempted_history': history,
      });
    } else {
      // Fallback if tracker missing
      // (Simplified logic for fallback)
    }

    // D. If this was a Custom Test, update its status
    if (sourceId.isNotEmpty) {
      final testRef = _firestore.collection('tests').doc(sourceId);
      // We use a safe update; if it fails (because sourceId is an assignment, not a test), we catch it or ignore.
      // Since 'tests' and 'questions_curation' are different collections, this update is specific to the old "Custom Test" flow.
      // We can check if it exists or just try/catch.
      try {
        final testDoc = await testRef.get();
        if(testDoc.exists) {
          batch.update(testRef, {'status': 'Attempted'});
        }
      } catch (e) {
        // Ignore, likely not a custom test document
      }
    }

    await batch.commit();
  }

  // ===========================================================================
  // 2. RESTORED CUSTOM TEST METHODS (Required by other screens)
  // ===========================================================================

  String _generateShareCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  // Creates a "Blueprint" (Custom Test)
  Future<TestModel?> createAndSaveTestBlueprint({
    required List<Question> questions,
    required int durationSeconds,
    required List<String> chapterNames,
    required String testName,
  }) async {
    if (_userId == null) return null;

    String shareCode;
    bool isUnique = false;
    // Generate unique code
    do {
      shareCode = _generateShareCode();
      final existing = await _firestore
          .collection('tests')
          .where('shareCode', isEqualTo: shareCode)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) isUnique = true;
    } while (!isUnique);

    final testRef = _firestore.collection('tests').doc();

    final newTest = TestModel(
      id: testRef.id,
      createdBy: _userId!,
      createdAt: Timestamp.now(),
      status: 'Not Attempted',
      testName: testName,
      config: TestConfig(
        durationSeconds: durationSeconds,
        totalQuestions: questions.length,
      ),
      questionIds: questions.map((q) => q.id).toList(),
      chapters: chapterNames,
      shareCode: shareCode,
      uidsAttemptedTests: [],
    );

    await testRef.set(newTest.toFirestore());
    return newTest;
  }

  // Records that a user started/viewed a test
  Future<void> recordTestAttempt(String testId) async {
    if (_userId == null) return;
    final batch = _firestore.batch();

    final testRef = _firestore.collection('tests').doc(testId);
    batch.update(testRef, {
      'uidsAttemptedTests': FieldValue.arrayUnion([_userId]),
    });

    final userRef = _firestore.collection('users').doc(_userId);
    batch.update(userRef, {
      'testIDsattempted': FieldValue.arrayUnion([testId]),
    });

    await batch.commit();
  }

  // Retrieves the previous attempt for a specific test ID (used for "View Analysis")
  Future<AttemptModel?> getAttemptForTest(String testId) async {
    if (_userId == null) return null;

    // Note: We now use 'sourceId' in the new model, but old data might use 'testId'.
    // We check both or rely on the query matching the field in Firestore.
    // Ideally, ensure your AttemptModel writes to a consistent field.
    // For now, we query 'sourceId' as we updated the write logic to use 'sourceId'.
    // If you have old data, you might need an OR query or check 'testId' field.

    final querySnapshot = await _firestore
        .collection('attempts')
        .where('sourceId', isEqualTo: testId)
        .where('userId', isEqualTo: _userId)
        .orderBy('completedAt', descending: true)
        .limit(1)
        .get();

    if (querySnapshot.docs.isNotEmpty) {
      return AttemptModel.fromFirestore(querySnapshot.docs.first);
    }

    // Fallback for older data using 'testId'
    final oldQuerySnapshot = await _firestore
        .collection('attempts')
        .where('testId', isEqualTo: testId)
        .where('userId', isEqualTo: _userId)
        .limit(1)
        .get();

    if (oldQuerySnapshot.docs.isNotEmpty) {
      return AttemptModel.fromFirestore(oldQuerySnapshot.docs.first);
    }

    return null;
  }

  // Get Saved Tests List
  Stream<List<TestModel>> getSavedTestsStream() {
    if (_userId == null) return Stream.value([]);
    return _firestore
        .collection('tests')
        .where('createdBy', isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => TestModel.fromFirestore(doc)).toList());
  }

  // Helper to fetch Test by Share Code
  Future<TestModel?> getTestByShareCode(String shareCode) async {
    final querySnapshot = await _firestore
        .collection('tests')
        .where('shareCode', isEqualTo: shareCode)
        .limit(1)
        .get();
    if (querySnapshot.docs.isNotEmpty) {
      return TestModel.fromFirestore(querySnapshot.docs.first);
    }
    return null;
  }

  // Helper: Fetch Questions
  Future<List<Question>> getQuestionsByIds(List<String> questionIds) async {
    if (questionIds.isEmpty) return [];
    final List<Question> questions = [];
    final chunks = [];
    for (var i = 0; i < questionIds.length; i += 10) {
      chunks.add(
        questionIds.sublist(
          i,
          i + 10 > questionIds.length ? questionIds.length : i + 10,
        ),
      );
    }
    for (final chunk in chunks) {
      final querySnapshot = await _firestore
          .collection('questions')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      questions.addAll(
        querySnapshot.docs.map((doc) => Question.fromFirestore(doc)),
      );
    }
    return questions;
  }
}