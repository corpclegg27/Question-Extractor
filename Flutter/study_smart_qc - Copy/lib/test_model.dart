import 'package:cloud_firestore/cloud_firestore.dart';

class TestConfig {
  final int durationSeconds;
  final int totalQuestions;

  TestConfig({
    required this.durationSeconds,
    required this.totalQuestions,
  });

  factory TestConfig.fromMap(Map<String, dynamic> map) {
    return TestConfig(
      durationSeconds: map['durationSeconds'] ?? 0,
      totalQuestions: map['totalQuestions'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'durationSeconds': durationSeconds,
      'totalQuestions': totalQuestions,
    };
  }
}

class TestModel {
  final String id;
  final String createdBy;
  final Timestamp createdAt;
  final String status;
  final String testName;
  final TestConfig config;
  final List<String> questionIds;
  final List<String> chapters;
  final String? shareCode; // New field
  final List<String> uidsAttemptedTests; // New field

  TestModel({
    required this.id,
    required this.createdBy,
    required this.createdAt,
    required this.status,
    required this.testName,
    required this.config,
    required this.questionIds,
    required this.chapters,
    this.shareCode,
    required this.uidsAttemptedTests,
  });

  factory TestModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    dynamic rawTimestamp = data['createdAt'];
    Timestamp createdAtTimestamp;
    if (rawTimestamp is String) {
      createdAtTimestamp = Timestamp.fromDate(DateTime.parse(rawTimestamp));
    } else if (rawTimestamp is Timestamp) {
      createdAtTimestamp = rawTimestamp;
    } else {
      createdAtTimestamp = Timestamp.now();
    }

    return TestModel(
      id: doc.id,
      createdBy: data['createdBy'] ?? '',
      createdAt: createdAtTimestamp,
      status: data['status'] ?? 'GENERATED',
      testName: data['testName'] ?? 'Unnamed Test',
      config: TestConfig.fromMap(data['config'] ?? {}),
      questionIds: List<String>.from(data['questionIds'] ?? []),
      chapters: List<String>.from(data['chapters'] ?? []),
      shareCode: data['shareCode'],
      uidsAttemptedTests: List<String>.from(data['uidsAttemptedTests'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'createdBy': createdBy,
      'createdAt': createdAt,
      'status': status,
      'testName': testName,
      'config': config.toMap(),
      'questionIds': questionIds,
      'chapters': chapters,
      'shareCode': shareCode,
      'uidsAttemptedTests': uidsAttemptedTests,
    };
  }
}
