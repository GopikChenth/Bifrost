# File Usage

This document explains the current file-related logic in Bifrost.

## Purpose

Bifrost needs file access for three core tasks:

1. Let the user choose where Minecraft server data should live.
2. Save that location so the app can reuse it later.
3. Download server `.jar` files into a usable local path.

## Current Files

### `lib/utils/directory_picker_service.dart`

This file isolates native directory picking from the UI.

- Uses `file_selector`
- Opens the platform file manager
- Returns a selected directory path as `String?`
- Keeps picker-specific code out of page widgets

Public API:

```dart
final String? path = await const DirectoryPickerService().pickDirectory();
```

### `lib/utils/settings_repository.dart`

This file stores and loads the server directory setting.

- Uses `shared_preferences`
- Saves whether the app should use the default path
- Saves a custom directory path when selected
- Builds the effective directory path used by the app

Main model:

```dart
ServerDirectorySettings
```

Main repository:

```dart
SettingsRepository
```

Default path:

```text
internal storage/minecraft
```

### `lib/Pages/setingspage.dart`

This page is the UI layer for file location settings.

- Loads the saved directory configuration
- Shows the current effective path
- Lets the user switch between default storage and a custom path
- Opens the native file manager through `DirectoryPickerService`
- Saves the result through `SettingsRepository`

This page should not contain low-level file picker logic or storage persistence logic directly.

### `lib/utils/jar_downloader.dart`

This file handles server jar downloads.

- Accepts an `http` or `https` URL
- Validates that the output file ends with `.jar`
- Creates parent directories when needed
- Streams the download to disk
- Exposes progress updates
- Deletes partial files if the download fails

Main class:

```dart
JarDownloader
```

Main method:

```dart
downloadJar(...)
```

## Current Flow

1. User opens Settings.
2. User chooses default storage or taps `Select Path`.
3. `DirectoryPickerService` opens the native file manager.
4. The selected path is saved by `SettingsRepository`.
5. Other backend services can read that saved path later.
6. `JarDownloader` can download server jars into that chosen directory.

## Why This Structure

This separation is the more professional approach because:

- UI stays simple and easier to maintain
- file picker behavior is reusable
- settings persistence is reusable
- backend download logic stays independent from screens
- future storage validation can be added without rewriting page code

## Recommended Next Step

The next file-related backend piece should be a storage service such as:

```text
lib/utils/server_storage_service.dart
```

That service should:

- read the saved directory setting
- validate the selected path
- create standard folders like `jars`, `worlds`, `mods`, and `backups`
- provide resolved paths to the rest of the app
