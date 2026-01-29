// lib/features/batches/screens/teacher_view_specific_batch.dart
// Description: Detailed view for a specific batch.
// UPDATED: Fixed nested TabBar conflict by wrapping inner tabs in their own DefaultTabController.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/models/batch_model.dart';
import 'package:study_smart_qc/models/user_model.dart';
import 'package:study_smart_qc/services/batch_service.dart';

// WIDGETS
import 'package:study_smart_qc/features/teacher/widgets/teacher_curation_preview_card.dart';
import 'package:study_smart_qc/features/batches/widgets/student_display_card.dart';
import 'package:study_smart_qc/features/teacher/widgets/clone_assignment_sheet.dart';

// SCREENS
import 'package:study_smart_qc/features/teacher/screens/curation_management_screen.dart';

class TeacherViewSpecificBatch extends StatefulWidget {
  final BatchModel batch;

  const TeacherViewSpecificBatch({super.key, required this.batch});

  @override
  State<TeacherViewSpecificBatch> createState() => _TeacherViewSpecificBatchState();
}

class _TeacherViewSpecificBatchState extends State<TeacherViewSpecificBatch> {
  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  void _openCloneSheet(DocumentSnapshot doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CloneAssignmentSheet(sourceDoc: doc),
    );
  }

  void _confirmRemoveStudent(UserModel student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Student?"),
        content: Text("Are you sure you want to remove ${student.displayName} from ${widget.batch.batchName}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context); // Close Dialog
              await _removeStudent(student.uid);
            },
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  Future<void> _removeStudent(String studentUid) async {
    try {
      await FirebaseFirestore.instance.collection('batches').doc(widget.batch.id).update({
        'studentRefs': FieldValue.arrayRemove([studentUid])
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Student removed successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD METHODS
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Outer Controller for Main Tabs
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        appBar: AppBar(
          title: Text(
            widget.batch.batchName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Color(0xFF6200EA),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF6200EA),
            tabs: [
              Tab(text: "Tests & Assignments"),
              Tab(text: "Manage Batch"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTestsAndAssignmentsTab(),
            _buildManageBatchTab(),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: TESTS & ASSIGNMENTS ---
  Widget _buildTestsAndAssignmentsTab() {
    // [FIX] Wrap this section in its own DefaultTabController to isolate it
    return DefaultTabController(
      length: 2, // 2 Nested Tabs
      child: Column(
        children: [
          // Nested Tab Bar styled as Segments
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const TabBar(
              labelColor: Colors.black87,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.deepPurple,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(text: "Tests (Strict)"),
                Tab(text: "Assignments (Practice)"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 1. Tests (Single Attempt = true)
                _buildCurationList(onlySingleAttempt: true),

                // 2. Assignments (Single Attempt = false)
                _buildCurationList(onlySingleAttempt: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurationList({required bool onlySingleAttempt}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('questions_curation')
          .where('targetAudience', isEqualTo: 'Batch')
          .where('batchId', isEqualTo: widget.batch.id)
          .where('onlySingleAttempt', isEqualTo: onlySingleAttempt)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                    onlySingleAttempt ? Icons.timer_off_outlined : Icons.assignment_outlined,
                    size: 64, color: Colors.grey.shade300
                ),
                const SizedBox(height: 16),
                Text(
                  onlySingleAttempt ? "No Tests assigned yet" : "No Assignments created yet",
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final title = data['title'] ?? 'Untitled';

            return TeacherCurationPreviewCard(
              doc: doc,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CurationManagementScreen(
                      curationId: doc.id,
                      title: title,
                    ),
                  ),
                );
              },
              onClone: () => _openCloneSheet(doc),
            );
          },
        );
      },
    );
  }

  // --- TAB 2: MANAGE BATCH ---
  Widget _buildManageBatchTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('batches')
          .doc(widget.batch.id)
          .snapshots(),
      builder: (context, batchSnap) {
        if (!batchSnap.hasData) return const Center(child: CircularProgressIndicator());

        final batchData = batchSnap.data!.data() as Map<String, dynamic>;
        final List<dynamic> studentRefs = batchData['studentRefs'] ?? [];

        if (studentRefs.isEmpty) {
          return const Center(
            child: Text("No students in this batch yet.", style: TextStyle(color: Colors.grey)),
          );
        }

        return FutureBuilder<List<UserModel>>(
          future: _fetchUsersByChunks(studentRefs.cast<String>()),
          builder: (context, usersSnap) {
            if (usersSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final students = usersSnap.data ?? [];

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                return StudentDisplayCard(
                  user: student,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: "Remove from Batch",
                    onPressed: () => _confirmRemoveStudent(student),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Helper to safely fetch >10 users
  Future<List<UserModel>> _fetchUsersByChunks(List<String> uids) async {
    if (uids.isEmpty) return [];
    List<UserModel> allUsers = [];

    // Chunk size 10 for 'whereIn' limit
    for (var i = 0; i < uids.length; i += 10) {
      int end = (i + 10 < uids.length) ? i + 10 : uids.length;
      List<String> chunk = uids.sublist(i, end);

      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        allUsers.addAll(snap.docs.map((d) => UserModel.fromMap(d.data())));
      } catch (e) {
        debugPrint("Error fetching user chunk: $e");
      }
    }
    return allUsers;
  }
}