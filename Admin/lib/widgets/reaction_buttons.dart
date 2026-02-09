import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

class ReactionButtons extends StatefulWidget {
  final String date;
  final String noteId;
  final String currentUserId;
  final String currentUserName;

  const ReactionButtons({
    super.key,
    required this.date,
    required this.noteId,
    required this.currentUserId,
    required this.currentUserName,
  });

  @override
  State<ReactionButtons> createState() => _ReactionButtonsState();
}

class _ReactionButtonsState extends State<ReactionButtons> {
  final List<String> _availableReactions = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
    '👏',
    '🔥'
  ];

  Map<String, int> _reactionCounts = {};
  String? _userReaction;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReactions();
  }

  void _loadReactions() async {
    try {
      print(
          'Loading reactions for date: ${widget.date}, noteId: ${widget.noteId}, userId: ${widget.currentUserId}');

      final counts = await NotificationService.getReactionCounts(
        date: widget.date,
        noteId: widget.noteId,
      );

      // Get user's current reaction using Firebase Auth UID
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) {
        throw Exception('User not authenticated');
      }

      final reactions = await FirebaseFirestore.instance
          .collection('daily_summaries')
          .doc(widget.date)
          .collection('notes')
          .doc(widget.noteId)
          .collection('reactions')
          .doc(authUid)
          .get();

      String? userReaction;
      if (reactions.exists) {
        userReaction = reactions.data()?['reaction'] as String?;
      }

      if (mounted) {
        setState(() {
          _reactionCounts = counts;
          _userReaction = userReaction;
        });
      }
    } catch (e) {
      print('Error loading reactions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load reactions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleReaction(String reaction) async {
    if (_isLoading) return;

    print('Toggling reaction: $reaction for user: ${widget.currentUserId}');

    setState(() {
      _isLoading = true;
    });

    try {
      if (_userReaction == reaction) {
        // Remove reaction
        await NotificationService.removeReactionFromNote(
          date: widget.date,
          noteId: widget.noteId,
          userId: widget.currentUserId,
        );
        setState(() {
          _userReaction = null;
          _reactionCounts[reaction] = (_reactionCounts[reaction] ?? 1) - 1;
          if (_reactionCounts[reaction]! <= 0) {
            _reactionCounts.remove(reaction);
          }
        });
      } else {
        // Add or change reaction
        if (_userReaction != null) {
          // Remove previous reaction first
          await NotificationService.removeReactionFromNote(
            date: widget.date,
            noteId: widget.noteId,
            userId: widget.currentUserId,
          );

          // Update counts
          final prevReaction = _userReaction!;
          _reactionCounts[prevReaction] =
              (_reactionCounts[prevReaction] ?? 1) - 1;
          if (_reactionCounts[prevReaction]! <= 0) {
            _reactionCounts.remove(prevReaction);
          }
        }

        // Add new reaction
        await NotificationService.addReactionToNote(
          date: widget.date,
          noteId: widget.noteId,
          reaction: reaction,
          userId: widget.currentUserId,
          userName: widget.currentUserName,
        );

        setState(() {
          _userReaction = reaction;
          _reactionCounts[reaction] = (_reactionCounts[reaction] ?? 0) + 1;
        });
      }
    } catch (e) {
      print('Error toggling reaction: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update reaction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is properly authenticated
    if (widget.currentUserId.isEmpty || widget.currentUserName.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'User not authenticated',
          style: TextStyle(color: Colors.red, fontSize: 12),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reaction buttons
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _availableReactions.map((reaction) {
              final count = _reactionCounts[reaction] ?? 0;
              final isSelected = _userReaction == reaction;

              return GestureDetector(
                onTap: _isLoading ? null : () => _toggleReaction(reaction),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        reaction,
                        style: TextStyle(fontSize: 16),
                      ),
                      if (count > 0) ...[
                        SizedBox(width: 4),
                        Text(
                          count.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.blue : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          // Show who reacted (if any reactions exist)
          if (_reactionCounts.isNotEmpty) ...[
            SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: NotificationService.getNoteReactionsStream(
                date: widget.date,
                noteId: widget.noteId,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return SizedBox.shrink();
                }

                final reactions = snapshot.data!.docs;
                if (reactions.isEmpty) {
                  return SizedBox.shrink();
                }

                // Group reactions by type
                final Map<String, List<String>> reactionGroups = {};
                for (var doc in reactions) {
                  final data = doc.data() as Map<String, dynamic>;
                  final reaction = data['reaction'] as String?;
                  final userName = data['user_name'] as String?;

                  if (reaction != null && userName != null) {
                    if (!reactionGroups.containsKey(reaction)) {
                      reactionGroups[reaction] = [];
                    }
                    reactionGroups[reaction]!.add(userName);
                  }
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: reactionGroups.entries.map((entry) {
                    final reaction = entry.key;
                    final users = entry.value;

                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$reaction ${users.join(', ')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
