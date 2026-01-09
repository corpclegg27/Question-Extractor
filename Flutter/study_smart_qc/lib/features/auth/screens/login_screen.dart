// lib/features/auth/screens/login_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';

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

  // UI States
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  Future<void> _signIn() async {
    // 1. Dismiss Keyboard immediately
    FocusScope.of(context).unfocus();

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        // 2. Attempt Login
        UserCredential? cred = await AuthService().signInWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );

        if (mounted && cred != null && cred.user != null) {
          // Success Navigation
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AuthWrapper(firebaseUser: cred.user!),
            ),
          );
        }
      } on FirebaseAuthException catch (e) {
        // 3. Handle Firebase Errors nicely
        String message = "Login failed. Please try again.";
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          message = "No account found with these credentials.";
        } else if (e.code == 'wrong-password') {
          message = "Incorrect password. Please try again.";
        } else if (e.code == 'invalid-email') {
          message = "The email address is badly formatted.";
        } else if (e.code == 'too-many-requests') {
          message = "Too many failed attempts. Try again later.";
        }
        _showSnackBar(message, isError: true);
      } catch (e) {
        // 4. Handle Generic Errors
        _showSnackBar("An unexpected error occurred: $e", isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInGoogle() async {
    setState(() => _isLoading = true);
    try {
      UserCredential? cred = await AuthService().signInWithGoogle();
      if (mounted && cred != null && cred.user != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AuthWrapper(firebaseUser: cred.user!)),
        );
      }
    } catch (e) {
      _showSnackBar("Google Sign-In failed. Please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Tap to Dismiss" Keyboard wrapper
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.deepPurple[50],
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.school_rounded, size: 80, color: Colors.deepPurple),
                  const SizedBox(height: 16),
                  const Text('ModX by Anup Sir',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple)),
                  const SizedBox(height: 8),
                  Text('Welcome back! Please login to continue.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                  const SizedBox(height: 40),

                  // EMAIL FIELD
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter an email';
                      if (!value.contains('@') || !value.contains('.')) return 'Please enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // PASSWORD FIELD (With Eye Icon)
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    validator: (value) => value!.isEmpty ? 'Please enter a password' : null,
                  ),
                  const SizedBox(height: 24),

                  // LOGIN BUTTON
                  ElevatedButton(
                    onPressed: _isLoading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                        : const Text('Sign In', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),

                  // GOOGLE BUTTON
                  ElevatedButton.icon(
                    icon: Image.asset('assets/google_logo.png', height: 24.0),
                    label: const Text('Sign in with Google', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      backgroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300)
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _signInGoogle,
                  ),
                  const SizedBox(height: 24),

                  // TOGGLE LINK
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Not a member? ", style: TextStyle(color: Colors.grey[700])),
                      GestureDetector(
                        onTap: widget.showRegisterScreen,
                        child: const Text('Register now',
                            style: TextStyle(
                                color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}