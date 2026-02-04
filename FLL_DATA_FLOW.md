# AncientVision - Data Flow Overview
## FLL Presentation

---

## 🎯 SIMPLE DATA FLOW DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ANCIENTVISION SYSTEM                            │
└─────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────┐
                              │   USER      │
                              │  (Student/  │
                              │ Archaeologist)│
                              └──────┬──────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
            ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
            │   CAMERA     │  │   M5STICKC   │  │    MANUAL    │
            │  (Phone)     │  │   DEVICE     │  │    INPUT     │
            └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
                   │                 │                 │
                   │ Photo           │ BLE             │ Text
                   │                 │ Bluetooth       │
                   ▼                 ▼                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│                        📱 ANCIENTVISION APP                              │
│                                                                          │
│  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐         │
│  │                │    │                │    │                │         │
│  │  🤖 AI ENGINE  │    │  📊 SAFETY     │    │  📚 DATABASE   │         │
│  │                │    │    MONITOR     │    │                │         │
│  │  • Object      │    │                │    │  • Artifact    │         │
│  │    Detection   │    │  • Vibration   │    │    History     │         │
│  │  • Coin ID     │    │  • Tilt Angle  │    │  • Coin Info   │         │
│  │  • Period      │    │  • Alerts      │    │  • Images      │         │
│  │    Dating      │    │                │    │                │         │
│  │                │    │                │    │                │         │
│  └───────┬────────┘    └───────┬────────┘    └───────┬────────┘         │
│          │                     │                     │                   │
│          └─────────────────────┼─────────────────────┘                   │
│                                │                                         │
│                                ▼                                         │
│                     ┌────────────────────┐                               │
│                     │     📋 RESULTS     │                               │
│                     │                    │                               │
│                     │  • What is it?     │                               │
│                     │  • How old?        │                               │
│                     │  • Condition?      │                               │
│                     │  • Safety status   │                               │
│                     └────────────────────┘                               │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                        ┌──────────────┐
                        │   OUTPUT     │
                        │              │
                        │  • Display   │
                        │  • Alerts    │
                        │  • Save      │
                        └──────────────┘
```

---

## 📊 THREE MAIN DATA FLOWS

### 1️⃣ AI RECOGNITION FLOW
```
CAMERA → IMAGE → AI ANALYSIS → IDENTIFICATION → DISPLAY RESULTS

  📷        🖼️        🧠            🏺              📱
 Take    Process   Google ML    "Roman Coin     Show to
 Photo    Image    Kit + Our    from 27 BC"      User
                   Algorithms
```

### 2️⃣ SAFETY MONITORING FLOW
```
M5STICKC → BLUETOOTH → APP → SAFETY CHECK → ALERT

   📟         📶        📱        ⚠️          🔔
 Sensors    Wireless   Receive   Too much    Warn
 (Motion)   Transfer    Data     shaking?    User!
```

### 3️⃣ DATA STORAGE FLOW
```
RESULTS → LOCAL DATABASE → HISTORY → EXPORT

   📋          💾            📚        📤
 Analysis    Save to      View past   Share
 Complete    Phone        discoveries  data
```

---

## 🔑 KEY COMPONENTS EXPLAINED

| Component | What It Does | Technology |
|-----------|--------------|------------|
| **Camera** | Takes photos of artifacts | Phone Camera |
| **M5StickC** | Monitors handling safety | ESP32 + Sensors |
| **AI Engine** | Identifies artifacts & coins | Google ML Kit |
| **Bluetooth** | Connects device to app | BLE (Bluetooth Low Energy) |
| **Database** | Stores all discoveries | SQLite Local Storage |

---

## 💡 WHY THIS MATTERS FOR ARCHAEOLOGY

```
PROBLEM:  Artifacts get damaged during discovery
          ↓
SOLUTION: Real-time safety monitoring + AI identification
          ↓
RESULT:   Protect artifacts while learning about them instantly
```

---

## 🎤 PRESENTATION TALKING POINTS

1. **"Our app has THREE main data flows"**
   - AI for identification
   - Safety monitoring
   - Data storage

2. **"Everything works together"**
   - Take a photo → AI tells you what it is
   - Hold the sensor → App warns if you're being too rough
   - All saved → Never lose your discoveries

3. **"It's designed for real archaeology"**
   - Works offline (no internet needed)
   - Protects artifacts (safety alerts)
   - Learns from each scan (improves over time)

---

*Created for FLL Presentation - AncientVision Team*
