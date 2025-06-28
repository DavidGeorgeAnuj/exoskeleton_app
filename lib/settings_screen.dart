import 'package:flutter/material.dart';

// Define the type for the command sending function
typedef SendCommandCallback = void Function(String commandType, {Map<String, dynamic>? params});
// Define the type for the Admin role request callback (includes password logic in parent)
typedef RequestAdminRoleCallback = void Function();


class SettingsScreen extends StatefulWidget {
  final String initialIp;
  final bool isConnected;
  final String currentRole;
  final bool isAdminPasswordRequired; // New: Status from parent
  final SendCommandCallback sendCommand; // For 'release_admin_role'
  final RequestAdminRoleCallback onRequestAdminRolePressed; // New: Callback for 'request_admin_role'


  const SettingsScreen({
    Key? key,
    required this.initialIp,
    required this.isConnected,
    required this.currentRole,
    required this.isAdminPasswordRequired, // Required
    required this.sendCommand,
    required this.onRequestAdminRolePressed, // Required
  }) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;
  late bool _isConnected;
  late String _currentRole;
  late bool _isAdminPasswordRequired; // State mirror

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialIp);
    _isConnected = widget.isConnected;
    _currentRole = widget.currentRole;
    _isAdminPasswordRequired = widget.isAdminPasswordRequired; // Initialize from widget
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update internal state if the widget properties change (especially role and connection status)
    if (widget.isConnected != oldWidget.isConnected ||
        widget.currentRole != oldWidget.currentRole ||
        widget.isAdminPasswordRequired != oldWidget.isAdminPasswordRequired // Also update if password status changes
    ) {
      setState(() {
        _isConnected = widget.isConnected;
        _currentRole = widget.currentRole;
        _isAdminPasswordRequired = widget.isAdminPasswordRequired;
      });
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Button enablement logic based on connection and role
    bool requestAdminEnabled = _isConnected && _currentRole == "User"; // Changed
    bool releaseAdminEnabled = _isConnected && _currentRole == "Admin"; // Changed

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: <Widget>[
            const Text(
              'Server IP Address:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ipController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g., 192.168.1.100',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 15.0),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final newIp = _ipController.text.trim();
                if (newIp.isNotEmpty) {
                  Navigator.pop(context, newIp);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('IP address cannot be empty.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('Save IP'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'The port will remain fixed at 8765.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Divider(height: 40),
            const Text(
              'Client Role Management:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Current Role: $_currentRole',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _currentRole == "Admin" // Changed
                    ? Colors.blue[800]
                    : (_currentRole == "User" ? Colors.orange[800] : Colors.grey[700]),
              ),
            ),
             const SizedBox(height: 4),
             if (_currentRole == "User" && _isConnected) // Show password status only for User role when connected
               Text(
                 _isAdminPasswordRequired
                     ? 'Admin password required for first request.'
                     : 'Admin password already set. No password needed.',
                 style: TextStyle(
                   fontSize: 12,
                   color: _isAdminPasswordRequired ? Colors.red[700] : Colors.green[700],
                 ),
               ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ElevatedButton(
                      // Use the callback provided by the parent for the Request action
                      onPressed: requestAdminEnabled
                          ? () => widget.onRequestAdminRolePressed.call() // Call the passed callback
                          : null,
                      child: const Text('Request Admin'), // Changed text
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 14),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ElevatedButton(
                      // Use the parent's sendCommand for the Release action
                      onPressed: releaseAdminEnabled
                          ? () => widget.sendCommand("release_admin_role") // Changed command name
                          : null,
                      child: const Text('Release Admin'), // Changed text
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 14),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_isConnected)
              const Text(
                'Connect to the server to manage your role.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (_isConnected && _currentRole == "Admin") // Changed
              const Text(
                'You have the Admin role. Release it to allow others to request.', // Changed
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (_isConnected && _currentRole == "User")
              const Text(
                'You have the User role. Request Admin to send commands.', // Changed
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}