import 'package:flutter/material.dart';
import 'package:study_smart_qc/core/services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("StudySmart V2"), actions: [
        IconButton(onPressed: () => AuthService().signOut(), icon: const Icon(Icons.logout))
      ]),
      body: const Center(child: Text("Home Screen Placeholder")),
    );
  }
}