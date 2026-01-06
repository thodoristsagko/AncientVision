# Firebase Setup Instructions

## Step 1: Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project"
3. Name it "AncientVision" (or similar)
4. Enable Google Analytics if desired
5. Click "Create project"

## Step 2: Add Android App
1. In your Firebase project, click the Android icon
2. Enter package name: `com.example.ancient_vision`
3. App nickname: "Ancient Vision"
4. Click "Register app"

## Step 3: Download Config File
1. Download `google-services.json`
2. Place it in: `android/app/google-services.json`

## Step 4: Enable Firestore
1. In Firebase Console, go to "Build" > "Firestore Database"
2. Click "Create database"
3. Choose "Start in test mode" (for development)
4. Select a location close to you
5. Click "Enable"

## Step 5: Run the App
After placing google-services.json, run:
```
flutter run
```

## Firestore Structure
The app uses this collection structure:

```
findings/
  A-001/
    name: "Bronze Coin"
    type: "Coin"
    site: "Trench B3"
    date: "2025-11-06"
    description: "..."
    latitude: 37.9715
    longitude: 23.7267
    imageUrl: null
    createdAt: <timestamp>
```

## Security Rules (Production)
For production, update Firestore rules:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /findings/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```
