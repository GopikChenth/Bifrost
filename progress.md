# Bifrost — Development Progress

## ✅ Completed Features

### 1. Server Creation

- User can create a new Minecraft server (name, version, type, memory)
- Downloads the server `.jar` from official sources
- Saves server metadata to local storage
- `ServerCard` + `AddServerWindow` UI complete

### 2. Server Start / Stop

- Starts the Minecraft server via the embedded JRE (JNI/NDK)
- Polls server status every 2 seconds
- UI shows: `Starting` → `Online` → `Stopping` → `Offline`
- Console label and runtime messages displayed on card
- Stop kills the JVM process cleanly

### 3. Bore Tunnel — Binary & Android Execution (Resolved)

Two major hurdles were solved:

#### Problem 1 — Share button not clickable

`LocalServerStatus.isBusy` returns `true` when server state is `running`.
The tunnel callbacks were gated behind `server.isBusy`, so the button
was always disabled when the server was online.
**Fix:** Removed `server.isBusy` from tunnel callback conditions.

#### Problem 2 — `Permission denied` on execve

The bore binary was copied to `filesDir/tools/bore`. Android mounts
`/data/user/0/<pkg>/files/` with `noexec` — the kernel blocks `execve()`
regardless of file permissions or SELinux grants.
**Fix:** Moved binary to `jniLibs/arm64-v8a/libbore.so`. Android package
manager extracts `.so` files to `nativeLibraryDir` which IS executable.
Added `android:extractNativeLibs="true"` to the manifest.

### 4. Tunnel UI (ServerCard)

- `_TunnelSection` widget — shown only when server is `Online`
- States: idle → starting (spinner) → active (address box) → error → stopped
- Active state: shows tunnel address prominently
- **Share** button opens a dialog with the address + instructions for friends
- **Copy** button copies address to clipboard with snackbar
- **Stop** link stops the tunnel
- Polling continues while active (detects if agent dies)

---

## ❌ Current Blocker — bore.pub Unreachable

```
bore: Error: could not connect to bore.pub:7835
bore: Caused by: timed out
```

bore.pub is a free community relay that has been persistently abused by
malware authors (phishing, C2 infrastructure). As a result:

- The service is intermittently down or throttled
- Some carriers/ISPs block port 7835 outright
- Confirmed unreachable on both WiFi and mobile data

**Decision: Switch to Playit.gg**

---

## 🔜 Next — Playit Tunnel Integration

### What you need to do first (manual steps):

1. Create account at [playit.gg](https://playit.gg)
2. Go to **Agents** → Add Agent → copy the `SK-xxxx...` secret key
3. Go to **Tunnels** → Add Tunnel → TCP, port 25565 → copy the permanent address
4. Download `playit-aarch64-unknown-linux-musl` from [GitHub releases](https://github.com/playit-cloud/playit-agent/releases)
5. Rename to `libplayit.so` → place in `android/app/src/main/jniLibs/arm64-v8a/`

### What will be implemented (code changes):

- `PlayitManager.kt` — runs agent, manages lifecycle
- `bifrost/playit` MethodChannel in `MainActivity.kt`
- `lib/Services/playit_service.dart` — Dart wrapper
- `lib/Services/settings_service.dart` — stores secret + address in SharedPreferences
- Settings UI — enter secret key + tunnel address
- Updated `ServerCard` — shows Playit tunnel state + permanent address

---

## Files Modified / Created

| File                                                | Status      | Notes                                              |
| --------------------------------------------------- | ----------- | -------------------------------------------------- |
| `lib/Utils/tunnel_models.dart`                      | ✅ Created  | `TunnelStatus` model                               |
| `lib/Services/tunnel_service.dart`                  | ✅ Created  | `bifrost/tunnel` MethodChannel Dart wrapper        |
| `lib/Models/bifrost_server.dart`                    | ✅ Modified | Added `tunnelState`, `tunnelPort`, `tunnelMessage` |
| `lib/Services/server_manager_service.dart`          | ✅ Modified | `startTunnel`, `stopTunnel`, polling               |
| `lib/Components/server_card.dart`                   | ✅ Modified | `_TunnelSection` widget                            |
| `lib/Pages/homepage.dart`                           | ✅ Modified | Wired tunnel callbacks                             |
| `android/.../TunnelManager.kt`                      | ✅ Created  | Runs bore via `nativeLibraryDir`                   |
| `android/.../MainActivity.kt`                       | ✅ Modified | Registered `bifrost/tunnel` channel                |
| `android/app/src/main/AndroidManifest.xml`          | ✅ Modified | `extractNativeLibs=true`                           |
| `android/app/src/main/jniLibs/arm64-v8a/libbore.so` | ✅ Placed   | Bore binary (2.76 MB, aarch64-musl)                |
