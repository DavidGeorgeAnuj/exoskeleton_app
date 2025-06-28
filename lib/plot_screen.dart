import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';


// --- Remove these constants as the interval is now passed ---
// const double SERVER_STATE_SEND_FREQUENCY = 50.0; // Hz
// const double SERVER_STATE_SEND_INTERVAL = 1.0 / SERVER_STATE_SEND_FREQUENCY; // seconds
// ------------------------------------------------------------


class PlotScreen extends StatefulWidget {
  final List<Map<String, dynamic>> logData;
  // --- The log interval is still passed, but NOT used for X-axis calculation ---
  final double logInterval; // Kept for completeness, but not used for X
  // -------------------------------------

  const PlotScreen({
    Key? key,
    required this.logData,
    // --- New: Require the log interval ---
    required this.logInterval, // Still required, but its use changes
    // -------------------------------------
  }) : super(key: key);

  @override
  _PlotScreenState createState() => _PlotScreenState();
}

class _PlotScreenState extends State<PlotScreen> {

  // Define categories and keys - Now includes commanded values
  final Map<String, List<String>> _plotCategories = {
    'Position (Rad)': ['position', 'cmd_position'], // 'position' is raw in this version of main.dart
    'Velocity (Rad/s)': ['velocity', 'cmd_velocity'],
    'Current (Amps)': ['current', 'cmd_current'], // Plots measured Q-axis current vs commanded FF current
    'Kp Gain': ['cmd_kp'], // Kp and Kd are only commanded, not measured in state
    'Kd Gain': ['cmd_kd'],
  };

  List<String> _plotOptions = [];
  String? _selectedCategory;

  // Map to assign colors and legend names - Added colors for commanded values
  final Map<String, Color> _lineColors = {
     'position': Colors.blueAccent,       // Measured Position (Raw)
     'cmd_position': Colors.lightBlue,    // Commanded Position
     'velocity': Colors.greenAccent,      // Measured Velocity
     'cmd_velocity': Colors.lightGreen,   // Commanded Velocity
     'current': Colors.orangeAccent,      // Measured Current (Q-axis)
     'cmd_current': Colors.deepOrangeAccent, // Commanded Current (FF)
     'cmd_kp': Colors.purpleAccent,       // Commanded Kp
     'cmd_kd': Colors.deepPurpleAccent,   // Commanded Kd
  };

  final Map<String, String> _legendNames = {
     'position': 'Position (Measured Raw)', // Clarified this is the raw value
     'cmd_position': 'Position (Commanded)',
     'velocity': 'Velocity (Measured)',
     'cmd_velocity': 'Velocity (Commanded)',
     'current': 'Current (Measured Q)',
     'cmd_current': 'Current (Commanded FF)',
     'cmd_kp': 'Kp (Commanded)',
     'cmd_kd': 'Kd (Commanded)',
  };

  // Declare lineBarsData as a class field
  List<LineChartBarData> _generatedLineBarsData = [];


  @override
  void initState() {
    super.initState();

    _plotOptions = _plotCategories.keys.toList();

    // Set initial category if data exists, prefer Position
    if (widget.logData.isNotEmpty) {
       _selectedCategory = _plotCategories.containsKey('Position (Rad)') ? 'Position (Rad)' : _plotOptions.first;
       // Generate initial plot data
       if (_selectedCategory != null) {
         _generatedLineBarsData = _generateLineChartBarDataForCategory(_selectedCategory!);
       }
    } else {
       _selectedCategory = null;
    }
  }

  // Separate logic to generate LineChartBarData from rendering LineChartData
  List<LineChartBarData> _generateLineChartBarDataForCategory(String category) {
      // Get the list of keys (measured and commanded) for the selected category
      final List<String> dataKeysToPlot = _plotCategories[category] ?? [];
      List<LineChartBarData> lineBarsData = [];

       // Iterate through each data key required for this category
       for (String key in dataKeysToPlot) {
          List<FlSpot> spots = [];

          // Iterate through each entry in the log data
          for (int i = 0; i < widget.logData.length; i++) {
            // Check if the current log entry contains the key
            if (widget.logData[i].containsKey(key)) {
              var value = widget.logData[i][key];
              double? yValue;
              // Try to parse the value as a double
              if (value is num) {
                 yValue = value.toDouble();
              } else if (value is String) {
                 yValue = double.tryParse(value);
              }
              // Note: null values will be ignored, creating gaps in the line or no line if all are null

              if (yValue != null) {
                 // --- MODIFIED: X-axis is now just the index ---
                 // X-axis now represents the order of the log entry (0, 1, 2, ...)
                 spots.add(FlSpot(i.toDouble(), yValue));
                 // -------------------------------------------------------------
              }
            }
          }

          // Only add a line if there are actual data points
          if (spots.isNotEmpty) {
             lineBarsData.add(
                LineChartBarData(
                  spots: spots,
                  isCurved: false, // Keep false for less ambiguity of points
                  color: _lineColors[key] ?? Colors.grey, // Use defined color or default
                  barWidth: 2, // Line thickness
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false), // Don't show individual dots
                  belowBarData: BarAreaData(show: false), // No area filling below the line
                ),
             );
          }
       }
       return lineBarsData;
  }


  // Helper function to generate the main LineChartData object
  LineChartData _generateLineChartData() {
    // Return empty data if no lines were generated
    if (_generatedLineBarsData.isEmpty) {
         return LineChartData(
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            lineBarsData: [], // Explicitly empty
         );
    }

    // Calculate min/max for axis scaling based ONLY on the generated spots
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    double maxX = 0; // Start X from 0

    bool foundAnySpots = false;
    for (var barData in _generatedLineBarsData) {
      for (var spot in barData.spots) {
        if (spot.y < minY) minY = spot.y;
        if (spot.y > maxY) maxY = spot.y;
        if (spot.x > maxX) maxX = spot.x; // Find max index (which is N-1)
        foundAnySpots = true;
      }
    }

    // Handle case where no valid spots were found (should be caught by _generatedLineBarsData.isEmpty but double check)
    if (!foundAnySpots) {
         return LineChartData(
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
             lineBarsData: [],
         );
    }

     // Add padding to Y-axis range
     double yRange = maxY - minY;
     if (yRange == 0) { // If all y values are the same
        minY -= 1;
        maxY += 1;
     } else {
       minY -= yRange * 0.1; // 10% padding below
       maxY += yRange * 0.1; // 10% padding above
     }
     // Ensure min is strictly less than max after padding
     if (minY >= maxY) {
        maxY = minY + 1;
     }

     // Adjust maxX padding based on index
     // Max index is logData.length - 1. Add some padding beyond the last index.
     double adjustedMaxX = (widget.logData.isNotEmpty ? widget.logData.length - 1 : 0).toDouble();
     adjustedMaxX = adjustedMaxX * 1.05; // Add 5% padding


     // Ensure minX starts at 0
     double minX = 0;


    return LineChartData(
      // Grid lines setup
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (value) {
          return const FlLine(color: Color(0x3368737d), strokeWidth: 0.5);
        },
        getDrawingVerticalLine: (value) {
          return const FlLine(color: Color(0x3368737d), strokeWidth: 0.5);
        },
      ),
      // Axis titles and labels setup
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        // Bottom Titles (X-axis: Log Entry Index)
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            // Calculate interval dynamically based on the number of points (indices)
            // Show roughly 5-10 labels. Clamped to at least 1.
            interval: ((widget.logData.length / 8).round()).toDouble().clamp(1.0, double.infinity),
            getTitlesWidget: (value, meta) {
               // Format X-axis labels (Index) - should be integers
               return Padding(
                 padding: const EdgeInsets.only(top: 8.0),
                 // Display as integer index
                 child: Text(value.toInt().toString(),
                     style: const TextStyle(color: Color(0xff68737d), fontSize: 10)),
               );
            },
          ),
        ),
        // Left Titles (Y-axis: Measured/Commanded Value)
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40, // Space reserved for labels
            // Calculate interval dynamically
            interval: (maxY - minY).abs() / 5 > 0 ? (maxY - minY).abs() / 5 : 1.0, // Divide range into approx 5 intervals
             getTitlesWidget: (value, meta) {
                // Format Y-axis labels
                int decimalPlaces = 2; // Default
                double range = (maxY - minY).abs();
                if (range >= 100) decimalPlaces = 0;
                else if (range >= 10) decimalPlaces = 1;
                else if (range < 1 && range > 0) decimalPlaces = 3;
                else if (range == 0) decimalPlaces = 2; // If range is zero, show 2 decimals for the single value

                return Text(value.toStringAsFixed(decimalPlaces),
                   style: const TextStyle(color: Color(0xff68737d), fontSize: 10),
                   textAlign: TextAlign.right, // Align labels to the right
                );
             },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d), width: 1),
      ),
      minX: minX, // Start at index 0
      maxX: adjustedMaxX, // Max index with padding
      minY: minY, // Min Y determined by data
      maxY: maxY, // Max Y determined by data
      lineBarsData: _generatedLineBarsData, // The generated lines
       // Tooltip when touching the chart
       lineTouchData: LineTouchData(
          enabled: true, // Enable touch
          touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.blueGrey, // Tooltip background color
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                  // Generate tooltip items for all touched spots
                  return touchedSpots.map((LineBarSpot touchedSpot) {
                       // Find the key associated with the touched line color
                       String? touchedKey;
                       // Check if the touchedSpot index is valid and barData exists
                       if (touchedSpot.barIndex < _generatedLineBarsData.length) {
                           Color? barColor = _generatedLineBarsData[touchedSpot.barIndex].color;

                            // Find the key that matches the color
                            _lineColors.forEach((key, color) {
                               if (color == barColor) {
                                   touchedKey = key;
                               }
                           });
                       }

                       // Get the legend name for the key, default to key or 'Unknown'
                       String name = _legendNames[touchedKey] ?? touchedKey ?? 'Unknown';

                       // Return the tooltip item with formatted data
                       return LineTooltipItem(
                           '$name\nEntry Index: ${touchedSpot.x.toInt().toString()}\nValue: ${touchedSpot.y.toStringAsFixed(3)}', // Show index as integer
                            const TextStyle(color: Colors.white, fontSize: 10), // Tooltip text style
                       );

                   }).toList(); // Convert the map result to a list
              }
          )
       ),
    );
  }

  // Widget to display the legend
  Widget _buildLegend() {
    // Don't show legend if no category is selected or no data was generated
    if (_selectedCategory == null || _generatedLineBarsData.isEmpty) {
      return Container();
    }

    List<Widget> legendItems = [];

    // Collect the actual keys that had data and generated lines
    List<String> generatedKeys = [];
    for (var barData in _generatedLineBarsData) {
        Color? barColor = barData.color;
         _lineColors.forEach((key, color) {
             if (color == barColor) {
                 generatedKeys.add(key);
             }
         });
    }


    // Create legend items for each generated key
    for (String key in generatedKeys) {
        if (_legendNames.containsKey(key) && _lineColors.containsKey(key)) {
           legendItems.add(
             Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Container(
                   width: 16,
                   height: 16,
                   color: _lineColors[key]!, // Use the defined color
                 ),
                 const SizedBox(width: 4),
                 Text(_legendNames[key]!, style: const TextStyle(fontSize: 12)), // Use the defined name
               ],
             ),
           );
        }
    }

    // Add spacing between legend items
    List<Widget> spacedLegendItems = [];
    for(int i = 0; i < legendItems.length; i++){
        spacedLegendItems.add(legendItems[i]);
        if(i < legendItems.length - 1){
            spacedLegendItems.add(const SizedBox(width: 12)); // Increased space
        }
    }

    // Wrap in SingleChildScrollView in case there are many items
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
         padding: const EdgeInsets.symmetric(vertical: 4.0),
         child: Row(
           mainAxisAlignment: MainAxisAlignment.center, // Center the legend items
           children: spacedLegendItems,
         ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motor Data Plot'),
        actions: [
           // Dropdown to select plot data category - only shown if data exists
          if (widget.logData.isNotEmpty && _selectedCategory != null)
            DropdownButtonHideUnderline( // Hide the default underline
              child: DropdownButton<String>(
                value: _selectedCategory,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                elevation: 16,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                dropdownColor: Theme.of(context).primaryColor, // Match app bar color
                items: _plotOptions.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value, style: TextStyle(color: Colors.white)),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedCategory = newValue;
                      // Regenerate data and update class field when category changes
                      _generatedLineBarsData = _generateLineChartBarDataForCategory(newValue);
                    });
                  }
                },
              ),
            ),
        ],
      ),
      body: widget.logData.isEmpty
          ? const Center(
              child: Text('No log data available to plot.'),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   // Display the selected category name
                   Text(
                     'Plotting: ${_selectedCategory ?? 'N/A'}',
                     textAlign: TextAlign.center,
                     style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                   ),
                   const SizedBox(height: 16),
                   // --- The Plot ---
                  Expanded(
                    // Use a Card for better visual separation? (Optional)
                    // Card(
                    //   elevation: 4,
                    //   child: Padding(
                    //     padding: const EdgeInsets.all(8.0),
                         child: LineChart(_generateLineChartData()), // Uses the class field
                    //   ),
                    // ),
                  ),
                   // --- Legend ---
                   const SizedBox(height: 8),
                   _buildLegend(), // Display the dynamically generated legend
                   const SizedBox(height: 8),
                   // X-axis label
                   const Text('X-axis: Log Entry Index', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)), // Label changed
                ],
              ),
            ),
    );
  }
}