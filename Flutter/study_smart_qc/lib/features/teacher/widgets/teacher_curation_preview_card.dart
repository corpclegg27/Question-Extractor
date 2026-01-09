import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TeacherCurationPreviewCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final VoidCallback? onTap;
  final VoidCallback? onClone; // New Callback

  const TeacherCurationPreviewCard({
    super.key,
    required this.doc,
    this.onTap,
    this.onClone,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    final String title = data['title'] ?? 'Untitled Assignment';
    final String code = data['assignmentCode'] ?? '----';
    final String status = data['status'] ?? 'Draft';
    final String audience = data['targetAudience'] ?? 'General';

    // FIX: Ensure we display the readable ID if available, else fall back gracefully
    // Assuming 'studentId' field stores the readable ID (e.g., STU-100)
    String studentInfo = "N/A";
    if (data['studentId'] != null && data['studentId'].toString().isNotEmpty) {
      studentInfo = "${data['studentId']}";
    } else if (data['studentUid'] != null) {
      // Fallback to UID substring if readable ID is missing
      studentInfo = "UID: ${data['studentUid'].toString().substring(0, 5)}..";
    }

    final DateFormat formatter = DateFormat('d MMM y, h:mm a');

    String formattedCreated = "Unknown";
    if (data['createdAt'] is Timestamp) {
      formattedCreated = formatter.format((data['createdAt'] as Timestamp).toDate());
    }

    String formattedDeadline = "No Deadline";
    if (data['deadline'] is Timestamp) {
      formattedDeadline = formatter.format((data['deadline'] as Timestamp).toDate());
    }

    Color statusColor = Colors.grey;
    if (status.toLowerCase() == 'assigned') statusColor = Colors.blue;
    if (status.toLowerCase() == 'submitted') statusColor = Colors.green;
    if (status.toLowerCase() == 'draft') statusColor = Colors.orange;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER: Title + Clone Button + Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.deepPurple.shade100),
                          ),
                          child: Text(
                            "Code: $code",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- CLONE BUTTON ---
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Colors.deepPurple),
                    tooltip: "Clone Assignment",
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: onClone,
                  ),

                  // --- STATUS BADGE ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // DETAILS GRID
              Row(
                children: [
                  _buildDetailCol(Icons.people_outline, "Audience", audience),
                  _buildDetailCol(Icons.badge_outlined, "Student ID", studentInfo),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildDetailCol(Icons.calendar_today_outlined, "Created", formattedCreated),
                  _buildDetailCol(Icons.timer_outlined, "Deadline", formattedDeadline, isDate: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCol(IconData icon, String label, String value, {bool isDate = false}) {
    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDate && value == "No Deadline" ? Colors.grey : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}