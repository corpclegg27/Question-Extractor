import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:study_smart_qc/attempt_item_model.dart';
import 'package:study_smart_qc/question_model.dart';
import 'package:study_smart_qc/test_model.dart';
import 'package:study_smart_qc/attempt_model.dart';

class TestOrchestrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  String _generateShareCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
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
      final existing = await _firestore.collection('tests').where('shareCode', isEqualTo: shareCode).limit(1).get();
      if (existing.docs.isEmpty) {
        isUnique = true;
      }
    } while (!isUnique);

    final testRef = _firestore.collection('tests').doc();

    final newTest = TestModel(
      id: testRef.id,
      createdBy: _userId!,
      createdAt: Timestamp.now(),
      status: 'Not Attempted',
      testName: testName,
      config: TestConfig(durationSeconds: durationSeconds, totalQuestions: questions.length),
      questionIds: questions.map((q) => q.id).toList(),
      chapters: chapterNames,
      shareCode: shareCode, 
      uidsAttemptedTests: [], 
    );

    await testRef.set(newTest.toFirestore());
    return newTest;
  }

  Future<void> saveTestAttempt({
    required String testId,
    required List<Question> questions,
    required int score,
    required int timeTakenSeconds,
    required Map<String, ResponseObject> responses,
  }) async {
    if (_userId == null) return;
    final batch = _firestore.batch();
    final attemptRef = _firestore.collection('attempts').doc();
    final newAttempt = AttemptModel(
      id: attemptRef.id,
      testId: testId,
      userId: _userId!,
      startedAt: Timestamp.now(),
      completedAt: Timestamp.now(),
      score: score,
      timeTakenSeconds: timeTakenSeconds,
      responses: responses,
    );
    batch.set(attemptRef, newAttempt.toFirestore());

    for (final question in questions) {
      final response = responses[question.id];
      if (response != null) {
        final attemptItemRef = _firestore.collection('attempt_items').doc('${_userId}_${question.id}');
        final attemptItem = AttemptItemModel(
          userId: _userId!,
          questionId: question.id,
          chapterId: question.chapterId,
          topicId: question.topicId,
          status: response.status,
          timeSpent: response.timeSpent,
          attemptedAt: Timestamp.now(),
        );
        batch.set(attemptItemRef, attemptItem.toFirestore());
      }
    }
    
    final testRef = _firestore.collection('tests').doc(testId);
    batch.update(testRef, {'status': 'Attempted'});

    await batch.commit();
  }

  Stream<List<TestModel>> getSavedTestsStream() {
    if (_userId == null) return Stream.value([]);
    return _firestore.collection('tests').where('createdBy', isEqualTo: _userId).orderBy('createdAt', descending: true).snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => TestModel.fromFirestore(doc)).toList(),
    );
  }

  Future<List<Question>> getQuestionsByIds(List<String> questionIds) async {
    if (questionIds.isEmpty) return [];
    final List<Question> questions = [];
    final chunks = [];
    for (var i = 0; i < questionIds.length; i += 10) {
      chunks.add(questionIds.sublist(i, i + 10 > questionIds.length ? questionIds.length : i + 10));
    }
    for (final chunk in chunks) {
      final querySnapshot = await _firestore.collection('questions').where(FieldPath.documentId, whereIn: chunk).get();
      questions.addAll(querySnapshot.docs.map((doc) => Question.fromFirestore(doc)));
    }
    return questions;
  }

  Future<TestModel?> getTestByShareCode(String shareCode) async {
    final querySnapshot = await _firestore.collection('tests').where('shareCode', isEqualTo: shareCode).limit(1).get();
    if (querySnapshot.docs.isNotEmpty) {
      return TestModel.fromFirestore(querySnapshot.docs.first);
    }
    return null;
  }

  Future<void> recordTestAttempt(String testId) async {
    if (_userId == null) return;
    final batch = _firestore.batch();

    final testRef = _firestore.collection('tests').doc(testId);
    batch.update(testRef, {
      'uidsAttemptedTests': FieldValue.arrayUnion([_userId])
    });

    final userRef = _firestore.collection('users').doc(_userId);
    batch.update(userRef, {
      'testIDsattempted': FieldValue.arrayUnion([testId])
    });

    await batch.commit();
  }

  // FIX: Added missing method
  Future<AttemptModel?> getAttemptForTest(String testId) async {
    if (_userId == null) return null;
    
    final querySnapshot = await _firestore
        .collection('attempts')
        .where('testId', isEqualTo: testId)
        .where('userId', isEqualTo: _userId)
        .limit(1)
        .get();
        
    if (querySnapshot.docs.isNotEmpty) {
      return AttemptModel.fromFirestore(querySnapshot.docs.first);
    }
    return null;
  }
}
