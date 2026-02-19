
# TurboWarp for Android (Unofficial Build)

**A native Android wrapper for TurboWarp Desktop, featuring hardware support for LEGO® EV3 (Bluetooth Classic) and Spike Prime (BLE).**

This project uses **Capacitor** to wrap the TurboWarp web client into a native Android app, injecting a custom Bluetooth bridge to allow JavaScript to talk to physical LEGO bricks.

---

## Project Structure

This repository is designed to live "side-by-side" with your other TurboWarp repositories. It cannot be built in isolation.

```text
/workspace/
├── extensions/          # (Clone: https://github.com/CrispStrobe/extensions)
├── scratch-gui/         # (Clone: https://github.com/CrispStrobe/scratch-gui)
└── turbowarp-android/   # (This Repo)
    ├── android/         # Native Android Studio Project
    ├── capacitor.config.json
    └── package.json
```

---

## Prerequisites

1. **Node.js** (v18 or newer)
2. **Android Studio** (Koala or newer recommended)
3. **Java JDK 17** (Required for Gradle 8.x)
4. **Xcode** (macOS only, for iOS builds)

---

## Quick Start (Build Scripts)

All build commands are available as npm scripts. Run them from the `turbowarp-android/` directory.

### One-Command Builds

```bash
# Build web assets + sync to Android
npm run build:android

# Build web assets + sync to iOS
npm run build:ios

# Build web assets + sync all platforms
npm run build:all
```

### Individual Steps

```bash
# Build scratch-gui web assets only
npm run build:web

# Sync to platforms (without rebuilding web)
npm run sync              # All platforms
npm run sync:android      # Android only
npm run sync:ios          # iOS only

# Copy extension files into Android assets
npm run copy:extensions

# Open in IDE
npm run open:android      # Opens Android Studio
npm run open:ios          # Opens Xcode

# Run on connected device/emulator
npm run run:android
npm run run:ios
```

### Full Android Build Workflow

```bash
# 1. Install dependencies (both projects)
cd ../scratch-gui && npm install && cd ../turbowarp-android && npm install

# 2. Build web + sync + copy extensions
npm run build:android
npm run copy:extensions

# 3. Open in Android Studio and build APK
npm run open:android
```

### Full iOS Build Workflow

```bash
# 1. Add iOS platform (first time only)
npx cap add ios

# 2. Install dependencies
cd ../scratch-gui && npm install && cd ../turbowarp-android && npm install

# 3. Build web + sync
npm run build:ios

# 4. Open in Xcode and build
npm run open:ios
```

---

## Part 1: Prepare "The Brain" (Scratch GUI)

Before building the Android app, you must patch the web client to trust the local Android environment and build the web assets.

### 1. Patch Security Manager

Open `../scratch-gui/src/containers/tw-security-manager.jsx`.
Add `http://localhost/` and `http://localhost:8000/` to the trusted extension list. This allows the Android WebView to load your custom extensions.

```javascript
const isTrustedExtension = url => (
    url.startsWith('https://extensions.turbowarp.org/') ||
    url.startsWith('http://localhost/') ||      // Trust Capacitor Android
    url.startsWith('http://localhost:8000/') || // Trust Dev Server
    extensionsTrustedByUser.has(url)
);
```

### 2. Build the Web App

Compile the Scratch GUI into a static web folder.

```bash
cd ../scratch-gui
npm install
npm run build
# Result: A populated 'build/' folder containing index.html and static assets.
```

Or use the shortcut from `turbowarp-android/`:

```bash
npm run build:web
```

---

## Part 2: Prepare "The Body" (Android Wrapper)

### 1. Initialize & Sync

Run these commands from the `turbowarp-android` root to pull in the latest web assets and plugins.

```bash
npm install
npm run sync:android
```

### 2. The "Brain Transplant" (Inject Extensions)

Copy the raw extension files and metadata into the Android assets.

```bash
npm run copy:extensions
```

Or manually:

```bash
mkdir -p android/app/src/main/assets/public/extensions
mkdir -p android/app/src/main/assets/public/generated-metadata
cp ../extensions/extensions/*.js android/app/src/main/assets/public/extensions/
cp ../extensions/extensions/extensions.json android/app/src/main/assets/public/generated-metadata/extensions-v0.json
```

### 3. Inject the Bluetooth Bridge

We need to inject a script that translates Scratch Link WebSocket calls into Android native Bluetooth commands.

1. **Create the Bridge Script:**
Ensure `android/app/src/main/assets/public/inject-android-bridge.js` exists. (See `inject-android-bridge.js` in this repo for content).
2. **Link it in HTML:**
Open `android/app/src/main/assets/public/index.html`.
Add this line just before the closing `</body>` tag:
```html
<script src="inject-android-bridge.js"></script>
</body>
```

---

## Part 3: Android Configuration

### 1. Gradle Versions (Critical)

To support **SDK 36** (Android 16 Preview) while maintaining compatibility with standard Android Studio versions, use this exact configuration.

* **`android/variables.gradle`**
```gradle
ext {
    minSdkVersion = 24
    compileSdkVersion = 36
    targetSdkVersion = 36
    // ... other versions ...
    cordovaAndroidVersion = '14.0.1'
}
```

* **`android/build.gradle` (Project Level)**
```gradle
dependencies {
    // AGP 8.12.3 is the stable max for current IDEs
    classpath 'com.android.tools.build:gradle:8.12.0'
    classpath 'com.google.gms:google-services:4.4.4'
}
```

* **`android/gradle/wrapper/gradle-wrapper.properties`**
```properties
# Gradle 8.13 is required to build SDK 36
distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-bin.zip
```

### 2. Android Manifest Permissions

Open `android/app/src/main/AndroidManifest.xml`. Ensure these permissions are present for LEGO Bluetooth support and force **Landscape Mode**.

```xml
<manifest ...>
    <uses-permission android:name="android.permission.BLUETOOTH" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

    <application ...>
        <activity
            android:name=".MainActivity"
            android:screenOrientation="landscape"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|locale|smallestScreenSize|screenLayout|uiMode|navigation|density"
            ...>
            </activity>
    </application>
</manifest>
```

---

## Native Plugins

### FileSavePlugin

A custom Capacitor plugin registered in `MainActivity.java` that provides native Android file picker integration via Storage Access Framework (SAF):

- **`saveFile()`** - Opens Android's native "Save As" dialog (`ACTION_CREATE_DOCUMENT`). Accepts base64-encoded file data, filename, and MIME type. Writes to the user-selected location.
- **`openFile()`** - Opens Android's native file browser (`ACTION_OPEN_DOCUMENT`). Returns the selected file as base64-encoded data along with filename and URI.

These are called from the web layer via `src/lib/tw-capacitor-file-bridge.js` and replace the browser's `showSaveFilePicker`/`showOpenFilePicker` APIs which are unavailable in Android WebView.

### Back Button Support

The `@capacitor/app` plugin provides hardware back button events. Modals listen for `backButton` events and close themselves, matching native Android navigation behavior.

---

## Part 4: Building the APK

### 1. Sync & Verify

Open the project in Android Studio:

```bash
npm run open:android
```

* Click **Sync Project with Gradle Files** (Elephant icon).
* **Verify:** Ensure the "Build" tab shows green checks.

### 2. Set App Icon (Optional)

* Right-click `app` folder in the project tree.
* Select **New > Image Asset**.
* Select your `Turbowarp_icon.png`.
* Resize to fit the Safe Zone and click Finish.

### 3. Generate Signed APK

1. Go to **Build > Generate Signed Bundle / APK**.
2. Select **APK**.
3. Create a new KeyStore (`release.jks`) if you don't have one.
4. Select **Release** build variant.
5. Click **Create**.

The final APK will be located at:
`android/app/release/app-release.apk`

### Command-Line APK Build (Alternative)

```bash
cd android
./gradlew assembleDebug    # Debug APK
./gradlew assembleRelease  # Release APK (requires signing config)
```

---

## Script Reference

| Script | Description |
|---|---|
| `npm run build:web` | Build scratch-gui web assets |
| `npm run build:android` | Build web + sync Android |
| `npm run build:ios` | Build web + sync iOS |
| `npm run build:all` | Build web + sync all platforms |
| `npm run sync` | Sync all platforms (no web rebuild) |
| `npm run sync:android` | Sync Android only |
| `npm run sync:ios` | Sync iOS only |
| `npm run open:android` | Open Android Studio |
| `npm run open:ios` | Open Xcode |
| `npm run run:android` | Run on Android device/emulator |
| `npm run run:ios` | Run on iOS device/simulator |
| `npm run copy:extensions` | Copy extensions into Android assets |

---

## License

Based on TurboWarp and Scratch.

* **This project** and **TurboWarp:** GPLv3
* **Scratch:** BSD-3-Clause

**Disclaimer:** This project is not affiliated with TurboWarp, the Scratch Team, or the LEGO Group.
