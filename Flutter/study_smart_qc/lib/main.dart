// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/auth/screens/auth_page.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StudySmart',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // DIAGNOSTIC: We access FirebaseAuth directly here to ensure the stream is valid.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {

          // DIAGNOSTIC LOGS: Check your Debug Console for these lines
          if (snapshot.connectionState == ConnectionState.waiting) {
            print("--- AUTH STREAM: WAITING ---");
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          if (snapshot.hasError) {
            print("--- AUTH STREAM: ERROR: ${snapshot.error} ---");
            return Scaffold(
              body: Center(child: Text("Auth Error: ${snapshot.error}")),
            );
          }

          if (snapshot.hasData && snapshot.data != null) {
            print("--- AUTH STREAM: USER LOGGED IN (${snapshot.data!.uid}) ---");
            print("--- NAVIGATING TO AUTH WRAPPER ---");
            // Successful Login -> Switch to Wrapper
            return AuthWrapper(firebaseUser: snapshot.data!);
          }

          print("--- AUTH STREAM: NO USER (Showing AuthPage) ---");
          // No User -> Show Login/Register
          return const AuthPage();
        },
      ),
    );
  }
}