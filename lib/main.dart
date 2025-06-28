import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// Import the plot screen file
import 'plot_screen.dart';
// Import the settings screen file
import 'settings_screen.dart';


// --- Define the desired log frequency ---
// This is the rate at which data is ADDED to the _logData list.
// Make sure this frequency is lower than or equal to the server's state update frequency
const double DESIRED_LOG_FREQUENCY = 1.0; // Hz (1 entry per second)
const double DESIRED_LOG_INTERVAL = 1.0 / DESIRED_LOG_FREQUENCY; // seconds


class MotorControlScreen extends StatefulWidget {
  const MotorControlScreen({Key? key}) : super(key: key);

  @override
  _MotorControlScreenState createState() => _MotorControlScreenState();
}

class _MotorControlScreenState extends State<MotorControlScreen> {
  // --- WebSocket Connection Details ---
  String _serverIp = '10.196.34.53';
  final int _serverPort = 8765; // WebSocket port (fixed)
  WebSocketChannel? _channel;
  bool _isConnected = false;

  // --- Client Role ---
  String _clientRole = "User"; // Default role is User
  // --- Password Status for Admin Role ---
  bool _isAdminPasswordRequired = false; // Server tells us if password is needed for Admin


  // --- Motor State Variables (Received from Server) ---
  double _position = 0.0;
  double _velocity = 0.0;
  double _current = 0.0; // Measured Q-axis current
  double _temperature = 0.0;
  int _error = 0;
  String _errorDescription = "";
  String _controlMode = "IDLE";

  // Commanded values stored client-side when sending commands.
  // Used to include commanded values in log data for plotting.
  double _cmdPosition = 0.0;
  double _cmdVelocity = 0.0;
  double _cmdCurrent = 0.0; // Corresponds to i_des
  double _cmdKp = 0.0;
  double _cmdKd = 0.0;


  // --- Data Accumulation for Logging ---
  final List<Map<String, dynamic>> _logData = [];
  double _lastLogTimestamp = 0.0;


  // --- Controllers for Command Input Fields ---
  final TextEditingController _desPController = TextEditingController(text: '0.0');
  final TextEditingController _desSController = TextEditingController(text: '0.0');
  final TextEditingController _desTController = TextEditingController(text: '0.0');
  final TextEditingController _kpController = TextEditingController(text: '0.0');
  final TextEditingController _kdController = TextEditingController(text: '0.0');

  // --- Lifecycle Methods ---
  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  @override
  void dispose() {
    // Attempt to release Admin role before closing if currently Admin
    if (_clientRole == "Admin" && _isConnected) {
        print("Attempting to release Admin role on dispose...");
        // We don't await this as dispose should be quick
        try {
            _sendCommand("release_admin_role"); // Use the new command name
        } catch(e) {
           print("Error sending release_admin_role on dispose: $e");
        }
    }
    // Send a specific close code if possible, e.g., 1000 for normal closure
    _channel?.sink.close(1000, 'Client Disposed');
    _desPController.dispose();
    _desSController.dispose();
    _desTController.dispose();
    _kpController.dispose();
    _kdController.dispose();
    super.dispose();
  }

  // --- WebSocket Connection Logic ---
  void _connectWebSocket() {
     if (_isConnected || _channel != null) {
       print('Connection request ignored: already connected or channel exists.');
       return;
     }

     print('Attempting to connect to ws://$_serverIp:$_serverPort');

     try {
      final uri = Uri.parse('ws://$_serverIp:$_serverPort');
      _channel = WebSocketChannel.connect(uri);

      _channel!.ready.then((_) {
        if (!mounted) return;
        setState(() {
          _isConnected = true;
           _logData.clear(); // Clear log on new connection
           _lastLogTimestamp = 0.0; // Reset last log timestamp on connection
           // Reset state display variables on fresh connect
           _position = 0.0;
           _velocity = 0.0;
           _current = 0.0;
           _temperature = 0.0;
           _error = 0;
           _errorDescription = "";
           _controlMode = "IDLE";
           // Reset commanded state variables
           _cmdPosition = 0.0;
           _cmdVelocity = 0.0;
           _cmdCurrent = 0.0;
           _cmdKp = 0.0;
           _cmdKd = 0.0;
           _clientRole = "User"; // Assume User until server says otherwise
           _isAdminPasswordRequired = false; // Assume false until server says otherwise
        });
        print('WebSocket Connected!');
        _showSnackBar('WebSocket Connected! Log cleared.');

        _listenForMessages();
      }).catchError((error) {
        print('WebSocket Connection Error: $error');
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _channel = null;
           _lastLogTimestamp = 0.0;
           _controlMode = "DISCONNECTED";
           _errorDescription = error.toString();
           _clientRole = "User"; // Ensure role is reset
           _isAdminPasswordRequired = false; // Ensure status is reset
        });
         _showSnackBar('Connection failed. Check IP, Port, and server. Error: $error');
      });

    } catch (e) {
      print('Failed to create WebSocket channel: $e');
       if (!mounted) return;
      setState(() {
        _isConnected = false;
        _channel = null;
         _controlMode = "DISCONNECTED";
         _errorDescription = e.toString();
         _clientRole = "User"; // Ensure role is reset
         _isAdminPasswordRequired = false; // Ensure status is reset
      });
       _showSnackBar('Failed to create WebSocket channel: $e');
    }
  }

  // --- Message Listening Logic (Handles State and Status Messages) ---
  void _listenForMessages() {
    if (_channel == null) {
      print('Cannot listen, channel is null.');
      return;
    }

    _channel!.stream.listen(
      (message) {
        try {
          final Map<String, dynamic> data = json.decode(message);

          // --- Check for status/error messages first ---
          // We only check for the 'status' key, which is unique to command responses
          if (data.containsKey("status")) {
             final status = data["status"];
             final msg = data["message"] ?? data["error"] ?? "No message"; // Get message from 'message' or 'error'
             print("Server Response ($status): $msg");
             _showSnackBar("Server: $msg");

             // If the status/error message also includes a new role, update it
             // Also check for the new password requirement flag
             if (mounted) {
                setState(() {
                   if (data.containsKey("role")) {
                      _clientRole = data['role'] ?? "User";
                      print("Client role updated from status/error message: $_clientRole");
                   }
                   if (data.containsKey("admin_password_required")) {
                       _isAdminPasswordRequired = data['admin_password_required'] as bool? ?? _isAdminPasswordRequired;
                       print("Admin password required status updated from status/error message: $_isAdminPasswordRequired");
                   }
                });
             }
             return; // Process status/error messages and stop further processing
          }

          // --- Assume it's a state message otherwise ---
          // This block is only executed if the message does NOT contain a "status" key.

          // Update state variables and client role
          if (!mounted) return;
          setState(() {
            _position = (data['position'] as num?)?.toDouble() ?? _position;
            _velocity = (data['velocity'] as num?)?.toDouble() ?? _velocity;
            _current = (data['current'] as num?)?.toDouble() ?? _current;
            _temperature = (data['temperature'] as num?)?.toDouble() ?? _temperature;

            // State messages contain the motor error code
            _error = data['error'] ?? _error;
            // Server now provides combined error_description including server-side issues
            _errorDescription = data['error_description'] ?? (_error != 0 ? "Motor Error Code: $_error" : "");
            _controlMode = data['control_mode'] ?? _controlMode;

            // Update the client's role based on the server's report from the state message
            // This handles the 'role' field in regular state updates
            _clientRole = data['role'] ?? "User"; // Default to User if role is missing
            // Update the password requirement status from the state message
            _isAdminPasswordRequired = data['admin_password_required'] as bool? ?? _isAdminPasswordRequired;


            // Optional: If server echoes commanded values in state, update them here
            // This ensures the UI reflects what the motor is *actually' being commanded by the server
            // (which might be different from this client's last command if another Admin is active)
            _cmdPosition = (data['cmd_position'] as num?)?.toDouble() ?? _cmdPosition;
            _cmdVelocity = (data['cmd_velocity'] as num?)?.toDouble() ?? _cmdVelocity;
            _cmdCurrent = (data['cmd_current'] as num?)?.toDouble() ?? _cmdCurrent;
            _cmdKp = (data['kp'] as num?)?.toDouble() ?? _cmdKp; // Use 'kp'/'kd' from server if echoed
            _cmdKd = (data['kd'] as num?)?.toDouble() ?? _cmdKd;


             // Trigger a UI update based on the state change (already inside setState)
          });


          // --- Data Accumulation for Logging (at desired frequency) ---
          // Check if the received state has a timestamp
          double? currentTimestamp = (data['timestamp'] as num?)?.toDouble();


          if (currentTimestamp != null) {
              // Only log if the timestamp is significantly different from the last logged one
              // OR if this is the very first entry (_lastLogTimestamp is 0.0)
              if (_lastLogTimestamp == 0.0 || (currentTimestamp - _lastLogTimestamp) >= DESIRED_LOG_INTERVAL) {

                 // Create a new map for logging
                 // Include relevant fields from the state message and the last sent commands
                 // Ensure keys match expected plot_screen keys
                 Map<String, dynamic> logEntry = {
                     "timestamp": currentTimestamp,
                     // Use the state variables which were just updated by setState
                     "position": _position,
                     "velocity": _velocity,
                     "current": _current,
                     "temperature": _temperature,
                     "error": _error,
                     "error_description": _errorDescription, // Log the combined desc
                     "control_mode": _controlMode,
                     // Add the last commanded values from the app's state
                     // Use the echoed values from the server state which were just updated
                     "cmd_position": _cmdPosition,
                     "cmd_velocity": _cmdVelocity,
                     "cmd_current": _cmdCurrent, // i_des sent / echoed
                     "cmd_kp": _cmdKp,
                     "cmd_kd": _cmdKd,
                     "client_role_at_log": _clientRole, // Log the role when the entry was made
                 };

                 _logData.add(logEntry); // Add the combined state map
                 _lastLogTimestamp = currentTimestamp;

                 // We don't strictly *need* an extra setState here just for log count,
                 // as the setState above updates the UI based on motor state and role.
                 // However, leaving it doesn't hurt and can be useful for debugging.
                 // if (mounted) {
                 //    setState(() {});
                 // }
              }
           }
          // --- End Data Accumulation ---


        } on FormatException {
          print('Error decoding JSON message: FormatException, Message: $message');
           // Avoid too many snackbars on continuous errors
           // _showSnackBar('Error decoding message JSON.');
        } catch (e) {
          print('Error processing received message: $e, Message: $message');
           // Avoid too many snackbars on continuous errors
           // _showSnackBar('Error processing message.');
        }
      },
      onError: (error) {
        print('WebSocket Stream Error: $error');
        if (!mounted) return;
        // Only update state if the connection is actually marked as connected,
        // to avoid state churn if errors happen during connection attempt etc.
        if (_isConnected) {
             setState(() {
               _isConnected = false;
               _channel = null;
               _lastLogTimestamp = 0.0; // Reset log timestamp on disconnection
               _controlMode = "DISCONNECTED";
               _errorDescription = "Stream error: ${error.toString()}";
               _clientRole = "User"; // Reset role on disconnection
               _isAdminPasswordRequired = false; // Reset status on disconnection
             });
             _showSnackBar('WebSocket stream error. Connection lost?');
        } else {
             // Handle potential errors during initial connection attempt
             setState(() {
               _errorDescription = "Error during connection attempt: ${error.toString()}";
                _clientRole = "User"; // Ensure role is user
                _isAdminPasswordRequired = false; // Ensure status is reset
             });
        }
      },
      onDone: () {
        print('WebSocket Stream Done (Connection Closed)');
        if (!mounted) return;
        // Only update state if we thought we were connected
        if (_isConnected) {
           setState(() {
             _isConnected = false;
             _channel = null;
             _lastLogTimestamp = 0.0; // Reset log timestamp on disconnection
             _controlMode = "DISCONNECTED";
             _errorDescription = "Connection closed.";
             _clientRole = "User"; // Reset role on disconnection
             _isAdminPasswordRequired = false; // Reset status on disconnection
           });
           _showSnackBar('WebSocket connection closed.');
        }
      },
    );
  }

  // --- Command Sending Logic (via WebSocket) ---
   // Now checks if the client is the Admin for certain commands
   void _sendCommand(String commandType, {Map<String, dynamic>? params}) {
    if (!_isConnected || _channel == null) {
      print('Not connected (WebSocket). Cannot send command "$commandType".');
      _showSnackBar('Not connected.');
      return;
    }

    // Check if it's a command requiring Admin privilege
    // List commands that do NOT require Admin privilege
    final bool requiresAdmin = ![
       "request_admin_role", // New command name
       "release_admin_role", // New command name
       "noop" // Assuming noop is always allowed
    ].contains(commandType);

    if (requiresAdmin && _clientRole != "Admin") {
       print('Command "$commandType" requires Admin privilege, but client is $_clientRole. Not sending.');
       // The server will also reject this, but we can give immediate feedback.
       _showSnackBar('Command requires Admin privilege.');
       // Don't send the command
       return;
    }

    try {
      final Map<String, dynamic> command = {"command": commandType};

      if (params != null) {
        command.addAll(params);
      }

      final jsonCommand = json.encode(command);
      _channel!.sink.add(jsonCommand);
      print('Sent command: $jsonCommand');
      // Server responses (status/error) will be handled by _listenForMessages

    } catch (e) {
      print('Error sending command "$commandType": $e');
       _showSnackBar('Error sending command.');
    }
  }

  // Sends the full set of state parameters (p_des, v_des, i_des, kp, kd)
  void _sendFullStateCommand() {
    // _sendCommand already checks for Admin role.
    // Check connection status explicitly here for button state, but _sendCommand does the final check.
     if (!_isConnected || _clientRole != "Admin") {
         print("Cannot send full state command: Not connected or not Admin.");
         // _showSnackBar("Cannot send command: Not connected or not Admin."); // Handled by _sendCommand if it's sent
         return; // Exit early if UI state is clearly disabled
     }

    try {
      // Parse input values, check for null
      final double? p_des = double.tryParse(_desPController.text);
      final double? v_des = double.tryParse(_desSController.text);
      final double? i_des = double.tryParse(_desTController.text);
      final double? kp = double.tryParse(_kpController.text);
      final double? kd = double.tryParse(_kdController.text);

      // Check if all values were parsed successfully
      if (p_des == null || v_des == null || i_des == null || kp == null || kd == null) {
         _showSnackBar('Invalid input. Please enter valid numbers.');
         return; // Exit function if any parse failed
      }

      // Store these commanded values in the app's state immediately
      // This makes them available for logging the next time state is received
      // (and also updates the UI if you were displaying cmd values)
      // Note: When the server echoes commands, the update in setState below
      // will be immediately overwritten by the values from the incoming state message.
      // This is fine; it ensures the UI and log uses the server's confirmed command values.
      setState(() {
        _cmdPosition = p_des;
        _cmdVelocity = v_des;
        _cmdCurrent = i_des;
        _cmdKp = kp;
        _cmdKd = kd;
      });

      final Map<String, dynamic> params = {
        "p_des": p_des,
        "v_des": v_des,
        "i_des": i_des,
        "kp": kp,
        "kd": kd,
      };

      _sendCommand("set_full_state_params", params: params);

    } catch (e) { // Catch any other potential errors during the process
      print('Error preparing full state command: $e');
      _showSnackBar('Error processing command inputs.');
    }
  }

   // Sends zero parameters THEN the hardware zero command
   void _sendZeroParamsThenHardwareZero() {
      // _sendCommand checks for Admin role
      // Check connection status explicitly here for button state
      if (!_isConnected || _clientRole != "Admin") {
         print("Cannot send zero command sequence: Not connected or not Admin.");
         // _showSnackBar("Cannot send command: Not connected or not Admin."); // Handled by _sendCommand if it's sent
         return; // Exit early if UI state is clearly disabled
      }

      // 1. Send the command to set desired parameters to zero
      _sendFullStateCommandWithZeros(); // This internally calls _sendCommand

      // 2. Then, send the hardware zero command
      // Add a small delay here in the client side to *try* and ensure
      // the zero params command arrives and is processed before the zero command,
      // although server-side processing order isn't strictly guaranteed just by this delay.
      // A more robust solution would be server-side sequencing or a dedicated zero command on the server.
      Future.delayed(const Duration(milliseconds: 50), () {
          _sendCommand("zero");
      });

       _showSnackBar("Sent zero parameters and then hardware zero command.");
       print("Sent zero parameters and then hardware zero command.");
   }

   // Helper to send a full state command with all zero parameters
   // Assumes Admin role check is done by the caller or _sendCommand
   void _sendFullStateCommandWithZeros() {
       // Update the app's tracked commanded values to zero
       setState(() {
         _cmdPosition = 0.0;
         _cmdVelocity = 0.0;
         _cmdCurrent = 0.0;
         _cmdKp = 0.0;
         _cmdKd = 0.0;
       });

       final Map<String, dynamic> params = {
         "p_des": 0.0,
         "v_des": 0.0,
         "i_des": 0.0,
         "kp": 0.0,
         "kd": 0.0,
       };

       // Use _sendCommand directly - it will check for Admin role
       _sendCommand("set_full_state_params", params: params);
   }

   // --- Handle Request Admin Role (Includes Password Logic) ---
   Future<void> _handleRequestAdminRole() async {
       if (!_isConnected) {
           _showSnackBar("Cannot request role: Not connected.");
           return;
       }
       if (_clientRole != "User") {
            _showSnackBar("Cannot request role: Already $_clientRole.");
            return;
       }

       String? password;
       // If the server indicated a password is required, show the dialog
       if (_isAdminPasswordRequired) {
           password = await _showPasswordDialog();
           if (password == null) {
               // User cancelled the dialog
               print("Admin role request cancelled by user.");
               return; // Don't send the command
           }
       }

       // Prepare params, adding password only if it was obtained from the dialog
       Map<String, dynamic>? params = password != null ? {"password": password} : null;

       // Send the request_admin_role command
       _sendCommand("request_admin_role", params: params);
   }

   // --- Show Password Dialog ---
   Future<String?> _showPasswordDialog() async {
      final TextEditingController passwordController = TextEditingController();
      return showDialog<String>(
         context: context,
         barrierDismissible: false, // User must tap a button
         builder: (BuildContext context) {
           return AlertDialog(
             title: const Text('Enter Admin Password'),
             content: TextField(
               controller: passwordController,
               obscureText: true,
               decoration: const InputDecoration(hintText: "Password"),
             ),
             actions: <Widget>[
               TextButton(
                 child: const Text('Cancel'),
                 onPressed: () {
                   Navigator.of(context).pop(); // Dismiss dialog, returns null
                 },
               ),
               TextButton(
                 child: const Text('Request'),
                 onPressed: () {
                   Navigator.of(context).pop(passwordController.text); // Dismiss dialog, returns entered text
                 },
               ),
             ],
           );
         },
      );
   }


  // --- Share Accumulated Data (Doesn't require broad storage permissions) ---
   Future<void> _shareLogData() async {
      if (_logData.isEmpty) {
        _showSnackBar("No data to share yet.");
        return;
      }

      _showSnackBar("Preparing log data for sharing...");

      // Prepare the CSV content string (same logic as saving)
      final Set<String> allKeys = {};
      for (var entry in _logData) {
          allKeys.addAll(entry.keys);
      }
      final List<String> csvHeader = allKeys.toList();
      csvHeader.sort();

      StringBuffer csvContent = StringBuffer();
      csvContent.writeln(csvHeader.join(','));

      for (var dataEntry in _logData) {
        List<String> row = [];
        for (var key in csvHeader) {
          var value = dataEntry[key];
          if (value == null) {
              row.add('');
          } else if (value is String) {
               row.add('"${value.replaceAll('"', '""')}"');
          }
          else {
             row.add(value?.toString() ?? '');
          }
        }
        csvContent.writeln(row.join(','));
      }

      try {
         // Get the temporary directory provided by the OS
         // This directory is guaranteed to be writable by your app without special permissions
         final directory = await getTemporaryDirectory();
         // Generate a unique filename for the temporary file
         final tempFileName = 'motor_log_share_${DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '_')}.csv';
         final filePath = '${directory.path}/$tempFileName';
         final file = File(filePath);

         // Write the CSV content to the temporary file
         await file.writeAsString(csvContent.toString());
         print('Temporary log file created for sharing at: ${file.path}');

         // Use the share_plus package to share the file
         // share_plus uses system Intents which handle file access securely
         // Pass the XFile object created from the temporary file path
         await Share.shareXFiles([XFile(file.path)], text: 'Motor Log Data');

         _showSnackBar("Log data prepared for sharing.");

         // Optional: Clean up the temporary file after sharing
         // Added a small delay before attempting to delete, to ensure the share sheet
         // has had time to access the file.
         Future.delayed(const Duration(seconds: 10), () async {
            if (await file.exists()) {
               try {
                 await file.delete();
                 print('Temporary log file deleted: ${file.path}');
               } catch (e) {
                 print('Error deleting temporary file ${file.path}: $e');
               }
            }
         });

      } catch (e) {
         print('Error preparing or sharing log data: $e');
         _showSnackBar('Error sharing log data: ${e.toString().split('\n').first}');
      }
   }


  // --- Clear Accumulated Log Data ---
  void _clearLogData() {
    if (_logData.isEmpty) {
      _showSnackBar("Log is already empty.");
      return;
    }
    setState(() {
      _logData.clear();
      _lastLogTimestamp = 0.0;
    });
    print("Log data cleared (${_logData.length} entries).");
    _showSnackBar("Log data cleared.");
  }

  // --- Navigate to Plot Screen ---
  void _navigateToPlot() {
     if (_logData.isEmpty) {
         _showSnackBar("Collect some data before plotting.");
         return;
     }
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => PlotScreen(
            logData: _logData,
            logInterval: DESIRED_LOG_INTERVAL,
         ),
       ),
     );
  }

   // --- Method to open the Settings Screen ---
   Future<void> _openSettings() async {
     // Navigate to the SettingsScreen and wait for a result to be returned
     final String? newIp = await Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => SettingsScreen(
           initialIp: _serverIp,
           isConnected: _isConnected, // Pass connection status
           currentRole: _clientRole, // Pass current role
           isAdminPasswordRequired: _isAdminPasswordRequired, // Pass password required status
           sendCommand: _sendCommand, // Pass the command sending function for Release
           onRequestAdminRolePressed: _handleRequestAdminRole, // Pass the callback for Request
         ),
       ),
     );

     // This code runs AFTER the SettingsScreen is popped.
     // Role changes and connection status updates happening in SettingsScreen
     // via `widget.sendCommand` will cause the *main* screen's state (_clientRole, _isConnected, _isAdminPasswordRequired)
     // to update via its WebSocket listener, which will trigger the main screen's UI to rebuild.
     // The IP change logic below also triggers a state update and rebuild.

     if (newIp != null && newIp.isNotEmpty && newIp != _serverIp) {
       print('New IP received from Settings: $newIp');
       _showSnackBar('IP changed to $newIp. Attempting to reconnect...');

       // Update the state with the new IP and trigger a rebuild
       setState(() {
         _serverIp = newIp;
         _errorDescription = ""; // Clear old error state
         _error = 0;
         // Role and password required status are already handled by the stream listener on connect
         // _clientRole = "User"; // Reset role on IP change/reconnect - redundant
         // _isAdminPasswordRequired = false; // Reset status on IP change/reconnect - redundant
       });

       // Close the existing connection if it exists
       if (_channel != null) {
           print('Closing existing WebSocket connection...');
           try {
              _channel?.sink.close(1001, 'IP Changed by User'); // 1001: Going Away
           } catch(e) {
              print('Error closing existing channel: $e');
           } finally {
               _channel = null; // Ensure channel is nullified
               // setState(() { _isConnected = false; }); // Redundant with stream listener onDone/onError
           }
       }

       // Attempt to connect to the new IP
       _connectWebSocket();

     } else if (newIp == null) {
        print('Settings dismissed without saving new IP.');
     } else if (newIp == _serverIp) {
         print('IP not changed (same as current).');
         _showSnackBar('IP not changed.');
     } else if (newIp.isEmpty) {
         print('IP received was empty string.');
         _showSnackBar('IP address cannot be empty.');
     }
   }

  // Helper to show simple messages at the bottom of the screen
  void _showSnackBar(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).hideCurrentSnackBar();
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         duration: Duration(seconds: message.length > 50 ? 5 : 3),
         backgroundColor: Colors.blueGrey,
       ),
     );
   }


  // --- UI Helper Widget ---
  // Modified to potentially disable TextField AND add Tooltip conditionally
  Widget _buildInputRow(String label, TextEditingController controller, bool enabled) {

    // Create the core TextField widget
    Widget textFieldWidget = TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        fillColor: enabled ? null : Colors.grey[200], // Add background color when disabled
        filled: !enabled,
        hintStyle: TextStyle(color: enabled ? Colors.grey : Colors.grey[400]), // Dim hint text
        labelStyle: TextStyle(color: enabled ? Colors.black87 : Colors.grey[600]), // Dim label if using labelText
      ),
      style: TextStyle(color: enabled ? Colors.black87 : Colors.grey[600]), // Dim input text
      enabled: enabled, // Enable/Disable the TextField
    );

    // Conditionally wrap the TextField with a Tooltip
    Widget wrappedInputField;
    if (!enabled) {
      // If disabled, wrap it in a Tooltip with the required message
      wrappedInputField = Tooltip(
         message: 'Requires Admin privilege', // The tooltip message (Changed)
         child: textFieldWidget, // The TextField is the child of the Tooltip
      );
    } else {
      // If enabled, just use the TextField directly
      wrappedInputField = textFieldWidget;
    }

    // Place the (potentially wrapped) TextField inside an Expanded
    Widget expandedInputField = Expanded(
      child: wrappedInputField, // This is either TextField or Tooltip(TextField)
    );

    // Return the final Row containing the label and the expanded input field
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 160,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: enabled ? Colors.black87 : Colors.grey[600]), // Dim label when disabled
              overflow: TextOverflow.ellipsis,
            ),
          ),
          expandedInputField, // This is Expanded(child: TextField) or Expanded(child: Tooltip(TextField))
        ],
      ),
    );
  }

  // --- Build Method (UI Layout) ---
  @override
  Widget build(BuildContext context) {
    // Determine if command controls should be enabled
    bool controlsEnabled = _isConnected && _clientRole == "Admin"; // Changed
    // Define the message for disabled controls (used on buttons)
    final String disabledMessage = 'Requires Admin privilege'; // Changed

    // Get the AppBar background color based on connection status
    Color appBarColor = _isConnected ? Colors.green[600]! : Colors.red[600]!;


    return Scaffold(
      appBar: AppBar(
        title: const Text('T-Motor Interface'),
        // Use the calculated color for the main AppBar
        backgroundColor: appBarColor,
        // ADD the bottom parameter for the icon row
        bottom: PreferredSize(
          // Set the height of the bottom bar where the icons will live
          preferredSize: const Size.fromHeight(56.0), // A typical height for a bar with icons
          child: Container( // Use a Container for background color and padding
             color: appBarColor, // Match the main AppBar color
             padding: const EdgeInsets.symmetric(horizontal: 8.0), // Add some horizontal padding
             child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly, // Distributes space evenly around icons
               children: [
                 // --- Move all the IconButtons from the old actions list here ---
                 // Settings button
                 IconButton(
                   icon: const Icon(Icons.settings),
                   onPressed: _openSettings,
                   tooltip: 'Settings (IP, Role)',
                   color: Colors.white, // Ensure icons are visible on the colored background
                 ),
                 // Reconnect button (enabled when disconnected)
                 IconButton(
                   icon: Icon(Icons.refresh),
                   onPressed: _isConnected ? null : _connectWebSocket,
                   tooltip: 'Reconnect WebSocket',
                   color: Colors.white, // Ensure icons are visible
                 ),
                  // Share Log button (New method using share_plus)
                 IconButton(
                   icon: Icon(Icons.share),
                   onPressed: _shareLogData,
                   tooltip: 'Share Accumulated Log (via system share sheet)',
                   color: Colors.white, // Ensure icons are visible
                 ),
                  // Clear Log button
                  IconButton(
                   icon: Icon(Icons.delete_sweep),
                   onPressed: _clearLogData,
                   tooltip: 'Clear Accumulated Log',
                   color: Colors.white, // Ensure icons are visible
                 ),
                 // Plot button
                 IconButton(
                   icon: const Icon(Icons.show_chart),
                   onPressed: _navigateToPlot,
                   tooltip: 'Show Plot',
                   color: Colors.white, // Ensure icons are visible
                 ),
                 // --- End of IconButtons ---
               ],
             ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: <Widget>[
            // --- Connection Status and Server Address ---
            Text(
              'Connection Status: ${_isConnected ? "Connected" : "Disconnected"}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _isConnected ? Colors.green[700] : Colors.red[700]),
            ),
             SizedBox(height: 4),
             Text(
               'Server Address: $_serverIp:$_serverPort',
               style: TextStyle(fontSize: 14, color: Colors.grey[600]),
             ),
            SizedBox(height: 4),
            Text(
              'Your Role: $_clientRole', // Display current role
              style: TextStyle(
                fontSize: 14,
                color: _clientRole == "Admin" ? Colors.blue[800] : (_clientRole == "User" ? Colors.orange[800] : Colors.grey[600]),
                fontWeight: FontWeight.bold,
              ),
            ),

             SizedBox(height: 8), // Adjust spacing after removing role UI
             Text(
               'Logged Entries: ${_logData.length}',
               style: TextStyle(fontSize: 14, color: Colors.blueGrey[700]),
             ),
            const Divider(height: 24),

            // --- Motor State Display (Measured Values) ---
            Text('Motor State ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Position: ${_position.toStringAsFixed(3)} rad'),
            Text('Velocity: ${_velocity.toStringAsFixed(3)} rad/s'),
            Text('Current: ${_current.toStringAsFixed(3)} A'),
            Text('Temperature: ${_temperature.toStringAsFixed(1)} °C'),
            Text('Reported Error: $_error'),
            if (_errorDescription.isNotEmpty)
              Text('Error Description: $_errorDescription', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
             Text('Reported Mode: ${_controlMode}'),

             SizedBox(height: 16),

            // --- Command Input Section (Full State) ---
            Text(
              'Full State Parameters',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: controlsEnabled ? Colors.black87 : Colors.grey[600]), // Dim title
            ),
            SizedBox(height: 8),

            // These now use the modified _buildInputRow which includes the Tooltip conditionally
            _buildInputRow('Des. Position (rad):', _desPController, controlsEnabled),
            _buildInputRow('Des. Velocity (rad/s):', _desSController, controlsEnabled),
            _buildInputRow('Des. Current (Amps):', _desTController, controlsEnabled),
            _buildInputRow('Kp Gain:', _kpController, controlsEnabled),
            _buildInputRow('Kd Gain:', _kdController, controlsEnabled),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              // Wrap the button's padding with a Tooltip
              child: Tooltip(
                 message: controlsEnabled ? 'Send the full set of desired parameters' : disabledMessage, // Conditional tooltip message
                 child: ElevatedButton(
                   onPressed: controlsEnabled ? _sendFullStateCommand : null,
                   child: const Text('Send'),
                   style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      textStyle: TextStyle(fontSize: 16),
                   ),
                 ),
              ),
            ),

            const Divider(height: 24),

            // --- Motor Power & Zero/Stop (Admin Only) ---
            Text(
              'Motor Power & Reset :',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: controlsEnabled ? Colors.black87 : Colors.grey[600]), // Dim title
             ),
            SizedBox(height: 8),

             Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                     // Wrap the button's padding with a Tooltip
                    child: Tooltip(
                       message: controlsEnabled ? 'Turn motor power on' : disabledMessage, // Conditional tooltip message
                       child: ElevatedButton(
                         onPressed: controlsEnabled ? () => _sendCommand("power_on") : null,
                         child: const Text('Power On'),
                         style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                         ),
                       ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    // Wrap the button's padding with a Tooltip
                    child: Tooltip(
                       message: controlsEnabled ? 'Turn motor power off' : disabledMessage, // Conditional tooltip message
                       child: ElevatedButton(
                         onPressed: controlsEnabled ? () => _sendCommand("power_off") : null,
                         child: const Text('Power Off'),
                         style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                         ),
                       ),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 16),

             // This button was already wrapped in a Tooltip, just make the message conditional
             Tooltip(
               message: controlsEnabled ? 'Set control parameters to zero THEN send hardware zero command' : disabledMessage, // Conditional tooltip message
               child: ElevatedButton(
                onPressed: controlsEnabled ? _sendZeroParamsThenHardwareZero : null,
                child: const Text('Stop and Hardware Zero'),
                style: ElevatedButton.styleFrom(
                   backgroundColor: Colors.orangeAccent,
                   foregroundColor: Colors.white,
                ),
               ),
             ),

             SizedBox(height: 8),


          ],
        ),
      ),
    );
  }
}

// --- Basic App Boilerplate ---
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Motor Control App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MotorControlScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}