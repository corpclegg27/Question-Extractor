// lib/services/auth_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:study_smart_qc/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream for auth changes
  Stream<User?> get userStream {
    return _auth.authStateChanges();
  }

  Future<void> _createUserDocumentIfNotExist(
      User user, {
        String? displayName,
      }) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final doc = await userRef.get();
    if (!doc.exists) {
      final newUser = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: displayName ?? user.displayName ?? '',
        stats: UserStats(),
        testIDsattempted: [],
        createdAt: Timestamp.now(),
        // Defaults
        role: 'student',
        onboardingCompleted: false,
      );
      await userRef.set(newUser.toFirestore());
    }
  }

  // UPDATED: Now rethrows exceptions so UI can handle them
  Future<UserCredential?> signInWithGoogle() async {
    // Let errors bubble up to be caught by the UI
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // User canceled

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    UserCredential userCredential = await _auth.signInWithCredential(credential);
    if (userCredential.user != null) {
      await _createUserDocumentIfNotExist(userCredential.user!);
    }
    return userCredential;
  }

  // UPDATED: Removed try-catch to allow specific error handling in UI
  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // UPDATED: Removed try-catch to allow specific error handling in UI
  Future<UserCredential?> signUpWithEmailAndPassword(String email, String password, String displayName) async {
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    User? user = userCredential.user;
    if (user != null) {
      await user.updateDisplayName(displayName);
      await _createUserDocumentIfNotExist(user, displayName: displayName);
    }
    return userCredential;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}