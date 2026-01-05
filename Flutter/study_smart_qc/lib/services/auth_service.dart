import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:study_smart_qc/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- UPDATED STREAM: Non-blocking ---
  Stream<User?> get userStream {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user != null) {
        try {
          // Try to create/check the doc, but don't crash the app if it fails
          await _createUserDocumentIfNotExist(user);
        } catch (e) {
          print("⚠️ Warning: Failed to init user profile: $e");
          // We still return 'user' so the UI can load and show a specific error
        }
      }
      return user;
    });
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

  // ... (Keep your existing signIn/signUp/signOut methods exactly as they are) ...
  Future<UserCredential?> signInWithGoogle() async {
    // ... (Your existing code)
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print("Error during Google Sign-In: $e");
      return null;
    }
  }

  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    // ... (Your existing code)
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      print("Error: ${e.message}");
      return null;
    }
  }

  Future<UserCredential?> signUpWithEmailAndPassword(String email, String password, String displayName) async {
    // ... (Your existing code)
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      User? user = userCredential.user;
      if (user != null) {
        await user.updateDisplayName(displayName);
        await _createUserDocumentIfNotExist(user, displayName: displayName);
      }
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print("Error: ${e.message}");
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}