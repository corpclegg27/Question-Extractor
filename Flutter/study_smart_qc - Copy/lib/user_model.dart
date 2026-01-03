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
  final Timestamp createdAt; // New field

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.stats,
    required this.testIDsattempted,
    required this.createdAt, // Added to constructor
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      stats: UserStats.fromMap(data['stats'] ?? {}),
      testIDsattempted: List<String>.from(data['testIDsattempted'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(), // Read the timestamp
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'stats': stats.toMap(),
      'testIDsattempted': testIDsattempted,
      'createdAt': createdAt, // Add to Firestore map
    };
  }
}
