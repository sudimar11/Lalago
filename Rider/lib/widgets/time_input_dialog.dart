import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';

class TimeInputDialog extends StatefulWidget {
  final String? currentTime;
  final Function(String) onTimeSelected;

  const TimeInputDialog({
    Key? key,
    this.currentTime,
    required this.onTimeSelected,
  }) : super(key: key);

  @override
  _TimeInputDialogState createState() => _TimeInputDialogState();
}

class _TimeInputDialogState extends State<TimeInputDialog> {
  late TimeOfDay _selectedTime;
  final TextEditingController _timeController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentTime != null && widget.currentTime!.isNotEmpty) {
      _selectedTime = _parseTimeString(widget.currentTime!);
    } else {
      _selectedTime = TimeOfDay.now();
    }
    _updateTimeController();
  }

  TimeOfDay _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(' ');
      if (parts.length == 2) {
        final timePart = parts[0];
        final period = parts[1];
        final timeParts = timePart.split(':');
        if (timeParts.length == 2) {
          int hour = int.parse(timeParts[0]);
          int minute = int.parse(timeParts[1]);

          if (period.toLowerCase() == 'pm' && hour != 12) {
            hour += 12;
          } else if (period.toLowerCase() == 'am' && hour == 12) {
            hour = 0;
          }

          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (e) {
      // If parsing fails, return current time
    }
    return TimeOfDay.now();
  }

  void _updateTimeController() {
    final period = _selectedTime.period == DayPeriod.am ? 'AM' : 'PM';
    int displayHour = _selectedTime.hour;
    if (displayHour == 0) {
      displayHour = 12;
    } else if (displayHour > 12) {
      displayHour -= 12;
    }
    _timeController.text =
        '${displayHour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')} $period';
    print(
        '🕐 DEBUG: TimeInputDialog - Updated controller text: "${_timeController.text}"');
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(COLOR_ACCENT),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      print(
          '🕐 DEBUG: TimeInputDialog - Time picked: ${picked.hour}:${picked.minute} ${picked.period}');
      setState(() {
        _selectedTime = picked;
        _updateTimeController();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      title: Text(
        'Set Check-in Time',
        style: TextStyle(
          color: isDarkMode(context) ? Colors.white : Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Please set your preferred check-in time',
            style: TextStyle(
              color: isDarkMode(context)
                  ? Colors.grey.shade300
                  : Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _selectTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDarkMode(context)
                      ? Colors.grey.shade600
                      : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: Color(COLOR_ACCENT),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _timeController.text,
                      style: TextStyle(
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: isDarkMode(context)
                  ? Colors.grey.shade400
                  : Colors.grey.shade600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : () => _saveTime(),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(COLOR_ACCENT),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isSaving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _saveTime() async {
    if (_isSaving) {
      print(
          '⚠️ DEBUG: Save operation already in progress, ignoring duplicate call');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    print('🔄 DEBUG: Starting save operation, _isSaving set to true');

    try {
      print(
          '🕐 DEBUG: Starting to save check-in time: ${_timeController.text}');
      await widget.onTimeSelected(_timeController.text);
      print('✅ DEBUG: Check-in time saved successfully');

      // Reset saving state
      setState(() {
        _isSaving = false;
      });
      print('🔄 DEBUG: Save operation completed, _isSaving set to false');

      // Close dialog after successful save
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ DEBUG: Error saving check-in time: $e');
      setState(() {
        _isSaving = false;
      });
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving time: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }
}
