# DorpOS Networking Protocol Reference

## Overview

All communication uses `shared/protocol.lua`. No code outside of that
module may call `rednet.*` directly.

## Service Discovery

Servers advertise themselves with `rednet.host()`:
```lua
rednet.host("dorpos", "dorpos.messages")
```

Clients discover them with `rednet.lookup()`:
```lua
local id = rednet.lookup("dorpos", "dorpos.messages")
```

This is handled automatically by `proto.lookup(C.HOST_MESSAGES)`.

## Packet Format

### Request
```lua
{
    protocol = "dorpos",       -- always "dorpos"
    version  = 1,              -- C.PROTOCOL_VERSION
    id       = "a1b2c3d4",    -- unique 8-char hex + timestamp
    endpoint = "/svc/action",  -- REST-style route
    session  = "token...",     -- omit for unauthenticated
    body     = { ... },        -- payload table
}
```

### Response
```lua
{
    protocol = "dorpos",
    version  = 1,
    id       = "a1b2c3d4",   -- mirrors the request id
    ok       = true,          -- boolean
    code     = 200,           -- HTTP-style status code
    message  = "OK",          -- human-readable
    body     = { ... },       -- response data
}
```

## Status Codes

| Code | Meaning |
|------|---------|
| 200 | OK |
| 201 | Created |
| 400 | Bad Request |
| 401 | Unauthorised (invalid/expired session) |
| 403 | Forbidden (valid session, no permission) |
| 404 | Not Found |
| 409 | Conflict (e.g. username taken) |
| 429 | Rate Limited |
| 500 | Internal Server Error |
| 503 | Service Unavailable |
| 504 | Gateway Timeout (client-generated, no response received) |

## Endpoints Reference

### Activation (`dorpos.activation`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/activate` | No | Get session token for device |
| `/activation/link` | Yes | Link device to user account |
| `/activation/verify` | No | Verify a token |

### Accounts (`dorpos.accounts`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/account/create` | No | Register new user |
| `/account/login` | No | Login and get token |
| `/profile/get` | Yes | Get own profile |
| `/profile/update` | Yes | Update theme/settings |
| `/contacts/sync` | Yes | Sync contact list |
| `/friends/add` | Yes | Add a friend |
| `/account/lookup` | No | Find user by username |

### Messages (`dorpos.messages`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/messages/start` | Yes | Start or find conversation |
| `/messages/send` | Yes | Send a message |
| `/messages/history` | Yes | Get message history |
| `/messages/conversations` | Yes | List all conversations |
| `/messages/poll` | Yes | Get offline-queued messages |

### Marketplace (`dorpos.marketplace`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/market/browse` | No | Browse listings with search/sort |
| `/market/listing` | No | Get single listing |
| `/market/post` | Yes | Create new listing |
| `/market/remove` | Yes | Remove own listing |
| `/market/sold` | Yes | Mark listing as sold |
| `/market/mine` | Yes | Get own listings |

### Notifications (`dorpos.notifications`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/notifications/push` | Yes/Internal | Push to a user |
| `/notifications/poll` | Yes | Drain pending notifications |
| `/notifications/broadcast` | Internal | Broadcast to all |

### Updates (`dorpos.updates`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/updates/manifest` | No | Get current file manifest |
| `/updates/file` | No | Download a specific file |
| `/updates/rebuild` | No | Rebuild the manifest cache |

### Cloud (`dorpos.cloud`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/cloud/backup` | Yes | Upload user data |
| `/cloud/restore` | Yes | Download user data |
| `/cloud/status` | Yes | Check backup status |

### Provisioning (`dorpos.provisioning`)
| Endpoint | Auth | Description |
|----------|------|-------------|
| `/provision/hello` | No | Bootstrap discovery broadcast |
| `/provision/file` | No | Download individual OS file |
| `/provision/complete` | No | Confirm installation |

## Retry Behaviour

`proto.request()` automatically retries up to `C.NET_MAX_RETRIES` (3) times
with `C.NET_RETRY_DELAY` (2s) between attempts. On exhaustion it returns a
synthetic 504 response.
