//lib/features/teacher/screens/teacher_curation_screen.dart

import 'package:flutter/material.dart';
import 'package:study_smart_qc/services/teacher_service.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_filter_screen.dart';

class TeacherCurationScreen extends StatefulWidget {
  const TeacherCurationScreen({super.key});

  @override
  State<TeacherCurationScreen> createState() => _TeacherCurationScreenState();
}

class _TeacherCurationScreenState extends State<TeacherCurationScreen> {
  final TeacherService _teacherService = TeacherService();
  final TextEditingController _studentIdController = TextEditingController();

  // State
  String _targetAudience = 'Particular Student'; // 'General', 'Particular Student', 'Batch'
  bool _isLoadingStats = false;
  Map<String, int>? _studentStats;

  void _fetchStats() async {
    final idStr = _studentIdController.text.trim();
    if (idStr.isEmpty) return;

    setState(() => _isLoadingStats = true);
    try {
      final stats = await _teacherService.getStudentStats(int.parse(idStr));
      setState(() => _studentStats = stats);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  void _onNextPressed() {
    if (_targetAudience == 'Particular Student' && _studentIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a Student ID")));
      return;
    }

    // Navigate to Step 2 (Filters)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TeacherFilterScreen(
          audienceType: _targetAudience,
          studentId: _studentIdController.text.isNotEmpty ? int.parse(_studentIdController.text) : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Questions Curation'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Audience
            _buildSectionHeader('1. Target Audience'),
            Wrap(
              spacing: 10,
              children: ['General', 'Particular Student', 'Batch'].map((type) {
                return ChoiceChip(
                  label: Text(type),
                  selected: _targetAudience == type,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                      _targetAudience = type;
                      _studentStats = null; // Reset stats on change
                    });
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 30),

            // 2. Student Input (Conditional)
            if (_targetAudience == 'Particular Student') ...[
              _buildSectionHeader('2. Student Details'),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _studentIdController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Enter Student ID',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      onChanged: (_) => setState(() => _studentStats = null), // Clear stats on edit
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _fetchStats,
                    child: const Text("Load Stats"),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_isLoadingStats)
                const Center(child: CircularProgressIndicator())
              else if (_studentStats != null)
                _buildStatsGrid(),
            ],

            const SizedBox(height: 40),

            // 3. Next Action
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _onNextPressed,
                child: const Text('Next', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }

  Widget _buildStatsGrid() {
    if (_studentStats!.isEmpty) return const Text("No data found for this student.");

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: _studentStats!.entries.map((e) {
        return Card(
          color: Colors.deepPurple.shade50,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(e.value.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              Text(e.key, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        );
      }).toList(),
    );
  }
}