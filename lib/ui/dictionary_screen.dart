import 'package:flutter/material.dart';
import '../services/dictionary_service.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final DictionaryService _service = DictionaryService.instance;

  @override
  Widget build(BuildContext context) {
    final terms = _service.allTerms;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text('Custom Dictionary'),
        backgroundColor: const Color(0xFF16213e),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: terms.isEmpty ? _buildEmptyState() : _buildTermList(terms),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF3B82F6),
        onPressed: () => _showTermDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.book_outlined, size: 64, color: Colors.white38),
          SizedBox(height: 16),
          Text(
            'No custom terms yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Add replacement rules to customize transcriptions',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTermList(List<Map<String, dynamic>> terms) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: terms.length,
      itemBuilder: (context, index) {
        final term = terms[index];
        return _buildTermCard(term);
      },
    );
  }

  Widget _buildTermCard(Map<String, dynamic> term) {
    final int id = term['id'] as int;
    final String source = term['source_value'] as String;
    final String destination = term['destination_value'] as String;
    final bool isEnabled = (term['is_enabled'] as int) == 1;

    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(source),
      onDismissed: (_) async {
        await _service.deleteTerm(id);
        setState(() {});
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  source,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 14, color: Colors.white38),
              ),
              Flexible(
                child: Text(
                  destination,
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: isEnabled,
                activeTrackColor: Colors.blue,
                onChanged: (value) async {
                  await _service.toggleTerm(id, value);
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.white38, size: 20),
                onPressed: () async {
                  final confirmed = await _confirmDelete(source);
                  if (confirmed == true) {
                    await _service.deleteTerm(id);
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          onTap: () => _showTermDialog(
            id: id,
            initialSource: source,
            initialDestination: destination,
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(String source) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Term', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "$source" from your dictionary?',
          style: const TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showTermDialog({
    int? id,
    String initialSource = '',
    String initialDestination = '',
  }) {
    final sourceController = TextEditingController(text: initialSource);
    final destinationController =
        TextEditingController(text: initialDestination);
    final isEditing = id != null;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            isEditing ? 'Edit Term' : 'Add Term',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: sourceController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Source word',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: destinationController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Replace with',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            TextButton(
              onPressed: () async {
                final source = sourceController.text.trim();
                final destination = destinationController.text.trim();
                if (source.isEmpty || destination.isEmpty) return;

                if (isEditing) {
                  await _service.updateTerm(id, source, destination);
                } else {
                  await _service.addTerm(source, destination);
                }
                if (context.mounted) Navigator.pop(context);
                setState(() {});
              },
              child: const Text(
                'Save',
                style: TextStyle(color: Color(0xFF3B82F6)),
              ),
            ),
          ],
        );
      },
    );
  }
}
