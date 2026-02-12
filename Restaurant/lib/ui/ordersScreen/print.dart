import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class BluetoothPrinterPage extends StatefulWidget {
  @override
  _BluetoothPrinterPageState createState() => _BluetoothPrinterPageState();
}

class _BluetoothPrinterPageState extends State<BluetoothPrinterPage> {
  List<String> availableBluetoothDevices = [];
  String? selectedDevice;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    requestBluetoothPermissions();
  }

  // Request required Bluetooth permissions
  Future<void> requestBluetoothPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothConnect] == PermissionStatus.granted &&
        statuses[Permission.bluetoothScan] == PermissionStatus.granted) {
      fetchBluetoothDevices();
    } else {
      showSnackBar("Bluetooth permissions are required to use this feature.");
    }
  }

  // Fetch paired Bluetooth devices
  Future<void> fetchBluetoothDevices() async {
    try {
      final List<dynamic>? devices =
          await PrintBluetoothThermal.pairedBluetooths;

      if (devices != null && devices.isNotEmpty) {
        setState(() {
          availableBluetoothDevices = devices.cast<String>();
        });
      } else {
        showSnackBar(
            "No paired devices found. Pair a device in Bluetooth settings.");
      }
    } catch (e) {
      print("Error fetching devices: $e");
      showSnackBar("Failed to fetch devices. Try again.");
    }
  }

  // Connect to the selected Bluetooth device
  Future<void> connectToDevice(String mac) async {
    try {
      final bool result = await PrintBluetoothThermal.connect(macPrinterAddress : mac);

      if (result == "true") {
        setState(() {
          selectedDevice = mac;
          isConnected = true;
        });
        showSnackBar("Connected to the printer successfully.");
      } else {
        showSnackBar("Failed to connect to the printer.");
      }
    } catch (e) {
      print("Error connecting to device: $e");
      showSnackBar("An error occurred while connecting.");
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bluetooth Printer"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: fetchBluetoothDevices,
              child: const Text("Refresh Devices"),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: availableBluetoothDevices.isEmpty
                  ? const Center(child: Text("No devices found."))
                  : ListView.builder(
                      itemCount: availableBluetoothDevices.length,
                      itemBuilder: (context, index) {
                        String device = availableBluetoothDevices[index];
                        List<String> deviceInfo = device.split("#");
                        String deviceName = deviceInfo[0];
                        String macAddress = deviceInfo[1];

                        return ListTile(
                          title: Text(deviceName.isEmpty
                              ? "Unknown Device"
                              : deviceName),
                          subtitle: Text("MAC: $macAddress"),
                          trailing: selectedDevice == macAddress
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          onTap: () {
                            connectToDevice(macAddress);
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed:
                  isConnected ? () => showSnackBar("Printer is ready.") : null,
              child: const Text("Confirm Connection"),
            ),
          ],
        ),
      ),
    );
  }
}
