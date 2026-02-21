import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';

class AttendanceCard extends StatelessWidget {
  final String? checkInTime;
  final String? checkOutTime;
  final String? totalHours;
  final VoidCallback? onCheckInTap;
  final VoidCallback? onCheckOutTap;
  final bool canCheckInToday;
  final VoidCallback? onCheckInTodayTap;
  final bool? checkedInToday;
  final String? todayCheckInTime;
  final VoidCallback? onCheckOutTodayTap;
  final bool? checkedOutToday;
  final String? todayCheckOutTime;
  final bool canCheckOutToday;
  final bool? isLate;
  final double? hoursLate;
  final String? lateMessage;

  const AttendanceCard({
    Key? key,
    this.checkInTime,
    this.checkOutTime,
    this.totalHours,
    this.onCheckInTap,
    this.onCheckOutTap,
    this.canCheckInToday = false,
    this.onCheckInTodayTap,
    this.checkedInToday = false,
    this.todayCheckInTime,
    this.onCheckOutTodayTap,
    this.checkedOutToday = false,
    this.todayCheckOutTime,
    this.canCheckOutToday = false,
    this.isLate = false,
    this.hoursLate = 0.0,
    this.lateMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: null, // Remove general tap, we'll handle individual taps
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      color: Color(COLOR_ACCENT),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Attendance',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    if (checkInTime == null || checkInTime!.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Set Time',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildTappableTimeInfo(
                        context,
                        'Check In',
                        checkInTime ?? '--:--',
                        Icons.login,
                        onCheckInTap,
                        checkInTime == null || checkInTime!.isEmpty,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: _buildTappableTimeInfo(
                        context,
                        'Check Out',
                        checkOutTime ?? '--:--',
                        Icons.logout,
                        onCheckOutTap,
                        checkOutTime == null || checkOutTime!.isEmpty,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: _buildTimeInfo(
                        context,
                        'Total Hours',
                        totalHours ?? '0h 0m',
                        Icons.timer,
                      ),
                    ),
                  ],
                ),
                if ((checkInTime == null || checkInTime!.isEmpty) ||
                    (checkOutTime == null || checkOutTime!.isEmpty))
                  const SizedBox(height: 12),
                if ((checkInTime == null || checkInTime!.isEmpty) ||
                    (checkOutTime == null || checkOutTime!.isEmpty))
                  Center(
                    child: Text(
                      'Tap on Check In or Check Out to set your times',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(COLOR_ACCENT),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                // Today's Check-in Status
                if (checkedInToday == true && todayCheckInTime != null)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Checked in today at $todayCheckInTime',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                if (checkedInToday == true && todayCheckInTime != null)
                  const SizedBox(height: 12),
                // Today's Check-out Status
                if (checkedOutToday == true && todayCheckOutTime != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Checked out today at $todayCheckOutTime',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (checkedOutToday == true && todayCheckOutTime != null)
                  const SizedBox(height: 12),
                // Late Status Display
                if (isLate == true && hoursLate != null && hoursLate! > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Late Check-in',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                lateMessage ??
                                    'You are ${hoursLate!.toStringAsFixed(1)} hours late',
                                style: TextStyle(
                                  color: Colors.red.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isLate == true && hoursLate != null && hoursLate! > 0)
                  const SizedBox(height: 12),
                // Single toggle button for Check In / Check Out
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: checkedInToday == true
                        ? (canCheckOutToday ? onCheckOutTodayTap : null)
                        : (canCheckInToday ? onCheckInTodayTap : null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: checkedOutToday == true
                          ? Colors.grey.shade400
                          : checkedInToday == true
                              ? Colors.blue
                              : Color(COLOR_ACCENT),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: checkedOutToday == true ? 0 : 2,
                    ),
                    child: Text(
                      checkedOutToday == true
                          ? 'Already Checked Out'
                          : checkedInToday == true
                              ? 'Check Out Today'
                              : 'Check In Today',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTappableTimeInfo(BuildContext context, String label, String time,
      IconData icon, VoidCallback? onTap, bool isEmpty) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          children: [
            Icon(
              icon,
              color: Color(COLOR_ACCENT),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode(context)
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
            if (isEmpty) const SizedBox(height: 2),
            if (isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tap to Set',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInfo(
      BuildContext context, String label, String time, IconData icon) {
    return Column(
      children: [
        Icon(
          icon,
          color: Color(COLOR_ACCENT),
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDarkMode(context)
                ? Colors.grey.shade400
                : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }
}
