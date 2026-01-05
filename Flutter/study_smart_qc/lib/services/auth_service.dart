//lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:study_smart_qc/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- FIX 1: Non-blocking Stream ---
  // We removed asyncMap. The UI will now receive updates instantly.
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

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // --- FIX 2: Ensure Document Exists for Google Users ---
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null) {
        // We manually check/create the doc here since we removed it from the stream
        await _createUserDocumentIfNotExist(userCredential.user!);
      }
      return userCredential;

    } catch (e) {
      print("Error during Google Sign-In: $e");
      return null;
    }
  }

  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      print("Error: ${e.message}");
      return null;
    }
  }

  Future<UserCredential?> signUpWithEmailAndPassword(String email, String password, String displayName) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      User? user = userCredential.user;
      if (user != null) {
        await user.updateDisplayName(displayName);
        // This was already correct, it creates the doc explicitly
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