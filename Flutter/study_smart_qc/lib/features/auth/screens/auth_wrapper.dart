// lib/features/auth/screens/auth_wrapper.dart
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
        if (snapshot.hasError) {
          return _buildErrorScreen("Error: ${snapshot.error}");
        }

        // 1. Loading State (Including if doc is null/not exist yet)
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData ||
            !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Setting up your profile..."),
                ],
              ),
            ),
          );
        }

        // 2. Data Ready
        try {
          UserModel user = UserModel.fromFirestore(snapshot.data!);
          if (user.onboardingCompleted) {
            return const HomeScreen();
          } else {
            return const OnboardingScreen();
          }
        } catch (e) {
          return _buildErrorScreen("Profile Error: $e");
        }
      },
    );
  }

  Widget _buildErrorScreen(String msg) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => AuthService().signOut(),
              child: const Text("Sign Out"),
            )
          ],
        ),
      ),
    );
  }
}