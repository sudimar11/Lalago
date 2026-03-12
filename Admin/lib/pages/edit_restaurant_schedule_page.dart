import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/working_hours_model.dart';
import '../services/vendor_service.dart';

class EditRestaurantSchedulePage extends StatefulWidget {
  const EditRestaurantSchedulePage({
    super.key,
    required this.vendorId,
    required this.initialWorkingHours,
    this.restaurantName,
  });

  final String vendorId;
  final List<WorkingHoursModel> initialWorkingHours;
  final String? restaurantName;

  @override
  State<EditRestaurantSchedulePage> createState() =>
      _EditRestaurantSchedulePageState();
}

class _EditRestaurantSchedulePageState extends State<EditRestaurantSchedulePage> {
  late List<WorkingHoursModel> _workingHours;
  final VendorService _vendorService = VendorService();
  bool _isSaving = false;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    final byDay = <String, WorkingHoursModel>{};
    for (final wh in widget.initialWorkingHours) {
      if (wh.day != null && wh.day!.isNotEmpty) {
        byDay[wh.day!] = WorkingHoursModel(
          day: wh.day,
          timeslot: wh.timeslot
              .map((t) => Timeslot(from: t.from, to: t.to))
              .toList(),
        );
      }
    }
    _workingHours = _days
        .map((d) =>
            byDay[d] ?? WorkingHoursModel(day: d, timeslot: []))
        .toList();
  }

  DateTime _parseTime(String time) {
    final s = time.trim();
    if (s.isEmpty) throw FormatException('Empty time');
    return DateFormat('HH:mm').parse(s);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    return DateFormat('HH:mm').format(
      DateTime(1970, 1, 1, t.hour, t.minute),
    );
  }

  Future<TimeOfDay?> _selectTime({TimeOfDay? initial}) async {
    FocusScope.of(context).unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
    return picked;
  }

  String? _validate() {
    for (final wh in _workingHours) {
      for (final slot in wh.timeslot) {
        final f = (slot.from ?? '').toString().trim();
        final t = (slot.to ?? '').toString().trim();
        if (f.isEmpty || t.isEmpty) {
          return 'Please enter both start and end time for each slot.';
        }
        try {
          final fromDt = _parseTime(f);
          final toDt = _parseTime(t);
          if (!toDt.isAfter(fromDt)) {
            return 'End time must be after start time (${wh.day}).';
          }
        } catch (_) {
          return 'Invalid time format. Use HH:mm.';
        }
      }
      if (wh.timeslot.length > 1) {
        final sorted = List<Timeslot>.from(wh.timeslot)
          ..sort((Timeslot a, Timeslot b) {
            final ad = _parseTime((a.from ?? '').toString());
            final bd = _parseTime((b.from ?? '').toString());
            return ad.compareTo(bd);
          });
        for (var i = 0; i < sorted.length - 1; i++) {
          final curEnd = _parseTime((sorted[i].to ?? '').toString());
          final nextStart = _parseTime((sorted[i + 1].from ?? '').toString());
          if (!nextStart.isAfter(curEnd)) {
            return 'Overlapping time slots on ${wh.day}.';
          }
        }
      }
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save schedule changes?'),
        content: const Text(
          'This will update the restaurant schedule. '
          'Changes will be visible in the Customer and Rider apps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _vendorService.updateVendorSchedule(widget.vendorId, _workingHours);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schedule updated successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.restaurantName ?? 'Edit Schedule'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Center(child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            )
          else
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Working Hours',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _workingHours.length,
              itemBuilder: (context, index) {
                final wh = _workingHours[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                wh.day ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle),
                                color: Colors.orange,
                                onPressed: () {
                                  setState(() {
                                    wh.timeslot.add(Timeslot(from: '', to: ''));
                                  });
                                },
                              ),
                            ],
                          ),
                          ...wh.timeslot.asMap().entries.map((entry) {
                            final i = entry.key;
                            final slot = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final initial = slot.from != null &&
                                                slot.from!.isNotEmpty
                                            ? _timeOfDayFromString(slot.from!)
                                            : TimeOfDay.now();
                                        final t = await _selectTime(
                                            initial: initial);
                                        if (t != null) {
                                          setState(() {
                                            slot.from = _formatTimeOfDay(t);
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12, horizontal: 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Colors.grey.shade400),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          slot.from?.isEmpty == true
                                              ? 'Start Time'
                                              : slot.from!,
                                          style: TextStyle(
                                            color: slot.from?.isEmpty == true
                                                ? Colors.grey
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        TimeOfDay initial = TimeOfDay.now();
                                        if (slot.to != null &&
                                            slot.to!.isNotEmpty) {
                                          initial =
                                              _timeOfDayFromString(slot.to!);
                                        }
                                        final t =
                                            await _selectTime(initial: initial);
                                        if (t != null) {
                                          setState(() {
                                            if (t.hour == 0 && t.minute == 0) {
                                              slot.to = '23:59';
                                            } else {
                                              slot.to = _formatTimeOfDay(t);
                                            }
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12, horizontal: 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: Colors.grey.shade400),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          slot.to?.isEmpty == true
                                              ? 'End Time'
                                              : slot.to!,
                                          style: TextStyle(
                                            color: slot.to?.isEmpty == true
                                                ? Colors.grey
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle,
                                        color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        wh.timeslot.removeAt(i);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  _isSaving ? 'Saving...' : 'Save',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _timeOfDayFromString(String s) {
    try {
      final t = s.trim();
      if (t.isEmpty) return TimeOfDay.now();
      final dt = DateFormat('HH:mm').parse(t);
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      return TimeOfDay.now();
    }
  }
}
