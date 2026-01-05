import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/auth/screens/onboarding_screen.dart';
import 'package:study_smart_qc/features/home/screens/home_screen.dart';
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/services/auth_service.dart';

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

        // 2. Error State
        if (snapshot.hasError) {
          return _buildErrorScreen("Error loading profile: ${snapshot.error}");
        }

        // 3. Profile Missing (New User lag)
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildErrorScreen("Profile initializing...", isLoading: true);
        }

        // 4. Parse User Data & Route
        try {
          UserModel user = UserModel.fromFirestore(snapshot.data!);

          if (user.onboardingCompleted) {
            return const HomeScreen();
          } else {
            return const OnboardingScreen();
          }
        } catch (e) {
          return _buildErrorScreen("Corrupt profile data. Please contact support.\n$e");
        }
      },
    );
  }

  // A helper to prevent getting "Stuck" on a broken screen
  Widget _buildErrorScreen(String msg, {bool isLoading = false}) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading) const CircularProgressIndicator() else const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              // THE ESCAPE HATCH: Allows you to logout if stuck
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text("Sign Out & Retry"),
                onPressed: () => AuthService().signOut(),
              )
            ],
          ),
        ),
      ),
    );
  }
}