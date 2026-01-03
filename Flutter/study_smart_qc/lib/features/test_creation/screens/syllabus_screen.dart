import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:study_smart_qc/services/auth_service.dart';
import 'package:study_smart_qc/widgets/test_configuration_bottom_sheet.dart';

class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  // State for user selections
  final Set<String> _selectedTopicIds = {};
  final Set<String> _selectedChapterIds = {};
  final Map<String, bool> _expansionState = {};

  // State to hold parsed syllabus data, preventing re-parsing on every UI rebuild
  Map<String, String> _chapterIdToNameMap = {};
  Map<String, String> _topicIdToNameMap = {};
  Map<String, Map<String, String>> _chapterIdToTopicsMap = {};
  List<String> _chapterKeys = [];

  void _onTopicSelected(bool isSelected, String chapterId, String topicId) {
    setState(() {
      if (isSelected) {
        _selectedTopicIds.add(topicId);
        _selectedChapterIds.add(chapterId);
      } else {
        _selectedTopicIds.remove(topicId);
        final chapterTopics = _chapterIdToTopicsMap[chapterId]?.keys ?? [];
        if (chapterTopics.every((topic) => !_selectedTopicIds.contains(topic))) {
          _selectedChapterIds.remove(chapterId);
        }
      }
    });
  }

  void _toggleSelectAll(String chapterId, Set<String> topicKeys) {
    setState(() {
      final areAllSelected = topicKeys.isNotEmpty && topicKeys.every((key) => _selectedTopicIds.contains(key));
      if (areAllSelected) {
        _selectedTopicIds.removeAll(topicKeys);
        _selectedChapterIds.remove(chapterId);
      } else {
        _selectedTopicIds.addAll(topicKeys);
        _selectedChapterIds.add(chapterId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Select Topics"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: () => AuthService().signOut()),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('static_data').doc('syllabus').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("No Syllabus Found"));
          }

          if (snapshot.hasData) {
            Map<String, dynamic> data = snapshot.data!.data() as Map<String, dynamic>;
            final chapters = data['subjects']?['physics']?['chapters'] as Map<String, dynamic>? ?? {};
            _chapterKeys = chapters.keys.toList();

            _chapterIdToNameMap = {};
            _topicIdToNameMap = {};
            _chapterIdToTopicsMap = {};

            for (var chapterKey in _chapterKeys) {
              final chapterData = chapters[chapterKey] as Map<String, dynamic>;
              _chapterIdToNameMap[chapterKey] = chapterData['name'] ?? 'Unnamed Chapter';
              final topics = Map<String, String>.from(chapterData['topics'] ?? {});
              _chapterIdToTopicsMap[chapterKey] = topics;
              for (var topicEntry in topics.entries) {
                _topicIdToNameMap[topicEntry.key] = topicEntry.value as String;
              }
            }
          }

          return ListView.builder(
            key: const PageStorageKey<String>('syllabus_list'),
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: _chapterKeys.length,
            itemBuilder: (context, index) {
              final chapterKey = _chapterKeys[index];
              final chapterName = _chapterIdToNameMap[chapterKey]!;
              final topics = _chapterIdToTopicsMap[chapterKey]!;
              final topicKeys = topics.keys.toSet();

              final areAllSelected = topicKeys.isNotEmpty && topicKeys.every((key) => _selectedTopicIds.contains(key));
              final isExpanded = _expansionState[chapterKey] ?? false;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: areAllSelected ? Colors.green : Colors.transparent, width: 2),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.book, color: Colors.deepPurple),
                      title: Text(chapterName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => _toggleSelectAll(chapterKey, topicKeys),
                      trailing: IconButton(
                        icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                        onPressed: () => setState(() => _expansionState[chapterKey] = !isExpanded),
                      ),
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: topicKeys.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, gridIndex) {
                            final topicKey = topicKeys.elementAt(gridIndex);
                            final topicName = topics[topicKey]!;
                            final isSelected = _selectedTopicIds.contains(topicKey);

                            return GestureDetector(
                              onTap: () => _onTopicSelected(!isSelected, chapterKey, topicKey),
                              child: Card(
                                color: isSelected ? Colors.green.withOpacity(0.15) : null,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(topicName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomSheet: _selectedTopicIds.isNotEmpty ? _buildStickyBottomBar() : null,
    );
  }

  Widget _buildStickyBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15).copyWith(bottom: MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(color: Colors.deepPurple.shade700, boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, -2))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_selectedTopicIds.length} Topic(s) Selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${_selectedChapterIds.length} Chapter(s)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(foregroundColor: Colors.deepPurple, backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (ctx) => TestConfigurationBottomSheet(
                  chapterIds: _selectedChapterIds,
                  topicIds: _selectedTopicIds,
                  chapterIdToNameMap: _chapterIdToNameMap,
                  topicIdToNameMap: _topicIdToNameMap,
                  chapterIdToTopicsMap: _chapterIdToTopicsMap, // FIX: This is now correctly passed
                ),
              );
            },
            child: const Row(children: [Text('Configure Test'), SizedBox(width: 5), Icon(Icons.arrow_forward_ios, size: 14)]),
          ),
        ],
      ),
    );
  }
}
