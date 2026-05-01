# Bifrost Android Runtime Flow

Simple reference for where code should live and how the Android server flow should work.

## Current `lib` View

```text
lib/
  main.dart
  Components/
    add_server_window.dart
    server_card.dart
  Pages/
    homepage.dart
    setingspage.dart
  Service/
    official_server_download_service.dart
    server_storage_service.dart
  Utils/
    directory_picker_service.dart
    jar_downloader.dart
    settings_repository.dart
```

## Folder Roles

### `Components/`
- Reusable UI pieces only
- No server process logic
- Current examples:
  - `add_server_window.dart`
  - `server_card.dart`

### `Pages/`
- Screen-level UI
- Calls managers and services
- Should not own process execution logic
- Current examples:
  - `homepage.dart`
  - `setingspage.dart`

### `Service/`
- Current service folder in the repo
- Holds backend-style work such as:
  - official jar/version resolution
  - server storage and file creation
- Current examples:
  - `official_server_download_service.dart`
  - `server_storage_service.dart`

### `Utils/`
- Shared helpers and managers
- Good place for:
  - repositories
  - pickers
  - download helpers
  - process manager
- Current examples:
  - `directory_picker_service.dart`
  - `jar_downloader.dart`
  - `settings_repository.dart`

## Target Runtime Structure

Use this structure as we continue Android server execution work.

```text
lib/
  Components/
  Pages/
  Services/
    jre_service.dart
    android_process_service.dart
    foreground_server_service.dart
    server_install_service.dart
    official_server_download_service.dart
    server_storage_service.dart
  Utils/
    server_process_manager.dart
    server_launch_config.dart
    server_state.dart
    directory_picker_service.dart
    jar_downloader.dart
    settings_repository.dart
```

## What Each Target Folder Should Do

### `Services/`
- Android or platform-facing execution work
- File preparation and install steps
- Runtime checks
- Foreground service lifecycle

Planned files:

#### `jre_service.dart`
- Check whether Android JRE exists
- Return Java binary path

#### `android_process_service.dart`
- Start Java process
- Stop Java process
- Send stdin commands
- Return stdout/stderr events

#### `foreground_server_service.dart`
- Start Android foreground task
- Keep server alive in background
- Stop foreground task after shutdown

#### `server_install_service.dart`
- Create `eula.txt`
- Resolve runnable jar path
- Prepare server before first launch

#### `official_server_download_service.dart`
- Fetch official version lists
- Resolve Vanilla and Paper jars
- Download selected artifact

#### `server_storage_service.dart`
- Create server folder
- Write `server.properties`
- Write `bifrost_server.json`
- Delete server folder

### `Utils/`
- App-level orchestration and simple data models
- Should not talk directly to Android UI

Planned files:

#### `server_process_manager.dart`
- Main manager for server lifecycle
- Coordinates all services
- Exposes start/stop/sendCommand
- Owns state updates for the UI

#### `server_launch_config.dart`
- Build Java launch command
- Hold executable, args, and working directory

#### `server_state.dart`
- State enum and models
- Example states:
  - `idle`
  - `starting`
  - `running`
  - `stopping`
  - `error`

## End-to-End Flow

### 1. User creates a server
- `AddServerWindow` collects:
  - server name
  - server type
  - version
  - RAM
- `homepage.dart` submits the request

### 2. Storage is created
- `server_storage_service.dart` creates:
  - server root
  - `world/`
  - `jars/`
  - `mods/`
  - `backups/`
  - `server.properties`
  - `bifrost_server.json`

### 3. Official jar is resolved
- `official_server_download_service.dart` checks the selected server type
- It resolves the correct official download

### 4. Jar is downloaded
- `jar_downloader.dart` downloads the file into `jars/`
- `homepage.dart` shows download progress through `ServerDownloadCard`

### 5. User presses Start
- `homepage.dart` calls `server_process_manager.dart`

### 6. Runtime is prepared
- `jre_service.dart` checks Java runtime
- `server_install_service.dart`:
  - writes `eula.txt`
  - confirms runnable jar path

### 7. Background execution is enabled
- `foreground_server_service.dart` starts Android foreground mode

### 8. Java server starts
- `android_process_service.dart` launches Java
- `server_launch_config.dart` provides:
  - Java executable
  - RAM flags
  - jar path
  - working directory

### 9. Manager updates UI
- `server_process_manager.dart` listens to logs and process state
- `homepage.dart` and `server_card.dart` read those states

### 10. User presses Stop
- `server_process_manager.dart` sends `stop`
- If graceful stop fails, it force-stops the process
- `foreground_server_service.dart` is stopped after shutdown

## Simple Build Order

Follow this order to avoid rework:

1. `server_state.dart`
2. `server_launch_config.dart`
3. `server_install_service.dart`
4. `jre_service.dart`
5. `foreground_server_service.dart`
6. `android_process_service.dart`
7. `server_process_manager.dart`
8. Start/Stop controls in `server_card.dart`
9. Console/log UI

## Rule of Thumb

- `Pages` show state
- `Components` render reusable UI
- `Services` do platform/backend work
- `Utils` coordinate and model the flow

## Important Note

The repo currently uses `lib/Service/` as the service folder.

If you want strict naming consistency with the runtime plan, we should later rename:

```text
lib/Service -> lib/Services
```

That rename should be done in one pass with import updates so the codebase stays clean.

## Bundled JRE 21 Contract

Use one bundled `arm64` runtime for Android.

### Native executable
- Package the Java launcher in the Android native library directory
- Current expected file name:
  - `libbifrost_java.so`
- Current expected resolved location on device:
  - `<nativeLibraryDir>/libbifrost_java.so`
- Source:
  - bundled `JRE-21/bin/java`

### Java home
- Ship the Java home data separately as bundled app data
- Current expected resolved location on device:
  - `<filesDir>/jre-home`
- Source:
  - bundled `JRE-21/`

### Runtime expectation
- `libbifrost_java.so` is the executable launcher
- `jre-home/` contains the Java runtime home layout:
  - `bin/` if needed by the runtime layout
  - `conf/`
  - `legal/`
  - `lib/`
  - `lib/modules`

### Required bundled JRE-21 files

#### `jniLibs/arm64-v8a/`
- `libbifrost_java.so`
  - from `JRE-21/bin/java`
- `libjava.so`
- `libjli.so`
- `libjsig.so`
- `libjvm.so`

#### `assets/jre-home/`
- `bin/`
- `conf/`
- `legal/`
- `lib/`
- `lib/modules`
- especially keep:
  - `lib/libjli.so`
  - `lib/server/libjvm.so`
  - `lib/libjsig.so`
  - `lib/jspawnhelper`

### Why the split exists
- Android blocks executing downloaded binaries from writable app storage
- Native executable code must come from packaged native locations
- Java home data can still live in normal app-owned readable storage

### Current implementation status
- Flutter now expects a bundled `JRE 21` contract
- Android native code now looks for:
  - executable in `nativeLibraryDir`
  - Java home in `filesDir/jre-home`
- Android now supports a `java -version` smoke test before server launch
- The actual packaged runtime files still need to be added
