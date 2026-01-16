import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// MODELS
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';

// SCREENS & WIDGETS
import 'package:study_smart_qc/features/auth/screens/auth_page.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'package:study_smart_qc/features/student/widgets/student_assignments_list.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_curation_screen.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_history_screen.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
// Note: attempt_list_widget is likely used inside DisplayResultsForStudentId now,
// so we import the new common widget instead.
import 'package:study_smart_qc/features/common/widgets/display_results_for_student_id.dart';
import 'package:study_smart_qc/widgets/student_lookup_sheet.dart';

// SERVICES
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/services/onboarding_service.dart';
import 'package:study_smart_qc/services/local_session_service.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';

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
  //  SORTING LOGIC (CLIENT SIDE)
  // ---------------------------------------------------------------------------

  /// Sorts documents:
  /// 1. Items with deadline (Ascending / Earliest first)
  /// 2. Items without deadline (Descending by CreatedAt / Newest first)
  int _deadlineAwareSort(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    final Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
    final Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;

    final Timestamp? deadlineA = dataA['deadline'];
    final Timestamp? deadlineB = dataB['deadline'];

    // Fallback: CreatedAt (assume non-null)
    final Timestamp createdA = dataA['createdAt'] ?? Timestamp.now();
    final Timestamp createdB = dataB['createdAt'] ?? Timestamp.now();

    // 1. Prioritize existence of Deadline
    if (deadlineA != null && deadlineB == null) return -1; // A comes first
    if (deadlineA == null && deadlineB != null) return 1;  // B comes first

    // 2. If both have deadlines, sort Ascending (Earliest deadline first)
    if (deadlineA != null && deadlineB != null) {
      int cmp = deadlineA.compareTo(deadlineB);
      if (cmp != 0) return cmp;
    }

    // 3. If neither have deadlines (or deadlines are equal), sort CreatedAt Descending
    return createdB.compareTo(createdA);
  }

  // ---------------------------------------------------------------------------
  //  RESUME LOGIC
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
        title: const Text("Resume Session?"),
        content: const Text(
            "You have an unfinished session saved on this device. Would you like to continue?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSubmitPending();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.grey),
            child: const Text("Discard & Submit"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleResumePending();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6200EA),
                foregroundColor: Colors.white),
            child: const Text("Resume"),
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

      // RECONCILE TIMER
      final newTime = _localSessionService.calculateResumeTime(
        mode: mode,
        savedTimerValue: savedTimer,
        savedTimestampIso: quitTimestamp,
      );

      if (newTime == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Time expired while you were away. Submitting..."),
          backgroundColor: Colors.red,
        ));
        _handleSubmitPending();
        return;
      }

      // FETCH DATA
      List<Question> questions = [];
      List<String> qIds = [];
      bool isSingleAttempt = false;

      final curationQuery = await FirebaseFirestore.instance
          .collection('questions_curation')
          .where('assignmentCode', isEqualTo: assignmentCode)
          .limit(1)
          .get();

      if (curationQuery.docs.isNotEmpty) {
        final data = curationQuery.docs.first.data();
        qIds = List<String>.from(data['questionIds'] ?? []);
        isSingleAttempt = data['onlySingleAttempt'] ?? false;
      } else {
        // Fallback for legacy 'tests' collection if needed
        final testQuery = await FirebaseFirestore.instance
            .collection('tests')
            .where('assignmentCode', isEqualTo: assignmentCode)
            .limit(1)
            .get();

        if (testQuery.docs.isNotEmpty) {
          qIds = List<String>.from(
              testQuery.docs.first.data()['questionIds'] ?? []);
        }
      }

      if (qIds.isNotEmpty) {
        questions = await TestOrchestrationService().getQuestionsByIds(qIds);
      }

      if (questions.isEmpty) {
        throw Exception("Could not retrieve questions.");
      }

      final responseMap = _localSessionService.parseResponses(
          Map<String, dynamic>.from(state['responses']));

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TestScreen(
              sourceId: curationQuery.docs.isNotEmpty
                  ? curationQuery.docs.first.id
                  : '',
              assignmentCode: assignmentCode,
              questions: questions,
              timeLimitInMinutes: 0, // Handled by resume logic usually
              testMode: mode == 'Test' ? TestMode.test : TestMode.practice,
              resumedTimerSeconds: newTime,
              resumedPageIndex: state['currentQuestionIndex'],
              resumedResponses: responseMap,
              title: meta['title'] ?? 'Resumed Session',
              onlySingleAttempt: isSingleAttempt,
            ),
          ),
        ).then((_) {
          _checkPendingSession();
          _fetchUserData();
        });
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error resuming: $e")),
      );
    }
  }

  Future<void> _handleSubmitPending() async {
    if (_pendingSessionData == null) return;

    final meta = _pendingSessionData!['meta'];
    final state = _pendingSessionData!['state'];
    final metaMode = meta['mode'] ?? 'Test';

    final responseMap = _localSessionService.parseResponses(
        Map<String, dynamic>.from(state['responses']));

    int correct = 0;
    int incorrect = 0;
    responseMap.forEach((k, v) {
      if (v.status == 'CORRECT') correct++;
      if (v.status == 'INCORRECT') incorrect++;
    });
    final score = (correct * 4) - incorrect;

    await TestOrchestrationService().submitAttempt(
      sourceId: meta['testId'] ?? '',
      assignmentCode: meta['assignmentCode'],
      mode: metaMode,
      title: meta['title'] ?? 'Untitled Test',
      onlySingleAttempt: false,
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
      _fetchUserData();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Session submitted successfully.")));
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
    // Single Stream Source for all tabs to ensure sync and efficiency
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Text(
          _getAppBarTitle(),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: false,
      ),
      drawer: _buildDrawer(context),

      // OUTER STREAM: Listen to User Profile (For real-time 'Completed' updates)
      body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_userModel!.uid)
              .snapshots(),
          builder: (context, userSnapshot) {

            // 1. Get Live Submitted Codes
            // Fallback to static _userModel if stream is loading/empty to prevent flicker
            List<String> liveSubmittedCodes = _userModel!.assignmentCodesSubmitted;

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>;
              liveSubmittedCodes = List<String>.from(userData['assignmentCodesSubmitted'] ?? []);
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('questions_curation')
              // CORRECTED: Matching the single number field 'studentId'
                  .where('studentId', isEqualTo: _userModel!.studentId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }

                final allDocs = snapshot.data?.docs ?? [];

                // 1. Filter: Strict (Test) vs Non-Strict (Assignment)
                final strictDocs = <QueryDocumentSnapshot>[];
                final normalDocs = <QueryDocumentSnapshot>[];

                for (var doc in allDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final bool isStrict = data['onlySingleAttempt'] ?? false;
                  if (isStrict) {
                    strictDocs.add(doc);
                  } else {
                    normalDocs.add(doc);
                  }
                }

                // 2. Filter: Pending vs Completed using LIVE CODES
                // 3. Sort: Apply Deadline->CreatedAt Logic

                // -- ASSIGNMENTS --
                final pendingAssignments = normalDocs
                    .where((d) => !liveSubmittedCodes.contains(d['assignmentCode']))
                    .toList()..sort(_deadlineAwareSort);

                final completedAssignments = normalDocs
                    .where((d) => liveSubmittedCodes.contains(d['assignmentCode']))
                    .toList()..sort(_deadlineAwareSort);

                // -- TESTS --
                final pendingTests = strictDocs
                    .where((d) => !liveSubmittedCodes.contains(d['assignmentCode']))
                    .toList()..sort(_deadlineAwareSort);

                final completedTests = strictDocs
                    .where((d) => liveSubmittedCodes.contains(d['assignmentCode']))
                    .toList()..sort(_deadlineAwareSort);

                return IndexedStack(
                  index: _currentTabIndex,
                  children: [
                    // Tab 0: Assignments
                    _AssignmentTabContainer(
                      pendingDocs: pendingAssignments,
                      completedDocs: completedAssignments,
                      resumableAssignmentCode: _pendingAssignmentCode,
                      onResumeTap: _handleResumePending,
                      onViewAnalysisTap: () => setState(() => _currentTabIndex = 2),
                    ),

                    // Tab 1: Tests
                    _AssignmentTabContainer(
                      pendingDocs: pendingTests,
                      completedDocs: completedTests,
                      resumableAssignmentCode: _pendingAssignmentCode,
                      onResumeTap: _handleResumePending,
                      onViewAnalysisTap: () => setState(() => _currentTabIndex = 2),
                    ),

                    // Tab 2: Analysis (REPLACED WITH NEW WIDGET)
                    const DisplayResultsForStudentId(
                      // No student ID passed means it defaults to current logged-in user
                    ),
                  ],
                );
              },
            );
          }
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentTabIndex = index),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEADBFF),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment, color: Color(0xFF6200EA)),
            label: 'Assignments',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer, color: Color(0xFF6200EA)),
            label: 'Tests',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics, color: Color(0xFF6200EA)),
            label: 'Analysis',
          ),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentTabIndex) {
      case 0:
        return "Assignments";
      case 1:
        return "Tests";
      case 2:
        return "Analysis";
      default:
        return "ModX by Anup Sir";
    }
  }

  Widget _buildDrawer(BuildContext context) {
    final isTeacher = _userModel?.role == 'teacher';
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              _userModel?.displayName ?? "User",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(_userModel?.email ?? ""),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                (_userModel?.displayName ?? "U")[0].toUpperCase(),
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6200EA)),
              ),
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF6200EA),
            ),
          ),
          if (!isTeacher && _userModel?.studentId != null) ...[
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text("Student ID: ${_userModel!.studentId}"),
              tileColor: Colors.grey.shade50,
            ),
            const Divider(),
          ],
          if (isTeacher) ...[
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
              child: Text("Teacher Tools",
                  style: TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.history_edu),
              title: const Text('My Curations'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherHistoryScreen()),
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

// ---------------------------------------------------------------------------
//  HELPER 1: TAB CONTAINER (MODIFIED TO ACCEPT LISTS)
// ---------------------------------------------------------------------------

class _AssignmentTabContainer extends StatefulWidget {
  // Now accepts Pre-Sorted Lists instead of just codes
  final List<QueryDocumentSnapshot> pendingDocs;
  final List<QueryDocumentSnapshot> completedDocs;

  final String? resumableAssignmentCode;
  final Future<void> Function() onResumeTap;
  final VoidCallback onViewAnalysisTap;

  const _AssignmentTabContainer({
    required this.pendingDocs,
    required this.completedDocs,
    required this.resumableAssignmentCode,
    required this.onResumeTap,
    required this.onViewAnalysisTap,
  });

  @override
  State<_AssignmentTabContainer> createState() => _AssignmentTabContainerState();
}

class _AssignmentTabContainerState extends State<_AssignmentTabContainer>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
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
            labelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicatorPadding: const EdgeInsets.all(4),
            tabs: const [
              Tab(text: "Pending"),
              Tab(text: "Completed"),
            ],
          ),
        ),

        // Lists
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // NOTE: StudentAssignmentsList must be updated to accept `documents` list
              // instead of fetching them internally.
              StudentAssignmentsList(
                documents: widget.pendingDocs, // Pass list directly
                resumableAssignmentCode: widget.resumableAssignmentCode,
                onResumeTap: widget.onResumeTap,
                onViewAnalysisTap: widget.onViewAnalysisTap,
              ),
              StudentAssignmentsList(
                documents: widget.completedDocs, // Pass list directly
                resumableAssignmentCode: widget.resumableAssignmentCode,
                onResumeTap: widget.onResumeTap,
                onViewAnalysisTap: widget.onViewAnalysisTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}