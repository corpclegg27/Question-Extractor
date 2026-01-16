import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_smart_qc/features/common/widgets/display_results_for_student_id.dart';

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
    // This forces the teacher to select a student first.
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

    // --- ANALYSIS VIEW (Student or Teacher viewing Student) ---
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Text(
          widget.targetStudentUid != null ? "Student Analysis" : "Performance Analysis",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      // The shared widget handles the Tabs (Assignments/Tests) and Lists
      body: DisplayResultsForStudentId(
        targetStudentUid: widget.targetStudentUid,
      ),
    );
  }
}