import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

class DashboardScreen extends StatefulWidget {
  final double Function() speedRef;
  final double Function() distanceRef;
  final double Function() caloriesRef;
  final VoidCallback onReset;
  final Function(String) sendCommand;

  DashboardScreen({
    super.key,
    required this.speedRef,
    required this.distanceRef,
    required this.caloriesRef,
    required this.onReset,
    required this.sendCommand,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    _startLiveUpdater();
  }

  // LIVE UI UPDATE (every 200ms)
  void _startLiveUpdater() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return false;
      setState(() {});
      return true;
    });
  }

  // Dialog for numeric input (rider weight / wheel diameter)
  Future<double?> _showNumberInputDialog({
    required String title,
    required String hint,
    required String unit,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);

    return showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: hint,
              suffixText: unit,
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () => Navigator.pop(context, null),
            ),
            ElevatedButton(
              child: const Text("OK"),
              onPressed: () {
                final val = double.tryParse(controller.text);
                if (val == null || val.isNaN) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Enter a valid number")),
                  );
                  return;
                }
                Navigator.pop(context, val);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final speed = widget.speedRef();
    final distance = widget.distanceRef();
    final calories = widget.caloriesRef();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        backgroundColor: Colors.blueGrey,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 250,
              child: SfRadialGauge(
                axes: [
                  RadialAxis(
                    minimum: 0,
                    maximum: 60,
                    ranges: [
                      GaugeRange(startValue: 0, endValue: 20, color: Colors.green),
                      GaugeRange(startValue: 20, endValue: 40, color: Colors.orange),
                      GaugeRange(startValue: 40, endValue: 60, color: Colors.red),
                    ],
                    pointers: [
                      NeedlePointer(
                        value: speed,
                        needleColor: Colors.black,
                        knobStyle: const KnobStyle(color: Colors.black),
                      ),
                    ],
                    annotations: [
                      GaugeAnnotation(
                        widget: Text(
                          "${speed.toStringAsFixed(1)} km/h",
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        angle: 90,
                        positionFactor: 0.8,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _infoBox("Distance", "${distance.toStringAsFixed(2)} m"),
                _infoBox("Calories", "${calories.toStringAsFixed(2)} kcal"),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final val = await _showNumberInputDialog(
                      title: "Set Rider Weight",
                      hint: "Enter weight",
                      unit: "kg",
                    );
                    if (val != null) {
                      widget.sendCommand("SETWEIGHT,${val.toStringAsFixed(1)}");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Sent weight ${val.toStringAsFixed(1)} kg")),
                      );
                    }
                  },
                  icon: const Icon(Icons.person),
                  label: const Text("Set Weight"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final val = await _showNumberInputDialog(
                      title: "Set Wheel Diameter",
                      hint: "Enter diameter (cm)",
                      unit: "cm",
                    );
                    if (val != null) {
                      widget.sendCommand("SETWHEEL,${val.toStringAsFixed(1)}");
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Sent wheel diameter ${val.toStringAsFixed(1)} cm")),
                      );
                    }
                  },
                  icon: const Icon(Icons.circle_outlined),
                  label: const Text("Set Wheel (cm)"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => widget.sendCommand("LOCK"),
                  icon: const Icon(Icons.lock),
                  label: const Text("LOCK"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                ),
                ElevatedButton.icon(
                  onPressed: () => widget.sendCommand("UNLOCK"),
                  icon: const Icon(Icons.lock_open),
                  label: const Text("UNLOCK"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                widget.onReset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Distance & calories reset")),
                );
              },
              child: const Text("Reset Distance & Calories"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBox(String title, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}
