import 'package:firebase_auth/firebase_auth.dart'; // Added import
import 'package:flutter/material.dart';
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart'; // Added import

class LoginScreen extends StatefulWidget {
  final VoidCallback showRegisterScreen;
  const LoginScreen({super.key, required this.showRegisterScreen});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      // 1. Capture Result
      UserCredential? cred = await AuthService().signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (mounted) {
        setState(() => _isLoading = false);

        // 2. FORCE NAVIGATION
        if (cred != null && cred.user != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AuthWrapper(firebaseUser: cred.user!),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('StudySmart', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                const SizedBox(height: 50),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) => value!.isEmpty ? 'Please enter an email' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (value) => value!.isEmpty ? 'Please enter a password' : null,
                ),
                const SizedBox(height: 20),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: _signIn,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text('Sign In'),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: Image.asset('assets/google_logo.png', height: 24.0),
                  label: const Text('Sign in with Google', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black, backgroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                  onPressed: () async {
                    // Manual nav for Google Sign In too
                    UserCredential? cred = await AuthService().signInWithGoogle();
                    if (cred != null && cred.user != null && mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => AuthWrapper(firebaseUser: cred.user!),
                        ),
                      );
                    }
                  },
                ),
                TextButton(
                  onPressed: widget.showRegisterScreen,
                  child: const Text('Not a member? Register now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}