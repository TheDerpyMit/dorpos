# DorpOS Server Setup Guide

## Overview

DorpOS requires backend servers to support its online services. You can deploy this in two ways:
1. **Dedicated Servers (Recommended for SMPs):** Run 8 separate ComputerCraft computers, each running one server daemon.
2. **All-in-One Server:** Run a single ComputerCraft computer executing all 8 daemons concurrently using parallel execution.

Every server computer needs a wireless modem attached.

---

## Interactive Installation (Easy Setup)

To quickly set up any server (dedicated or all-in-one), run the interactive setup wizard:

```
/servers/setup.lua
```

This setup script will:
- Let you choose the server's role (1-8 or All-in-One).
- Configure the shared HMAC secret in `/data/secret.txt`.
- Copy phone repository files to `/phone_files/` automatically if serving provisioning or updates.
- Set up `/startup.lua` to run the daemon automatically on computer boot.

---

## Manual Setup Steps

If you prefer to configure the server manually, follow these steps:

### Step 1: Set up the shared secret

Every server needs the SAME HMAC secret so that tokens issued by the Activation Server can be verified by any other server.

On each server computer, create `/data/secret.txt`:
```
my-super-secret-smp-key-change-this
```

Replace this value with something long and random. Copy the exact same key to all server instances.

---

### Step 2: Copy files to each server

Each server needs:
- `shared/` directory (constants.lua, protocol.lua, api.lua)
- `system/crypto/` (sha256.lua, token.lua)
- `servers/shared/server_base.lua`
- Its own `servers/<name>/server.lua` (or `servers/all.lua` for All-in-One)

For the **Provisioning** and **Update** servers, you must copy the entire contents of the `/phone` directory to `/phone_files` on their local filesystems.

---

### Step 3: Start the server

Run the server script directly, or write a `startup.lua`:


```
-- Provisioning server
dofile("/servers/provisioning/server.lua")

-- Activation server
dofile("/servers/activation/server.lua")

-- etc.
```

Each server will call `rednet.host()` automatically and begin listening.

---

## Step 4: Verify connectivity

From any CC computer with a modem, test service discovery:

```lua
rednet.open("back")  -- or whatever side your modem is on
local id = rednet.lookup("dorpos", "dorpos.accounts")
print("Accounts server ID: " .. tostring(id))
```

If `nil` is returned, the server is not running or out of range.

---

## Server Responsibilities

| Server | Hostname | Purpose |
|--------|----------|---------|
| Provisioning | `dorpos.provisioning` | Install OS on fresh phones |
| Activation | `dorpos.activation` | Issue session tokens |
| Accounts | `dorpos.accounts` | User profiles, login, contacts |
| Messages | `dorpos.messages` | DMs, group chats |
| Notifications | `dorpos.notifications` | Push notification queue |
| Marketplace | `dorpos.marketplace` | Listings, post, remove |
| Updates | `dorpos.updates` | OTA update manifest + file delivery |
| Cloud | `dorpos.cloud` | User data backup/restore |

---

## Updating OS Files

1. Copy new `phone/` files to `/phone_files/` on the Updates and Provisioning servers
2. Update `C.OS_VERSION` in `shared/constants.lua`
3. On the Updates server, send: `dorpos_rebuild` event or restart the server
4. Phones will automatically detect the update within `C.UPDATE_POLL_INTERVAL` seconds

---

## Security Notes

- Never share or expose `/data/secret.txt`
- The HMAC secret should be changed if a server is compromised
- Marketplace validation is entirely server-side — client cannot fake listings or ownership
- Session tokens expire after `C.SESSION_TTL` seconds (default 24 hours)
