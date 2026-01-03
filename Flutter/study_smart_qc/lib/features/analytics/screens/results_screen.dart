import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/nta_test_models.dart';
import 'package:study_smart_qc/models/test_result.dart';
import 'package:study_smart_qc/widgets/solution_detail_sheet.dart';

class ResultsScreen extends StatefulWidget {
  final TestResult result;

  const ResultsScreen({super.key, required this.result});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int correctCount = 0;
  int incorrectCount = 0;
  int unattemptedCount = 0;
  int attemptedCount = 0;
  int marksObtained = 0;
  double accuracy = 0.0;
  double attemptPercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _calculateResults();
  }

  void _calculateResults() {
    int tempCorrect = 0;
    int tempIncorrect = 0;

    widget.result.answerStates.forEach((index, state) {
      if (state.status == AnswerStatus.answered || state.status == AnswerStatus.answeredAndMarked) {
        final question = widget.result.questions[index];
        final userAnswer = state.userAnswer;

        if (userAnswer != null && userAnswer.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase()) {
          tempCorrect++;
        } else {
          tempIncorrect++;
        }
      }
    });

    setState(() {
      correctCount = tempCorrect;
      incorrectCount = tempIncorrect;
      attemptedCount = correctCount + incorrectCount;
      unattemptedCount = widget.result.questions.length - attemptedCount;
      marksObtained = (correctCount * 4) - (incorrectCount * 1);
      accuracy = (attemptedCount > 0) ? (correctCount / attemptedCount) * 100 : 0.0;
      attemptPercentage = (widget.result.questions.isNotEmpty) ? (attemptedCount / widget.result.questions.length) * 100 : 0.0;
    });
  }

  void _showSolutionSheet(int initialIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          child: SolutionDetailSheet(
            result: widget.result,
            initialIndex: initialIndex,
          ),
        );
      },
    );
  }

  String get _formattedTimeTaken {
    final minutes = widget.result.timeTaken.inMinutes.toString().padLeft(2, '0');
    final seconds = (widget.result.timeTaken.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Analysis'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScoreCard(),
            const SizedBox(height: 20),
            _buildStatsRow(),
            const SizedBox(height: 20),
            _buildVisualAnalysis(),
            const SizedBox(height: 20),
            _buildReviewSolutionsGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreCard() {
    double percentage = (marksObtained / widget.result.totalMarks) * 100;
    String motivation = percentage >= 75 ? 'Excellent Work!' : percentage >= 50 ? 'Good Effort!' : 'Keep Improving!';

    return Card(
      color: Colors.deepPurple.shade700,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text('Marks Obtained', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16)),
            const SizedBox(height: 8),
            Text('$marksObtained / ${widget.result.totalMarks}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(motivation, style: const TextStyle(color: Colors.yellowAccent, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
     return Row(
      children: [
        _buildStatCard('Accuracy', '${accuracy.toStringAsFixed(0)}%', Icons.track_changes),
        _buildStatCard('Attempt %', '${attemptPercentage.toStringAsFixed(0)}%', Icons.rule),
        _buildStatCard('Time Taken', _formattedTimeTaken, Icons.timer_outlined),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [Icon(icon, color: Colors.deepPurple, size: 28), const SizedBox(height: 8), Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])), const SizedBox(height: 4), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualAnalysis() {
     return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 40,
                  pieTouchData: PieTouchData(touchCallback: (event, pieTouchResponse) {}),
                  sections: [
                    PieChartSectionData(value: correctCount.toDouble(), showTitle: false, color: Colors.green, radius: 25),
                    PieChartSectionData(value: incorrectCount.toDouble(), showTitle: false, color: Colors.red, radius: 25),
                    PieChartSectionData(value: unattemptedCount.toDouble(), showTitle: false, color: Colors.grey, radius: 25),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildLegend(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildLegendItem(Colors.green, 'Correct ($correctCount)'),
        _buildLegendItem(Colors.red, 'Incorrect ($incorrectCount)'),
        _buildLegendItem(Colors.grey, 'Skipped ($unattemptedCount)'),
      ],
    );
  }
  
  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 16, height: 16, color: color),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }

  Widget _buildReviewSolutionsGrid() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Review Solutions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: widget.result.questions.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final state = widget.result.answerStates[index]!;
                final question = widget.result.questions[index];
                Color color = Colors.grey;
                if (state.status == AnswerStatus.answered || state.status == AnswerStatus.answeredAndMarked) {
                  color = state.userAnswer == question.correctAnswer ? Colors.green : Colors.red;
                }

                return GestureDetector(
                  onTap: () => _showSolutionSheet(index),
                  child: CircleAvatar(
                    backgroundColor: color,
                    child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
