// lib/features/teacher/widgets/clone_assignment_sheet.dart
// Description: Bottom sheet for cloning assignments.
// Features: Select Audience (Student/Batch/General), Pick Deadline, Call TeacherService.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/models/batch_model.dart';
import 'package:study_smart_qc/services/batch_service.dart';
import 'package:study_smart_qc/services/teacher_service.dart';

class CloneAssignmentSheet extends StatefulWidget {
  final DocumentSnapshot sourceDoc;

  const CloneAssignmentSheet({super.key, required this.sourceDoc});

  @override
  State<CloneAssignmentSheet> createState() => _CloneAssignmentSheetState();
}

class _CloneAssignmentSheetState extends State<CloneAssignmentSheet> {
  final TeacherService _teacherService = TeacherService();
  final BatchService _batchService = BatchService();

  // State
  TargetAudienceType _selectedType = TargetAudienceType.individual;
  bool _isLoading = false;
  String? _errorMessage;

  // Inputs
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _deadlineController = TextEditingController();
  DateTime _selectedDeadline = DateTime.now().add(const Duration(days: 7)); // Default 1 week

  // Batch Data
  List<BatchModel> _myBatches = [];
  String? _selectedBatchId;
  bool _loadingBatches = false;

  @override
  void initState() {
    super.initState();
    _initializeDeadline();
    _fetchBatches();
  }

  void _initializeDeadline() {
    final data = widget.sourceDoc.data() as Map<String, dynamic>;
    if (data['deadline'] != null && data['deadline'] is Timestamp) {
      _selectedDeadline = (data['deadline'] as Timestamp).toDate();
      // If deadline passed, push it forward
      if (_selectedDeadline.isBefore(DateTime.now())) {
        _selectedDeadline = DateTime.now().add(const Duration(days: 1));
      }
    }
    _deadlineController.text = DateFormat('MMM d, y  •  h:mm a').format(_selectedDeadline);
  }

  Future<void> _fetchBatches() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loadingBatches = true);
    try {
      final batches = await _batchService.getBatchesForTeacher(uid);
      if (mounted) {
        setState(() {
          _myBatches = batches;
          if (batches.isNotEmpty) _selectedBatchId = batches.first.id;
          _loadingBatches = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDeadline),
    );
    if (time == null) return;

    setState(() {
      _selectedDeadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _deadlineController.text = DateFormat('MMM d, y  •  h:mm a').format(_selectedDeadline);
    });
  }

  Future<void> _handleClone() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String targetId = '';
      String targetName = '';

      // VALIDATION LOGIC
      if (_selectedType == TargetAudienceType.individual) {
        final rawId = _studentIdController.text.trim();
        if (rawId.isEmpty) throw Exception("Enter a Student ID");

        final int? sId = int.tryParse(rawId);
        if (sId == null) throw Exception("Invalid Student ID");

        // Resolve UID
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('studentId', isEqualTo: sId)
            .limit(1)
            .get();

        if (userQuery.docs.isEmpty) throw Exception("Student ID not found");

        targetId = userQuery.docs.first.id; // UID
        targetName = userQuery.docs.first.data()['displayName'] ?? 'Unknown Student';

      } else if (_selectedType == TargetAudienceType.batch) {
        if (_selectedBatchId == null) throw Exception("Select a Batch");

        final batch = _myBatches.firstWhere((b) => b.id == _selectedBatchId);
        targetId = batch.id;
        targetName = batch.batchName;
      } else {
        targetName = "General Audience";
      }

      // CALL SERVICE
      await _teacherService.cloneAssignment(
        sourceDoc: widget.sourceDoc,
        targetType: _selectedType,
        targetId: targetId,
        targetName: targetName,
        newDeadline: _selectedDeadline,
      );

      if (mounted) {
        Navigator.pop(context); // Close Sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Assignment cloned successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Basic Data
    final data = widget.sourceDoc.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Untitled';

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Clone Assignment", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text("Source: $title", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 20),

          // 1. Audience Type Selector
          SegmentedButton<TargetAudienceType>(
            segments: const [
              ButtonSegment(value: TargetAudienceType.individual, label: Text("Student"), icon: Icon(Icons.person)),
              ButtonSegment(value: TargetAudienceType.batch, label: Text("Batch"), icon: Icon(Icons.groups)),
              ButtonSegment(value: TargetAudienceType.general, label: Text("General"), icon: Icon(Icons.public)),
            ],
            selected: {_selectedType},
            onSelectionChanged: (Set<TargetAudienceType> newSelection) {
              setState(() => _selectedType = newSelection.first);
            },
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 20),

          // 2. Dynamic Input Fields
          if (_selectedType == TargetAudienceType.individual)
            TextField(
              controller: _studentIdController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: "Student ID",
                hintText: "e.g. 2605",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            )
          else if (_selectedType == TargetAudienceType.batch)
            _loadingBatches
                ? const Center(child: LinearProgressIndicator())
                : DropdownButtonFormField<String>(
              value: _selectedBatchId,
              decoration: const InputDecoration(
                labelText: "Select Batch",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.class_outlined),
              ),
              items: _myBatches.map((b) => DropdownMenuItem(
                value: b.id,
                child: Text(b.batchName, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (val) => setState(() => _selectedBatchId = val),
              hint: _myBatches.isEmpty ? const Text("No batches found") : null,
            ),

          const SizedBox(height: 16),

          // 3. Deadline Picker
          TextField(
            controller: _deadlineController,
            readOnly: true,
            onTap: _pickDateTime,
            decoration: const InputDecoration(
              labelText: "Deadline",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.calendar_month_outlined),
              suffixIcon: Icon(Icons.arrow_drop_down),
            ),
          ),

          // Error Message
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: 24),

          // 4. Action Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isLoading ? null : _handleClone,
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Clone Now", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}