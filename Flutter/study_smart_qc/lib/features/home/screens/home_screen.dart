// lib/features/home/screens/home_screen.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// MODELS
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';

// SCREENS
import 'package:study_smart_qc/features/auth/screens/auth_page.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'package:study_smart_qc/features/student/widgets/student_assignments_list.dart';
import 'package:study_smart_qc/features/analytics/screens/analysis_screen.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_curation_screen.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_history_screen.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';

// SERVICES
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/services/onboarding_service.dart';
import 'package:study_smart_qc/services/local_session_service.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
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

  // --- RESUME SESSION STATE ---
  final LocalSessionService _localSessionService = LocalSessionService();
  bool _hasPendingSession = false;
  Map<String, dynamic>? _pendingSessionData;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _checkPendingSession();
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

  // Helper to extract pending code safely
  String? get _pendingAssignmentCode {
    if (!_hasPendingSession || _pendingSessionData == null) return null;
    return _pendingSessionData!['meta']['assignmentCode'];
  }

  // ---------------------------------------------------------------------------
  //  RESUME LOGIC START
  // ---------------------------------------------------------------------------

  Future<void> _checkPendingSession() async {
    final hasSession = await _localSessionService.hasPendingSession();
    if (hasSession) {
      final data = await _localSessionService.getSessionData();
      setState(() {
        _hasPendingSession = true;
        _pendingSessionData = data;
      });
      if (mounted) _showResumeDialog();
    }
  }

  void _showResumeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Resume Test?"),
        content: const Text(
            "You have an unfinished test session saved on this device. Would you like to continue?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSubmitPending();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: const Text("No, Submit"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleResumePending();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            child: const Text("Yes, Resume"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleResumePending() async {
    if (_pendingSessionData == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final meta = _pendingSessionData!['meta'];
      final timestamps = _pendingSessionData!['timestamps'];
      final state = _pendingSessionData!['state'];

      final String mode = meta['mode'] ?? 'Test';
      final String assignmentCode = meta['assignmentCode'];
      final int savedTimer = timestamps['quitTimeTimerValue'];
      final String quitTimestamp = timestamps['quitTimeTimestamp'];

      // A. RECONCILE TIMER
      final newTime = _localSessionService.calculateResumeTime(
        mode: mode,
        savedTimerValue: savedTimer,
        savedTimestampIso: quitTimestamp,
      );

      // B. CHECK EXPIRY
      if (newTime == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Time expired while you were away. Submitting test..."),
          backgroundColor: Colors.red,
        ));
        _handleSubmitPending();
        return;
      }

      // C. FETCH QUESTIONS
      List<Question> questions = [];
      List<String> qIds = [];

      final curationQuery = await FirebaseFirestore.instance
          .collection('questions_curation')
          .where('assignmentCode', isEqualTo: assignmentCode)
          .limit(1)
          .get();

      if (curationQuery.docs.isNotEmpty) {
        final data = curationQuery.docs.first.data();
        qIds = List<String>.from(data['questionIds'] ?? []);
      } else {
        final testQuery = await FirebaseFirestore.instance
            .collection('tests')
            .where('assignmentCode', isEqualTo: assignmentCode)
            .limit(1)
            .get();

        if(testQuery.docs.isNotEmpty) {
          qIds = List<String>.from(testQuery.docs.first.data()['questionIds'] ?? []);
        }
      }

      if (qIds.isNotEmpty) {
        questions = await TestOrchestrationService().getQuestionsByIds(qIds);
      }

      if (questions.isEmpty) {
        throw Exception("Could not retrieve questions for Code: $assignmentCode");
      }

      // D. PARSE RESPONSES
      final responseMap = _localSessionService.parseResponses(
          Map<String, dynamic>.from(state['responses'])
      );

      // E. NAVIGATE TO TEST SCREEN
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TestScreen(
              sourceId: curationQuery.docs.isNotEmpty ? curationQuery.docs.first.id : '',
              assignmentCode: assignmentCode,
              questions: questions,
              timeLimitInMinutes: 0,
              testMode: mode == 'Test' ? TestMode.test : TestMode.practice,
              resumedTimerSeconds: newTime,
              resumedPageIndex: state['currentQuestionIndex'],
              resumedResponses: responseMap,
            ),
          ),
        ).then((_) {
          _checkPendingSession();
          _fetchUserData(); // Refresh to check if they submitted
        });
      }

    } catch (e) {
      if (mounted) Navigator.pop(context);
      print("Resume Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error resuming session: $e")),
      );
    }
  }

  Future<void> _handleSubmitPending() async {
    if (_pendingSessionData == null) return;

    final meta = _pendingSessionData!['meta'];
    final state = _pendingSessionData!['state'];
    final metaMode = meta['mode'] ?? 'Test';

    final responseMap = _localSessionService.parseResponses(
        Map<String, dynamic>.from(state['responses'])
    );

    int correct = 0;
    int incorrect = 0;
    responseMap.forEach((k, v) {
      if(v.status == 'CORRECT') correct++;
      if(v.status == 'INCORRECT') incorrect++;
    });
    final score = (correct * 4) - incorrect;

    await TestOrchestrationService().submitAttempt(
      sourceId: meta['testId'] ?? '',
      assignmentCode: meta['assignmentCode'],
      mode: metaMode,
      title: meta['title'] ?? 'Untitled Test', // <--- ADD THIS LINE
      questions: [],
      score: score,
      timeTakenSeconds: 0,
      responses: responseMap,
    );

    await _localSessionService.clearSession();

    setState(() {
      _hasPendingSession = false;
      _pendingSessionData = null;
    });

    if (mounted) {
      _fetchUserData(); // Refresh user data to get the new submission code
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Test submitted successfully.")));
    }
  }

  // ---------------------------------------------------------------------------
  //  UI BUILD
  // ---------------------------------------------------------------------------

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

    // --- TEACHER DASHBOARD ---
    if (_userModel!.role == 'teacher') {
      return Scaffold(
        appBar: AppBar(title: const Text("Teacher Dashboard")),
        drawer: _buildDrawer(context),
        body: const TeacherCurationScreen(),
      );
    }

    // --- STUDENT DASHBOARD ---
    // Prepare common params for lists
    final List<String> submitted = _userModel!.assignmentCodesSubmitted;
    final String? resumeCode = _pendingAssignmentCode;
    final VoidCallback navToAnalysis = () => setState(() => _currentTabIndex = 2);

    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        elevation: 0,
        centerTitle: false,
      ),
      drawer: _buildDrawer(context),

      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Assignments (General / Practice)
          StudentAssignmentsList(
            isStrict: false,
            submittedCodes: submitted,
            resumableAssignmentCode: resumeCode,
            onResumeTap: _handleResumePending,
            onViewAnalysisTap: navToAnalysis,
          ),

          // Tab 1: Tests (Strict / Timed)
          // Removed the duplicate 'Resume Card' - now handled inside the list
          StudentAssignmentsList(
            isStrict: true,
            submittedCodes: submitted,
            resumableAssignmentCode: resumeCode,
            onResumeTap: _handleResumePending,
            onViewAnalysisTap: navToAnalysis,
          ),

          // Tab 2: Analysis
          const AnalysisScreen(),
        ],
      ),

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

          if (!isTeacher && _userModel?.studentId != null) ...[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text("Student ID: ${_userModel!.studentId}"),
              subtitle: const Text("Share this with your teacher"),
              tileColor: Colors.grey.shade50,
            ),
            const Divider(),
          ],

          if (isTeacher) ...[
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
              child: Text("Teacher Tools", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
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
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Curate Questions'),
              onTap: () {
                Navigator.pop(context);
                if (ModalRoute.of(context)?.settings.name != '/') {
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              },
            ),
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