// lib/features/analytics/screens/analysis_screen.dart

import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/analytics/widgets/attempt_list_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalysisScreen extends StatefulWidget {
  final String? targetStudentUid; // The specific student to view (optional)

  const AnalysisScreen({super.key, this.targetStudentUid});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  bool _isTeacher = false;
  bool _isLoadingRole = true;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (mounted) {
          setState(() {
            _isTeacher = doc.data()?['role'] == 'teacher';
            _isLoadingRole = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingRole = false);
      }
    } else {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // --- TEACHER GUARD ---
    // Condition: I am a Teacher AND I did not come from the Drawer (targetStudentUid is null)
    if (_isTeacher && widget.targetStudentUid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Analysis"),
          automaticallyImplyLeading: false, // Hide back button on main tab
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.admin_panel_settings_outlined, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 24),
                const Text(
                  "Teacher Mode",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  "To view student analytics, please open the Side Drawer and select 'Check Student Performance'.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // --- NORMAL VIEW ---
    // (For Students OR Teachers who passed the Guard)
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.targetStudentUid != null ? "Student Analysis" : "Performance Analysis",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.deepPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.deepPurple,
            tabs: [
              Tab(icon: Icon(Icons.school_outlined), text: "Assignments"),
              Tab(icon: Icon(Icons.timer_outlined), text: "Tests"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Practice
            AttemptListWidget(
              filterMode: 'Practice',
              targetUserId: widget.targetStudentUid, // Pass the ID down
            ),
            // Tab 2: Tests
            AttemptListWidget(
              filterMode: 'Test',
              targetUserId: widget.targetStudentUid, // Pass the ID down
            ),
          ],
        ),
      ),
    );
  }
}