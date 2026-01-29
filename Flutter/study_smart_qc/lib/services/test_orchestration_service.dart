// lib/services/test_orchestration_service.dart
// Description: Manages test submission.
// UPDATED: Fixed 'getQuestionsByIds' to support both Document IDs (for Results) and Custom IDs (for Assignments).

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:study_smart_qc/models/attempt_item_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_model.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/marking_configuration.dart';

class TestOrchestrationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? get _userId => _auth.currentUser?.uid;

  // ===========================================================================
  // 1. HISTORY FETCH LOGIC
  // ===========================================================================

  Future<List<AttemptModel>> getUserAttempts({String? targetUserId}) async {
    final String? idToQuery = targetUserId ?? _userId;
    if (idToQuery == null) return [];
    try {
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
  // 2. UNIVERSAL SUBMISSION LOGIC
  // ===========================================================================

  Future<AttemptModel?> submitAttempt({
    required String sourceId,
    required String assignmentCode,
    required String title,
    required bool onlySingleAttempt,
    required String mode,
    required List<Question> questions,
    required num score,
    required int timeTakenSeconds,
    required Map<String, ResponseObject> responses,
    int? timeLimitMinutes,

    // Required Analytics Fields
    required Map<String, dynamic> markingSchemes,
    required Map<String, dynamic> marksBreakdown,
  }) async {
    if (_userId == null) return null;

    // --- STEP 1: FETCH CONFIG & AUTHORITATIVE TITLE ---
    Map<String, dynamic> idealTimeMap = {};
    double carelessFactor = 0.25;
    double goodSkipFactorRaw = 20.0;

    String finalTitle = title;
    bool isCurationDocument = false;

    try {
      // 1. Fetch Config
      final configSnap = await _firestore.collection('static_data').doc('option_sets').get();
      if (configSnap.exists) {
        final data = configSnap.data()!;
        if (data['idealTimePerQuestion'] != null) {
          idealTimeMap = Map<String, dynamic>.from(data['idealTimePerQuestion']);
        }
        carelessFactor = (data['factorForCarelessAttempt'] ?? 0.25).toDouble();
        goodSkipFactorRaw = (data['factorForGoodSkip'] ?? 20.0).toDouble();
      }

      // 2. Fetch Authoritative Title & Determine Type
      if (sourceId.isNotEmpty) {
        final curationDoc = await _firestore.collection('questions_curation').doc(sourceId).get();
        if (curationDoc.exists) {
          isCurationDocument = true;
          if (curationDoc.data()?['title'] != null) {
            finalTitle = curationDoc.data()!['title'];
          }
        } else {
          final testDoc = await _firestore.collection('tests').doc(sourceId).get();
          if (testDoc.exists && testDoc.data()?['testName'] != null) {
            finalTitle = testDoc.data()!['testName'];
          }
        }
      }
    } catch (e) {
      print("Error fetching analysis config or title: $e");
    }

    final batch = _firestore.batch();
    final timestamp = Timestamp.now();

    // --- PHASE 2: Enrich Responses & Calculate Tags ---
    Map<String, ResponseObject> enrichedResponses = {};

    Map<String, int> analysisCounts = {
      "Perfect Attempt": 0, "Overtime Correct": 0, "Careless Mistake": 0,
      "Wasted Attempt": 0, "Good Skip": 0, "Time Wasted": 0
    };

    Map<String, int> highLevelTime = {
      "CORRECT": 0, "INCORRECT": 0, "SKIPPED": 0, "PARTIALLY_CORRECT": 0
    };

    Map<String, int> smartTimeBreakdown = {
      "Perfect Attempt": 0, "Overtime Correct": 0, "Careless Mistake": 0,
      "Wasted Attempt": 0, "Good Skip": 0, "Time Wasted": 0
    };

    int correctCount = 0;
    int incorrectCount = 0;
    int skippedCount = 0;

    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final userResponse = responses[question.id];

      String status = userResponse?.status ?? QuestionStatus.skipped;
      if (status.contains('REVIEW')) status = QuestionStatus.skipped;

      final int timeSpent = userResponse?.timeSpent ?? 0;

      if (status == QuestionStatus.correct || status == QuestionStatus.partiallyCorrect) {
        correctCount++;
      } else if (status == QuestionStatus.incorrect) {
        incorrectCount++;
      } else {
        skippedCount++;
      }

      highLevelTime[status] = (highLevelTime[status] ?? 0) + timeSpent;

      String smartTag = _generateSmartTag(
        status: status,
        timeTaken: timeSpent,
        examName: question.exam,
        subject: question.subject,
        questionType: question.type,
        idealTimeMap: idealTimeMap,
        carelessFactor: carelessFactor,
        goodSkipFactorRaw: goodSkipFactorRaw,
      );

      if (smartTag.isNotEmpty) {
        String shortKey = smartTag.split(' (').first.trim();
        analysisCounts[shortKey] = (analysisCounts[shortKey] ?? 0) + 1;
        smartTimeBreakdown[shortKey] = (smartTimeBreakdown[shortKey] ?? 0) + timeSpent;
      }

      final enrichedResponse = ResponseObject(
        status: status,
        selectedOption: userResponse?.selectedOption,
        correctOption: userResponse?.correctOption ?? question.correctAnswer.toString(),
        timeSpent: timeSpent,
        visitCount: userResponse?.visitCount ?? 0,
        q_no: userResponse?.q_no ?? (i + 1),
        exam: question.exam,
        subject: question.subject,
        chapter: question.chapter,
        topic: question.topic,
        topicL2: question.topicL2,
        chapterId: question.chapterId,
        topicId: question.topicId,
        topicL2Id: question.topicL2Id,
        smartTimeAnalysis: smartTag,
        mistakeCategory: userResponse?.mistakeCategory,
        mistakeNote: userResponse?.mistakeNote,
        pyq: question.isPyq ? 'Yes' : 'No',
        difficultyTag: question.difficulty,
        questionType: userResponse?.questionType ?? '',
        marksObtained: userResponse?.marksObtained ?? 0,
        imageUrl: question.imageUrl,
        solutionUrl: question.solutionUrl,
        aiGenSolutionText: question.aiGenSolutionText,
      );
      enrichedResponses[question.id] = enrichedResponse;
    }

    // --- PHASE 3: Create Records ---
    int finalMaxMarks = questions.length * 4;
    if (marksBreakdown.containsKey("Overall") && marksBreakdown["Overall"]["maxMarks"] != null) {
      finalMaxMarks = (marksBreakdown["Overall"]["maxMarks"] as num).toInt();
    }

    final attemptRef = _firestore.collection('attempts').doc();
    final newAttempt = AttemptModel(
      id: attemptRef.id,
      sourceId: sourceId,
      assignmentCode: assignmentCode,
      title: finalTitle,
      onlySingleAttempt: onlySingleAttempt,
      mode: mode,
      userId: _userId!,
      startedAt: timestamp,
      completedAt: timestamp,
      score: score,
      totalQuestions: questions.length,
      maxMarks: finalMaxMarks,
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      skippedCount: skippedCount,
      timeTakenSeconds: timeTakenSeconds,
      timeLimitMinutes: timeLimitMinutes,
      smartTimeAnalysisCounts: analysisCounts,
      secondsBreakdownHighLevel: highLevelTime,
      secondsBreakdownSmartTimeAnalysis: smartTimeBreakdown,
      responses: enrichedResponses,
      markingSchemes: markingSchemes,
      marksBreakdown: marksBreakdown,
    );
    batch.set(attemptRef, newAttempt.toFirestore());

    for (final question in questions) {
      final response = enrichedResponses[question.id];
      if (response != null) {
        final attemptItemRef = _firestore.collection('attempt_items').doc();
        batch.set(attemptItemRef, AttemptItemModel(
          userId: _userId!,
          attemptRef: attemptRef,
          questionId: question.id,
          chapterId: question.chapterId,
          topicId: question.topicId,
          status: response.status,
          timeSpent: response.timeSpent,
          attemptedAt: timestamp,
          assignmentCode: assignmentCode,
          mode: mode,
          mistakeCategory: response.mistakeCategory,
          mistakeNote: response.mistakeNote,
        ).toFirestore());
      }
    }

    // --- PHASE 4: Update Tracker & Source Document ---
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

      enrichedResponses.forEach((qid, response) {
        unattempted.remove(qid);
        correct.remove(qid);
        incorrect.remove(qid);
        skipped.remove(qid);

        if (response.status == QuestionStatus.correct || response.status == QuestionStatus.partiallyCorrect) {
          correct.add(qid);
        } else if (response.status == QuestionStatus.incorrect) {
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

    if (sourceId.isNotEmpty) {
      try {
        if (isCurationDocument) {
          final assignmentRef = _firestore.collection('questions_curation').doc(sourceId);
          Map<String, dynamic> updates = {
            'attemptDocRefs': FieldValue.arrayUnion([attemptRef]),
          };
          if (onlySingleAttempt) {
            updates['status'] = 'submitted';
          }
          batch.update(assignmentRef, updates);
        } else {
          final testRef = _firestore.collection('tests').doc(sourceId);
          final testDoc = await testRef.get();
          if (testDoc.exists) {
            batch.update(testRef, {'status': 'Attempted'});
          }
        }
      } catch (e) {
        print("Error updating status/refs: $e");
      }
    }

    if (assignmentCode.isNotEmpty && assignmentCode != 'PRAC') {
      final userRef = _firestore.collection('users').doc(_userId);
      batch.update(userRef, {
        'assignmentCodesSubmitted': FieldValue.arrayUnion([assignmentCode])
      });
    }

    await batch.commit();
    return newAttempt;
  }

  // ===========================================================================
  // 3. HYBRID QUESTION FETCHING (FIXED)
  // ===========================================================================

  Future<List<Question>> getQuestionsByIds(List<String> questionIds) async {
    if (questionIds.isEmpty) return [];

    // Filter empty IDs
    final uniqueIds = questionIds.where((id) => id.isNotEmpty).toSet().toList();
    final List<Question> fetchedQuestions = [];

    // Process in chunks of 10
    for (var i = 0; i < uniqueIds.length; i += 10) {
      final chunk = uniqueIds.sublist(i, min(i + 10, uniqueIds.length));

      try {
        // [FIX] Strategy 1: Fetch by Firestore Document ID (Attempt Keys)
        var snapshot = await _firestore
            .collection('questions')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        // [FIX] Strategy 2: If no results, fetch by Custom 'question_id' string (Assignment Legacy)
        if (snapshot.docs.isEmpty) {
          snapshot = await _firestore
              .collection('questions')
              .where('question_id', whereIn: chunk)
              .get();
        }

        // [FIX] Strategy 3: If still no results, try Custom 'question_id' as Integer
        if (snapshot.docs.isEmpty) {
          final intChunk = chunk.map((e) => int.tryParse(e)).whereType<int>().toList();
          if (intChunk.isNotEmpty) {
            snapshot = await _firestore
                .collection('questions')
                .where('question_id', whereIn: intChunk)
                .get();
          }
        }

        fetchedQuestions.addAll(snapshot.docs.map((doc) => Question.fromFirestore(doc)));
      } catch (e) {
        print("Error fetching chunk: $e");
      }
    }

    // Re-order results to match input order
    List<Question> orderedResult = [];
    for (String requestedId in questionIds) {
      try {
        final match = fetchedQuestions.firstWhere((q) {
          if (q.id == requestedId) return true; // Matches Doc ID
          if (q.customId == requestedId) return true; // Matches Custom ID
          if (q.questionNo.toString() == requestedId) return true;
          return false;
        });
        orderedResult.add(match);
      } catch (e) {
        // ID not found in fetched results
      }
    }

    if (orderedResult.isEmpty && fetchedQuestions.isNotEmpty) return fetchedQuestions;
    return orderedResult;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _generateSmartTag({
    required String status,
    required int timeTaken,
    required String examName,
    required String subject,
    required QuestionType questionType,
    required Map<String, dynamic> idealTimeMap,
    required double carelessFactor,
    required double goodSkipFactorRaw,
  }) {
    String eName = examName.isEmpty ? "JEE Main" : examName;
    String sName = subject.isEmpty ? "Physics" : subject;

    String eNameNorm = eName.replaceAll(' ', '_');
    String sNameNorm = sName.replaceAll(' ', '_');

    String typeStr = _mapTypeToConfigString(questionType);
    String granularKey = "${eNameNorm}_${sNameNorm}_$typeStr";
    String fallbackKey1 = "${eNameNorm}_$sNameNorm";
    String fallbackKey2 = "${eName}_$sName";

    int idealTime = 120; // Default

    if (_hasTime(idealTimeMap, granularKey)) {
      idealTime = _parseIdealTime(idealTimeMap[granularKey]);
    } else if (_hasTime(idealTimeMap, fallbackKey1)) {
      idealTime = _parseIdealTime(idealTimeMap[fallbackKey1]);
    } else if (_hasTime(idealTimeMap, fallbackKey2)) {
      idealTime = _parseIdealTime(idealTimeMap[fallbackKey2]);
    }

    double fastThreshold = idealTime * carelessFactor;
    double skipFactor = (goodSkipFactorRaw > 1) ? goodSkipFactorRaw / 100 : goodSkipFactorRaw;
    double goodSkipThreshold = idealTime * skipFactor;

    if (status == QuestionStatus.correct) {
      return (timeTaken <= idealTime)
          ? "Perfect Attempt (Correct & answered within reasonable time)"
          : "Overtime Correct (Correct but took too long)";

    } else if (status == QuestionStatus.incorrect || status == QuestionStatus.partiallyCorrect) {
      return (timeTaken < fastThreshold)
          ? "Careless Mistake (Incorrect & answered too fast)"
          : "Wasted Attempt (Incorrect & took too long)";

    } else {
      return (timeTaken < goodSkipThreshold)
          ? "Good Skip (Skipped quickly)"
          : "Time Wasted (Skipped but spent too much time)";
    }
  }

  bool _hasTime(Map<String, dynamic> map, String key) {
    return map.containsKey(key) && map[key] != null;
  }

  int _parseIdealTime(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 120;
    return 120;
  }

  String _mapTypeToConfigString(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return 'Single_Correct';
      case QuestionType.numerical: return 'NumericalType';
      case QuestionType.oneOrMoreOptionsCorrect: return 'OneOrMoreOptionsCorrect';
      default: return 'Default';
    }
  }

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
      if (existing.docs.isEmpty) isUnique = true;
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
      markingSchemes: {
        QuestionType.singleCorrect: MarkingConfiguration.jeeMain(),
        QuestionType.numerical: const MarkingConfiguration(correctScore: 4, incorrectScore: 0),
        QuestionType.oneOrMoreOptionsCorrect: MarkingConfiguration.jeeAdvanced(),
      },
    );
    await testRef.set(newTest.toFirestore());
    return newTest;
  }

  Future<void> recordTestAttempt(String testId) async {
    if (_userId == null) return;
    final batch = _firestore.batch();
    batch.update(_firestore.collection('tests').doc(testId), {'uidsAttemptedTests': FieldValue.arrayUnion([_userId])});
    batch.update(_firestore.collection('users').doc(_userId), {'testIDsattempted': FieldValue.arrayUnion([testId])});
    await batch.commit();
  }

  Future<AttemptModel?> getAttemptForTest(String testId) async {
    if (_userId == null) return null;
    final querySnapshot = await _firestore.collection('attempts').where('sourceId', isEqualTo: testId).where('userId', isEqualTo: _userId).orderBy('completedAt', descending: true).limit(1).get();
    if (querySnapshot.docs.isNotEmpty) return AttemptModel.fromFirestore(querySnapshot.docs.first);
    final oldQuerySnapshot = await _firestore.collection('attempts').where('testId', isEqualTo: testId).where('userId', isEqualTo: _userId).limit(1).get();
    if (oldQuerySnapshot.docs.isNotEmpty) return AttemptModel.fromFirestore(oldQuerySnapshot.docs.first);
    return null;
  }

  Stream<List<TestModel>> getSavedTestsStream() {
    if (_userId == null) return Stream.value([]);
    return _firestore.collection('tests').where('createdBy', isEqualTo: _userId).orderBy('createdAt', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => TestModel.fromFirestore(doc)).toList());
  }

  Future<TestModel?> getTestByShareCode(String shareCode) async {
    final querySnapshot = await _firestore.collection('tests').where('shareCode', isEqualTo: shareCode).limit(1).get();
    return querySnapshot.docs.isNotEmpty ? TestModel.fromFirestore(querySnapshot.docs.first) : null;
  }

  Future<void> updateQuestionMistake({
    required String attemptId,
    required String questionId,
    required String mistakeCategory,
    String? mistakeNote,
  }) async {
    if (_userId == null) return;
    try {
      final attemptRef = _firestore.collection('attempts').doc(attemptId);
      final attemptSnapshot = await attemptRef.get();
      if (!attemptSnapshot.exists) return;
      final data = attemptSnapshot.data();
      final String? assignmentCode = data?['assignmentCode'];

      await attemptRef.update({
        'responses.$questionId.mistakeCategory': mistakeCategory,
        'responses.$questionId.mistakeNote': mistakeNote ?? '',
      });
      if (assignmentCode != null) {
        final itemQuery = await _firestore.collection('attempt_items').where('userId', isEqualTo: _userId).where('questionId', isEqualTo: questionId).where('assignmentCode', isEqualTo: assignmentCode).limit(1).get();
        if (itemQuery.docs.isNotEmpty) {
          await itemQuery.docs.first.reference.update({'mistakeCategory': mistakeCategory, 'mistakeNote': mistakeNote ?? ''});
        }
      }
    } catch (e) {
      print("Error updating mistake category: $e");
      rethrow;
    }
  }
}