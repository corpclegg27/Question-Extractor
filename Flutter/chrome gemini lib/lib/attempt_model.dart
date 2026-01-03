import 'package:cloud_firestore/cloud_firestore.dart';

// Represents the response for a single question within an attempt.
class ResponseObject {
  final String status; // e.g., 'CORRECT', 'INCORRECT', 'SKIPPED'
  final String? selectedOption;
  final String correctOption;
  final int timeSpent; // in seconds
  final int visitCount;
  final int q_no; // Added question number

  ResponseObject({
    required this.status,
    this.selectedOption,
    required this.correctOption,
    required this.timeSpent,
    required this.visitCount,
    required this.q_no,
  });

  factory ResponseObject.fromMap(Map<String, dynamic> map) {
    return ResponseObject(
      status: map['status'] ?? 'SKIPPED',
      selectedOption: map['selectedOption'],
      correctOption: map['correctOption'] ?? '',
      timeSpent: map['timeSpent'] ?? 0,
      visitCount: map['visitCount'] ?? 0,
      q_no: map['q_no'] ?? 0,
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
    };
  }
}

// Represents an attempt document in the 'attempts' collection.
class AttemptModel {
  final String id;
  final String testId;
  final String userId;
  final Timestamp startedAt;
  final Timestamp completedAt;
  final int score;
  final int timeTakenSeconds;
  final Map<String, ResponseObject> responses;

  AttemptModel({
    required this.id,
    required this.testId,
    required this.userId,
    required this.startedAt,
    required this.completedAt,
    required this.score,
    required this.timeTakenSeconds,
    required this.responses,
  });

  factory AttemptModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    dynamic rawStartedAt = data['startedAt'];
    Timestamp startedAtTimestamp = (rawStartedAt is String) ? Timestamp.fromDate(DateTime.parse(rawStartedAt)) : rawStartedAt ?? Timestamp.now();

    dynamic rawCompletedAt = data['completedAt'];
    Timestamp completedAtTimestamp = (rawCompletedAt is String) ? Timestamp.fromDate(DateTime.parse(rawCompletedAt)) : rawCompletedAt ?? Timestamp.now();

    Map<String, ResponseObject> parsedResponses = {};
    if (data['responses'] is Map) {
      (data['responses'] as Map).forEach((key, value) {
        if (value is Map) {
          parsedResponses[key] = ResponseObject.fromMap(value as Map<String, dynamic>);
        }
      });
    }

    return AttemptModel(
      id: doc.id,
      testId: data['testId'] ?? '',
      userId: data['userId'] ?? '',
      startedAt: startedAtTimestamp,
      completedAt: completedAtTimestamp,
      score: data['score'] ?? 0,
      timeTakenSeconds: data['timeTakenSeconds'] ?? 0,
      responses: parsedResponses,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'testId': testId,
      'userId': userId,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'score': score,
      'timeTakenSeconds': timeTakenSeconds,
      'responses': responses.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}
