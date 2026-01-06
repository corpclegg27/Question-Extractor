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
import 'package:study_smart_qc/widgets/expandable_image.dart';
import 'package:study_smart_qc/widgets/question_input_widget.dart';

class TestScreen extends StatefulWidget {
  final String sourceId;
  final String assignmentCode;
  final List<Question> questions;
  final int timeLimitInMinutes;
  final TestMode testMode;

  const TestScreen({
    super.key,
    required this.questions,
    required this.timeLimitInMinutes,
    this.sourceId = '',
    this.assignmentCode = 'PRAC',
    this.testMode = TestMode.test,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  late final PageController _pageController;
  late final Timer _timer;
  late Duration _overallTimeCounter;
  bool _isPaused = false;

  // State Maps
  final Map<int, AnswerState> _answerStates = {};
  final Map<int, int> _visitCounts = {};
  final Map<int, Stopwatch> _timeTrackers = {};

  int _currentPage = 0;
  bool _isAnswerChecked = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // 1. Timer Setup
    if (widget.testMode == TestMode.test) {
      _overallTimeCounter = Duration(minutes: widget.timeLimitInMinutes);
    } else {
      _overallTimeCounter = Duration.zero;
    }

    // 2. Initialize Questions
    for (int i = 0; i < widget.questions.length; i++) {
      _answerStates[i] = AnswerState(status: AnswerStatus.notVisited);
      _visitCounts[i] = 0;
      _timeTrackers[i] = Stopwatch();
    }

    // Initialize first page
    _onPageChanged(0, fromInit: true);
    _startTimer();
  }

  // --- TIMER LOGIC ---
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

    if (_timeTrackers.containsKey(page)) {
      _timeTrackers[page]!.start();
    }
  }

  // Internal toggle helper
  void _togglePauseState() {
    setState(() => _isPaused = !_isPaused);
    if (_isPaused) {
      _timeTrackers[_currentPage]?.stop();
    } else {
      _timeTrackers[_currentPage]?.start();
    }
  }

  // UI Dialog for Pause
  void _showPauseDialog() {
    _togglePauseState(); // Pause the timer

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                  _togglePauseState(); // Resume timer
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Resume',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // --- HELPER: COMPARE ANSWERS (Handles Lists & Maps) ---
  bool _checkEquality(dynamic userAns, dynamic correctAns) {
    if (userAns == null || correctAns == null) return false;

    // 1. Simple String/Number comparison
    if (userAns is String || userAns is num) {
      return userAns.toString().trim().toLowerCase() ==
          correctAns.toString().trim().toLowerCase();
    }

    // 2. List Comparison (Multi-Correct) - Order doesn't matter
    if (userAns is List && correctAns is List) {
      if (userAns.length != correctAns.length) return false;
      final userSet = userAns.map((e) => e.toString()).toSet();
      final correctSet = correctAns.map((e) => e.toString()).toSet();
      return userSet.containsAll(correctSet);
    }

    // 3. Map Comparison (Matrix)
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

  // --- ACTION HANDLERS ---

  void _checkAnswer() {
    final state = _answerStates[_currentPage]!;
    bool isEmpty = false;
    if (state.userAnswer == null) isEmpty = true;
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty)
      isEmpty = true;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty)
      isEmpty = true;
    if (state.userAnswer is Map && (state.userAnswer as Map).isEmpty)
      isEmpty = true;

    if (isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select an answer first!")));
      return;
    }
    setState(() {
      _isAnswerChecked = true;
    });
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
            const Text("Solution",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 10),
            Text("Correct Answer: ${q.correctAnswer}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 10),
            if (q.solutionUrl != null)
              Expanded(
                  child:
                  Center(child: ExpandableImage(imageUrl: q.solutionUrl!)))
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
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty)
      hasAnswer = false;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty)
      hasAnswer = false;

    if (hasAnswer) {
      setState(() => state.status = AnswerStatus.answered);
    } else {
      setState(() => state.status = AnswerStatus.notAnswered);
    }
    _moveToNextPage();
  }

  void _handleSaveAndMarkForReview() {
    final state = _answerStates[_currentPage]!;
    bool hasAnswer = state.userAnswer != null;
    if (state.userAnswer is String && (state.userAnswer as String).isEmpty)
      hasAnswer = false;
    if (state.userAnswer is List && (state.userAnswer as List).isEmpty)
      hasAnswer = false;

    if (hasAnswer) {
      setState(() => state.status = AnswerStatus.answeredAndMarked);
      _moveToNextPage();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select an answer to Save & Mark for Review")),
      );
    }
  }

  void _handleMarkForReviewAndNext() {
    setState(() {
      _answerStates[_currentPage]!.status = AnswerStatus.markedForReview;
    });
    _moveToNextPage();
  }

  void _handleClearResponse() {
    setState(() {
      _answerStates[_currentPage]!.userAnswer = null;
      _answerStates[_currentPage]!.status = AnswerStatus.notAnswered;
      _isAnswerChecked = false;
    });
  }

  void _moveToNextPage() {
    if (_currentPage < widget.questions.length - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text("You are on the last question. Click Submit to finish.")),
      );
    }
  }

  // =================================================================
  //  CORE SUBMISSION LOGIC (Updated for Smart Analysis Integration)
  // =================================================================
  void _handleSubmit() async {
    // 1. Stop Timers
    _timer.cancel();
    _timeTrackers.values.forEach((sw) => sw.stop());

    // 2. Show Loading Indicator (Critical for UX during async processing)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // 3. Prepare Local Data (Basic data needed for submission)
    Map<String, ResponseObject> initialResponses = {};
    for (int i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      final state = _answerStates[i]!;
      String finalStatus = 'SKIPPED';

      if (state.status == AnswerStatus.answered || state.status == AnswerStatus.answeredAndMarked) {
        final isCorrect = _checkEquality(state.userAnswer, question.correctAnswer);
        finalStatus = isCorrect ? 'CORRECT' : 'INCORRECT';
      } else if (state.status == AnswerStatus.markedForReview) {
        finalStatus = 'REVIEW';
      }

      // Metadata populated from Question model
      initialResponses[question.id] = ResponseObject(
        status: finalStatus,
        selectedOption: state.userAnswer.toString(),
        correctOption: question.correctAnswer.toString(),
        timeSpent: _timeTrackers[i]!.elapsed.inSeconds,
        visitCount: _visitCounts[i] ?? 0,
        q_no: i + 1,

        // Metadata
        exam: question.exam,
        subject: question.subject,
        chapter: question.chapter,
        topic: question.topic,
        topicL2: question.topicL2,

        // IDs
        chapterId: question.chapterId,
        topicId: question.topicId,
        topicL2Id: question.topicL2Id,

        pyq: question.isPyq ? 'Yes' : 'No',
        difficultyTag: question.difficulty,
      );
    }

    // 4. Calculate final stats
    final score = (initialResponses.values.where((r) => r.status == 'CORRECT').length * 4) -
        (initialResponses.values.where((r) => r.status == 'INCORRECT').length * 1);

    final finalTime = widget.testMode == TestMode.test
        ? (Duration(minutes: widget.timeLimitInMinutes) - _overallTimeCounter).inSeconds
        : _overallTimeCounter.inSeconds;

    // 5. CALL SERVICE & AWAIT ENRICHED RESULT
    // The service returns the AttemptModel containing the generated smartTimeAnalysisTags
    final enrichedAttempt = await TestOrchestrationService().submitAttempt(
      sourceId: widget.sourceId,
      assignmentCode: widget.assignmentCode,
      mode: widget.testMode == TestMode.test ? 'Test' : 'Practice',
      questions: widget.questions,
      score: score,
      timeTakenSeconds: finalTime,
      responses: initialResponses,
    );

    // 6. Navigate to Results
    if (mounted) {
      // Remove Loading Indicator
      Navigator.pop(context);

      if (enrichedAttempt != null) {
        // Construct Result using the ENRICHED responses (containing the calculated smart tags)
        final result = TestResult(
          attemptId: enrichedAttempt.id,
          questions: widget.questions,
          answerStates: _answerStates,
          timeTaken: Duration(seconds: finalTime),
          totalMarks: widget.questions.length * 4,
          responses: enrichedAttempt.responses, // <--- KEY: Using service data with tags
        );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => ResultsScreen(result: result)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Error saving attempt. Please check internet connection."))
        );
      }
    }
  }

  // --- CONFIRMATION DIALOGS ---
  Future<bool> _onWillPop() async {
    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quit Test?'),
        content: const Text(
            'If you quit now, your progress will be lost. Are you sure?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, Resume')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Quit'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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

  // --- UI BUILDERS ---

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

          // 1. CLOSE BUTTON (Top-Left)
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

          // 2. CENTER TITLE (Timer Pill)
          title: _buildOverallTimerWidget(),

          // 3. ACTIONS (Pause + Submit)
          actions: [
            // Pause Button: ONLY if in Practice Mode
            if (widget.testMode == TestMode.practice)
              IconButton(
                onPressed: _showPauseDialog,
                icon:
                const Icon(Icons.pause_circle_filled, color: Colors.white),
                tooltip: "Pause",
              ),

            // Submit Button
            TextButton(
              onPressed: _showSubmitConfirmationDialog,
              child: const Text('Submit',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
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
                // Disable swiping when paused
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
                            Text('Q.${index + 1}',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
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

                        if (widget.testMode == TestMode.practice &&
                            _isAnswerChecked)
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
        style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildQuestionTimerWidget(int index) {
    final duration = _timeTrackers[index]?.elapsed ?? Duration.zero;
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
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildNTAQuestionPalette() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.grey.shade50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final state = _answerStates[index]!;
          final isCurrent = index == _currentPage;

          BoxShape shape = BoxShape.rectangle;
          Color color = Colors.white;
          Border? border = Border.all(color: Colors.grey.shade300);
          Widget? badge;

          switch (state.status) {
            case AnswerStatus.notVisited:
              color = Colors.white;
              break;
            case AnswerStatus.notAnswered:
              color = Colors.red;
              border = null;
              break;
            case AnswerStatus.answered:
              color = Colors.green;
              border = null;
              break;
            case AnswerStatus.markedForReview:
              shape = BoxShape.circle;
              color = Colors.purple;
              border = null;
              break;
            case AnswerStatus.answeredAndMarked:
              shape = BoxShape.circle;
              color = Colors.purple;
              border = null;
              badge = const Positioned(
                bottom: 0,
                right: 0,
                child: Icon(Icons.check_circle, size: 14, color: Colors.green),
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
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: shape,
                      border: isCurrent
                          ? Border.all(color: Colors.blueAccent, width: 3)
                          : border,
                      borderRadius: shape == BoxShape.rectangle
                          ? BorderRadius.circular(4)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        "${index + 1}",
                        style: TextStyle(
                          color: (color == Colors.white)
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.bold,
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
    final isCorrect =
    _checkEquality(_answerStates[_currentPage]?.userAnswer, q.correctAnswer);

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
            Icon(isCorrect ? Icons.check_circle : Icons.cancel,
                color: isCorrect ? Colors.green : Colors.red),
            const SizedBox(width: 10),
            Text(isCorrect ? "Correct!" : "Incorrect",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? Colors.green : Colors.red)),
          ]),
          const SizedBox(height: 10),
          ElevatedButton(
              onPressed: _showSolution,
              child: const Text("View Full Solution")),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [
        BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, -2))
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
                      style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                      style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                  child: const Text("Clear",
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
                  child: const Text("Save & Next",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}