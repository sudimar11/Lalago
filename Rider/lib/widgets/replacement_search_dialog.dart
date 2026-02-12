import 'package:flutter/material.dart';

/// Searchable dialog to pick a replacement item from a restaurant's menu.
class ReplacementSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> candidates;
  final String? restaurantName;

  const ReplacementSearchDialog({
    Key? key,
    required this.candidates,
    this.restaurantName,
  }) : super(key: key);

  /// Shows the dialog and returns the selected item, or null if dismissed.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required List<Map<String, dynamic>> candidates,
    String? restaurantName,
  }) {
    if (candidates.isEmpty) return Future.value(null);
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ReplacementSearchDialog(
        candidates: candidates,
        restaurantName: restaurantName,
      ),
    );
  }

  @override
  State<ReplacementSearchDialog> createState() =>
      _ReplacementSearchDialogState();
}

class _ReplacementSearchDialogState extends State<ReplacementSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return widget.candidates;
    final q = _query.trim().toLowerCase();
    return widget.candidates
        .where((f) =>
            (f['name']?.toString() ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.restaurantName != null &&
            widget.restaurantName!.isNotEmpty
        ? 'Replace with — ${widget.restaurantName}'
        : 'Search restaurant menu';
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.none,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: _filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.trim().isEmpty
                            ? 'No items available'
                            : 'No items match "$_query"',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final f = _filtered[index];
                        final name = f['name']?.toString() ?? 'Food';
                        final price = f['price']?.toString();
                        return ListTile(
                          title: Text(name),
                          subtitle: price != null && price.isNotEmpty
                              ? Text('₱$price')
                              : null,
                          onTap: () => Navigator.of(context).pop(f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
