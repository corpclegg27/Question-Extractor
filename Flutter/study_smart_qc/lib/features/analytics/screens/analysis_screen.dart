//lib/features/analytics/screens/analysis_screen.dart

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

class _AnalysisScreenState extends State<AnalysisScreen> with SingleTickerProviderStateMixin {
  bool _isTeacher = false;
  bool _isLoadingRole = true;
  late TabController _mainTabController;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _checkRole();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
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
      body: Column(
        children: [
          // 1. MAIN TAB BAR (Assignments vs Tests)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _mainTabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: const Color(0xFF6200EA),
              unselectedLabelColor: Colors.grey.shade600,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicatorPadding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: "Assignments"),
                Tab(text: "Tests"),
              ],
            ),
          ),

          // 2. TAB VIEW
          Expanded(
            child: TabBarView(
              controller: _mainTabController,
              children: [
                // Tab 1: Assignments Analysis (Has nested tabs)
                _buildAssignmentsAnalysisTab(),

                // Tab 2: Tests (Strict Mode)
                AttemptListWidget(
                  filterMode: 'Test',
                  onlySingleAttempt: true,
                  targetUserId: widget.targetStudentUid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentsAnalysisTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: 36,
            child: const TabBar(
              isScrollable: false,
              labelColor: Colors.deepPurple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.deepPurple,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(text: "Practice Mode"),
                Tab(text: "Test Mode"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                AttemptListWidget(
                  filterMode: 'Practice',
                  onlySingleAttempt: false,
                  targetUserId: widget.targetStudentUid,
                ),
                AttemptListWidget(
                  filterMode: 'Test',
                  onlySingleAttempt: false,
                  targetUserId: widget.targetStudentUid,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}