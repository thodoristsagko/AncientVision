# AncientVision - Field Guide

A quick guide for using the AncientVision safety monitoring system at your archaeological site.

---

## What's in the Box

- **M5StickC Plus 2** - the small sensor device (orange button on front, side button)
- **USB-C cable** - for charging the sensor
- **Your Android phone** - with the AncientVision app installed

---

## 1. Charging the Sensor

Plug the USB-C cable into the sensor. A full charge takes about 2 hours and lasts approximately **1 hour** of continuous monitoring. **Keep the USB-C cable and a power bank handy** for longer sessions. You can check the battery level in the app once connected (shown as a small chip in the top bar).

---

## 2. Turning On the Sensor

Press and hold the **side button** (small button on the left edge) for 2 seconds. The screen will light up and show "AncientVision" with a status display. The sensor starts broadcasting automatically - no setup needed.

---

## 3. Connecting the App

1. Open the **AncientVision** app on your phone
2. Make sure **Bluetooth** is turned on
3. Tap the **Monitor** tab (shield icon, bottom right)
4. The app will automatically scan for the sensor
5. Wait a few seconds - you'll see "Connected to M5StickC Plus 2" when ready
6. If it doesn't connect, tap the yellow **Scan** button

**If connection drops:** The app will try to reconnect automatically. If it doesn't, tap the yellow **Reconnect** button.

---

## 4. Placing the Sensor

Place the sensor **on stable, flat ground** near your excavation area:

- Keep it **out of direct sunlight** if possible (heat affects readings)
- Place it on **firm soil**, not on loose fill or backfill
- Keep it **away from foot traffic** and heavy equipment
- The closer to the trench wall, the better the detection

---

## 5. Learning Your Site (First Time Setup)

The system needs to learn what "normal" ground vibration feels like at your specific site. This only takes a few minutes and makes the alerts much more accurate.

1. Make sure the sensor is placed and connected
2. In the Monitor tab, look for the **tune icon** (small slider icon) in the top right
3. Tap it
4. Give your site a name (e.g., "Paros North Trench")
5. Tap **Start**
6. **Keep the area quiet** - no walking nearby, no machinery, no loud work
7. Wait at least **5 minutes** (a progress bar shows how much data has been collected)
8. When the bar is full and it says "Ready!", tap the **orange stop button** in the top right
9. Done! The system now knows what normal feels like here

**Tips:**
- Do this during a quiet moment - early morning works well
- If the app warns about "high variance", the ground was shaking during learning. Try again when it's quieter
- You only need to do this once per site location. If you move the sensor to a different area, learn that site too

---

## 6. Reading the Monitor Screen

Once connected, the Monitor screen shows you everything you need:

### Status Colors (the big number at the top)
- **Green** = Everything is fine. Ground is stable.
- **Yellow** = Something unusual detected. Stay alert, check surroundings.
- **Red** = Danger detected. **Stop work and move away from the trench.**

### Alert Banners
- **Red banner** ("Unusual vibration pattern detected") = The sensor is picking up ground movement that isn't normal for this site
- **Orange banner** with a pattern name = The system recognizes a specific warning pattern (like soil slowly shifting)
- **Teal/green banner** ("Learning...") = Site calibration is in progress

### What the Numbers Mean (Simple Mode)
- The **large number** is the ground vibration intensity
- **"Safe"** / **"Perceptible"** / **"Heritage limit"** / **"CRITICAL"** tells you the risk level in plain words
- You don't need to understand the numbers - just watch the colors and words

---

## 7. What to Do When You Get an Alert

### Yellow Alert (Unusual)
1. **Pause work** near the trench
2. Look for obvious causes (nearby construction, heavy truck passing)
3. If no obvious cause, **monitor for a few minutes**
4. If it goes back to green, resume work carefully

### Red Alert (Danger)
1. **Stop all work immediately**
2. **Move away from trench walls**
3. **Alert everyone** at the site
4. Wait until the reading returns to green for at least 5 minutes before approaching
5. Inspect the trench walls for cracks or bulging before resuming

### Full-Screen Alert
If the screen goes entirely red with large text, this is the **highest priority**. Follow the on-screen instructions immediately.

---

## 8. Daily Routine

1. **Morning**: Charge sensor fully. Turn it on, place it, open app, verify connection (green dot = connected).
2. **During work**: Keep the app open on your phone. Glance at it regularly. Listen for alert sounds.
3. **Battery**: The sensor lasts about **1 hour**. Keep a **power bank** connected for all-day monitoring, or swap in a freshly charged sensor when the battery chip in the app turns red.
4. **End of day**: Turn off by holding the side button for 6 seconds.

---

## 9. Troubleshooting

| Problem | Solution |
|---------|----------|
| App can't find sensor | Make sure Bluetooth is on. Turn sensor off and on again. Tap **Scan**. |
| Connection keeps dropping | Move phone closer to sensor (within 10 meters). Check sensor battery. |
| Sensor screen is blank | Battery is dead (lasts ~1 hour). Charge it or plug in a power bank. Press side button to wake. |
| Constant yellow alerts | The site might be near a road or construction. Re-do the "Learn Your Site" step during a quiet moment. |
| App crashed | Just reopen it. It reconnects automatically. |
| "Not enough data" when stopping calibration | You stopped too early. Start again and wait the full 5 minutes. |

---

## 10. Important Safety Notes

- This system is an **aid**, not a replacement for your own judgment and site safety protocols
- Always follow your site's established safety procedures
- The system monitors **ground vibration only** - it cannot detect all hazards (overhead collapse, flooding, etc.)
- If something looks or feels wrong at the site, **trust your instincts** and move to safety regardless of what the app shows
- Keep your phone charged - if the app dies, you lose monitoring

---

## Need Help?

Contact the development team:
- The app is built and maintained by the AncientVision team
- For technical issues, describe what you see on screen and we'll help remotely
