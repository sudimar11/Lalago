import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class MessageBadgePage extends StatelessWidget {
  /// Pass in the restaurant's (vendor's) ID here.
  final String vendorId;

  const MessageBadgePage({Key? key, required this.vendorId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // A collectionGroup query on subcollection "thread"
    // where 'receiverId' == vendorId and 'isread' == false
    final unreadMessagesStream = FirebaseFirestore.instance
        .collectionGroup('thread')
        .where('receiverId', isEqualTo: vendorId)
        .where('isread', isEqualTo: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text('Messages with Badge'),
      ),
      body: Center(
        child: StreamBuilder<QuerySnapshot>(
          stream: unreadMessagesStream,
          builder: (context, snapshot) {
            // Handle errors
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }

            // Show a loading indicator until the query returns data
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            }

            // The total count of unread messages is the length of docs
            final int unreadCount = snapshot.data?.docs.length ?? 0;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Main icon
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 50,
                      color: Colors.grey[700],
                    ),
                    // Badge (only visible if unreadCount > 0)
                    if (unreadCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Center(
                            child: Text(
                              '$unreadCount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 20),
                // Display the vendor (restaurant) ID for verification
                Text(
                  'Restaurant ID: $vendorId',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
