//lib/features/teacher/screens/teacher_history_screen.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/services/teacher_service.dart';
import 'package:study_smart_qc/features/teacher/screens/curation_management_screen.dart';
import 'package:study_smart_qc/features/teacher/widgets/teacher_curation_preview_card.dart';

class TeacherHistoryScreen extends StatefulWidget {
  const TeacherHistoryScreen({super.key});

  @override
  State<TeacherHistoryScreen> createState() => _TeacherHistoryScreenState();
}

class _TeacherHistoryScreenState extends State<TeacherHistoryScreen> {

  String _generateAssignmentCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  void _showCloneBottomSheet(BuildContext parentContext, DocumentSnapshot sourceDoc) {
    final data = sourceDoc.data() as Map<String, dynamic>;
    final TextEditingController studentIdController = TextEditingController();
    final TextEditingController deadlineController = TextEditingController();

    DateTime selectedDateTime = DateTime.now().add(const Duration(days: 1));
    if (data['deadline'] != null && data['deadline'] is Timestamp) {
      selectedDateTime = (data['deadline'] as Timestamp).toDate();
    }

    deadlineController.text = DateFormat('MMM d, y  •  h:mm a').format(selectedDateTime);

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        bool isLoading = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setSheetState) {

            Future<void> pickFullDateTime() async {
              final date = await showDatePicker(
                context: context,
                initialDate: selectedDateTime,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date == null) return;

              if (!context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(selectedDateTime),
              );
              if (time == null) return;

              final combined = DateTime(
                  date.year, date.month, date.day,
                  time.hour, time.minute
              );

              setSheetState(() {
                selectedDateTime = combined;
                deadlineController.text = DateFormat('MMM d, y  •  h:mm a').format(combined);
              });
            }

            Future<void> handleClone() async {
              setSheetState(() {
                errorMessage = null;
                isLoading = true;
              });

              final rawInput = studentIdController.text.trim();

              if (rawInput.isEmpty) {
                setSheetState(() {
                  errorMessage = "Please enter a Student ID";
                  isLoading = false;
                });
                return;
              }

              final int? targetId = int.tryParse(rawInput);

              if (targetId == null) {
                setSheetState(() {
                  errorMessage = "Student ID must be a valid number";
                  isLoading = false;
                });
                return;
              }

              try {
                // Correct Query using camelCase 'studentId' and integer targetId
                final userQuery = await FirebaseFirestore.instance
                    .collection('users')
                    .where('studentId', isEqualTo: targetId)
                    .limit(1)
                    .get();

                if (userQuery.docs.isEmpty) {
                  setSheetState(() {
                    errorMessage = "Student ID '$targetId' not found.";
                    isLoading = false;
                  });
                  return;
                }

                final userDoc = userQuery.docs.first;
                final userData = userDoc.data();

                // --- DUPLICATION LOGIC ---
                // 1. Create a clean copy of the source data
                final Map<String, dynamic> cleanData = Map.from(data);

                // 2. Remove 'progress' fields from this COPY so the new student starts fresh.
                // This replaces the 'FieldValue.delete()' which caused the error.
                cleanData.remove('submittedAt');
                cleanData.remove('score');
                cleanData.remove('feedback');
                cleanData.remove('status');

                // 3. Generate new unique code
                final newCode = _generateAssignmentCode();


                cleanData['studentId'] = targetId;
                cleanData['studentUid'] = userDoc.id;
                cleanData['studentName'] = userData['name'] ?? 'Unknown';
                cleanData['status'] = 'Assigned';
                cleanData['createdAt'] = FieldValue.serverTimestamp();
                cleanData['deadline'] = Timestamp.fromDate(selectedDateTime);

                // 5. Save the new document
                await FirebaseFirestore.instance.collection('questions_curation').add(cleanData);

                if (mounted) {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text("Cloned successfully! Code: $newCode"),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 4),
                      )
                  );
                }

              } catch (e) {
                setSheetState(() {
                  errorMessage = "Error: $e";
                  isLoading = false;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Clone Assignment",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text("Copying: ${data['title'] ?? 'Untitled'}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),

                  const SizedBox(height: 20),

                  TextField(
                    controller: studentIdController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                      labelText: "New Student ID",
                      hintText: "e.g. 2602",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: deadlineController,
                    readOnly: true,
                    onTap: pickFullDateTime,
                    decoration: const InputDecoration(
                      labelText: "New Deadline",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                      hintText: "Tap to set date & time",
                    ),
                  ),

                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: isLoading ? null : handleClone,
                    child: isLoading
                        ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                        : const Text("Clone Assignment"),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherUid = FirebaseAuth.instance.currentUser?.uid;

    if (teacherUid == null) {
      return const Scaffold(body: Center(child: Text("Authentication Error")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Curations"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: TeacherService().getTeacherCurations(teacherUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("No curations found.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final DocumentSnapshot doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final String title = data['title'] ?? 'Untitled';
              final String docId = doc.id;

              return TeacherCurationPreviewCard(
                doc: doc,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CurationManagementScreen(
                        curationId: docId,
                        title: title,
                      ),
                    ),
                  );
                },
                onClone: () => _showCloneBottomSheet(context, doc),
              );
            },
          );
        },
      ),
    );
  }
}