// lib/models/test_model.dart
// Description: Model representing a Test/Exam. Updated to include 'markingSchemes'.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/marking_configuration.dart'; // [IMPORT ADDED]

class TestConfig {
  final int durationSeconds;
  final int totalQuestions;

  TestConfig({required this.durationSeconds, required this.totalQuestions});

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
  final String? shareCode;
  final List<String> uidsAttemptedTests;

  // NEW FIELD: Maps QuestionType to its specific Marking Rules
  final Map<QuestionType, MarkingConfiguration> markingSchemes;

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
    required this.markingSchemes,
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

    // --- PARSE MARKING SCHEMES ---
    Map<QuestionType, MarkingConfiguration> parsedSchemes = {};

    if (data['markingSchemes'] != null && data['markingSchemes'] is Map) {
      (data['markingSchemes'] as Map).forEach((key, value) {
        QuestionType type = _mapStringToType(key.toString());
        if (type != QuestionType.unknown) {
          parsedSchemes[type] = MarkingConfiguration.fromMap(Map<String, dynamic>.from(value));
        }
      });
    } else {
      // FALLBACK DEFAULTS
      parsedSchemes[QuestionType.singleCorrect] = MarkingConfiguration.jeeMain();
      parsedSchemes[QuestionType.numerical] = const MarkingConfiguration(correctScore: 4, incorrectScore: 0);
      parsedSchemes[QuestionType.oneOrMoreOptionsCorrect] = MarkingConfiguration.jeeAdvanced();
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
      markingSchemes: parsedSchemes,
    );
  }

  Map<String, dynamic> toFirestore() {
    Map<String, dynamic> schemesMap = {};
    markingSchemes.forEach((key, value) {
      schemesMap[_mapTypeToString(key)] = value.toMap();
    });

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
      'markingSchemes': schemesMap,
    };
  }

  static QuestionType _mapStringToType(String typeString) {
    switch (typeString) {
      case 'Single Correct': return QuestionType.singleCorrect;
      case 'Numerical type': return QuestionType.numerical;
      case 'One or more options correct': return QuestionType.oneOrMoreOptionsCorrect;
      case 'Single Matrix Match': return QuestionType.matrixSingle;
      case 'Multi Matrix Match': return QuestionType.matrixMulti;
      default: return QuestionType.unknown;
    }
  }

  static String _mapTypeToString(QuestionType type) {
    switch (type) {
      case QuestionType.singleCorrect: return 'Single Correct';
      case QuestionType.numerical: return 'Numerical type';
      case QuestionType.oneOrMoreOptionsCorrect: return 'One or more options correct';
      case QuestionType.matrixSingle: return 'Single Matrix Match';
      case QuestionType.matrixMulti: return 'Multi Matrix Match';
      default: return 'Unknown';
    }
  }
}