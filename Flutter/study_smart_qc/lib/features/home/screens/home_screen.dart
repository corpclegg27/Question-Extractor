// lib/features/home/screens/home_screen.dart
// Description: Main Dashboard.
// UPDATED: Used IndexedStack to save reads, but passes 'isVisible' to trigger animations.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// MODELS
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/marking_configuration.dart';

// SCREENS & WIDGETS
import 'package:study_smart_qc/features/auth/screens/auth_page.dart';
import 'package:study_smart_qc/features/auth/screens/auth_wrapper.dart';
import 'package:study_smart_qc/features/student/widgets/student_assignments_list.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_curation_screen.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_history_screen.dart';
import 'package:study_smart_qc/features/test_taking/screens/test_screen.dart';
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

  Future<void> _refreshState() async {
    await _fetchUserData();
    await _checkPendingSession();
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

  String? get _pendingAssignmentCode {
    if (!_hasPendingSession || _pendingSessionData == null) return null;
    return _pendingSessionData!['meta']['assignmentCode'];
  }

  // ---------------------------------------------------------------------------
  //  RESUME LOGIC
  // ---------------------------------------------------------------------------
  // (Keeping existing resume logic intact)
  Future<void> _checkPendingSession() async {
    final hasSession = await _localSessionService.hasPendingSession();
    if (hasSession) {
      final data = await _localSessionService.getSessionData();
      if (mounted) {
        setState(() {
          _hasPendingSession = true;
          _pendingSessionData = data;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _hasPendingSession = false;
          _pendingSessionData = null;
        });
      }
    }
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
      Map<QuestionType, MarkingConfiguration> markingSchemes = {};

      final curationQuery = await FirebaseFirestore.instance
          .collection('questions_curation')
          .where('assignmentCode', isEqualTo: assignmentCode)
          .limit(1)
          .get();

      if (curationQuery.docs.isNotEmpty) {
        final data = curationQuery.docs.first.data();
        qIds = List<String>.from(data['questionIds'] ?? []);
        isSingleAttempt = data['onlySingleAttempt'] ?? false;

        if (data['markingSchemes'] != null && data['markingSchemes'] is Map) {
          (data['markingSchemes'] as Map).forEach((key, value) {
            QuestionType type = _mapStringToType(key.toString());
            if (type != QuestionType.unknown) {
              markingSchemes[type] = MarkingConfiguration.fromMap(Map<String, dynamic>.from(value));
            }
          });
        }
      } else {
        final testQuery = await FirebaseFirestore.instance
            .collection('tests')
            .where('assignmentCode', isEqualTo: assignmentCode)
            .limit(1)
            .get();

        if (testQuery.docs.isNotEmpty) {
          qIds = List<String>.from(testQuery.docs.first.data()['questionIds'] ?? []);
        }
      }

      if (qIds.isNotEmpty) {
        questions = await TestOrchestrationService().getQuestionsByIds(qIds);
      }

      if (questions.isEmpty) throw Exception("Could not retrieve questions.");

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
              timeLimitInMinutes: 0,
              testMode: mode == 'Test' ? TestMode.test : TestMode.practice,
              resumedTimerSeconds: newTime,
              resumedPageIndex: state['currentQuestionIndex'],
              resumedResponses: responseMap,
              title: meta['title'] ?? 'Resumed Session',
              onlySingleAttempt: isSingleAttempt,
              markingSchemes: markingSchemes.isNotEmpty ? markingSchemes : null,
            ),
          ),
        ).then((_) {
          _refreshState();
        });
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error resuming: $e")),
      );
    }
  }

  QuestionType _mapStringToType(String typeString) {
    switch (typeString) {
      case 'Single Correct': return QuestionType.singleCorrect;
      case 'Numerical type': return QuestionType.numerical;
      case 'One or more options correct': return QuestionType.oneOrMoreOptionsCorrect;
      case 'Single Matrix Match': return QuestionType.matrixSingle;
      case 'Multi Matrix Match': return QuestionType.matrixMulti;
      default: return QuestionType.unknown;
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
      markingSchemes: {},
      marksBreakdown: {},
    );

    await _localSessionService.clearSession();

    setState(() {
      _hasPendingSession = false;
      _pendingSessionData = null;
    });

    if (mounted) {
      _fetchUserData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Session submitted successfully.")));
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

    if (_userModel!.role == 'teacher') {
      return Scaffold(
        appBar: AppBar(title: const Text("Teacher Dashboard")),
        drawer: _buildDrawer(context),
        body: const TeacherCurationScreen(),
      );
    }

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

      // [CRITICAL] Use IndexedStack to preserve state (SAVING READS)
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _AssignmentTabContainer(
            user: _userModel!,
            isTest: false,
            resumableAssignmentCode: _pendingAssignmentCode,
            onResumeTap: _handleResumePending,
            onViewAnalysisTap: () => setState(() => _currentTabIndex = 2),
            onRefreshNeeded: _refreshState,
          ),
          _AssignmentTabContainer(
            user: _userModel!,
            isTest: true,
            resumableAssignmentCode: _pendingAssignmentCode,
            onResumeTap: _handleResumePending,
            onViewAnalysisTap: () => setState(() => _currentTabIndex = 2),
            onRefreshNeeded: _refreshState,
          ),
          // [CRITICAL] Pass 'isVisible' flag to trigger animation without re-read
          DisplayResultsForStudentId(
            isVisible: _currentTabIndex == 2,
          ),
        ],
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
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
      case 0: return "Assignments";
      case 1: return "Tests";
      case 2: return "Analysis";
      default: return "ModX by Anup Sir";
    }
  }

  Widget _buildDrawer(BuildContext context) {
    final isTeacher = _userModel?.role == 'teacher';
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_userModel?.displayName ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(_userModel?.email ?? ""),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text((_userModel?.displayName ?? "U")[0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF6200EA))),
            ),
            decoration: const BoxDecoration(color: Color(0xFF6200EA)),
          ),
          if (!isTeacher && _userModel?.studentId != null) ...[
            ListTile(leading: const Icon(Icons.badge_outlined), title: Text("Student ID: ${_userModel!.studentId}"), tileColor: Colors.grey.shade50),
            const Divider(),
          ],
          if (isTeacher) ...[
            const Padding(padding: EdgeInsets.only(left: 16, top: 16, bottom: 8), child: Text("Teacher Tools", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
            ListTile(leading: const Icon(Icons.history_edu), title: const Text('My Curations'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherHistoryScreen())); }),
            ListTile(leading: const Icon(Icons.edit_note), title: const Text('Curate Questions'), onTap: () { Navigator.pop(context); if (ModalRoute.of(context)?.settings.name != '/') Navigator.popUntil(context, (route) => route.isFirst); }),
            ListTile(leading: const Icon(Icons.analytics), title: const Text("Check Student Performance"), onTap: () { Navigator.pop(context); showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const StudentLookupSheet()); }),
            const Divider(),
          ],
          ListTile(leading: const Icon(Icons.person), title: const Text('Profile'), onTap: () { Navigator.pop(context); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Logout', style: TextStyle(color: Colors.red)), onTap: () async { await AuthService().signOut(); if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const AuthPage()), (route) => false); }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
//  WIDGET 1: TAB CONTAINER
// ---------------------------------------------------------------------------

class _AssignmentTabContainer extends StatefulWidget {
  final UserModel user;
  final bool isTest;
  final String? resumableAssignmentCode;
  final Future<void> Function() onResumeTap;
  final VoidCallback onViewAnalysisTap;
  final VoidCallback onRefreshNeeded;

  const _AssignmentTabContainer({
    required this.user,
    required this.isTest,
    required this.resumableAssignmentCode,
    required this.onResumeTap,
    required this.onViewAnalysisTap,
    required this.onRefreshNeeded,
  });

  @override
  State<_AssignmentTabContainer> createState() => _AssignmentTabContainerState();
}

class _AssignmentTabContainerState extends State<_AssignmentTabContainer> with SingleTickerProviderStateMixin {
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
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          height: 48,
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))]),
            labelColor: const Color(0xFF6200EA),
            unselectedLabelColor: Colors.grey.shade600,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicatorPadding: const EdgeInsets.all(4),
            tabs: const [Tab(text: "Pending"), Tab(text: "Completed")],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _PaginatedListWrapper(
                user: widget.user,
                isTest: widget.isTest,
                isCompleted: false,
                resumableAssignmentCode: widget.resumableAssignmentCode,
                onResumeTap: widget.onResumeTap,
                onViewAnalysisTap: widget.onViewAnalysisTap,
                onRefreshNeeded: widget.onRefreshNeeded,
              ),
              _PaginatedListWrapper(
                user: widget.user,
                isTest: widget.isTest,
                isCompleted: true,
                resumableAssignmentCode: widget.resumableAssignmentCode,
                onResumeTap: widget.onResumeTap,
                onViewAnalysisTap: widget.onViewAnalysisTap,
                onRefreshNeeded: widget.onRefreshNeeded,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
//  WIDGET 2: PAGINATED LIST WRAPPER
// ---------------------------------------------------------------------------

class _PaginatedListWrapper extends StatefulWidget {
  final UserModel user;
  final bool isTest;
  final bool isCompleted;
  final String? resumableAssignmentCode;
  final Future<void> Function() onResumeTap;
  final VoidCallback onViewAnalysisTap;
  final VoidCallback onRefreshNeeded;

  const _PaginatedListWrapper({
    required this.user,
    required this.isTest,
    required this.isCompleted,
    required this.resumableAssignmentCode,
    required this.onResumeTap,
    required this.onViewAnalysisTap,
    required this.onRefreshNeeded,
  });

  @override
  State<_PaginatedListWrapper> createState() => _PaginatedListWrapperState();
}

class _PaginatedListWrapperState extends State<_PaginatedListWrapper> {
  final List<QueryDocumentSnapshot> _documents = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _fetchNextBatch();
  }

  Future<void> _fetchNextBatch() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('questions_curation')
          .where('studentId', isEqualTo: widget.user.studentId)
          .where('onlySingleAttempt', isEqualTo: widget.isTest);

      if (widget.isCompleted) {
        query = query.orderBy('createdAt', descending: true);
      } else {
        query = query.orderBy('deadline', descending: false);
      }

      query = query.limit(_limit);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        final filteredDocs = snapshot.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final code = data['assignmentCode'] ?? '';
          final isSubmitted = widget.user.assignmentCodesSubmitted.contains(code);
          return widget.isCompleted ? isSubmitted : !isSubmitted;
        }).toList();

        if (mounted) {
          setState(() {
            _documents.addAll(filteredDocs);
            if (snapshot.docs.length < _limit) _hasMore = false;
          });
        }

        if (filteredDocs.isEmpty && snapshot.docs.length == _limit && _hasMore) {
          _isLoading = false;
          _fetchNextBatch();
        }
      } else {
        if (mounted) setState(() => _hasMore = false);
      }
    } catch (e) {
      print("Pagination Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudentAssignmentsList(
      documents: _documents,
      resumableAssignmentCode: widget.resumableAssignmentCode,
      onResumeTap: widget.onResumeTap,
      onViewAnalysisTap: widget.onViewAnalysisTap,
      isHistoryMode: widget.isCompleted,
      isLoadingMore: _isLoading,
      hasMore: _hasMore,
      onLoadMore: _fetchNextBatch,
      onRefreshNeeded: widget.onRefreshNeeded,
    );
  }
}