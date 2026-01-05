import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/auth/screens/auth_page.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'package:study_smart_qc/services/auth_service.dart';
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
      home: StreamBuilder<User?>(
        stream: AuthService().userStream,
        builder: (context, snapshot) {
          // 1. Connection Error / Loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          // 2. Stream Error (Network, etc)
          if (snapshot.hasError) {
            return Scaffold(
                body: Center(child: Text("Authentication Error: ${snapshot.error}"))
            );
          }

          // 3. Logged In -> Wrapper
          if (snapshot.hasData && snapshot.data != null) {
            return AuthWrapper(firebaseUser: snapshot.data!);
          }

          // 4. Logged Out -> AuthPage
          return const AuthPage();
        },
      ),
    );
  }
}