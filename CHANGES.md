# TurboWarp Mobile — Change Log

Changes made to adapt TurboWarp (scratch-gui) for Android and iOS via Capacitor.

---

## scratch-gui

### New files

#### `src/lib/tw-platform.js`
Platform-detection helpers used throughout the GUI to branch between web, Capacitor-Android, and Capacitor-iOS code paths.

```
isAndroid()          — UA-based Android detection
isIOS()              — UA-based iOS detection
isCapacitor()        — true when running inside any Capacitor native shell
capacitorPlatform()  — returns 'android' | 'ios' | null
isCapacitorAndroid() — true only inside Capacitor on Android
isCapacitorIOS()     — true only inside Capacitor on iOS
isMobile()           — isAndroid() || isIOS()
```

#### `src/lib/tw-capacitor-file-bridge.js`
JavaScript bridge to the native `FileSave` Capacitor plugin (Android: Java, iOS: Swift).
- `saveFile(blob, fileName, mimeType)` — converts a Blob to base64 and calls `Capacitor.Plugins.FileSave.saveFile`; shows the OS file-picker for the user to choose a save location.
- `openFile(options)` — calls `Capacitor.Plugins.FileSave.openFile`; shows the OS document-picker; returns `{data: base64, name, uri}`.
- `base64ToArrayBuffer(base64)` — helper used by the file-uploader to turn the plugin's response back into an ArrayBuffer.

#### `src/containers/addon-settings-modal.jsx`
A React modal wrapper for the Addon Settings page, used when running inside Capacitor (where opening a new browser window/tab is not possible). Uses `React.lazy` + `Suspense` to lazily load the heavy `settings.jsx` chunk.

### Modified files

#### `src/containers/modal.jsx`
**Bug fix: Android back button left orphaned history entries.**

`handleCapacitorBackButton` previously called `this.props.onRequestClose()` directly. This closed the modal visually but did not pop the `history.pushState` entry added in `componentDidMount`, leaving the history stack polluted. Repeated modal opens would eventually let the back button navigate away from the app entirely.

Fix: call `history.back()` instead. This pops the history entry, fires the `popstate` event, which triggers `handlePopState`, which calls `onRequestClose()`.

Also added: registration of the Capacitor `App.addListener('backButton', …)` listener in `addEventListeners` and clean removal in `removeEventListeners`.

#### `src/containers/sb3-downloader.jsx`
**Bug fix: Capacitor file-save dialog cancel was showing an error alert.**

`handleSaveError` only suppressed `AbortError` (the FS API's cancel signal). When the user tapped Cancel in the native Android/iOS save dialog, the Capacitor plugin rejected with `{code: 'CANCELLED'}`. This fell through to `onShowSaveErrorAlert()` and showed a spurious error.

Fix: added `|| (e && e.code === 'CANCELLED')` to the early-return guard.

On Capacitor the `downloadProject` path is routed through `capacitorSaveFile` (the bridge above) instead of `downloadBlob`.

The `showSaveFilePicker` default prop explicitly excludes Android UA strings to prevent Chrome-on-Android from invoking the FS API with strict MIME enforcement on `.sb3` files.

#### `src/lib/sb-file-uploader-hoc.jsx`
On Capacitor, file opening is routed through `capacitorOpenFile` (the bridge) instead of `<input type="file">` or the FS `showOpenFilePicker` API.

`showOpenFilePicker` default prop also excludes Android UA strings, for the same reason as save.

Cancel from the native picker (`e.code === 'CANCELLED'`) is silently ignored.

#### `src/reducers/modals.js`
Added `MODAL_ADDON_SETTINGS = 'addonSettingsModal'` modal key with matching `openAddonSettingsModal` / `closeAddonSettingsModal` action creators. The modal state flows to `gui.jsx` via `mapStateToProps`.

#### `src/components/gui/gui.jsx` and `src/containers/gui.jsx`
- `AddonSettingsModal` imported and conditionally rendered when `addonSettingsModalVisible` is true.
- Props/propTypes updated accordingly.

#### `src/playground/render-interface.jsx`
- On Capacitor: `onClickAddonSettings` dispatches `openAddonSettingsModal()` (renders the modal in-app).
- On web: `onClickAddonSettings` opens `addons.html` in a new window (existing behaviour preserved).
- `mapDispatchToProps` was previously `() => ({})` (a no-op); replaced with a real implementation that wires both cases.

#### `src/playground/index.ejs`
Added `<script src="inject-android-bridge.js"></script>` to load the legacy Cordova Bluetooth Serial bridge at startup (required by the existing Bluetooth extension).

---

## turbowarp-android (Capacitor project)

### Android (existing, documented for reference)

#### `android/app/src/main/java/com/crispstrobe/turbowarp/FileSavePlugin.java`
Custom Capacitor plugin. Handles:
- `saveFile` — launches `ACTION_CREATE_DOCUMENT` intent; resolves with `{uri}`.
- `openFile` — launches `ACTION_OPEN_DOCUMENT` intent; resolves with `{data: base64, name, uri}`.
- Cancel: rejects with `call.reject("User cancelled", "CANCELLED")` — the `CANCELLED` code is what JS detects.

### iOS (new)

#### Added `@capacitor/ios` platform
```
cd turbowarp-android
npm install @capacitor/ios
npx cap add ios        # generated ios/ Xcode project
npx cap sync ios       # copied build/ assets + plugin metadata
```

The generated project lives at `turbowarp-android/ios/`.

#### `ios/App/App/FileSavePlugin.swift`
iOS equivalent of the Android `FileSavePlugin`, using `UIDocumentPickerViewController`:
- `saveFile` — writes the incoming base64 data to a temp file, presents the picker in export mode (`forExporting`/`exportToService`), resolves with `{uri}`.
- `openFile` — presents the picker in open mode (`forOpeningContentTypes`/`.open`) with `asCopy: true`, reads the file, resolves with `{data: base64, name, uri}`.
- Cancel: rejects with `call.reject("User cancelled", "CANCELLED")` — same code as Android, so the JS layer needs no changes.

Conforms to `UIDocumentPickerDelegate` (`documentPicker(_:didPickDocumentsAt:)` and `documentPickerWasCancelled(_:)`).

#### `ios/App/App/FileSavePlugin.m`
Objective-C bridge file required by Capacitor's runtime to auto-register the Swift plugin:
```objc
CAP_PLUGIN(FileSavePlugin, "FileSave",
    CAP_PLUGIN_METHOD(saveFile, CAPPluginReturnPromise);
    CAP_PLUGIN_METHOD(openFile, CAPPluginReturnPromise);
)
```
This is what makes `window.Capacitor.Plugins.FileSave` available in the WebView on iOS.

---

## Platform file I/O matrix (after all changes)

| Platform | Open file | Save file |
|---|---|---|
| Desktop Chrome/Edge | `showOpenFilePicker` (FS API) | `showSaveFilePicker` (FS API) |
| Firefox / Safari / older Chrome | `<input type="file">` | `downloadBlob` (anchor click) |
| Android browser (Chrome) | `<input type="file">` | `downloadBlob` |
| Capacitor Android | `FileSavePlugin.openFile` (Java) | `FileSavePlugin.saveFile` (Java) |
| Capacitor iOS | `FileSavePlugin.openFile` (Swift) | `FileSavePlugin.saveFile` (Swift) |
| iOS Safari browser | `<input type="file">` | `downloadBlob` (iOS 12/13 workarounds in download-blob.js) |
