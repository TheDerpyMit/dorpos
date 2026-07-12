# DorpOS Architecture

## Overview

DorpOS is a complete smartphone operating system for ComputerCraft: Tweaked
running on Advanced Pocket Computers. It is structured as a set of independently
testable modules with clean separation between phone-side code, backend servers,
and shared libraries.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Advanced Pocket Computer               │
│                                                          │
│  startup.lua → boot.lua → kernel.lua                    │
│                    │                                     │
│            ┌───────┼───────────────────┐                │
│            │       │                   │                 │
│         system/   apps/             data/               │
│         ui/       home/             config/             │
│         theme/    messages/         cache/              │
│         network/  marketplace/      logs/               │
│         crypto/   settings/         user/               │
│         storage/  calculator/                           │
│         services/ notes/ files/                         │
│         animation/ contacts/                            │
│         utils/    clock/ calendar/                      │
│                   about/ cloud/                         │
└────────────────────────┬────────────────────────────────┘
                         │ Rednet (hostname discovery)
                         │
┌────────────────────────┴────────────────────────────────┐
│                   Backend Servers                         │
│                                                          │
│  dorpos.provisioning   dorpos.activation                │
│  dorpos.accounts       dorpos.messages                  │
│  dorpos.notifications  dorpos.marketplace               │
│  dorpos.updates        dorpos.cloud                     │
└─────────────────────────────────────────────────────────┘
```

## Module Reference

### phone/startup.lua
Tiny bootstrap (< 150 lines). Checks if OS is installed.
- If yes: hands off to `boot.lua`
- If no: broadcasts provisioning request, downloads all files, reboots

### phone/boot.lua
Main boot sequence:
1. Animated logo
2. Hardware / filesystem / network checks
3. Activation (issues session token)
4. First-run detection → setup wizard or lock screen
5. Hands off to `kernel.lua`

### phone/kernel.lua
Central event loop. Manages:
- App launch via `app_manager`
- Notification banners
- Background update and notification polling
- Crash recovery and error screen

### phone/system/ui/ui.lua
UI framework. All drawing goes through here.
- Never call `term.*` directly from apps
- 14 reusable components (button, label, list, dialog, keyboard, etc.)
- All colours come from the active theme

### phone/system/theme/theme.lua
Theme engine. Lazy-loads theme tables from `themes/*.lua`.
- `Theme.get()` → current theme table
- `Theme.set("dark"|"light"|"amoled")` → switch + persist

### phone/system/network/network.lua
Phone-side networking facade.
- Auto-injects session tokens
- Offline message queue
- `net.post(hostname, endpoint, body)` → ok, response

### phone/system/storage/storage.lua
Atomic persistent key-value storage.
- `Storage.open("name")` → store object
- Atomic writes via temp-file rename

### phone/system/crypto/sha256.lua
Pure-Lua SHA-256. Used for PIN hashing and file integrity.

### phone/system/crypto/token.lua
HMAC-signed session tokens. Servers issue, phones forward, servers verify.

### phone/system/services/app_manager.lua
App registry and protected launch. Built-in apps + third-party.

### phone/system/services/notification_manager.lua
Local notification queue with DND, priorities, and persistence.

### phone/system/services/updater.lua
OTA update service. Hash-based delta downloads.

### phone/system/animation/animation.lua
Lightweight animation engine using `window.create`.
Transitions: slideLeft/Right/Up/Down, fade, popIn, spinner, progress, toast.

## Data Flow: Boot → Home

```
Power on
  └─ startup.lua opens modem
       └─ boot.lua exists?
            ├─ No  → provision from server → reboot
            └─ Yes → logo → checks → activation
                          → first run?
                               ├─ Yes → wizard → write user_config
                               └─ No  → lockscreen → PIN entry
                          → kernel.lua
                               └─ app_manager.launch("com.dorpos.home")
                                    └─ home/init.lua event loop
```

## Data Flow: Sending a Message

```
User types in messages/init.lua
  └─ net.post(HOST_MESSAGES, "/messages/send", { convoId, text })
       └─ network.lua injects session token
            └─ protocol.lua → rednet.lookup("dorpos.messages") → ID
                 └─ rednet.send to Messages Server
                      └─ server verifies token (HMAC)
                           └─ stores message
                                └─ queues offline notification for recipient
                                     └─ responds ok → phone shows sent
```

## File Naming Conventions

| Pattern | Meaning |
|---------|---------|
| `system/*/module.lua` | Phone subsystem library |
| `apps/*/init.lua` | App entry point |
| `servers/*/server.lua` | Backend server program |
| `shared/*.lua` | Used by both phone and servers |
| `data/*.dat` | Serialised storage files |

## Security Model

1. **Tokens**: HMAC-SHA256, issued by Activation Server, verified by all servers
2. **PINs**: SHA-256 hashed on device, never sent to server
3. **Marketplace**: All listing/purchase validation server-side; client balance/ownership never trusted
4. **Sessions**: 24-hour TTL, stored locally, re-issued on boot if expired
5. **Updates**: Every downloaded file verified by SHA-256 before replacing

## Adding a New App

See `ADDING_APPS.md` for the step-by-step guide.
