// lib/features/batches/widgets/batch_display_card.dart
// Description: A dumb widget to display basic Batch details.
// Shows Name, Creation Date, Student Count, Teacher Count.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:study_smart_qc/models/batch_model.dart';

class BatchDisplayCard extends StatelessWidget {
  final BatchModel batch;
  final VoidCallback onTap;

  const BatchDisplayCard({
    super.key,
    required this.batch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String dateStr = DateFormat('MMM d, y').format(batch.createdAt.toDate());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Name + Arrow
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      batch.batchName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                ],
              ),

              const SizedBox(height: 4),
              Text(
                "Created on $dateStr",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 16),

              // Stats Row
              Row(
                children: [
                  _buildStatPill(Icons.groups, "${batch.studentIds.length} Students", Colors.blue),
                  const SizedBox(width: 12),
                  _buildStatPill(Icons.person, "${batch.teacherIds.length} Teachers", Colors.orange),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}