// lib/models/attempt_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ResponseObject {
  // ... (No changes to ResponseObject needed, keeping it as is) ...
  final String status;
  final dynamic selectedOption;
  final String correctOption;
  final int timeSpent;
  final int visitCount;
  final int q_no;

  // Context Fields
  final String exam;
  final String subject;

  // Tags
  final String chapter;
  final String topic;
  final String topicL2;

  // IDs
  final String? chapterId;
  final String? topicId;
  final String? topicL2Id;

  // Smart Time Analysis Tag
  final String smartTimeAnalysis;

  final String pyq;
  final String difficultyTag;

  final String? mistakeCategory;
  final String? mistakeNote;

  ResponseObject({
    required this.status,
    this.selectedOption,
    required this.correctOption,
    required this.timeSpent,
    required this.visitCount,
    required this.q_no,
    required this.exam,
    required this.subject,
    this.chapter = '',
    this.topic = '',
    this.topicL2 = '',
    this.chapterId,
    this.topicId,
    this.topicL2Id,
    this.smartTimeAnalysis = '',
    this.pyq = '',
    this.difficultyTag = '',
    this.mistakeCategory,
    this.mistakeNote,
  });

  Map<String, dynamic> toJson() => toMap();
  factory ResponseObject.fromJson(Map<String, dynamic> json) =>
      ResponseObject.fromMap(json);

  factory ResponseObject.fromMap(Map<String, dynamic> map) {
    return ResponseObject(
      status: map['status'] ?? 'SKIPPED',
      selectedOption: map['selectedOption'],
      correctOption: map['correctOption'] ?? '',
      timeSpent: map['timeSpent'] ?? 0,
      visitCount: map['visitCount'] ?? 0,
      q_no: map['q_no'] ?? 0,
      exam: map['exam'] ?? '',
      subject: map['subject'] ?? 'Physics',
      chapter: map['chapter'] ?? '',
      topic: map['topic'] ?? '',
      topicL2: map['topicL2'] ?? '',
      chapterId: map['chapterId'] as String?,
      topicId: map['topicId'] as String?,
      topicL2Id: map['topicL2Id'] as String?,
      smartTimeAnalysis: map['smartTimeAnalysis'] ?? '',
      pyq: map['pyq'] ?? '',
      difficultyTag: map['difficultyTag'] ?? '',
      mistakeCategory: map['mistakeCategory'],
      mistakeNote: map['mistakeNote'],
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
      'topicL2': topicL2,
      'chapterId': chapterId,
      'topicId': topicId,
      'topicL2Id': topicL2Id,
      'smartTimeAnalysis': smartTimeAnalysis,
      'pyq': pyq,
      'difficultyTag': difficultyTag,
      'mistakeCategory': mistakeCategory,
      'mistakeNote': mistakeNote,
    };
  }
}

class AttemptModel {
  final String id;
  final String sourceId;
  final String assignmentCode;

  // Title
  final String title;

  // NEW FIELD: Only Single Attempt Flag
  final bool onlySingleAttempt;

  final String mode;
  final String userId;
  final Timestamp startedAt;
  final Timestamp completedAt;
  final num score;
  final int totalQuestions;
  final int maxMarks;

  final int correctCount;
  final int incorrectCount;
  final int skippedCount;

  final int timeTakenSeconds;

  final int? timeLimitMinutes;

  final Map<String, int> smartTimeAnalysisCounts;
  final Map<String, int> secondsBreakdownHighLevel;
  final Map<String, int> secondsBreakdownSmartTimeAnalysis;

  final Map<String, ResponseObject> responses;

  AttemptModel({
    required this.id,
    required this.sourceId,
    required this.assignmentCode,
    this.title = 'Test Attempt',

    // Initialize new field (Defaulting to false ensures backward compatibility)
    this.onlySingleAttempt = false,

    required this.mode,
    required this.userId,
    required this.startedAt,
    required this.completedAt,
    required this.score,
    required this.totalQuestions,
    required this.maxMarks,
    required this.correctCount,
    required this.incorrectCount,
    required this.skippedCount,
    required this.timeTakenSeconds,
    this.timeLimitMinutes,
    required this.smartTimeAnalysisCounts,
    required this.responses,
    this.secondsBreakdownHighLevel = const {},
    this.secondsBreakdownSmartTimeAnalysis = const {},
  });

  factory AttemptModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    dynamic rawStartedAt = data['startedAt'];
    Timestamp startedAtTimestamp = (rawStartedAt is String)
        ? Timestamp.fromDate(DateTime.parse(rawStartedAt))
        : rawStartedAt ?? Timestamp.now();

    dynamic rawCompletedAt = data['completedAt'];
    Timestamp completedAtTimestamp = (rawCompletedAt is String)
        ? Timestamp.fromDate(DateTime.parse(rawCompletedAt))
        : rawCompletedAt ?? Timestamp.now();

    Map<String, ResponseObject> parsedResponses = {};
    if (data['responses'] is Map) {
      (data['responses'] as Map).forEach((key, value) {
        if (value is Map) {
          parsedResponses[key] = ResponseObject.fromMap(
            value as Map<String, dynamic>,
          );
        }
      });
    }

    Map<String, int> parseIntMap(dynamic mapData) {
      Map<String, int> result = {};
      if (mapData is Map) {
        mapData.forEach((key, value) {
          result[key.toString()] = (value as num).toInt();
        });
      }
      return result;
    }

    return AttemptModel(
      id: doc.id,
      sourceId: data['sourceId'] ?? data['testId'] ?? '',
      assignmentCode: data['assignmentCode'] ?? '----',
      title: data['title'] ?? 'Test Attempt',

      // READ NEW FIELD
      onlySingleAttempt: data['onlySingleAttempt'] ?? false,

      mode: data['mode'] ?? 'Test',
      userId: data['userId'] ?? '',
      startedAt: startedAtTimestamp,
      completedAt: completedAtTimestamp,
      score: data['score'] ?? 0,
      totalQuestions: data['total_questions'] ?? 0,
      maxMarks: data['max_marks'] ?? 0,
      correctCount: data['correct_count'] ?? 0,
      incorrectCount: data['incorrect_count'] ?? 0,
      skippedCount: data['skipped_count'] ?? 0,
      timeTakenSeconds: data['timeTakenSeconds'] ?? 0,
      timeLimitMinutes: data['timeLimitMinutes'],
      smartTimeAnalysisCounts: parseIntMap(data['smartTimeAnalysisCounts']),
      responses: parsedResponses,
      secondsBreakdownHighLevel: parseIntMap(data['secondsBreakdownHighLevel']),
      secondsBreakdownSmartTimeAnalysis: parseIntMap(
        data['secondsBreakdownSmartTimeAnalysis'],
      ),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sourceId': sourceId,
      'assignmentCode': assignmentCode,
      'title': title,

      // WRITE NEW FIELD
      'onlySingleAttempt': onlySingleAttempt,

      'mode': mode,
      'userId': userId,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'score': score,
      'total_questions': totalQuestions,
      'max_marks': maxMarks,
      'correct_count': correctCount,
      'incorrect_count': incorrectCount,
      'skipped_count': skippedCount,
      'timeTakenSeconds': timeTakenSeconds,
      'timeLimitMinutes': timeLimitMinutes,
      'smartTimeAnalysisCounts': smartTimeAnalysisCounts,
      'secondsBreakdownHighLevel': secondsBreakdownHighLevel,
      'secondsBreakdownSmartTimeAnalysis': secondsBreakdownSmartTimeAnalysis,
      'responses': responses.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}
