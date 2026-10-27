# Sonarr, Radarr, Lidarr: managed Connect (webhook) lifecycle

Verified 2026-10-27 with a live create, drift, repair and delete cycle on Sonarr 4.0.19, Radarr 6.4.3 and Lidarr 3.1.0, plus source reading. Endpoint and payload details are in [../research/arr-connect-api.md](../research/arr-connect-api.md).

| Step | Sonarr | Radarr | Lidarr |
|---|---|---|---|
| Create (`POST /notification`) from the app's own Webhook schema template | 201, **one synchronous `Test` POST** to our URL | same | same |
| Read back against the desired definition | identical | identical | identical |
| Custom headers readable on GET | yes | yes | yes |
| Drift detection (one event flag changed, URL changed) | detected | detected | detected |
| Repair with a full PUT | 202, re-tested once, no drift afterwards | same | same |
| **PUT of an unchanged definition** | **no re-test** | **no re-test** | **re-tests every time** |
| Delete | 200, gone | 200, gone | 200, gone |

## Implications
- **The receiver must be up and answer `Test` with 2xx** before a connection is created or repaired.
- **Only PUT when drift is detected.** Lidarr re-tests on every PUT.
- **`Test` payload keys:**

  | App | Keys |
  |---|---|
  | Sonarr | `applicationUrl, episodes, eventType, instanceName, series` |
  | Radarr | `applicationUrl, eventType, instanceName, movie, release, remoteMovie` |
  | Lidarr | `albums, applicationUrl, artist, eventType, instanceName` (plural `albums`) |

  The receiver must accept `Test` without requiring the fields used for scanning.
- **Identifying our connection:**
  - A fingerprint header (for example `X-Autoplow-Instance`) is stored and returned as-is, so it identifies our connection reliably.
  - Password fields come back masked.
- **Migration detection:** Webhook connections whose URL path contains `/triggers/` reliably identify existing autoscan-style hooks.
- **Other tools manage Arr webhooks too.** Tofa, for example, maintains its own named connections. Leave connections we don't own untouched.
