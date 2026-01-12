// lib/features/test_taking/screens/test_screen.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 1. IMPORT MODELS
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';

// 2. IMPORT SCREENS & SERVICES
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/services/local_session_service.dart';
import 'package:study_smart_qc/widgets/expandable_image.dart';
import 'package:study_smart_qc/widgets/question_input_widget.dart';

class TestScreen extends StatefulWidget {
  final String sourceId;
  final String assignmentCode;

  // Title
  final String title;

  // NEW FIELD: Only Single Attempt Flag
  final bool onlySingleAttempt;

  final List<Question> questions;
  final int timeLimitInMinutes;
  final TestMode testMode;

  final int? resumedTimerSeconds;
  final int? resumedPageIndex;
  final Map<String, ResponseObject>? resumedResponses;

  const TestScreen({
    super.key,
    required this.questions,
    required this.timeLimitInMinutes,
    this.sourceId = '',
    this.assignmentCode = 'PRAC',
    this.title = 'Practice Test',

    // Initialize new field
    this.onlySingleAttempt = false,

    this.testMode = TestMode.test,
    this.resumedTimerSeconds,
    this.resumedPageIndex,
    this.resumedResponses,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> with WidgetsBindingObserver {
  late final PageController _pageController;
  late final Timer _timer;
  late Duration _overallTimeCounter;
  bool _isPaused = false;

  // ADDED: Scroll Controller for NTA Palette
  final ScrollController _paletteController = ScrollController();

  final Map<int, AnswerState> _answerStates = {};
  final Map<int, int> _visitCounts = {};
  final Map<int, Stopwatch> _timeTrackers = {};
  final Map<int, int> _accumulatedTime = {};

  int _currentPage = 0;
  bool _isAnswerChecked = false;

  final LocalSessionService _localSessionService = LocalSessionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentPage = widget.resumedPageIndex ?? 0;
    _pageController = PageController(initialPage: _currentPage);

    if (widget.resumedTimerSeconds != null) {
      _overallTimeCounter = Duration(seconds: widget.resumedTimerSeconds!);
    } else {
      if (widget.testMode == TestMode.test) {
        _overallTimeCounter = Duration(minutes: widget.timeLimitInMinutes);
      } else {
        _overallTimeCounter = Duration.zero;
      }
    }

    for (int i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      _visitCounts[i] = 0;
      _timeTrackers[i] = Stopwatch();
      _accumulatedTime[i] = 0;

      AnswerState newState = AnswerState(status: AnswerStatus.notVisited);

      if (widget.resumedResponses != null &&
          widget.resumedResponses!.containsKey(question.id)) {

        final savedResponse = widget.resumedResponses![question.id]!;
        newState.userAnswer = savedResponse.selectedOption;
        _accumulatedTime[i] = savedResponse.timeSpent;

        switch (savedResponse.status) {
          case 'REVIEW':
            newState.status = AnswerStatus.markedForReview;
            break;
          case 'REVIEW_ANSWERED':
            newState.status = AnswerStatus.answeredAndMarked;
            break;
          case 'ANSWERED':
          case 'CORRECT':
          case 'INCORRECT':
            newState.status = AnswerStatus.answered;
            break;
          case 'SKIPPED':
            newState.status = AnswerStatus.notAnswered;
            break;
          default:
            if (savedResponse.selectedOption != null) {
              newState.status = AnswerStatus.answered;
            }
        }
        _visitCounts[i] = savedResponse.visitCount;
      }
      _answerStates[i] = newState;
    }

    _onPageChanged(_currentPage, fromInit: true);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _pageController.dispose();
    _paletteController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _triggerLocalSave();
    }
  }

  Future<void> _triggerLocalSave() async {
    Map<String, ResponseObject> currentResponses = _buildResponseMap();
    await _localSessionService.saveSession(
      assignmentCode: widget.assignmentCode,
      mode: widget.testMode == TestMode.test ? 'Test' : 'Practice',
      testId: widget.sourceId,
      totalQuestions: widget.questions.length,
      currentTimerValue: _overallTimeCounter.inSeconds,
      currentQuestionIndex: _currentPage,
      responses: currentResponses,
    );
  }

  Map<String, ResponseObject> _buildResponseMap() {
    Map<String, ResponseObject> responses = {};
    for (int i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      final state = _answerStates[i]!;

      final int totalTimeSpent = (_accumulatedTime[i] ?? 0) + (_timeTrackers[i]?.elapsed.inSeconds ?? 0);

      String statusString = 'SKIPPED';
      if (state.status == AnswerStatus.answered) {
        final isCorrect = _checkEquality(state.userAnswer, question.correctAnswer);
        statusString = isCorrect ? 'CORRECT' : 'INCORRECT';
      } else if (state.status == AnswerStatus.answeredAndMarked) {
        statusString = 'REVIEW_ANSWERED';
      } else if (state.status == AnswerStatus.markedForReview) {
        statusString = 'REVIEW';
      } else if (state.status == AnswerStatus.notAnswered) {
        statusString = 'SKIPPED';
      }

      responses[question.id] = ResponseObject(
        status: statusString,
        selectedOption: state.userAnswer,
        correctOption: question.correctAnswer.toString(),
        timeSpent: totalTimeSpent,
        visitCount: _visitCounts[i] ?? 0,
        q_no: i + 1,
        exam: question.exam,
        subject: question.subject,
        chapter: question.chapter,
        topic: question.topic,
        topicL2: question.topicL2,
        chapterId: question.chapterId,
        topicId: question.topicId,
        topicL2Id: question.topicL2Id,
        pyq: question.isPyq ? 'Yes' : 'No',
        difficultyTag: question.difficulty,
      );
    }
    return responses;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;
      if (mounted) {
        setState(() {
          if (widget.testMode == TestMode.test) {
            if (_overallTimeCounter.inSeconds > 0) {
              _overallTimeCounter -= const Duration(seconds: 1);
            } else {
              _timer.cancel();
              _handleSubmit();
            }
          } else {
            _overallTimeCounter += const Duration(seconds: 1);
          }
        });
      }
    });
  }

  void _onPageChanged(int page, {bool fromInit = false}) {
    if (!fromInit && _timeTrackers.containsKey(_currentPage)) {
      _timeTrackers[_currentPage]!.stop();
    }
    setState(() {
      _currentPage = page;
      _isAnswerChecked = false;
      _visitCounts[page] = (_visitCounts[page] ?? 0) + 1;
      if (_answerStates[page]?.status == AnswerStatus.notVisited) {
        _answerStates[page]?.status = AnswerStatus.notAnswered;
      }
    });

    if (_paletteController.hasClients) {
      double targetOffset = (page * 60.0) - (MediaQuery.of(context).size.width / 2) + 30;
      if (targetOffset < 0) targetOffset = 0;

      _paletteController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (_timeTrackers.containsKey(page)) {
      _timeTrackers[page]!.start();
    }
    if(!fromInit) _triggerLocalSave();
  }

  void _togglePauseState() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _timeTrackers[_currentPage]?.stop();
      _triggerLocalSave();
    } else {
      _timeTrackers[_currentPage]?.start();
    }
  }

  void _showPauseDialog() {
    _togglePauseState();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: const [
              Icon(Icons.pause_circle_filled, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text('Paused'),
            ],
          ),
          content: const Text(
            'Test timer is paused. Click Resume to continue.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _togglePauseState();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Resume',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _checkEquality(dynamic userAns, dynamic correctAns) {
    if (userAns == null || correctAns == null) return false;
    if (userAns is String || userAns is num) {
      return userAns.toString().trim().toLowerCase() ==
          correctAns.toString().trim().toLowerCase();
    }
    if (userAns is List && correctAns is List) {
      if (userAns.length != correctAns.length) return false;
      final userSet = userAns.map((e) => e.toString()).toSet();
      final correctSet = correctAns.map((e) => e.toString()).toSet();
      return userSet.containsAll(correctSet);
    }
    if (userAns is Map && correctAns is Map) {
      if (userAns.length != correctAns.length) return false;
      for (var key in userAns.keys) {
        if (!correctAns.containsKey(key)) return false;
        if (!_checkEquality(userAns[key], correctAns[key])) return false;
      }
      return true;
    }
    return userAns == correctAns;
  }

  void _checkAnswer() {
    final state = _answerStates[_currentPage]!;
    bool isEmpty = false;
    if (state.userAnswer == null) isEmpty = true;
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty) isEmpty = true;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty) isEmpty = true;
    if (state.userAnswer is Map && (state.userAnswer as Map).isEmpty) isEmpty = true;

    if (isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please select an answer first!")));
      }
      return;
    }
    setState(() {
      _isAnswerChecked = true;
    });
    _triggerLocalSave();
  }

  void _showSolution() {
    final q = widget.questions[_currentPage];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Solution", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 10),
            Text("Correct Answer: ${q.correctAnswer}",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 10),
            if (q.solutionUrl != null)
              Expanded(child: Center(child: ExpandableImage(imageUrl: q.solutionUrl!)))
            else
              const Text("No image solution available."),
          ],
        ),
      ),
    );
  }

  void _handleSaveAndNext() {
    final state = _answerStates[_currentPage]!;
    bool hasAnswer = state.userAnswer != null;
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty) hasAnswer = false;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty) hasAnswer = false;

    if (hasAnswer) {
      setState(() => state.status = AnswerStatus.answered);
    } else {
      setState(() => state.status = AnswerStatus.notAnswered);
    }

    _triggerLocalSave().then((_) {
      if (mounted) _moveToNextPage();
    });
  }

  void _handleSaveAndMarkForReview() {
    final state = _answerStates[_currentPage]!;
    bool hasAnswer = state.userAnswer != null;
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty) hasAnswer = false;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty) hasAnswer = false;

    if (hasAnswer) {
      setState(() => state.status = AnswerStatus.answeredAndMarked);
      _triggerLocalSave().then((_) {
        if (mounted) _moveToNextPage();
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select an answer to Save & Mark for Review")),
        );
      }
    }
  }

  void _handleMarkForReviewAndNext() {
    setState(() {
      _answerStates[_currentPage]!.status = AnswerStatus.markedForReview;
    });
    _triggerLocalSave().then((_) {
      if (mounted) _moveToNextPage();
    });
  }
  void _handleClearResponse() {
    setState(() {
      _answerStates[_currentPage]!.userAnswer = null;
      _answerStates[_currentPage]!.status = AnswerStatus.notAnswered;
      _isAnswerChecked = false;
    });
    _triggerLocalSave();
  }

  void _moveToNextPage() {
    if (_currentPage < widget.questions.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You are on the last question. Click Submit to finish.")),
        );
      }
    }
  }

  // =================================================================
  //  CORE SUBMISSION LOGIC
  // =================================================================
  void _handleSubmit() async {
    _timer.cancel();
    _timeTrackers.values.forEach((sw) => sw.stop());

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // FETCH AUTHORITATIVE DATA FOR RESUMED SESSIONS
    String actualTitle = widget.title;
    int actualTimeLimit = widget.timeLimitInMinutes;

    if (widget.sourceId.isNotEmpty) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('questions_curation').doc(widget.sourceId).get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['title'] != null) actualTitle = data['title'];
          if (data['timeLimitMinutes'] != null) actualTimeLimit = data['timeLimitMinutes'];
        } else {
          doc = await FirebaseFirestore.instance.collection('tests').doc(widget.sourceId).get();
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['testName'] != null) actualTitle = data['testName'];
            if (data['config'] != null && data['config'] is Map) {
              final config = data['config'] as Map<String, dynamic>;
              if (config['durationSeconds'] != null) {
                actualTimeLimit = (config['durationSeconds'] / 60).round();
              }
            }
          }
        }
      } catch (e) {
        print("Error fetching source details for submission: $e");
      }
    }

    Map<String, ResponseObject> initialResponses = _buildResponseMap();

    final score = (initialResponses.values.where((r) => r.status == 'CORRECT').length * 4) -
        (initialResponses.values.where((r) => r.status == 'INCORRECT').length * 1);

    final finalTime = widget.testMode == TestMode.test
        ? (Duration(minutes: actualTimeLimit) - _overallTimeCounter).inSeconds
        : _overallTimeCounter.inSeconds;

    final int? limitToSave = widget.testMode == TestMode.test
        ? actualTimeLimit
        : null;

    final enrichedAttempt = await TestOrchestrationService().submitAttempt(
      sourceId: widget.sourceId,
      assignmentCode: widget.assignmentCode,
      title: actualTitle,
      onlySingleAttempt: widget.onlySingleAttempt,
      mode: widget.testMode == TestMode.test ? 'Test' : 'Practice',
      questions: widget.questions,
      score: score,
      timeTakenSeconds: finalTime,
      responses: initialResponses,
      timeLimitMinutes: limitToSave,
    );

    if (mounted) {
      Navigator.pop(context);

      if (enrichedAttempt != null) {
        await _localSessionService.clearSession();

        final result = TestResult(
          attemptId: enrichedAttempt.id,
          questions: widget.questions,
          answerStates: _answerStates,
          timeTaken: Duration(seconds: finalTime),
          totalMarks: widget.questions.length * 4,
          responses: enrichedAttempt.responses,

          // UPDATED: Pass the limit inside the Model as requested
          timeLimitMinutes: limitToSave,
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ResultsScreen(result: result),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error uploading. Progress saved locally. Check internet."))
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quit Test?'),
        content: const Text('If you quit now, your progress will be saved locally. You can resume later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, Resume')),
          TextButton(
            onPressed: () {
              _triggerLocalSave().then((_) => Navigator.pop(ctx, true));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Quit (Save & Exit)'),
          ),
        ],
      ),
    );
    return shouldPop ?? false;
  }

  Future<void> _showSubmitConfirmationDialog() async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit Test'),
        content: const Text('Are you sure you want to finish the test?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleSubmit();
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              final shouldExit = await _onWillPop();
              if (shouldExit && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: _buildOverallTimerWidget(),
          actions: [
            if (widget.testMode == TestMode.practice)
              IconButton(
                onPressed: _showPauseDialog,
                icon: const Icon(Icons.pause_circle_filled, color: Colors.white),
                tooltip: "Pause",
              ),
            TextButton(
              onPressed: _showSubmitConfirmationDialog,
              child: const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            _buildNTAQuestionPalette(),
            const Divider(height: 1),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: _isPaused
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                onPageChanged: (index) => _onPageChanged(index),
                itemCount: widget.questions.length,
                itemBuilder: (context, index) {
                  final q = widget.questions[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Q.${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            _buildQuestionTimerWidget(index),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (q.imageUrl.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ExpandableImage(imageUrl: q.imageUrl),
                          ),
                        const SizedBox(height: 20),
                        QuestionInputWidget(
                          question: q,
                          currentAnswer: _answerStates[index]?.userAnswer,
                          onAnswerChanged: (newAnswer) {
                            if (!_isPaused) {
                              setState(() {
                                _answerStates[index]?.userAnswer = newAnswer;
                                if (widget.testMode == TestMode.practice) {
                                  _isAnswerChecked = false;
                                }
                              });
                            }
                          },
                        ),
                        if (widget.testMode == TestMode.practice && _isAnswerChecked)
                          _buildFeedbackUI(q),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildOverallTimerWidget() {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(_overallTimeCounter.inMinutes.remainder(60));
    final seconds = twoDigits(_overallTimeCounter.inSeconds.remainder(60));
    final hours = twoDigits(_overallTimeCounter.inHours);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade700,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        "$hours:$minutes:$seconds",
        style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildQuestionTimerWidget(int index) {
    final currentElapsed = _timeTrackers[index]?.elapsed.inSeconds ?? 0;
    final totalSeconds = (_accumulatedTime[index] ?? 0) + currentElapsed;
    final duration = Duration(seconds: totalSeconds);

    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_filled, size: 16, color: Colors.black54),
          const SizedBox(width: 5),
          Text(
            "$minutes:$seconds",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildNTAQuestionPalette() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: ListView.builder(
        controller: _paletteController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final state = _answerStates[index]!;
          final isCurrent = index == _currentPage;
          BoxShape shape = BoxShape.rectangle;
          Color fillColor = Colors.white;
          Color textColor = Colors.black;
          Border? border = Border.all(color: Colors.grey.shade300);
          Widget? badge;

          switch (state.status) {
            case AnswerStatus.notVisited:
              fillColor = Colors.white;
              textColor = Colors.black;
              border = Border.all(color: Colors.grey.shade400);
              shape = BoxShape.rectangle;
              break;
            case AnswerStatus.notAnswered:
              fillColor = Colors.red.shade600;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.rectangle;
              break;
            case AnswerStatus.answered:
              fillColor = Colors.green.shade600;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.rectangle;
              break;
            case AnswerStatus.markedForReview:
              fillColor = Colors.purple.shade700;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.circle;
              break;
            case AnswerStatus.answeredAndMarked:
              fillColor = Colors.purple.shade700;
              textColor = Colors.white;
              border = null;
              shape = BoxShape.circle;
              badge = Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 12, color: Colors.green),
                ),
              );
              break;
          }

          return GestureDetector(
            onTap: () => _pageController.jumpToPage(index),
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fillColor,
                      shape: shape,
                      border: isCurrent
                          ? Border.all(color: Colors.blueAccent, width: 3)
                          : border,
                      borderRadius: shape == BoxShape.rectangle
                          ? BorderRadius.circular(4)
                          : null,
                      boxShadow: isCurrent
                          ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        "${index + 1}",
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  if (badge != null) badge,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeedbackUI(Question q) {
    final isCorrect = _checkEquality(_answerStates[_currentPage]?.userAnswer, q.correctAnswer);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCorrect ? Colors.green : Colors.red),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red),
            const SizedBox(width: 10),
            Text(isCorrect ? "Correct!" : "Incorrect",
                style: TextStyle(fontWeight: FontWeight.bold, color: isCorrect ? Colors.green : Colors.red)),
          ]),
          const SizedBox(height: 10),
          ElevatedButton(onPressed: _showSolution, child: const Text("View Full Solution")),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(color: Colors.grey.shade200, blurRadius: 4, offset: const Offset(0, -2))
      ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.testMode == TestMode.practice)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _checkAnswer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Check Answer"),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleSaveAndMarkForReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text("Save & Mark Review",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleMarkForReviewAndNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.purple,
                    side: const BorderSide(color: Colors.purple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: const Text("Mark Review & Next",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _handleClearResponse,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text("Clear", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _handleSaveAndNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Save & Next", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}