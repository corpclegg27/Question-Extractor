// lib/features/teacher/screens/teacher_curation_screen.dart
// Description: Screen to select target audience (Student/Batch/General).
// UPDATED: Added Batch Selection Dropdown and logic to fetch teacher's batches.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/batch_model.dart';
import 'package:study_smart_qc/services/batch_service.dart';
import 'package:study_smart_qc/services/teacher_service.dart';
import 'package:study_smart_qc/features/teacher/screens/teacher_filter_screen.dart';

class TeacherCurationScreen extends StatefulWidget {
  const TeacherCurationScreen({super.key});

  @override
  State<TeacherCurationScreen> createState() => _TeacherCurationScreenState();
}

class _TeacherCurationScreenState extends State<TeacherCurationScreen> {
  final TeacherService _teacherService = TeacherService();
  final BatchService _batchService = BatchService(); // [NEW]

  final TextEditingController _studentIdController = TextEditingController();

  // State
  String _targetAudience = 'Particular Student'; // 'General', 'Particular Student', 'Batch'
  bool _isLoadingStats = false;
  Map<String, int>? _studentStats;

  // [NEW] Batch State
  List<BatchModel> _myBatches = [];
  String? _selectedBatchId;
  bool _loadingBatches = false;

  @override
  void initState() {
    super.initState();
    // Pre-fetch batches if needed, or wait until tab selection
  }

  // [NEW] Fetch Batches Logic
  Future<void> _fetchBatches() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loadingBatches = true);
    try {
      final batches = await _batchService.getBatchesForTeacher(uid);
      if (mounted) {
        setState(() {
          _myBatches = batches;
          // Auto-select first if available
          if (batches.isNotEmpty && _selectedBatchId == null) {
            _selectedBatchId = batches.first.id;
          }
          _loadingBatches = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
      debugPrint("Error fetching batches: $e");
    }
  }

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
    // 1. Validation for Student
    if (_targetAudience == 'Particular Student' && _studentIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a Student ID")));
      return;
    }

    // 2. [NEW] Validation for Batch
    if (_targetAudience == 'Batch' && _selectedBatchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a Batch")));
      return;
    }

    // 3. Prepare Data
    int? sId;
    if (_targetAudience == 'Particular Student' && _studentIdController.text.isNotEmpty) {
      sId = int.tryParse(_studentIdController.text);
    }

    String? bName;
    if (_targetAudience == 'Batch' && _selectedBatchId != null) {
      try {
        bName = _myBatches.firstWhere((b) => b.id == _selectedBatchId).batchName;
      } catch (_) {}
    }

    // 4. Navigate to Step 2 (Filters)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TeacherFilterScreen(
          audienceType: _targetAudience,
          studentId: sId,
          // [NEW] Pass Batch Info (Update TeacherFilterScreen constructor next!)
          batchId: _targetAudience == 'Batch' ? _selectedBatchId : null,
          batchName: _targetAudience == 'Batch' ? bName : null,
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
                        _studentStats = null; // Reset stats
                      });
                      // [NEW] Fetch batches if tab selected
                      if (type == 'Batch' && _myBatches.isEmpty) {
                        _fetchBatches();
                      }
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 30),

            // 2A. Student Input (Conditional)
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

            // 2B. [NEW] Batch Dropdown (Conditional)
            if (_targetAudience == 'Batch') ...[
              _buildSectionHeader('2. Select Batch'),
              if (_loadingBatches)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: LinearProgressIndicator()),
                )
              else if (_myBatches.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Row(children: [
                    Icon(Icons.error_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text("No batches found. Create one first.")),
                  ]),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedBatchId,
                  decoration: const InputDecoration(
                    labelText: "Select Class/Batch",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  items: _myBatches.map((batch) {
                    return DropdownMenuItem(
                      value: batch.id,
                      child: Text(batch.batchName, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedBatchId = val);
                  },
                ),
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