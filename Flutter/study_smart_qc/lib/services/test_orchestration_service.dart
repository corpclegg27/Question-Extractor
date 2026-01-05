// lib/services/test_orchestration_service.dart

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
  // 1. HISTORY FETCH LOGIC
  // ===========================================================================

  /// Fetch attempts for a user. If [targetUserId] is provided (Mentor Mode),
  /// it fetches for that specific student. Otherwise, it defaults to the current user.
  Future<List<AttemptModel>> getUserAttempts({String? targetUserId}) async {
    final String? idToQuery = targetUserId ?? _userId;
    if (idToQuery == null) return [];

    try {
      // NOTE: Requires a Composite Index for 'userId' (Asc) and 'completedAt' (Desc)
      final snapshot = await _firestore
          .collection('attempts')
          .where('userId', isEqualTo: idToQuery)
          .orderBy('completedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => AttemptModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print("Error fetching user attempts: $e");
      return [];
    }
  }

  // ===========================================================================
  // 2. UNIVERSAL SUBMISSION LOGIC (With Aggregates & Behavioral Fields)
  // ===========================================================================

  Future<void> submitAttempt({
    required String sourceId,
    required String assignmentCode,
    required String mode,
    required List<Question> questions,
    required num score,
    required int timeTakenSeconds,
    required Map<String, ResponseObject> responses,
  }) async {
    if (_userId == null) return;

    final batch = _firestore.batch();
    final timestamp = Timestamp.now();

    // 1. Calculate Aggregates
    int correctCount = 0;
    int incorrectCount = 0;
    int skippedCount = 0;

    responses.forEach((qid, response) {
      if (response.status == 'CORRECT') {
        correctCount++;
      } else if (response.status == 'INCORRECT') {
        incorrectCount++;
      } else {
        skippedCount++;
      }
    });

    final int totalQuestionsCount = questions.length;
    final int maxMarksValue = totalQuestionsCount * 4;

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
      totalQuestions: totalQuestionsCount,
      maxMarks: maxMarksValue,
      correctCount: correctCount,     // SAVED: New Aggregate
      incorrectCount: incorrectCount, // SAVED: New Aggregate
      skippedCount: skippedCount,     // SAVED: New Aggregate
      timeTakenSeconds: timeTakenSeconds,
      responses: responses,
    );
    batch.set(attemptRef, newAttempt.toFirestore());

    // B. Create Attempt Items (Question-level history)
    for (final question in questions) {
      final response = responses[question.id];
      if (response != null) {
        final attemptItemRef = _firestore.collection('attempt_items').doc(); //

        final attemptItem = AttemptItemModel(
          userId: _userId!,
          attemptRef: attemptRef, // Passing parent reference here
          questionId: question.id,
          chapterId: question.chapterId,
          topicId: question.topicId,
          status: response.status,
          timeSpent: response.timeSpent,
          attemptedAt: timestamp,
          assignmentCode: assignmentCode,
          mode: mode,
          // NEW: Support for manual categorization
          mistakeCategory: response.mistakeCategory,
          mistakeNote: response.mistakeNote,
        );

        batch.set(attemptItemRef, attemptItem.toFirestore()); //
      }
    }

    // C. Update Student Tracker (Latest Status Logic)
    final trackerRef = _firestore.collection('student_question_tracker').doc(_userId);
    final trackerDoc = await trackerRef.get();

    if (trackerDoc.exists) {
      final data = trackerDoc.data()!;
      final buckets = data['buckets'] as Map<String, dynamic>;

      List<String> unattempted = List<String>.from(buckets['unattempted'] ?? []);
      List<String> correct = List<String>.from(buckets['correct'] ?? []);
      List<String> incorrect = List<String>.from(buckets['incorrect'] ?? []);
      List<String> skipped = List<String>.from(buckets['skipped'] ?? []);
      List<String> history = List<String>.from(data['attempted_history'] ?? []);

      responses.forEach((qid, response) {
        unattempted.remove(qid);
        correct.remove(qid);
        incorrect.remove(qid);
        skipped.remove(qid);

        if (response.status == 'CORRECT') {
          correct.add(qid);
        } else if (response.status == 'INCORRECT') {
          incorrect.add(qid);
        } else {
          skipped.add(qid);
        }

        if (!history.contains(qid)) history.add(qid);
      });

      batch.update(trackerRef, {
        'buckets.unattempted': unattempted,
        'buckets.correct': correct,
        'buckets.incorrect': incorrect,
        'buckets.skipped': skipped,
        'attempted_history': history,
      });
    }

    // D. Update Assignment Status
    if (sourceId.isNotEmpty) {
      try {
        final assignmentRef = _firestore.collection('questions_curation').doc(sourceId);
        final assignmentDoc = await assignmentRef.get();

        if (assignmentDoc.exists) {
          final data = assignmentDoc.data();

          // 1. CHECK THE FLAG
          // If the field is missing (old data), assume false (allow retries)
          final bool isStrict = data?['onlySingleAttempt'] ?? false;

          // 2. DECIDE FATE
          if (isStrict) {
            // Strict Mode: Mark 'submitted'.
            batch.update(assignmentRef, {'status': 'submitted'});
          } else {
            // Practice Mode: Do NOT update status.
          }

        } else {
          // Fallback for legacy "Test" collection
          final testRef = _firestore.collection('tests').doc(sourceId);
          final testDoc = await testRef.get();
          if(testDoc.exists) {
            batch.update(testRef, {'status': 'Attempted'});
          }
        }
      } catch (e) {
        print("Error updating status: $e");
      }
    }

    await batch.commit();
  }

  // ===========================================================================
  // 3. CUSTOM TEST & HELPER METHODS
  // ===========================================================================

  String _generateShareCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }

  Future<TestModel?> createAndSaveTestBlueprint({
    required List<Question> questions,
    required int durationSeconds,
    required List<String> chapterNames,
    required String testName,
  }) async {
    if (_userId == null) return null;

    String shareCode;
    bool isUnique = false;
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

  Future<AttemptModel?> getAttemptForTest(String testId) async {
    if (_userId == null) return null;

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

  Stream<List<TestModel>> getSavedTestsStream() {
    if (_userId == null) return Stream.value([]);
    return _firestore
        .collection('tests')
        .where('createdBy', isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => TestModel.fromFirestore(doc)).toList());
  }

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

  // --- CRITICAL UPDATE: Sorts questions to match input order ---
  Future<List<Question>> getQuestionsByIds(List<String> questionIds) async {
    if (questionIds.isEmpty) return [];

    final List<Question> fetchedQuestions = [];
    final chunks = [];

    // Chunking to handle Firestore limit of 10 items per 'whereIn'
    for (var i = 0; i < questionIds.length; i += 10) {
      chunks.add(
        questionIds.sublist(
          i,
          i + 10 > questionIds.length ? questionIds.length : i + 10,
        ),
      );
    }

    // Fetch data (This comes back in RANDOM order from Firestore)
    for (final chunk in chunks) {
      final querySnapshot = await _firestore
          .collection('questions')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      fetchedQuestions.addAll(
        querySnapshot.docs.map((doc) => Question.fromFirestore(doc)),
      );
    }

    // CRITICAL FIX: Sort the fetched questions to match the 'questionIds' order
    final questionMap = {for (var q in fetchedQuestions) q.id: q};

    // Map original IDs to question objects, filtering out any that might have been deleted
    final List<Question> orderedQuestions = questionIds
        .map((id) => questionMap[id])
        .whereType<Question>() // Removes nulls if a question was not found
        .toList();

    return orderedQuestions;
  }

  // ===========================================================================
  // 4. MISTAKE UPDATE LOGIC (NEW)
  // ===========================================================================

  /// Updates the mistake category and note for a specific question in an existing attempt.
  /// This updates BOTH the main 'attempts' document (nested map) AND the individual 'attempt_items' document.
  Future<void> updateQuestionMistake({
    required String attemptId,
    required String questionId,
    required String mistakeCategory,
    String? mistakeNote,
  }) async {
    if (_userId == null) return;

    try {
      final attemptRef = _firestore.collection('attempts').doc(attemptId);

      // 1. Fetch the attempt to get context (assignmentCode) needed to find the item
      final attemptSnapshot = await attemptRef.get();
      if (!attemptSnapshot.exists) return;

      final data = attemptSnapshot.data();
      // Ensure we safeguard against nulls, though assignmentCode should exist
      final String? assignmentCode = data?['assignmentCode'];

      // 2. Update the parent Attempt document (Nested Map Update)
      // Note: We use dot notation to update just the specific fields inside the responses map
      await attemptRef.update({
        'responses.$questionId.mistakeCategory': mistakeCategory,
        'responses.$questionId.mistakeNote': mistakeNote ?? '',
      });

      // 3. Update the specific Attempt Item document
      // We use assignmentCode + questionId + userId to target the specific item
      if (assignmentCode != null) {
        final itemQuery = await _firestore
            .collection('attempt_items')
            .where('userId', isEqualTo: _userId)
            .where('questionId', isEqualTo: questionId)
            .where('assignmentCode', isEqualTo: assignmentCode)
            .limit(1)
            .get();

        if (itemQuery.docs.isNotEmpty) {
          await itemQuery.docs.first.reference.update({
            'mistakeCategory': mistakeCategory,
            'mistakeNote': mistakeNote ?? '',
          });
        }
      }
    } catch (e) {
      print("Error updating mistake category: $e");
      rethrow;
    }
  }
}