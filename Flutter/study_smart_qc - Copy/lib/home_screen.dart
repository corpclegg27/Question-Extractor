import 'package:flutter/material.dart';
import 'package:study_smart_qc/custom_test_history_screen.dart';
import 'package:study_smart_qc/enter_code_screen.dart';
import 'package:study_smart_qc/services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StudySmart'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.deepPurple),
              child: Text('StudySmart', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () {
                Navigator.of(context).pop();
                AuthService().signOut();
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('Create your own test'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), textStyle: const TextStyle(fontSize: 18)),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const CustomTestHistoryScreen()),
                  );
                },
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                 icon: const Icon(Icons.qr_code_scanner),
                 label: const Text('Attempt pre-made tests'),
                 style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), textStyle: const TextStyle(fontSize: 18)),
                 onPressed: () {
                   Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const EnterCodeScreen()),
                  );
                 },
              )
            ],
          ),
        ),
      ),
    );
  }
}
