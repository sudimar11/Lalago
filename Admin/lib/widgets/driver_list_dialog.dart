import 'package:flutter/material.dart';
import 'package:brgy/driver_location_page.dart';
import 'package:brgy/services/driver_service.dart';
import 'package:brgy/models/driver.dart';

class DriverListDialog extends StatefulWidget {
  const DriverListDialog({super.key});

  @override
  State<DriverListDialog> createState() => _DriverListDialogState();
}

class _DriverListDialogState extends State<DriverListDialog> {
  final DriverService _service = DriverService();
  final Set<String> _busy = {};
  String _filter = 'activeToday'; // 'all' | 'activeToday'

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.drive_eta, color: Colors.orange),
          SizedBox(width: 8),
          Text('Drivers'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: MediaQuery.of(context).size.height * 0.6,
        child: StreamBuilder<List<Driver>>(
          stream: _service.streamDrivers(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final List<Driver> drivers = List<Driver>.from(snapshot.data ?? []);
            drivers.sort((a, b) =>
                (a.name.toLowerCase()).compareTo(b.name.toLowerCase()));
            List<Driver> toShow = _filter == 'activeToday'
                ? drivers.where((d) => d.activeToday).toList()
                : drivers;
            final String emptyMessage = toShow.isEmpty && _filter == 'activeToday'
                ? 'No active riders today'
                : 'No drivers found';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ChoiceChip(
                      label: Text('All'),
                      selected: _filter == 'all',
                      onSelected: (selected) {
                        if (selected) setState(() => _filter = 'all');
                      },
                    ),
                    SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('Active today'),
                      selected: _filter == 'activeToday',
                      onSelected: (selected) {
                        if (selected) setState(() => _filter = 'activeToday');
                      },
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Expanded(
                  child: toShow.isEmpty
                      ? Center(child: Text(emptyMessage))
                      : ListView.separated(
                          itemCount: toShow.length,
                          separatorBuilder: (_, __) => Divider(height: 1),
                          itemBuilder: (context, index) {
                            final Driver d = toShow[index];
                            final bool disabled = _busy.contains(d.id);
                            return ListTile(
                              title: Text(
                                d.name.isEmpty ? 'Unknown Driver' : d.name,
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: d.phoneNumber.isEmpty
                                  ? null
                                  : Text(d.phoneNumber),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.location_on,
                                      color: d.hasLocation
                                          ? Colors.orange
                                          : Colors.grey,
                                    ),
                                    tooltip: d.hasLocation
                                        ? 'View location'
                                        : 'Location not available',
                                    onPressed: d.hasLocation
                                        ? () {
                                            Navigator.of(context).pop();
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    DriverLocationPage(
                                                  driverName: d.name,
                                                  latitude: d.latitude!,
                                                  longitude: d.longitude!,
                                                ),
                                              ),
                                            );
                                          }
                                        : () {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Location not available'),
                                              ),
                                            );
                                          },
                                  ),
                                  Opacity(
                                    opacity: disabled ? 0.5 : 1.0,
                                    child: Switch(
                                      value: d.active,
                                      onChanged: disabled
                                          ? null
                                          : (bool val) async {
                                              setState(() => _busy.add(d.id));
                                              try {
                                                await _service.setActive(
                                                    d.id, val);
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Failed to update '
                                                          '${d.name}: $e'),
                                                      backgroundColor:
                                                          Colors.red,
                                                    ),
                                                  );
                                                }
                                              } finally {
                                                if (mounted) {
                                                  setState(
                                                      () => _busy.remove(d.id));
                                                }
                                              }
                                            },
                                      activeColor: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'),
        ),
      ],
    );
  }
}
