import 'package:flutter/material.dart';

class CurationManagementScreen extends StatefulWidget {
  final String curationId;
  final String title;

  const CurationManagementScreen({
    Key? key,
    required this.curationId,
    required this.title,
  }) : super(key: key);

  @override
  State<CurationManagementScreen> createState() => _CurationManagementScreenState();
}

class _CurationManagementScreenState extends State<CurationManagementScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Tab 0: Manage Questions, Tab 1: Student Stats
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.edit_note), text: "Manage Content"),
            Tab(icon: Icon(Icons.bar_chart), text: "Performance"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Placeholder for the Re-ordering/Randomizing Logic
          Center(child: Text("Manage content for ${widget.curationId}")),

          // Placeholder for the Student Stats Logic
          Center(child: Text("Student stats for ${widget.curationId}")),
        ],
      ),
    );
  }
}