# DorpOS

**A complete smartphone-style operating system for ComputerCraft: Tweaked**  
Designed for Advanced Pocket Computers (Ender Pocket Computers) on Minecraft SMPs.

---

## What is DorpOS?

DorpOS is a modular, professionally structured operating system that runs entirely
within ComputerCraft: Tweaked. It looks and behaves like a real smartphone OS:

- 📱 **Home screen** with icon grid, dock, app drawer, and notification centre
- 🔒 **Lock screen** with PIN protection
- 🔔 **Notification system** with banners and DND mode
- 📨 **Messages** — DMs with any DorpOS user on the SMP
- 🛒 **DorpMarket** — Facebook Marketplace style listings
- 📓 Notes, Contacts, Files, Calculator, Clock, Calendar
- ⚙️ Settings — theme picker, PIN change, network status
- ☁️ Cloud backup and restore
- 🔄 Automatic OTA updates
- 🎨 3 built-in themes (Dark, Light, AMOLED) + custom theme support
- 🔌 8 backend servers with full REST-style API

---

## Quick Start

### For Players (Phone Setup)

1. **Get an Advanced Pocket Computer** with a wireless modem
2. **Copy `phone/startup.lua`** to `/startup.lua` on the pocket computer
3. **Boot the computer** — it will automatically find the Provisioning Server and install DorpOS
4. Follow the on-screen setup wizard

### For SMP Operators (Server Setup)

See [docs/SERVER_SETUP.md](docs/SERVER_SETUP.md) for full server setup instructions.

Quick summary:
1. Set up 8 CC computers as backend servers
2. Copy files to each server (see server_setup doc)
3. Set the same `/data/secret.txt` on all servers
4. Run each `servers/<name>/server.lua`
5. Copy `phone/` to `/phone_files/` on Provisioning and Updates servers

---

## Project Structure

```
DorpOS/
├── phone/                  # Everything that runs on the phone
│   ├── startup.lua         # Tiny bootstrap (copy this first)
│   ├── boot.lua            # Boot sequence
│   ├── kernel.lua          # Central event loop
│   ├── system/             # OS subsystems
│   │   ├── ui/             # UI framework + 14 components
│   │   ├── theme/          # Theme engine + 3 themes
│   │   ├── network/        # Networking facade
│   │   ├── storage/        # Atomic key-value storage
│   │   ├── crypto/         # SHA-256, HMAC tokens
│   │   ├── animation/      # Transition engine
│   │   ├── services/       # App manager, notifications, updater
│   │   ├── setup/          # First-boot wizard
│   │   └── utils/          # Logger, helpers
│   └── apps/               # All phone apps
│       ├── home/           # Home screen / launcher
│       ├── lockscreen/     # PIN lock screen
│       ├── messages/       # DM messaging
│       ├── marketplace/    # DorpMarket
│       ├── settings/       # System settings
│       ├── calculator/     # Calculator
│       ├── clock/          # Clock + stopwatch + timer
│       ├── notes/          # Notes
│       ├── files/          # File browser
│       ├── contacts/       # Address book
│       ├── calendar/       # Calendar + events
│       ├── about/          # System info
│       └── cloud/          # Cloud sync
│
├── servers/                # Backend server programs
│   ├── shared/             # server_base.lua (common routing)
│   ├── provisioning/       # OS installer server
│   ├── activation/         # Token issuer
│   ├── accounts/           # User profiles
│   ├── messages/           # Chat server
│   ├── notifications/      # Push queue
│   ├── marketplace/        # Listings
│   ├── updates/            # OTA updates
│   └── cloud/              # Backup/restore
│
├── shared/                 # Used by phone AND servers
│   ├── constants.lua       # All hostnames, versions, limits
│   ├── protocol.lua        # Core networking (rednet abstraction)
│   └── api.lua             # Convenience facade
│
└── docs/                   # Documentation
    ├── ARCHITECTURE.md
    ├── ADDING_APPS.md
    ├── SERVER_SETUP.md
    ├── NETWORKING.md
    └── THEMES.md
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System architecture and data flow |
| [SERVER_SETUP.md](docs/SERVER_SETUP.md) | How to run the backend servers |
| [ADDING_APPS.md](docs/ADDING_APPS.md) | How to create new apps |
| [NETWORKING.md](docs/NETWORKING.md) | Protocol reference and all endpoints |
| [THEMES.md](docs/THEMES.md) | Theme system and custom themes |

---

## Requirements

- ComputerCraft: Tweaked (1.100+)
- Advanced Pocket Computer (or any CC computer for testing)
- Wireless modem on the phone
- CC computers with modems for backend servers
- (Optional) Ender modems for unlimited range

---

## Scope

Music player and camera are intentionally excluded from this version.

---

*DorpOS — not affiliated with Mojang, CurseForge, or CC:T. Made for fun on an SMP.*
