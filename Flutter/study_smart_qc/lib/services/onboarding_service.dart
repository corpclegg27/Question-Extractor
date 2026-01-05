import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import this
import 'package:study_smart_qc/models/user_model.dart'; // Import this

class OnboardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // Add auth instance

  // --- NEW METHOD TO FIX ERROR ---
  Future<UserModel?> getCurrentUserModel() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    }
    return null;
  }

  /// Completes the onboarding process.
  // ... (Keep the rest of your existing code below specifically completeOnboarding, _handleStudentOnboarding, etc.)
  Future<void> completeOnboarding({
    required String uid,
    required String role,
    required Map<String, dynamic> profileData,
  }) async {
    // ... (Your existing logic) ...
    final userRef = _firestore.collection('users').doc(uid);
    if (role == 'student') {
      await _handleStudentOnboarding(userRef, uid, profileData);
    } else {
      await _handleTeacherOnboarding(userRef, profileData);
    }
  }

  // ... (Keep _handleStudentOnboarding and _handleTeacherOnboarding exactly as they were) ...
  Future<void> _handleStudentOnboarding(
      DocumentReference userRef,
      String uid,
      Map<String, dynamic> profileData,
      ) async {
    // ... existing implementation ...
    final optionSetsRef = _firestore.collection('static_data').doc('option_sets');
    final trackerRef = _firestore.collection('student_question_tracker').doc(uid);

    return _firestore.runTransaction((transaction) async {
      DocumentSnapshot optionSetsSnapshot = await transaction.get(optionSetsRef);
      if (!optionSetsSnapshot.exists) throw Exception("System Error");

      int currentId = optionSetsSnapshot.get('last_assigned_student_id') ?? 0;
      int newId = currentId + 1;

      transaction.update(optionSetsRef, {'last_assigned_student_id': newId});
      transaction.update(userRef, {
        'role': 'student',
        'onboardingCompleted': true,
        'studentId': newId,
        'targetExam': profileData['targetExam'],
        'currentClass': profileData['currentClass'],
        'targetYear': profileData['targetYear'],
        'teachingExams': FieldValue.delete(),
        'teachingSubjects': FieldValue.delete(),
      });
      transaction.set(trackerRef, {
        'student_id': newId,
        'assigned_history': [],
        'buckets': {'unattempted': [], 'skipped': [], 'incorrect': [], 'correct': []}
      });
    });
  }

  Future<void> _handleTeacherOnboarding(DocumentReference userRef, Map<String, dynamic> profileData) async {
    await userRef.update({
      'role': 'teacher',
      'onboardingCompleted': true,
      'teachingExams': profileData['teachingExams'],
      'teachingSubjects': profileData['teachingSubjects'],
      'studentId': FieldValue.delete(),
      'targetExam': FieldValue.delete(),
      'currentClass': FieldValue.delete(),
      'targetYear': FieldValue.delete(),
    });
  }
}