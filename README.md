# webOS Clean

A unified, surgical **debloat, privacy hardening, and performance optimization toolkit** for rooted LG webOS Smart TVs (powered by Homebrew Channel).  
Synthesizes and improves upon the best techniques from `gist-lucataco`, `glasshouse`, `webos10-homescreen-customization`, and `free-my-tv`.

**Zero external dependencies:** written in **100% pure POSIX shell** utilizing native operating system utilities (`luna-send`, `systemctl`, BusyBox, and Linux OverlayFS). No Node.js, no Python, and **zero persistent background daemons**.

---

## ✅ Requirements

### On the television
| Requirement | Detail |
| :--- | :--- |
| **LG webOS TV** | webOS 4.x or newer. Validated on **webOS 10.3.1** (aarch64, 2 GB RAM). Feature differences: webOS 10+ uses the OverlayFS Home Screen path, webOS 9 falls back to the manifest XML path, and daemon masking uses `systemctl` (Upstart fallback on webOS 3). |
| **Root access** | Mandatory. Provided by **Homebrew Channel** (RootMyTV / Crashd exploit). The boot hook needs a writable `/var/lib/webosbrew/init.d/`. Without root every action aborts immediately. |
| **Remote shell** | Working **telnet** (port 23) or **SSH** (port 22) login as root. Verify it *before* running anything, since it is your recovery path. |
| **Free space in `/var`** | At least **2 MB** for state snapshots and the boot counter (`--selftest` and every run check this). SquashFS partitions are never written. |
| **Native binaries** | Only utilities already shipped with webOS: `luna-send`, `systemctl`, `mount`/`umount` (OverlayFS + tmpfs), `tar`, `awk`, `sed`, `grep`, `od`, `sha256sum`, `df` (BusyBox / ash). **Nothing to install on the TV — no Node.js, no Python, no daemons.** |

### On your computer (only for the helper tools and the test suite)
| Requirement | Needed by |
| :--- | :--- |
| POSIX `sh`, `tar`, `sha256sum`, `nc` (netcat) | `tools/pull-backup.sh` (streams the backup over TCP 9000, listens locally) |
| `python3` | `tools/deploy_to_tv.sh` (local HTTP server for deployment) |
| `telnet` (or `nc`) | `test/tv_exec.sh` remote execution bridge and on-device integration runs |
| Nothing else | `test/run-tests.sh` is fully offline and runs on any POSIX shell |

> ⚠️ **Not included by design:** restoring raw state tarballs onto a live system (`--restore-backup`) is disabled (`BACKUP_RESTORE_ENABLED=0`). Use `--restore` or LG's official factory reset instead.

---

## ⚠️ Legal Disclaimer & Risk Notice

**USE STRICTLY AT YOUR OWN RISK. THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NONINFRINGEMENT.**

Modifying Smart TV system services, internal bus settings, application manifests, or persistent preferences carries inherent risks:
- You alone are responsible for any modifications made to your device.
- In the event of data loss, application malfunctions, loss of root privileges following firmware upgrades, or hardware issues, neither the authors nor any contributors can be held liable.
- Rooting your television and tampering with system internals may void your manufacturer warranty.
- **Before proceeding, read this entire document**, familiarize yourself with the fail-safe recovery procedures, and verify that you have working telnet or SSH access to your TV.

---

## 💡 Why Everything is 100% Reversible

A fundamental design requirement of `webOS Clean` is that **no change is destructive or permanent without a clean path back to factory stock**. Here is why:

### 1. Read-Only SquashFS System Partitions
The core webOS operating system partitions (`/usr`, `/lib`, `/etc`, and the Linux kernel) reside on signed, read-only SquashFS images verified with `dm-verity`.  
- **`webOS Clean` never modifies, formats, or writes to SquashFS partitions.**
- All file manipulations are carried out through **Linux OverlayFS** mounts, volatile **tmpfs** (RAM) filesystems, or non-destructive configurations inside the writable `/var` partition.

### 2. Comprehensive Atomic State Backups
Before modifying any configuration (such as regional app blocklists or home screen layout templates), the tool creates an exact snapshot in `/var/lib/webos-clean/backup/`. Running `--restore` reinstates the factory files byte-for-byte.

### 3. Pure Volatile Test Mode (`--test`)
Running the tool with the `--test` flag applies all optimizations (systemd transient masking, Preload Manager policy, DNS telemetry blocking, and Home Screen OverlayFS) strictly in **RAM (tmpfs)**.  
- **Zero writes to persistent flash.**
- If you reboot the TV or unplug the power cable, every single modification vanishes instantly, returning the TV 100% to its original state.
- You can also revert the test session immediately without rebooting via `--undo-test`.

### 4. The Ultimate Safety Net: Official Factory Reset
Because the core operating system is immutable inside read-only SquashFS, even in the worst-case scenario of complete filesystem corruption inside the writable `/var` partition, triggering a standard **"Reset to Initial Settings"** from the TV's official Settings menu reformats `/var` and restores the TV 100% to out-of-the-box factory condition.

---

## 🛡️ Multi-Tiered Safety Architecture & Fail-safes

To safeguard against black screens, bootloops, or communication failures, `webOS Clean` incorporates five autonomous layers of defense:

### 1. Boot Watchdog (Dead-Man's Switch)
The startup hook installed at `/var/lib/webosbrew/init.d/50-webos-clean` tracks consecutive boot attempts via a persistent counter in `/var/lib/webos-clean/boot_fails`:
- On startup, the counter increments.
- If the TV fails to reach a healthy operational state **two consecutive times** (e.g., if a crash prevents the system from reaching the user interface), the watchdog automatically triggers an **emergency auto-rollback (`--restore`)** and disables itself.
- Once the TV boots successfully and the System Application Manager (SAM) responds normally, the counter is reset to `0`.

### 2. Blind USB Rescue Recovery
If the television screen remains blank or the network interface becomes inaccessible:
1. Take any standard USB flash drive formatted in **FAT32, exFAT, or EXT4**.
2. Create an empty file in the root of the drive named `WEBOS_CLEAN_REVERT` or `REVERT_NOW`.
3. Plug the drive into any USB port on the TV and turn it on (or power-cycle).
4. During early boot, before user-space services start, the hook directly probes all block devices (`/dev/sd*`), detects the rescue file, executes a full rollback (`--restore`), deletes the boot hook, and safely unmounts the drive.

### 3. Real-Time Luna Bus Smoke Test
Whenever changes are permanently applied (`--apply`), the script waits for system daemons to settle and conducts a real-time smoke test via `luna-send` against `com.webos.service.applicationmanager`. If SAM fails to return a valid response within 3 seconds, the script **immediately triggers an automatic rollback** and restores all original configurations.

### 4. Non-Destructive OverlayFS Sandboxing
On webOS 10+, customizing the Home Screen layout (`home.xml`) never overwrites the Flutter bundle on disk. Instead, an **OverlayFS** mount transparently overrides the XML in RAM. Crucial containers (such as `herobanner` and `appList`) and structural lateral anchors (`globalline` shrunk to `0x0` rather than removed) are preserved mathematically so the Flutter rendering engine never panics or produces a black screen.

### 5. Strict Path-Whitelisted State Backups
All off-device backups (`pull-backup.sh` and `--backup`) validate every archived entry against a strict whitelist (`var/preferences`, `var/luna/preferences`, `var/db`, `var/lib/webosbrew`, `var/lib/webos-clean`). Any archive containing paths outside this whitelist (such as system root files or `etc/hosts`) is flatly rejected with an error code.

---

## ⚡ Measured Hardware Benchmarks (LG webOS 10.3.1, aarch64)

Benchmarked and validated on physical hardware (LG webOS TV 10.3.1 / Rockhopper 10.3.1-3006, Linux kernel 5.4.268, 2 GB physical RAM, aarch64):

| Optimization Stage | Live Hardware Result |
| :--- | :--- |
| **Systemd Service Masking in `/run`** | 7 telemetry/tracking daemons masked: `remotelogger`, `rdxd`, `camera`, `mycar`, `contentminer`, `nudge` stopped; `uploadd` dead |
| **Luna `setPreloadPolicy` Per App** | Suppressed for `browser`, `lgchannels`, `livemenu` (`false`); `home` and `hdmi1..4` strictly preserved (`true`) |
| **Telemetry & ACR DNS Block** | 25 tracking domains directed to `0.0.0.0`; YouTube (HTTP 200) and Netflix (HTTP 302) fully operational |
| **Controlled RAM Gain (A/B Test)** | **+85.2 MB uncompressed RAM freed** (585.2 MB baseline with LG Channels resident vs. 670.4 MB closed) |
| **Effective RAM Headroom Gain** | **~20% increase in available operational RAM** (`+88.2 MB` reported by `measure.sh` under live workload) |
| **Blind USB Rescue (End-to-End)** | Flash drive on `/tmp/usb/sda/sda1` detected via `WEBOS_CLEAN_REVERT`; automatic `--restore` triggered |
| **Ephemeral Mode Disk Writes** | **0 bytes written to persistent storage**: `/var/lib/webos-clean` non-existent; init hooks untouched |

### Hardware Quirks Discovered on webOS 10.3+
1. **`luna-send` Argument Handling:** On webOS 10+, the legacy `-t` flag initiates multi-iteration timing benchmarks and swallows stdout. Calls must use `-i -n 1 -w 3000`.
2. **Preload Policy Payload:** `com.webos.service.preloadmanager/setPreloadPolicy` rejects bulk maps with *"Invalid 'application' parameter"*. It requires atomic, per-app calls: `{"application":{"id":"<appId>","isEnabled":false}}`.
3. **Daemon Overwrites:** The Preload Manager daemon actively rewrites `/var/preferences/webos-preload-manager-conf.json` ~3 seconds after an app enters the foreground. Storing policy in config files fails; policy suppression must be re-sent over Luna by the startup hook on every boot.
4. **Tmpfs Hosts Mount:** On modern webOS, `/etc/hosts` is already a tmpfs mount managed by Homebrew Channel's `startup.sh`. Editing it directly is volatile in RAM and avoids nesting bind mounts.

---

## 🔄 Firmware & Application Updates (What You Need to Know)

Before optimizing your television, understand how official LG updates interact with modifications:

### 1. How a Firmware Update (OTA) Can Break Debloat
LG firmware updates write directly to the read-only SquashFS partitions (`/usr`, `/lib`, `/etc`, kernel):
- **Loss of Root (Critical Hazard):** An OTA update patches the security vulnerability (Crashd, RootMyTV) that enabled root access. Without root, `/var/lib/webosbrew/startup.sh` cannot elevate privileges, causing the debloat hook `/var/lib/webosbrew/init.d/50-webos-clean` to be skipped. Debloat is deactivated and all stock bloatware returns.
- **Wiping or Migration of `/var`:** Major version upgrades (e.g., webOS 23 to webOS 24) frequently reformat or run migration routines that wipe `/var/preferences/` and `/var/db/`, deleting custom blocklists.
- **Luna Bus and Systemd Changes:** LG occasionally changes daemon names or updates Luna API signatures (e.g., the complete redesign of `setPreloadPolicy` between webOS 9 and 10).

### 2. How Application Updates Can Break Debloat
- **Third-Party Apps (Netflix, YouTube, Prime Video, Plex):** **Zero impact.** They operate inside sandboxed user space (`/media/cryptofs/apps/`) and never interfere with system daemons or debloat configs.
- **Built-in System Apps (Home Launcher, LG Channels, Web Browser):**
  - Core system apps are bundled into the read-only firmware; they are **not** updated as standalone IPKs via the LG Content Store.
  - However, system app updates that arrive with firmware patches may reset Preload Manager registers (our boot hook continuously re-suppresses this) or alter the internal Flutter `home.xml` asset hierarchy.

### 3. Dual-Layer OTA Update Blocking (Enabled by Default)
To guarantee that an unexpected background update does not revoke root or break your setup, **`webOS Clean` blocks firmware updates by default** in permanent mode (`--apply`):
1. **DNS Layer (`/etc/hosts`):** Official LG update endpoints are sinkholed to `0.0.0.0`:
   - `snu.lge.com`
   - `su-dev.lge.com`
   - `su.lge.com`
   - `su-ssl.lge.com`
2. **Homebrew Channel Boot Flag (`webosbrew_block_updates`):**
   - The tool manages the trigger flag `/var/luna/preferences/webosbrew_block_updates`.
   - During early boot, Homebrew Channel's `startup.sh` reads this flag and routes LG update hosts to loopback (`127.0.0.1` and `::1`) before network daemons initialize.
3. **Restoration:** Running `--restore` removes the block flag only if it was originally created by `webOS Clean`, preserving prior user preferences.

---

## 🖥️ Minimalist Home Screen (App Tiles Only)

Inspired by the [Glasshouse Project (App Tiles Dashboard)](https://rorygallagher2024.github.io/glasshouse/dashboard/apps/), **`webOS Clean` enables a distraction-free, ultra-fast Home Screen by default**:

```text
+--------------------------------------------------------------+
|                                                              |
|              Clean Top Hero Banner (No Ads)                  |
|                                                              |
+--------------------------------------------------------------+
| [Netflix] [YouTube] [Plex] [Prime] [HDMI 1] [HDMI 2] [...]   |
+--------------------------------------------------------------+
```

### What is Removed:
- **Quick Cards (`qcardList`):** Large promotional cards for LG Gaming, Sports, Home Office, and Music.
- **Recommended Shelf (`recommendedShelf`):** Algorithmic carousel promoting sponsored TV shows and third-party streaming content.
- **Side Control Icons (`globalline`):** Search, account, and notification icons collapsed to `0x0` dimension to prevent visual clutter without crashing the Flutter container.

### What Remains:
- **Application & Input Row (`appList`):** Your installed streaming services, Homebrew apps, and HDMI inputs.
- **Comfortable Bottom Anchoring:** The top banner height is mathematically recalculated to compensate for removed shelves, keeping your app row comfortably anchored at the lower third of the screen rather than floating awkwardly in the middle.

---

## 🚀 Operating Modes & Usage

Deploy `webOS Clean` to your television (e.g., via telnet on port 23 or SSH on port 22 into `/tmp/wc`):

### 1. Ephemeral Test Mode (Zero Risk, RAM Only)
Run optimizations entirely in memory to evaluate stability and performance without writing to disk:
```sh
sh bin/webos-clean --test
```
*To undo the test session immediately without restarting the TV:*
```sh
sh bin/webos-clean --undo-test
```

### 2. Full Permanent Debloat (Recommended)
Applies all optimizations, configures the Minimalist Home Screen, masks daemons, silences telemetry, blocks OTA updates, and installs the boot watchdog:
```sh
sh bin/webos-clean --apply
```
*To apply the full debloat while keeping LG's stock promotional cards and recommendations:*
```sh
sh bin/webos-clean --apply --no-clean-home
```

### 3. Isolated Minimalist Home Screen (Permanent & Reversible)
If you **only** want the clean, ad-free Home Screen without touching system daemons, telemetry, or app preloading:
```sh
# Apply ONLY the minimal Home Screen permanently:
sh bin/webos-clean --clean-home

# Revert ONLY the Home Screen back to LG factory stock:
sh bin/webos-clean --restore-home
```

### 4. Full Factory Restoration
Completely restores the television to factory stock settings:
```sh
sh bin/webos-clean --restore
```
- Restores original regional app blocklists (`BRA.json`, `USA.json`, etc.).
- Re-enables factory Preload Manager policies.
- Unmasks and restarts all telemetry daemons.
- Restores original system settings and terms of service agreements.
- Removes the startup hook from `/var/lib/webosbrew/init.d/` and cleans state files.

### 5. Diagnostics & Benchmarking
```sh
# Measure available RAM and identify running bloatware processes:
sh bin/webos-clean --measure

# Run pre-flight sanity checks (root permissions, Luna bus responsiveness, disk space):
sh bin/webos-clean --selftest
```

---

## 📦 State Backup & Disaster Recovery

### Streaming Backup to Computer (Zero Disk Usage on TV)
To create an off-device backup of your television's state without consuming the limited storage in `/var`:
```sh
# On your computer: opens a TCP receiver on port 9000 and signals the TV to stream state
./tools/pull-backup.sh 10.1.1.11 ./backups
```
*Produces an archive (typically ~3 MB compressed) containing `var/preferences`, `var/luna/preferences`, `var/db`, and `var/lib/webosbrew`, complete with a cryptographic `.manifest`.*

### On-Device RAM Backup
```sh
# Archives state into the /tmp ramdisk:
sh bin/webos-clean --backup /tmp
```

### Restoring State Backups (`--restore-backup`)
> ⚠️ **Note:** Physical hardware restoration from raw tarballs is intentionally disabled by default (`BACKUP_RESTORE_ENABLED=0`). While path validation and checksum checks are strictly enforced, restoring arbitrary database snapshots onto a running system can cause state discrepancies with `settingsservice`. Prefer using official settings reset or `--restore` whenever possible.

---

## 🧪 Automated Testing Suite

The repository includes a comprehensive, 7-stage offline mock test suite that validates every script without touching real hardware:
```sh
test/run-tests.sh
```
1. **POSIX Syntax Validation (`sh -n`):** Verifies all shell scripts against strict POSIX syntax.
2. **Ephemeral Mode Verification (`--test`):** Proves zero persistent files are created on disk.
3. **Permanent Mode Verification (`--apply`):** Validates backups, boot hook installation, and update blocking.
4. **Full Restore Verification (`--restore`):** Ensures complete removal of state markers and hooks.
5. **Regression Coverage:** Asserts that `luna_call` preserves raw JSON payloads without corruption.
6. **Failsafe & USB Rescue Verification:** Simulates dead-man's switch triggers and USB markers.
7. **Isolated Home Screen Verification:** Verifies that `--clean-home` and `--restore-home` operate in complete isolation from services and preload configurations.

---

## 📂 Project Architecture

```text
anotherwebosdebloat/
├── bin/
│   └── webos-clean           # Unified CLI interface (--test, --apply, --restore, --clean-home, etc.)
├── init/
│   └── 50-webos-clean        # Startup hook with dead-man's boot watchdog and blind USB rescue
├── lib/
���   ├── common.sh             # Platform detection, logging, and robust Luna Bus transport
│   ├── measure.sh            # Live RAM benchmarking (/proc/meminfo) and RSS attribution
│   ├── services.sh           # Transient & permanent systemd daemon masking
│   ├── preload.sh            # Preload Manager policy suppression and resident memory reclamation
│   ├── privacy.sh            # ACR/LivePlus disabling, telemetry DNS blocking, and eulaStatus revocation
│   ├── hide_apps.sh          # blockedSystemAppList management with zero-restart samrescan
│   ├── homescreen.sh         # Non-destructive OverlayFS layout transformation (webOS 10+)
│   └── backup.sh             # Path-whitelisted state packaging and manifest generation
├── test/
│   ├── run-tests.sh          # Complete 7-stage offline mock test harness
│   ├── mock-luna-send.sh     # Luna Bus test double
│   └── tv_exec.sh            # Remote execution bridge for automated TV integration
└── tools/
    ├── deploy_to_tv.sh       # One-step HTTP deployment to television ramdisk
    └── pull-backup.sh        # TCP network backup streamer
```

---

## License

This project is released under the **MIT License**. Use responsibly and enjoy a faster, cleaner, and private webOS experience!
