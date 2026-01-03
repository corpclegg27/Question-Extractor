import 'package:cloud_firestore/cloud_firestore.dart';

class OnboardingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Completes the onboarding process.
  /// If the user is a STUDENT, this runs a Transaction to safely generate a unique Student ID.
  /// If the user is a TEACHER, this performs a simple update.
  Future<void> completeOnboarding({
    required String uid,
    required String role, // 'student' or 'teacher'
    required Map<String, dynamic> profileData,
  }) async {
    final userRef = _firestore.collection('users').doc(uid);

    if (role == 'student') {
      await _handleStudentOnboarding(userRef, uid, profileData);
    } else {
      await _handleTeacherOnboarding(userRef, profileData);
    }
  }

  /// Transactional logic for Students
  Future<void> _handleStudentOnboarding(
      DocumentReference userRef,
      String uid,
      Map<String, dynamic> profileData,
      ) async {
    final optionSetsRef =
    _firestore.collection('static_data').doc('option_sets');
    final trackerRef =
    _firestore.collection('student_question_tracker').doc(uid);

    return _firestore.runTransaction((transaction) async {
      // 1. READ: Get the current ID counter
      // This read locks the document until the transaction completes
      DocumentSnapshot optionSetsSnapshot = await transaction.get(optionSetsRef);

      if (!optionSetsSnapshot.exists) {
        throw Exception("System Error: 'static_data/option_sets' not found.");
      }

      int currentId = optionSetsSnapshot.get('last_assigned_student_id') ?? 0;
      int newId = currentId + 1;

      // 2. WRITE: Update the counter
      transaction.update(optionSetsRef, {
        'last_assigned_student_id': newId,
      });

      // 3. WRITE: Update the User Profile
      transaction.update(userRef, {
        'role': 'student',
        'onboardingCompleted': true,
        'studentId': newId,
        'targetExam': profileData['targetExam'],
        'currentClass': profileData['currentClass'],
        'targetYear': profileData['targetYear'],
        // Clear teacher fields if they existed by mistake
        'teachingExams': FieldValue.delete(),
        'teachingSubjects': FieldValue.delete(),
      });

      // 4. WRITE: Create the Question Tracker
      transaction.set(trackerRef, {
        'student_id': newId,
        'assigned_history': [],
        'buckets': {
          'unattempted': [],
          'skipped': [],
          'incorrect': [],
          'correct': [],
        }
      });
    });
  }

  /// Simple update logic for Teachers
  Future<void> _handleTeacherOnboarding(
      DocumentReference userRef,
      Map<String, dynamic> profileData,
      ) async {
    await userRef.update({
      'role': 'teacher',
      'onboardingCompleted': true,
      'teachingExams': profileData['teachingExams'],
      'teachingSubjects': profileData['teachingSubjects'],
      // Clear student fields
      'studentId': FieldValue.delete(),
      'targetExam': FieldValue.delete(),
      'currentClass': FieldValue.delete(),
      'targetYear': FieldValue.delete(),
    });
  }
}