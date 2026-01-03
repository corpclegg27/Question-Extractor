import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:study_smart_qc/core/constants/firebase_constants.dart';
import 'package:study_smart_qc/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream of User status
  Stream<User?> get userStream {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user != null) {
        await _ensureUserDocumentExists(user);
      }
      return user;
    });
  }

  // Get current user ID safely
  String? get currentUserId => _auth.currentUser?.uid;

  // Ensure Firestore document exists
  Future<void> _ensureUserDocumentExists(User user, {String? displayName}) async {
    final userRef = _firestore.collection(FirebaseConstants.users).doc(user.uid);
    final doc = await userRef.get();

    if (!doc.exists) {
      final newUser = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: displayName ?? user.displayName ?? 'Student',
        stats: UserStats(),
        testIDsAttempted: [],
        createdAt: DateTime.now(),
      );
      await userRef.set(newUser.toFirestore());
    }
  }

  // Google Sign In
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User canceled

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      print("Google Sign-In Error: $e");
      return null;
    }
  }

  // Email Sign In
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      print("Email Sign-In Error: ${e.message}");
      rethrow; // Pass error to UI to show snackbar
    }
  }

  // Email Sign Up
  Future<UserCredential?> signUpWithEmail(String email, String password, String name) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (cred.user != null) {
        await cred.user!.updateDisplayName(name);
        await _ensureUserDocumentExists(cred.user!, displayName: name);
      }
      return cred;
    } on FirebaseAuthException catch (e) {
      print("Sign-Up Error: ${e.message}");
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}