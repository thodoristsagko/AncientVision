"""
AncientVision BLE Monitor with Firebase
Connects to M5StickC Plus 2 via laptop Bluetooth and saves alerts to Firebase
"""

import asyncio
import json
import requests
import time
from datetime import datetime
from bleak import BleakClient, BleakScanner

# BLE UUIDs - must match firmware
SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
IMU_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
MOISTURE_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9"
ALERT_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26aa"

# Firebase config
FIREBASE_PROJECT_ID = "ancientvision-7ef8a"
FIREBASE_API_KEY = "AIzaSyCBd3FejQawa9VpoWL5TK-ZdPNUPEfmXIA"
FIRESTORE_URL = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/safety_alerts"

# Thresholds
MOISTURE_MIN = 30
MOISTURE_MAX = 60
VIB_WARNING = 0.3
VIB_CRITICAL = 0.8

# Current data
current_data = {
    'accX': 0, 'accY': 0, 'accZ': 0, 'vibration': 0,
    'moisture': 0, 'alert_level': 'safe', 'alert_msg': '',
    'device_name': 'Unknown', 'device_address': ''
}

last_alert_level = 'safe'
last_firebase_save = 0

def save_alert_to_firebase(level, message):
    global last_firebase_save
    """Save alert to Firebase Firestore"""
    try:
        data = {
            "fields": {
                "level": {"stringValue": level},
                "message": {"stringValue": message},
                "vibration": {"doubleValue": current_data['vibration']},
                "moisture": {"integerValue": str(current_data['moisture'])},
                "accX": {"doubleValue": current_data['accX']},
                "accY": {"doubleValue": current_data['accY']},
                "accZ": {"doubleValue": current_data['accZ']},
                "deviceName": {"stringValue": current_data['device_name']},
                "deviceAddress": {"stringValue": current_data['device_address']},
                "timestamp": {"timestampValue": datetime.utcnow().isoformat() + "Z"},
                "source": {"stringValue": "BLE_Monitor_PC"}
            }
        }

        response = requests.post(
            f"{FIRESTORE_URL}?key={FIREBASE_API_KEY}",
            json=data,
            headers={"Content-Type": "application/json"}
        )

        if response.status_code == 200:
            last_firebase_save = time.time()
            print(f"\n  >> ALERT SAVED TO FIREBASE: {level} - {message}")
        else:
            print(f"\n  >> Firebase error: {response.status_code} - {response.text}")

    except Exception as e:
        print(f"\n  >> Firebase error: {e}")

def imu_callback(sender, data):
    try:
        json_data = json.loads(data.decode())
        current_data['accX'] = json_data.get('x', 0)
        current_data['accY'] = json_data.get('y', 0)
        current_data['accZ'] = json_data.get('z', 0)
        current_data['vibration'] = json_data.get('vib', 0)
    except:
        pass

def moisture_callback(sender, data):
    try:
        json_data = json.loads(data.decode())
        current_data['moisture'] = json_data.get('percent', 0)
    except:
        pass

def alert_callback(sender, data):
    global last_alert_level
    try:
        json_data = json.loads(data.decode())
        level = json_data.get('level', 'safe')
        message = json_data.get('message', '')

        current_data['alert_level'] = level
        current_data['alert_msg'] = message

        # Save to Firebase when alert changes to warning or critical
        if level != 'safe' and message and level != last_alert_level:
            save_alert_to_firebase(level, message)

        last_alert_level = level
    except:
        pass

def print_status():
    vib = current_data['vibration']
    moist = current_data['moisture']

    # Status indicators
    vib_status = "CRITICAL!" if vib > VIB_CRITICAL else "Warning" if vib > VIB_WARNING else "Stable"
    moist_status = "Too Wet!" if moist > MOISTURE_MAX else "Too Dry" if moist < MOISTURE_MIN else "Safe"

    # Colors (ANSI)
    RED = '\033[91m'
    YELLOW = '\033[93m'
    GREEN = '\033[92m'
    CYAN = '\033[96m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

    vib_color = RED if vib > VIB_CRITICAL else YELLOW if vib > VIB_WARNING else GREEN
    moist_color = RED if moist > MOISTURE_MAX else YELLOW if moist < MOISTURE_MIN else GREEN

    print("\033[2J\033[H")  # Clear screen
    print(f"{BOLD}========== AncientVision Sensor Monitor =========={RESET}")
    print(f"  {CYAN}Device: {current_data['device_name']}{RESET}")
    print(f"  {CYAN}Address: {current_data['device_address']}{RESET}")
    print()
    print(f"  {BOLD}VIBRATION:{RESET}  {vib_color}{vib:.4f} g{RESET}  [{vib_status}]")
    print(f"  {BOLD}MOISTURE:{RESET}   {moist_color}{moist}%{RESET}  [{moist_status}]  (Safe: 30-60%)")
    print()
    print(f"  Accelerometer:  X={current_data['accX']:.3f}  Y={current_data['accY']:.3f}  Z={current_data['accZ']:.3f}")
    print()

    if current_data['alert_level'] != 'safe':
        alert_color = RED if current_data['alert_level'] == 'critical' else YELLOW
        print(f"  {alert_color}{BOLD}ALERT: {current_data['alert_msg']}{RESET}")
        print(f"  {CYAN}(Alert saved to Firebase){RESET}")
    else:
        print(f"  {GREEN}Status: All sensors normal{RESET}")

    print()
    print("=" * 52)
    print(f"  {CYAN}Alerts are saved to Firebase: safety_alerts{RESET}")
    print("  Press Ctrl+C to exit")

async def main():
    print("Scanning for AncientVision-Sensor...")

    device = None
    while device is None:
        devices = await BleakScanner.discover(timeout=5.0)
        for d in devices:
            if d.name and "AncientVision" in d.name:
                device = d
                break
        if device is None:
            print("Device not found, scanning again...")

    current_data['device_name'] = device.name
    current_data['device_address'] = device.address

    print(f"Found: {device.name} ({device.address})")
    print("Connecting...")

    async with BleakClient(device.address) as client:
        print("Connected! Subscribing to sensors...")

        # Subscribe to all characteristics
        await client.start_notify(IMU_CHAR_UUID, imu_callback)
        await client.start_notify(MOISTURE_CHAR_UUID, moisture_callback)
        await client.start_notify(ALERT_CHAR_UUID, alert_callback)

        print("Receiving data... Alerts saved to Firebase every second!")

        try:
            while True:
                print_status()
                # Save alert to Firebase every 1 second if there's an active alert
                if current_data['alert_level'] != 'safe' and current_data['alert_msg']:
                    save_alert_to_firebase(current_data['alert_level'], current_data['alert_msg'])
                await asyncio.sleep(1.0)
        except KeyboardInterrupt:
            print("\nDisconnecting...")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nExited.")
