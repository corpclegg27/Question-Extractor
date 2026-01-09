// lib/models/user_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class UserStats {
  final int testsTaken;
  final int questionsSolved;
  final double averageAccuracy;

  UserStats({
    this.testsTaken = 0,
    this.questionsSolved = 0,
    this.averageAccuracy = 0.0,
  });

  factory UserStats.fromMap(Map<String, dynamic> map) {
    return UserStats(
      testsTaken: map['testsTaken'] ?? 0,
      questionsSolved: map['questionsSolved'] ?? 0,
      averageAccuracy: (map['averageAccuracy'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'testsTaken': testsTaken,
      'questionsSolved': questionsSolved,
      'averageAccuracy': averageAccuracy,
    };
  }
}

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final UserStats stats;
  final List<String> testIDsattempted;
  final Timestamp createdAt;

  // --- NEW FIELD FOR TRACKING SUBMISSIONS ---
  final List<String> assignmentCodesSubmitted;

  // --- NEW ONBOARDING FIELDS ---
  final String role; // 'student' or 'teacher'
  final bool onboardingCompleted;

  // Student Specific
  final int? studentId;
  final String? targetExam;
  final String? currentClass;
  final int? targetYear;

  // Teacher Specific
  final List<String>? teachingExams;
  final List<String>? teachingSubjects;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.stats,
    required this.testIDsattempted,
    required this.createdAt,
    this.assignmentCodesSubmitted = const [], // Default empty
    this.role = 'student',
    this.onboardingCompleted = false,
    this.studentId,
    this.targetExam,
    this.currentClass,
    this.targetYear,
    this.teachingExams,
    this.teachingSubjects,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      stats: UserStats.fromMap(data['stats'] ?? {}),
      testIDsattempted: List<String>.from(data['testIDsattempted'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(),

      // Map New Submission Tracking Field
      assignmentCodesSubmitted: List<String>.from(
        data['assignmentCodesSubmitted'] ?? [],
      ),

      // Map Onboarding Fields
      role: data['role'] ?? 'student',
      onboardingCompleted: data['onboardingCompleted'] ?? false,
      studentId: data['studentId'],
      targetExam: data['targetExam'],
      currentClass: data['currentClass'],
      targetYear: data['targetYear'],
      teachingExams: data['teachingExams'] != null
          ? List<String>.from(data['teachingExams'])
          : null,
      teachingSubjects: data['teachingSubjects'] != null
          ? List<String>.from(data['teachingSubjects'])
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'stats': stats.toMap(),
      'testIDsattempted': testIDsattempted,
      'createdAt': createdAt,

      // Save New Submission Tracking Field
      'assignmentCodesSubmitted': assignmentCodesSubmitted,

      // Save Onboarding Fields
      'role': role,
      'onboardingCompleted': onboardingCompleted,
      'studentId': studentId,
      'targetExam': targetExam,
      'currentClass': currentClass,
      'targetYear': targetYear,
      'teachingExams': teachingExams,
      'teachingSubjects': teachingSubjects,
    };
  }
}
