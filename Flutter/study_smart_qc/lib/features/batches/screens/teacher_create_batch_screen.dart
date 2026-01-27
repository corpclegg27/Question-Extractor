// lib/features/batches/screens/teacher_create_batch_screen.dart
// Description: Form to create a new batch.
// Features: Batch Name input, searchable/scrollable student list with checkboxes.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/features/batches/widgets/student_display_card.dart';
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/services/batch_service.dart';

class TeacherCreateBatchScreen extends StatefulWidget {
  const TeacherCreateBatchScreen({super.key});

  @override
  State<TeacherCreateBatchScreen> createState() => _TeacherCreateBatchScreenState();
}

class _TeacherCreateBatchScreenState extends State<TeacherCreateBatchScreen> {
  final BatchService _batchService = BatchService();
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = true;
  bool _isCreating = false;

  List<UserModel> _allStudents = [];
  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    final students = await _batchService.getAllStudents();
    if (mounted) {
      setState(() {
        _allStudents = students;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleCreateBatch() async {
    final String batchName = _nameController.text.trim();
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (batchName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a batch name")),
      );
      return;
    }

    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one student")),
      );
      return;
    }

    if (currentUserId == null) return;

    setState(() => _isCreating = true);

    try {
      await _batchService.createBatch(
        batchName: batchName,
        createdByUserId: currentUserId,
        selectedStudentIds: _selectedStudentIds.toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Batch created successfully!")),
        );
        Navigator.pop(context); // Go back to Landing Page
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error creating batch: $e"), backgroundColor: Colors.red),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("Create New Batch", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // 1. Batch Name Input
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Batch Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: "Enter Batch Name (e.g., Class 11 - Batch A)",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 2. Student List Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Select Students (${_selectedStudentIds.length})",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedStudentIds.length == _allStudents.length) {
                        _selectedStudentIds.clear();
                      } else {
                        _selectedStudentIds.addAll(_allStudents.map((e) => e.uid));
                      }
                    });
                  },
                  child: Text(_selectedStudentIds.length == _allStudents.length ? "Clear All" : "Select All"),
                ),
              ],
            ),
          ),

          // 3. Scrollable List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _allStudents.length,
              itemBuilder: (context, index) {
                final student = _allStudents[index];
                final bool isSelected = _selectedStudentIds.contains(student.uid);

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedStudentIds.remove(student.uid);
                      } else {
                        _selectedStudentIds.add(student.uid);
                      }
                    });
                  },
                  child: StudentDisplayCard(
                    user: student,
                    trailing: Checkbox(
                      value: isSelected,
                      activeColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedStudentIds.add(student.uid);
                          } else {
                            _selectedStudentIds.remove(student.uid);
                          }
                        });
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          // 4. Bottom Action Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isCreating ? null : _handleCreateBatch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6200EA),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isCreating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Create Batch", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}