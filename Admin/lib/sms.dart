import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/sms_service.dart';

class ClassListPage extends StatefulWidget {
  @override
  _ClassListPageState createState() => _ClassListPageState();
}

class _ClassListPageState extends State<ClassListPage> {
  String? selectedClassListId;
  Map<String, dynamic>? classListData;
  List<DocumentSnapshot> students = [];
  final SMSService _smsService = SMSService();
  bool _isLoading = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _initializeSMS();
  }

  // Initialize SMS service
  Future<void> _initializeSMS() async {
    try {
      await _smsService.initialize();
      setState(() {
        _hasPermission = _smsService.hasSmsPermission;
      });
    } catch (e) {
      print('Error initializing SMS: $e');
    }
  }

  Future<void> _fetchClassListDetails(String classListId) async {
    try {
      final classListDoc = await FirebaseFirestore.instance
          .collection('class_lists')
          .doc(classListId)
          .get();

      setState(() {
        classListData = classListDoc.data();
        students =
            []; // Clear the student list when a new class list is selected
      });

      // Fetch students in the selected class list
      await _fetchStudentsInClassList();
    } catch (e) {
      print('Error fetching class list details: $e');
      _showMessage('Error loading class list: ${e.toString()}');
    }
  }

  Future<void> _fetchStudentsInClassList() async {
    if (classListData == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('classLists', arrayContains: {
        'classId': classListData!['classId'],
        'academicYear': classListData!['academicYear'],
        'gradeLevel': classListData!['gradeLevel'],
        'subject': classListData!['subject'],
        'teacher': classListData!['subject'],
      }).get();

      setState(() {
        students = snapshot.docs;
      });
    } catch (e) {
      print('Error fetching students in class list: $e');
      _showMessage('Error loading students: ${e.toString()}');
    }
  }

  // Function to send SMS with grade information
  Future<void> _sendMessage(
      String phoneNumber, Map<String, dynamic> grades) async {
    if (!_hasPermission) {
      _showMessage(
          'SMS permission is required. Please grant permission first.');
      return;
    }

    final message = _formatGradesMessage(grades);

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic> result = await _smsService.sendSingleSMS(
        phoneNumber: phoneNumber,
        message: message,
        useFallback: true,
      );

      if (result['success']) {
        _showMessage('✅ SMS successfully sent to $phoneNumber');
      } else {
        _showMessage(
            '❌ Failed to send SMS to $phoneNumber: ${result['message']}');
      }
    } catch (e) {
      _showMessage('❌ Error sending SMS to $phoneNumber: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Send SMS to all students
  Future<void> _sendToAll() async {
    if (!_hasPermission) {
      _showMessage(
          'SMS permission is required. Please grant permission first.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      List<String> phoneNumbers = [];
      List<Map<String, dynamic>> gradeData = [];

      for (var student in students) {
        final studentData = student.data() as Map<String, dynamic>;
        final phoneNumber = studentData['contactNumber'] ?? 'N/A';
        final grades = studentData['grades']?[classListData!['classId']] ?? {};

        if (phoneNumber != 'N/A') {
          phoneNumbers.add(phoneNumber);
          gradeData.add(grades);
        }
      }

      if (phoneNumbers.isEmpty) {
        _showMessage('No valid phone numbers found for students.');
        return;
      }

      // Send bulk SMS with the same message format
      final message = _formatGradesMessage(gradeData.first);

      Map<String, dynamic> result = await _smsService.sendBulkSMS(
        phoneNumbers: phoneNumbers,
        message: message,
        useFallback: true,
        onProgress: (current, total) {
          _showMessage('Sending SMS: $current/$total');
        },
      );

      if (result['success']) {
        _showMessage(
            '✅ Bulk SMS completed: ${result['totalSent']} sent, ${result['totalFailed']} failed');
      } else {
        _showMessage('❌ Bulk SMS failed: ${result['message']}');
      }
    } catch (e) {
      _showMessage('❌ Error in bulk SMS: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Format grades into a message
  String _formatGradesMessage(Map<String, dynamic> grades) {
    final subject = classListData!['subject'];
    return '''Panamao National High, grades for $subject:
First Quarter: ${grades['firstQuarter'] ?? 'N/A'}
Second Quarter: ${grades['secondQuarter'] ?? 'N/A'}
Third Quarter: ${grades['thirdQuarter'] ?? 'N/A'}
Fourth Quarter: ${grades['fourthQuarter'] ?? 'N/A'}
Average: ${grades['average'] ?? 'N/A'}
Remarks: ${grades['remarks'] ?? 'N/A'}
''';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3),
        backgroundColor: message.contains('✅')
            ? Colors.green
            : message.contains('❌')
                ? Colors.red
                : Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Class List Page'),
        backgroundColor: Colors.blue,
        actions: [
          // Permission status indicator
          Icon(
            _hasPermission ? Icons.check_circle : Icons.error,
            color: _hasPermission ? Colors.green : Colors.red,
          ),
          SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _isLoading ? null : _sendToAll,
            tooltip: 'Send to All',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Permission warning
                  if (!_hasPermission)
                    Card(
                      color: Colors.orange[100],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange[800]),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'SMS permissions required to send grade notifications',
                                style: TextStyle(
                                  color: Colors.orange[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!_hasPermission) SizedBox(height: 16),

                  // Dropdown to select class list
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('class_lists')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error loading class lists: ${snapshot.error}',
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return Center(child: CircularProgressIndicator());
                      }

                      // Populate dropdown with class list data from Firestore
                      List<DropdownMenuItem<String>> classListItems =
                          snapshot.data!.docs.map((doc) {
                        final classList = doc.data() as Map<String, dynamic>;
                        final classId = classList['classId'] ?? 'No Class ID';
                        final gradeLevel = classList['gradeLevel'] ?? '';
                        final academicYear = classList['academicYear'] ?? '';
                        final subject = classList['subject'] ?? '';
                        final dropdownText =
                            '$classId - $subject ($gradeLevel, $academicYear)';

                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(dropdownText),
                        );
                      }).toList();

                      return DropdownButton<String>(
                        hint: Text('Select Class List'),
                        value: selectedClassListId,
                        onChanged: (value) {
                          setState(() {
                            selectedClassListId = value;
                            classListData = null; // Clear class list data
                          });
                          if (value != null) {
                            _fetchClassListDetails(value);
                          }
                        },
                        items: classListItems,
                        isExpanded: true,
                      );
                    },
                  ),
                  SizedBox(height: 16),

                  // Display class list details
                  if (classListData != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Class ID: ${classListData!['classId']}'),
                            Text(
                                'Academic Year: ${classListData!['academicYear']}'),
                            Text(
                                'Grade Level: ${classListData!['gradeLevel']}'),
                            Text('Subject: ${classListData!['subject']}'),
                            Text('Teacher: ${classListData!['teacher']}'),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                  ],

                  // Display students in the selected class list
                  Expanded(
                    child: students.isEmpty
                        ? Center(
                            child:
                                Text('No students found in this class list.'))
                        : ListView.builder(
                            itemCount: students.length,
                            itemBuilder: (context, index) {
                              final student = students[index];
                              final studentData =
                                  student.data() as Map<String, dynamic>;
                              final studentName =
                                  studentData['name'] ?? 'No Name';
                              final studentGender =
                                  studentData['gender'] ?? 'Unknown';
                              final guardianName =
                                  studentData['guardianName'] ?? 'No Guardian';
                              final phoneNumber =
                                  studentData['contactNumber'] ?? 'N/A';
                              final studentImageUrl =
                                  studentData['imageUrl'] ?? '';
                              final grades = studentData['grades']
                                      ?[classListData!['classId']] ??
                                  {};

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 8.0, horizontal: 16.0),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: studentImageUrl.isNotEmpty
                                        ? NetworkImage(studentImageUrl)
                                        : null,
                                    child: studentImageUrl.isEmpty
                                        ? Icon(Icons.person, size: 30)
                                        : null,
                                    radius: 30,
                                  ),
                                  title: Text(studentName),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Gender: $studentGender'),
                                      Text('Guardian: $guardianName'),
                                      Text('Phone: $phoneNumber'),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.message,
                                        color: Colors.green),
                                    onPressed: _hasPermission &&
                                            phoneNumber != 'N/A'
                                        ? () =>
                                            _sendMessage(phoneNumber, grades)
                                        : null,
                                    tooltip: _hasPermission
                                        ? 'Send grade notification'
                                        : 'SMS permission required',
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
