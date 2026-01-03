// ... existing imports ...
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/question_model.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/models/attempt_model.dart';
import 'package:study_smart_qc/features/analytics/screens/results_screen.dart';
import 'package:study_smart_qc/services/test_orchestration_service.dart';
import 'package:study_smart_qc/models/test_enums.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';

class TestScreen extends StatefulWidget {
  final String sourceId; // The Document ID
  final String assignmentCode; // NEW: The Readable Code (e.g. A7B2)
  final List<Question> questions;
  final int timeLimitInMinutes;
  final TestMode testMode;

  const TestScreen({
    super.key,
    required this.questions,
    required this.timeLimitInMinutes,
    this.sourceId = '',
    this.assignmentCode = 'PRAC', // Default for general practice
    this.testMode = TestMode.test,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  // ... (Keep existing State variables: _pageController, _timer, _answerStates, etc.) ...
  late final PageController _pageController;
  late final Timer _timer;
  late Duration _timeCounter;
  bool _isPaused = false;
  final Map<int, AnswerState> _answerStates = {};
  final Map<String, TextEditingController> _numericalControllers = {};
  int _currentPage = 0;
  final Map<int, int> _visitCounts = {};
  final Map<int, Stopwatch> _timeTrackers = {};
  bool _isAnswerChecked = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    if (widget.testMode == TestMode.test) {
      _timeCounter = Duration(minutes: widget.timeLimitInMinutes);
    } else {
      _timeCounter = Duration.zero;
    }

    for (int i = 0; i < widget.questions.length; i++) {
      _answerStates[i] = AnswerState();
      final q = widget.questions[i];
      if (q.type.trim() == 'Numerical type') {
        _numericalControllers[q.id] = TextEditingController();
      }
      _visitCounts[i] = 0;
      _timeTrackers[i] = Stopwatch();
    }

    _onPageChanged(_currentPage, fromInit: true);
    _startTimer();
  }

  // ... (Keep existing helpers: _startTimer, _togglePause, _onPageChanged) ...

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;
      if (mounted) {
        setState(() {
          if (widget.testMode == TestMode.test) {
            if (_timeCounter.inSeconds > 0) {
              _timeCounter -= const Duration(seconds: 1);
            } else {
              _timer.cancel();
              _handleSubmit();
            }
          } else {
            _timeCounter += const Duration(seconds: 1);
          }
        });
      }
    });
  }

  void _togglePause() {
    setState(() { _isPaused = !_isPaused; });
    if (_isPaused) _timeTrackers[_currentPage]?.stop();
    else _timeTrackers[_currentPage]?.start();
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
    if (_timeTrackers.containsKey(page)) _timeTrackers[page]!.start();
  }

  // ... (Keep _checkAnswer, _showSolution, _handleSaveAndNext, _showSubmitConfirmationDialog) ...

  void _checkAnswer() {
    final q = widget.questions[_currentPage];
    final state = _answerStates[_currentPage]!;

    String? answer = (q.type.trim() == 'Single Correct')
        ? state.userAnswer
        : _numericalControllers[q.id]?.text;

    if (answer == null || answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select an answer first!")));
      return;
    }
    setState(() {
      _isAnswerChecked = true;
      _answerStates[_currentPage]?.status = AnswerStatus.answered;
    });
  }

  void _showSolution() {
    final q = widget.questions[_currentPage];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(ctx).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Solution", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 10),
            Text("Correct Answer: ${q.correctAnswer}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 10),
            if (q.solutionUrl != null)
              Expanded(child: Image.network(q.solutionUrl!))
            else
              const Text("No image solution available."),
          ],
        ),
      ),
    );
  }

  void _handleSaveAndNext() {
    if (_currentPage < widget.questions.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
    } else {
      _showSubmitConfirmationDialog();
    }
  }

  Future<void> _showSubmitConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Submit Session?'),
          content: Text(widget.testMode == TestMode.practice
              ? 'Finish practice session and save progress?'
              : 'Are you sure you want to end the test?'),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(child: const Text('Submit'), onPressed: () {
              Navigator.of(context).pop();
              _handleSubmit();
            }),
          ],
        );
      },
    );
  }

  // --- UPDATED SUBMISSION ---
  void _handleSubmit() async {
    _timer.cancel();
    _timeTrackers.values.forEach((sw) => sw.stop());

    Map<String, ResponseObject> responses = {};

    for (int i = 0; i < widget.questions.length; i++) {
      final question = widget.questions[i];
      final state = _answerStates[i]!;
      String finalStatus = 'SKIPPED';
      String? finalAnswer = state.userAnswer;

      if (state.status == AnswerStatus.answered || state.status == AnswerStatus.answeredAndMarked) {
        final isCorrect = finalAnswer?.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase();
        finalStatus = isCorrect ? 'CORRECT' : 'INCORRECT';
      } else if (state.status == AnswerStatus.markedForReview) {
        finalStatus = 'REVIEW';
      }

      responses[question.id] = ResponseObject(
        status: finalStatus,
        selectedOption: finalAnswer,
        correctOption: question.correctAnswer,
        timeSpent: _timeTrackers[i]!.elapsed.inSeconds,
        visitCount: _visitCounts[i] ?? 0,
        q_no: i + 1,
      );
    }

    final score = (responses.values.where((r) => r.status == 'CORRECT').length * 4) -
        (responses.values.where((r) => r.status == 'INCORRECT').length * 1);

    await TestOrchestrationService().submitAttempt(
      sourceId: widget.sourceId, // Doc ID
      assignmentCode: widget.assignmentCode, // Readable Code
      mode: widget.testMode == TestMode.test ? 'Test' : 'Practice', // Readable Mode
      questions: widget.questions,
      score: score,
      timeTakenSeconds: widget.testMode == TestMode.test
          ? (Duration(minutes: widget.timeLimitInMinutes) - _timeCounter).inSeconds
          : _timeCounter.inSeconds,
      responses: responses,
    );

    if (mounted) {
      final result = TestResult(
        questions: widget.questions,
        answerStates: _answerStates,
        timeTaken: widget.testMode == TestMode.test
            ? Duration(minutes: widget.timeLimitInMinutes) - _timeCounter
            : _timeCounter,
        totalMarks: widget.questions.length * 4,
        responses: responses,
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => ResultsScreen(result: result)),
      );
    }
  }

  // ... (Keep UI Builders: build, _buildTimerWidget, etc. - ensure radio/text fields update state!) ...
  // Re-pasting UI builders just to be safe and ensure the fix from previous turn is included

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTimerWidget(),
        centerTitle: true,
        backgroundColor: widget.testMode == TestMode.practice ? Colors.deepPurple.shade50 : Colors.deepPurple,
        foregroundColor: widget.testMode == TestMode.practice ? Colors.deepPurple : Colors.white,
        actions: [
          if (widget.testMode == TestMode.practice)
            IconButton(
              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
              onPressed: _togglePause,
            ),
          TextButton(
            onPressed: _showSubmitConfirmationDialog,
            child: Text('Submit', style: TextStyle(color: widget.testMode == TestMode.practice ? Colors.deepPurple : Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildCompactQuestionPalette(),
              const Divider(height: 1),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: _isPaused ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                  onPageChanged: _onPageChanged,
                  itemCount: widget.questions.length,
                  itemBuilder: (context, index) {
                    final q = widget.questions[index];
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Q.${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          if (q.imageUrl.isNotEmpty)
                            InteractiveViewer(maxScale: 4.0, child: Image.network(q.imageUrl)),
                          const SizedBox(height: 20),
                          if (q.type.trim() == 'Single Correct')
                            _buildScqOptions(q)
                          else
                            _buildNumericalInput(q),

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
          if (_isPaused)
            Container(
              color: Colors.black.withOpacity(0.8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pause_circle_filled, size: 80, color: Colors.white),
                    const SizedBox(height: 20),
                    const Text("Session Paused", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _togglePause,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                      child: const Text("Resume"),
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildTimerWidget() {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(_timeCounter.inMinutes.remainder(60));
    final seconds = twoDigits(_timeCounter.inSeconds.remainder(60));
    final hours = twoDigits(_timeCounter.inHours);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: widget.testMode == TestMode.practice ? Colors.deepPurple : Colors.white),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: widget.testMode == TestMode.practice ? Colors.deepPurple : Colors.white),
          const SizedBox(width: 4),
          Text("$hours:$minutes:$seconds", style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildCompactQuestionPalette() {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.questions.length,
        itemBuilder: (context, index) {
          final state = _answerStates[index]!;
          final isCurrent = index == _currentPage;
          return Container(
            width: 40, margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: state.status.color,
                borderRadius: BorderRadius.circular(4),
                border: isCurrent ? Border.all(width: 2) : null
            ),
            child: Center(child: Text("${index + 1}", style: const TextStyle(color: Colors.white))),
          );
        },
      ),
    );
  }

  Widget _buildScqOptions(Question q) {
    return Column(children: ['A','B','C','D'].map((opt) => RadioListTile<String>(
      title: Text(opt),
      value: opt,
      groupValue: _answerStates[_currentPage]?.userAnswer,
      onChanged: _isPaused ? null : (String? v) {
        setState(() {
          _answerStates[_currentPage]?.userAnswer = v;
          _answerStates[_currentPage]?.status = AnswerStatus.answered; // Explicitly mark answered
        });
      },
    )).toList());
  }

  Widget _buildNumericalInput(Question q) {
    return TextField(
      controller: _numericalControllers[q.id],
      enabled: !_isPaused,
      onChanged: (v) {
        setState(() {
          _answerStates[_currentPage]?.userAnswer = v;
          _answerStates[_currentPage]?.status = v.isNotEmpty ? AnswerStatus.answered : AnswerStatus.notAnswered;
        });
      },
      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Answer"),
    );
  }

  Widget _buildFeedbackUI(Question q) {
    final userAnswer = _answerStates[_currentPage]?.userAnswer;
    final isCorrect = userAnswer?.trim().toLowerCase() == q.correctAnswer.trim().toLowerCase();

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
            Text(isCorrect ? "Correct!" : "Incorrect", style: TextStyle(fontWeight: FontWeight.bold, color: isCorrect ? Colors.green : Colors.red)),
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
      color: Colors.white,
      child: Row(
        children: [
          if (widget.testMode == TestMode.practice)
            Expanded(
              child: ElevatedButton(
                onPressed: _checkAnswer,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                child: const Text("Check Answer"),
              ),
            ),

          if (widget.testMode == TestMode.practice) const SizedBox(width: 10),

          Expanded(
            child: ElevatedButton(
              onPressed: _handleSaveAndNext,
              child: Text(_currentPage == widget.questions.length - 1 ? 'Finish' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}