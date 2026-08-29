// ESP32: MPU6050 + TinyGPS + Hall-effect + BluetoothSerial (Classic)
// Upload with Arduino IDE (select ESP32 board)

#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Wire.h>
#include <TinyGPSPlus.h>
#include "BluetoothSerial.h"

BluetoothSerial SerialBT;
Adafruit_MPU6050 mpu;
TinyGPSPlus gps;

const char* btDeviceName = "ESP32_Motion_Alert";
const int BUZZER_PIN = 13;

// Hall sensor
const int HALL_PIN = 4;
volatile unsigned long hallLastTimeMicros = 0;
volatile unsigned long hallIntervalMicros = 0;
volatile unsigned long hallRevolutions = 0;
const float WHEEL_CIRCUMFERENCE_M = 2.1;
float USER_WEIGHT_KG = 70.0;
const unsigned long HALL_REPORT_INTERVAL_MS = 1000;
float totalDistance_m = 0.0;
float accumulatedCalories = 0.0;

// Motion detection
const float MOTION_THRESHOLD_ACCEL = 10.5;
const int MOTION_PERSIST_COUNT = 3;
int motionCounter = 0;

// GPS pins
#define RXD2 16
#define TXD2 17

bool motionMonitoringEnabled = true;
bool gpsEnabled = true;
unsigned long lastHallReportMillis = 0;
unsigned long lastGpsSendMillis = 0;

void IRAM_ATTR hallISR() {
  unsigned long now = micros();
  if (hallLastTimeMicros != 0) {
    hallIntervalMicros = now - hallLastTimeMicros;
  }
  hallLastTimeMicros = now;
  hallRevolutions++;
}

void setup() {
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(HALL_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(HALL_PIN), hallISR, CHANGE);

  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);
  SerialBT.begin(btDeviceName);
  Serial.println("Bluetooth device started as: ESP32_Motion_Alert");

  if (!mpu.begin()) {
    Serial.println("Failed to find MPU6050 chip.");
    while (1) {
      tone(BUZZER_PIN, 500);
      delay(300);
      noTone(BUZZER_PIN);
      delay(300);
    }
  }

  mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_5_HZ);
  Serial.println("MPU6050 initialized!");
}

// ----------------------------------------------------------
float getCyclingMET(float speed_kmh) {
  if (speed_kmh < 16.0) {          // Leisure
    return 4.0;
  } else if (speed_kmh < 19.0) {   // Low-moderate
    return 8.0;
  } else if (speed_kmh < 22.0) {   // Moderate
    return 10.0;
  } else if (speed_kmh < 25.5) {   // High-moderate
    return 12.0;
  } else {
    return 12.0;                   // Cap MET at 12 for high speeds
  }
}

// ----------------------------------------------------------
float caloriesForDurationMs(unsigned long dt_ms, float MET, float weight_kg) {
  float hours = dt_ms / 3600000.0;
  return MET * weight_kg * hours;
}

// ----------------------------------------------------------
void activateBuzzerAlert() {
  tone(BUZZER_PIN, 1000, 200);
  delay(200);
  tone(BUZZER_PIN, 1500, 200);
  delay(200);
  noTone(BUZZER_PIN);
}

// ----------------------------------------------------------
float computeAndResetDistanceSince(unsigned long &prevRevs) {
  noInterrupts();
  unsigned long currentRevs = hallRevolutions;
  interrupts();

  unsigned long deltaRevs = (currentRevs >= prevRevs) ? currentRevs - prevRevs : 0;
  prevRevs = currentRevs;

  unsigned long trueDeltaRevs = deltaRevs / 2;
  float dist = trueDeltaRevs * WHEEL_CIRCUMFERENCE_M;
  totalDistance_m += dist;
  return dist;
}

// ----------------------------------------------------------
void loop() {
  // Bluetooth commands
  if (SerialBT.available()) {
    String cmd = SerialBT.readStringUntil('\n');
    cmd.trim();
    cmd.toUpperCase();

    if (cmd == "LOCK") {
      motionMonitoringEnabled = true;
      gpsEnabled = true;
      SerialBT.println("LOCKED");
    } else if (cmd == "UNLOCK") {
      motionMonitoringEnabled = false;
      gpsEnabled = false;
      motionCounter = 0;
      SerialBT.println("UNLOCKED");
    } else if (cmd.startsWith("SETWEIGHT")) {
      int comma = cmd.indexOf(',');
      if (comma > 0) {
        USER_WEIGHT_KG = cmd.substring(comma + 1).toFloat();
      }
    }
  }

  // GPS parsing
  while (Serial2.available() > 0) gps.encode(Serial2.read());

  unsigned long nowMillis = millis();

  // Send GPS every 1s
  if (gpsEnabled && gps.location.isValid() && nowMillis - lastGpsSendMillis > 1000) {
    String gpsData = "GPS," + String(gps.location.lat(), 6) + "," + String(gps.location.lng(), 6);
    SerialBT.println(gpsData);
    lastGpsSendMillis = nowMillis;
  }

  // -------- Motion Detection ----------
  if (motionMonitoringEnabled) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);

    double ta = sqrt(a.acceleration.x * a.acceleration.x +
                      a.acceleration.y * a.acceleration.y +
                      a.acceleration.z * a.acceleration.z);

    if (abs(ta) > MOTION_THRESHOLD_ACCEL) {
      motionCounter++;
      if (motionCounter >= MOTION_PERSIST_COUNT) {
        activateBuzzerAlert();
        SerialBT.println("ALERT,MOTION_DETECTED");
        motionCounter = 0;
        delay(250);
      }
    } else {
      motionCounter = 0;
    }
  }

  // -------- HALL SENSOR REPORT --------
  if (nowMillis - lastHallReportMillis >= HALL_REPORT_INTERVAL_MS) {
    static unsigned long prevRevs = 0;
    unsigned long dt_ms = nowMillis - lastHallReportMillis;
    float dist_m = computeAndResetDistanceSince(prevRevs);
    float dt_s = dt_ms / 1000.0;
    float speed_m_s = (dt_s > 0) ? dist_m / dt_s : 0;
    float speed_kmh = speed_m_s * 3.6;

    float kcal = 0.0;
    if (speed_kmh > 0.5) {
      float MET = getCyclingMET(speed_kmh);
      kcal = caloriesForDurationMs(dt_ms, MET, USER_WEIGHT_KG);
      accumulatedCalories += kcal;
    }

    String hallMsg = "HALL," + String(speed_kmh, 2) + "," + String(dist_m, 2) + "," +
                      String(totalDistance_m, 2) + "," + String(kcal, 4) + "," +
                      String(accumulatedCalories, 4);
    SerialBT.println(hallMsg);
    lastHallReportMillis = nowMillis;
  }

  delay(50);
}
