import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactUsScreen extends StatefulWidget {
  @override
  _ContactUsScreenState createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  String address = '', phone = '', email = '', locationStr = '';
  bool isLoading = true;
  String? errorMessage;

  Future<void> _loadContactUs() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final value = await FireStoreUtils().getContactUs();
      if (!mounted) return;
      // #region agent log
      final _lp = '/Users/sudimard/Downloads/Lalago/.cursor/debug.log';
      try {
        File(_lp).writeAsStringSync(
          '${jsonEncode({"location":"ContactUsScreen.dart:_loadContactUs","message":"contact loaded","data":{"phone":value['Phone']?.toString(),"address":value['Address']?.toString()},"timestamp":DateTime.now().millisecondsSinceEpoch,"hypothesisId":"H1"})}\n',
          mode: FileMode.append,
        );
      } catch (_) {}
      // #endregion
      setState(() {
        address = value['Address']?.toString() ?? '';
        phone = value['Phone']?.toString() ?? '';
        email = value['Email']?.toString() ?? '';
        locationStr = value['Location']?.toString() ?? '';
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadContactUs();
  }

  void _showPhoneActions(BuildContext context) {
    final isDark = isDarkMode(context);
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                phone,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'On Simulator, Call may not open. Use Copy to paste the number.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _launchPhone();
                },
                icon: const Icon(Icons.phone),
                label: const Text('Call'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied: $phone'),
                      backgroundColor: Color(COLOR_PRIMARY),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy number'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchPhone() async {
    // #region agent log
    final _logPath = '/Users/sudimard/Downloads/Lalago/.cursor/debug.log';
    void _log(String msg, Map<String, dynamic> data, String hid) {
      try {
        File(_logPath).writeAsStringSync(
          '${jsonEncode({"location":"ContactUsScreen.dart:_launchPhone","message":msg,"data":data,"timestamp":DateTime.now().millisecondsSinceEpoch,"hypothesisId":hid})}\n',
          mode: FileMode.append,
        );
      } catch (_) {}
    }
    _log('_launchPhone called', {
      'phone': phone,
      'phoneEmpty': phone.isEmpty,
      'platform': Platform.operatingSystem,
    }, 'H1');
    // #endregion
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    try {
      // #region agent log
      final canLaunch = await canLaunchUrl(uri);
      _log('canLaunchUrl result', {'canLaunch': canLaunch, 'uri': uri.toString()}, 'H2');
      // #endregion
      // Try launch() - same API used by OrderDetailsScreen for Call Driver;
      // launchUrl can fail silently on some platforms despite completing.
      // #region agent log
      _log('calling launch', {'canLaunchWas': canLaunch}, 'H3');
      // #endregion
      await launch('tel:$phone');
      // #region agent log
      _log('launch completed', {}, 'H3');
      // #endregion
    } catch (e) {
      // #region agent log
      _log('launchPhone catch', {'error': e.toString()}, 'H3');
      // #endregion
      if (!mounted) return;
      setState(() => errorMessage = 'Could not open phone: $e');
    }
  }

  Future<void> _launchEmail() async {
    if (email.isEmpty) return;
    final uri = Uri.parse('mailto:$email');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'Could not open email: $e');
    }
  }

  Future<void> _launchAddress() async {
    if (address.isEmpty) return;
    final uri = Uri.parse(
      'geo:0,0?q=${Uri.encodeComponent(address)}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => errorMessage = 'Could not open maps: $e');
    }
  }

  bool get _hasContactInfo =>
      address.isNotEmpty || phone.isNotEmpty || email.isNotEmpty;

  LatLng? _parseLocation() {
    if (locationStr.isEmpty) return null;
    final parts = locationStr.split(',').map((e) => e.trim()).toList();
    if (parts.length < 2) return null;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = isDarkMode(context);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Color(COLOR_PRIMARY),
          elevation: 0,
          iconTheme: IconThemeData(
            color: isDark ? Colors.grey.shade200 : Colors.white,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Contact Us',
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        floatingActionButton: phone.isNotEmpty
            ? FloatingActionButton(
                heroTag: "contactUs",
                onPressed: () => _showPhoneActions(context),
                backgroundColor: Color(COLOR_ACCENT),
                child: Icon(
                  CupertinoIcons.phone_solid,
                  color: isDark ? Colors.black : Colors.white,
                ),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _loadContactUs,
          child: _buildBody(context, theme, isDark),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator.adaptive(
          valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
        ),
      );
    }

    if (errorMessage != null) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SelectableText.rich(
                    TextSpan(
                      text: errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadContactUs,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_hasContactInfo) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Text(
              'Contact information not available',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Material(
        elevation: 2,
        color: isDark ? Colors.black12 : Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0, left: 16, top: 16),
              child: Text(
                "Our Address",
                style: theme.textTheme.titleLarge?.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _AddressSection(
              address: address,
              onTap: () => _launchAddress(),
              isDark: isDark,
            ),
            if (_parseLocation() != null) _LocationMap(latLng: _parseLocation()!),
            ListTile(
              onTap: phone.isNotEmpty ? () => _showPhoneActions(context) : null,
              title: Text(
                'Phone',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(phone.isEmpty ? '—' : phone),
              trailing: phone.isNotEmpty
                  ? Icon(
                      CupertinoIcons.chevron_forward,
                      color: isDark ? Colors.white54 : Colors.black54,
                    )
                  : null,
            ),
            ListTile(
              onTap: email.isNotEmpty ? _launchEmail : null,
              title: Text(
                'Email Us',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(email.isEmpty ? '—' : email),
              trailing: email.isNotEmpty
                  ? Icon(
                      CupertinoIcons.chevron_forward,
                      color: isDark ? Colors.white54 : Colors.black54,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationMap extends StatelessWidget {
  const _LocationMap({required this.latLng});

  final LatLng latLng;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        height: 180,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: latLng,
              zoom: 14,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('contact'),
                position: latLng,
              ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({
    required this.address,
    required this.onTap,
    required this.isDark,
  });

  final String address;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(
        right: 16.0,
        left: 16,
        top: 16,
        bottom: 16,
      ),
      child: Text(
        address.replaceAll(r'\n', '\n'),
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
      ),
    );

    if (address.isEmpty) return content;

    return InkWell(
      onTap: onTap,
      child: content,
    );
  }
}
