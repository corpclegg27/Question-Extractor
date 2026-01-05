// lib/features/home/screens/home_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/auth/screens/auth_page.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'package:study_smart_qc/features/student/widgets/student_assignments_list.dart';
import 'package:study_smart_qc/features/analytics/screens/analysis_screen.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_curation_screen.dart';
// --- IMPORT THE NEW HISTORY SCREEN ---
import 'package:study_smart_qc/features/teacher/screens/teacher_history_screen.dart';
import 'package:study_smart_qc/features/test_creation/screens/custom_test_history_screen.dart';
import 'package:study_smart_qc/features/test_taking/screens/enter_code_screen.dart';
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/services/onboarding_service.dart';
import 'package:study_smart_qc/widgets/student_lookup_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  UserModel? _userModel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = await OnboardingService().getCurrentUserModel();
    if (mounted) {
      setState(() {
        _userModel = user;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_userModel == null) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        return AuthWrapper(firebaseUser: currentUser);
      } else {
        return const AuthPage();
      }
    }

    // --- TEACHER DASHBOARD (Main Screen) ---
    if (_userModel!.role == 'teacher') {
      return Scaffold(
        appBar: AppBar(title: const Text("Teacher Dashboard")),
        drawer: _buildDrawer(context),
        body: const TeacherCurationScreen(),
      );
    }

    // --- STUDENT DASHBOARD ---
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        elevation: 0,
        centerTitle: false,
      ),
      drawer: _buildDrawer(context),

      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          StudentAssignmentsList(isStrict: false),
          StudentAssignmentsList(isStrict: true),
          AnalysisScreen(),
        ],
      ),

      floatingActionButton: _currentTabIndex == 1
          ? _buildTestFab(context)
          : null,

      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Assignments',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Tests',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analysis',
          ),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentTabIndex) {
      case 0: return "My Assignments";
      case 1: return "My Tests";
      case 2: return "Performance";
      default: return "Study Smart";
    }
  }

  Widget _buildTestFab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: "code",
          tooltip: "Enter Test Code",
          backgroundColor: Colors.white,
          foregroundColor: Colors.deepPurple,
          child: const Icon(Icons.keyboard),
          onPressed: () {
            Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EnterCodeScreen())
            );
          },
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: "create",
          label: const Text("Create Custom Test"),
          icon: const Icon(Icons.add),
          backgroundColor: Colors.deepPurple,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomTestHistoryScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final isTeacher = _userModel?.role == 'teacher';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_userModel?.displayName ?? "User"),
            accountEmail: Text(_userModel?.email ?? ""),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                (_userModel?.displayName ?? "U")[0].toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            decoration: const BoxDecoration(color: Colors.deepPurple),
          ),

          // --- Student ID Display (Only for Students) ---
          if (!isTeacher && _userModel?.studentId != null) ...[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text("Student ID: ${_userModel!.studentId}"),
              subtitle: const Text("Share this with your teacher"),
              tileColor: Colors.grey.shade50,
            ),
            const Divider(),
          ],

          // --- TEACHER TOOLS SECTION ---
          if (isTeacher) ...[
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
              child: Text("Teacher Tools", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),

            // 1. My Curations (View History) [Image of Mobile app drawer menu with 'My Curations' highlighted]
            ListTile(
              leading: const Icon(Icons.history_edu),
              title: const Text('My Curations'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TeacherHistoryScreen()),
                );
              },
            ),

            // 2. Curate (Create New)
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Curate Questions'),
              onTap: () {
                Navigator.pop(context);
                // We are already on the teacher dashboard, but if we were elsewhere this resets it
                if (ModalRoute.of(context)?.settings.name != '/') {
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              },
            ),

            // 3. Check Performance
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text("Check Student Performance"),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const StudentLookupSheet(),
                );
              },
            ),
            const Divider(),
          ],

          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthPage()),
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}