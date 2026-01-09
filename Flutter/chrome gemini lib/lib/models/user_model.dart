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
      testsTaken: (map['testsTaken'] ?? 0) as int,
      questionsSolved: (map['questionsSolved'] ?? 0) as int,
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
  final List<String> testIDsAttempted;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.stats,
    required this.testIDsAttempted,
    required this.createdAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    DateTime createdDate = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      createdDate = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
       createdDate = DateTime.tryParse(data['createdAt']) ?? DateTime.now();
    }

    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      stats: UserStats.fromMap(data['stats'] ?? {}),
      testIDsAttempted: List<String>.from(data['testIDsattempted'] ?? []),
      createdAt: createdDate,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'stats': stats.toMap(),
      'testIDsattempted': testIDsAttempted,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}