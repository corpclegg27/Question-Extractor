//lib/models/attempt_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class AttemptModel {
  final String id;
  final String sourceId;
  final String assignmentCode;
  final String title;
  final String mode;
  final String userId;
  final Timestamp startedAt;
  final Timestamp completedAt;
  final bool onlySingleAttempt;

  // STATS
  final num score;
  final int totalQuestions;
  final int maxMarks;
  final int correctCount;
  final int incorrectCount;
  final int skippedCount;
  final int timeTakenSeconds;
  final int? timeLimitMinutes;

  // BREAKDOWNS
  final Map<String, int> smartTimeAnalysisCounts;
  final Map<String, int> secondsBreakdownHighLevel;
  final Map<String, int> secondsBreakdownSmartTimeAnalysis;
  final Map<String, ResponseObject> responses;

  AttemptModel({
    required this.id,
    required this.sourceId,
    required this.assignmentCode,
    required this.title,
    required this.mode,
    required this.userId,
    required this.startedAt,
    required this.completedAt,
    this.onlySingleAttempt = false,
    required this.score,
    required this.totalQuestions,
    required this.maxMarks,
    required this.correctCount,
    required this.incorrectCount,
    required this.skippedCount,
    required this.timeTakenSeconds,
    this.timeLimitMinutes,
    required this.smartTimeAnalysisCounts,
    required this.secondsBreakdownHighLevel,
    required this.secondsBreakdownSmartTimeAnalysis,
    required this.responses,
  });

  /// Factory to create AttemptModel from Firestore Document
  factory AttemptModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return AttemptModel(
      id: doc.id,
      sourceId: data['sourceId'] ?? '',
      assignmentCode: data['assignmentCode'] ?? '',
      title: data['title'] ?? '',
      mode: data['mode'] ?? 'Practice',
      userId: data['userId'] ?? '',
      startedAt: data['startedAt'] as Timestamp? ?? Timestamp.now(),
      completedAt: data['completedAt'] as Timestamp? ?? Timestamp.now(),
      onlySingleAttempt: data['onlySingleAttempt'] ?? false,
      score: data['score'] ?? 0,

      // === FIX: Read BOTH snake_case (Old) and camelCase (New) ===
      totalQuestions: (data['totalQuestions'] ?? data['total_questions'] ?? 0) as int,
      maxMarks: (data['maxMarks'] ?? data['max_marks'] ?? 0) as int,
      correctCount: (data['correctCount'] ?? data['correct_count'] ?? 0) as int,
      incorrectCount: (data['incorrectCount'] ?? data['incorrect_count'] ?? 0) as int,
      skippedCount: (data['skippedCount'] ?? data['skipped_count'] ?? 0) as int,

      timeTakenSeconds: (data['timeTakenSeconds'] ?? 0) as int,
      timeLimitMinutes: data['timeLimitMinutes'] as int?,

      smartTimeAnalysisCounts: Map<String, int>.from(data['smartTimeAnalysisCounts'] ?? {}),
      secondsBreakdownHighLevel: Map<String, int>.from(data['secondsBreakdownHighLevel'] ?? {}),
      secondsBreakdownSmartTimeAnalysis: Map<String, int>.from(data['secondsBreakdownSmartTimeAnalysis'] ?? {}),

      responses: (data['responses'] as Map<String, dynamic>? ?? {}).map(
            (key, value) => MapEntry(key, ResponseObject.fromMap(value)),
      ),
    );
  }

  /// Converts Model to Map for Firestore writing
  Map<String, dynamic> toFirestore() {
    return {
      'sourceId': sourceId,
      'assignmentCode': assignmentCode,
      'title': title,
      'mode': mode,
      'userId': userId,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'onlySingleAttempt': onlySingleAttempt,
      'score': score,

      // === FIX: Write CLEAN camelCase ===
      'totalQuestions': totalQuestions,
      'maxMarks': maxMarks,
      'correctCount': correctCount,
      'incorrectCount': incorrectCount,
      'skippedCount': skippedCount,

      'timeTakenSeconds': timeTakenSeconds,
      'timeLimitMinutes': timeLimitMinutes,
      'smartTimeAnalysisCounts': smartTimeAnalysisCounts,
      'secondsBreakdownHighLevel': secondsBreakdownHighLevel,
      'secondsBreakdownSmartTimeAnalysis': secondsBreakdownSmartTimeAnalysis,
      'responses': responses.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}

class ResponseObject {
  final String status;
  final String? selectedOption;
  final String correctOption;
  final int timeSpent;
  final int visitCount;
  final int q_no;
  final String exam;
  final String subject;
  final String chapter;
  final String topic;
  final String topicL2; // Added
  final String chapterId;
  final String topicId;
  final String topicL2Id;
  final String smartTimeAnalysis;
  final String? mistakeCategory;
  final String? mistakeNote;
  final String pyq;
  final String difficultyTag;

  ResponseObject({
    required this.status,
    this.selectedOption,
    required this.correctOption,
    required this.timeSpent,
    this.visitCount = 0,
    this.q_no = 0,
    this.exam = '',
    this.subject = '',
    this.chapter = '',
    this.topic = '',
    this.topicL2 = '', // Added
    this.chapterId = '',
    this.topicId = '',
    this.topicL2Id = '',
    this.smartTimeAnalysis = '',
    this.mistakeCategory,
    this.mistakeNote,
    this.pyq = '',
    this.difficultyTag = '',
  });

  // === NEW: ALIASES FOR LOCAL SESSION SERVICE ===
  factory ResponseObject.fromJson(Map<String, dynamic> json) => ResponseObject.fromMap(json);
  Map<String, dynamic> toJson() => toMap();
  // ==============================================

  ResponseObject copyWith({
    String? status,
    String? selectedOption,
    String? correctOption,
    int? timeSpent,
    int? visitCount,
    int? q_no,
    String? exam,
    String? subject,
    String? chapter,
    String? topic,
    String? topicL2,
    String? chapterId,
    String? topicId,
    String? topicL2Id,
    String? smartTimeAnalysis,
    String? mistakeCategory,
    String? mistakeNote,
    String? pyq,
    String? difficultyTag,
  }) {
    return ResponseObject(
      status: status ?? this.status,
      selectedOption: selectedOption ?? this.selectedOption,
      correctOption: correctOption ?? this.correctOption,
      timeSpent: timeSpent ?? this.timeSpent,
      visitCount: visitCount ?? this.visitCount,
      q_no: q_no ?? this.q_no,
      exam: exam ?? this.exam,
      subject: subject ?? this.subject,
      chapter: chapter ?? this.chapter,
      topic: topic ?? this.topic,
      topicL2: topicL2 ?? this.topicL2,
      chapterId: chapterId ?? this.chapterId,
      topicId: topicId ?? this.topicId,
      topicL2Id: topicL2Id ?? this.topicL2Id,
      smartTimeAnalysis: smartTimeAnalysis ?? this.smartTimeAnalysis,
      mistakeCategory: mistakeCategory ?? this.mistakeCategory,
      mistakeNote: mistakeNote ?? this.mistakeNote,
      pyq: pyq ?? this.pyq,
      difficultyTag: difficultyTag ?? this.difficultyTag,
    );
  }

  factory ResponseObject.fromMap(Map<String, dynamic> map) {
    return ResponseObject(
      status: map['status'] ?? 'SKIPPED',
      selectedOption: map['selectedOption'],
      correctOption: map['correctOption'] ?? '',
      timeSpent: (map['timeSpent'] ?? 0) as int,
      visitCount: (map['visitCount'] ?? 0) as int,
      q_no: (map['q_no'] ?? 0) as int,
      exam: map['exam'] ?? '',
      subject: map['subject'] ?? '',
      chapter: map['chapter'] ?? '',
      topic: map['topic'] ?? '',
      topicL2: map['topicL2'] ?? '', // Added
      chapterId: map['chapterId'] ?? '',
      topicId: map['topicId'] ?? '',
      topicL2Id: map['topicL2Id'] ?? '',
      smartTimeAnalysis: map['smartTimeAnalysis'] ?? '',
      mistakeCategory: map['mistakeCategory'],
      mistakeNote: map['mistakeNote'],
      pyq: map['pyq'] ?? '',
      difficultyTag: map['difficultyTag'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'selectedOption': selectedOption,
      'correctOption': correctOption,
      'timeSpent': timeSpent,
      'visitCount': visitCount,
      'q_no': q_no,
      'exam': exam,
      'subject': subject,
      'chapter': chapter,
      'topic': topic,
      'topicL2': topicL2, // Added
      'chapterId': chapterId,
      'topicId': topicId,
      'topicL2Id': topicL2Id,
      'smartTimeAnalysis': smartTimeAnalysis,
      'mistakeCategory': mistakeCategory,
      'mistakeNote': mistakeNote,
      'pyq': pyq,
      'difficultyTag': difficultyTag,
    };
  }
}