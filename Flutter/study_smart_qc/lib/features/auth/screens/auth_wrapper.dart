import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/auth/screens/onboarding_screen.dart';
import 'package:study_smart_qc/features/home/screens/home_screen.dart';
import 'package:study_smart_qc/models/user_model.dart';

class AuthWrapper extends StatelessWidget {
  final User firebaseUser;

  const AuthWrapper({super.key, required this.firebaseUser});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        // 1. Loading State
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Error State or No Data
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: Text("Error loading user profile.")),
          );
        }

        // 3. Parse User Data
        try {
          // We use our model to parse the data safely
          UserModel user = UserModel.fromFirestore(snapshot.data!);

          // 4. routing Logic
          if (user.onboardingCompleted) {
            return const HomeScreen();
          } else {
            return const OnboardingScreen();
          }
        } catch (e) {
          return Scaffold(
            body: Center(child: Text("Error parsing user data: $e")),
          );
        }
      },
    );
  }
}