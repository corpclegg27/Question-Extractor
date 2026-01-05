import 'package:firebase_auth/firebase_auth.dart'; // Import for currentUser
import 'package:flutter/material.dart';
// REMOVED: import 'package:provider/provider.dart'; (Unused)
import 'package:study_smart_qc/features/auth/screens/auth_page.dart'; // Import AuthPage
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'package:study_smart_qc/features/student/widgets/student_assignments_list.dart';
import 'package:study_smart_qc/features/analytics/screens/analysis_screen.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_curation_screen.dart';
import 'package:study_smart_qc/features/test_creation/screens/custom_test_history_screen.dart';
import 'package:study_smart_qc/features/test_taking/screens/enter_code_screen.dart';
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/services/onboarding_service.dart';

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
    // FIX 1: This method now exists in OnboardingService
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
      // FIX 2: If no user model found, check if firebase user exists
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        return AuthWrapper(firebaseUser: currentUser);
      } else {
        return const AuthPage(); // Or LoginScreen
      }
    }

    // --- TEACHER DASHBOARD ---
    if (_userModel!.role == 'Teacher') {
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
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            // FIX 3: Use 'displayName', not 'name'
            accountName: Text(_userModel?.displayName ?? "User"),
            accountEmail: Text(_userModel?.email ?? ""),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                // FIX 3: Use 'displayName' here too
                (_userModel?.displayName ?? "U")[0].toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            decoration: const BoxDecoration(color: Colors.deepPurple),
          ),
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
                // FIX 4: Navigate to AuthPage (or wrapper) properly
                // Since we are logging out, we can't pass a firebaseUser to AuthWrapper
                // So we go to the root AuthPage
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