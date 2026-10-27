# ADR-0013: Google Drive monitoring with the user's own OAuth client

## Status
Accepted

## Date
2026-10-26

## Context
- Drive change monitoring needs the `drive.readonly` scope, which Google classifies as *restricted*. An OAuth client shipped with Autoplow would need Google's security verification, and the device flow doesn't allow Drive read scopes.
- Service accounts give a poor user experience.

## Decision
- **Sign-in:** users create a Google OAuth *web application* client, enter its ID and secret in the UI, and connect through a redirect back to Autoplow.
- **Coverage:** My Drive and shared drives, across several accounts.
- **Change tracking:** a snapshot plus the Changes API, with events committed before the page token is saved.
- **Polling:** default 1 minute, minimum 30 seconds.
- **Minimum age:** defaults above the rclone mount's poll interval.

## Alternatives Considered
- **Service accounts** (autoscan's bernard).
- **Reusing tokens from `rclone.conf`:** possible later.

## Consequences
- One-time Google Cloud setup per user, with an in-app guide.
- Requires a reachable HTTPS URL for the redirect.
