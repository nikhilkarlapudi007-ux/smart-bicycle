# Smart Bicycle — Anti-Theft & Telemetry System

An IoT-enabled bicycle module combining motion/tamper detection, GPS tracking,
and ride telemetry (speed, distance, calories), controlled from a companion
Flutter app over Bluetooth Classic.

## Overview

- **Firmware (ESP32):** reads an MPU6050 accelerometer for motion/tamper
  detection, a Hall-effect sensor for wheel speed and distance, and a
  Neo-6M GPS module for location. Streams data to the app over Bluetooth
  Classic SPP and accepts commands (lock/unlock, set rider weight, set
  wheel size).
- **App (Flutter):** connects to the ESP32 over Bluetooth, shows live speed
  on a radial gauge, distance/calories, a live GPS map, and sends control
  commands. Fires a local notification on a tamper alert.
- **ML prototype (Python/PyTorch):** an offline 1D-CNN exploring whether a
  learned classifier can replace the firmware's fixed accelerometer
  threshold for tamper detection. **This is a synthetic-data prototype,
  not yet deployed on-device or validated on real sensor data** — see
  `ml_prototype/README.md` for details and honest results.

## Why the ML prototype exists

The current firmware flags a tamper event whenever instantaneous
acceleration magnitude exceeds a fixed threshold (`10.5 m/s²`, sustained for
a few consecutive readings). This is simple and works, but a single peak
threshold can't distinguish a **brief bump** (a stray knock, a dog nudging
the frame) from a **sustained pattern** (someone sawing or prying at the
lock) — both can momentarily cross the same magnitude.

While self-studying deep learning for computer vision on NPTEL, I wanted to
try applying a learned classifier to a project I already had running, using
a short window of accelerometer readings instead of a single instantaneous
value. The prototype is trained entirely on synthetic signals modeled after
the firmware's real sampling rate and threshold — it is a feasibility
exploration, not a finished replacement for the threshold rule.

## Repository structure
smart-bicycle/
├── README.md
├── firmware/
│ └── esp32_motion_alert.ino
├── app/
│ ├── main.dart
│ ├── dashboard_screen.dart
│ ├── notifications.dart
│ └── pubspec.yaml
├── ml_prototype/
│ ├── prototype_motion_classifier.py
│ ├── requirements.txt
│ └── results/
│ ├── training_curve.png
│ ├── confusion_matrix.png
│ └── threshold_comparison.txt
└── docs/
├── hardware_schematic.png
└── demo_photos/


## Hardware

- ESP32 dev board
- MPU6050 accelerometer/gyroscope
- Neo-6M GPS module
- Hall-effect sensor + magnet (wheel speed/distance)
- Piezo buzzer (alert)

*(hardware photos/schematic go in `docs/`)*

## Status & next steps

- [x] Motion/tamper alert via fixed accelerometer threshold — working on hardware
- [x] GPS tracking, streamed to app
- [x] Speed/distance/calorie telemetry via Hall sensor
- [x] Flutter app: live gauges, map, lock/unlock, notifications
- [x] 1D-CNN tamper classifier prototyped offline on synthetic data
- [ ] Collect real accelerometer logs from controlled bump-vs-tamper tests
- [ ] Retrain/validate the CNN on real data
- [ ] Quantize and port the model to the ESP32, replacing the fixed threshold

## License

MIT




