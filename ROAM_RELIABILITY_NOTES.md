# Roam-inspired reliability changes (development branch)

## Provenance
- Roam Control's official public [user guide](https://github.com/seanhowarthdev/Roam-Control/blob/main/Documentation/UserGuide.md) describes interrupted-session recovery and explicit restoration.
- Historical reference: [0.9.0 Beta 1 commit](https://github.com/hxhlb/Roam-Control/tree/f4db410a3a7a54d2ad2c72a6659e38d). Its tree listing and MIT license were returned during initial research, but subsequent individual-file reads returned 404; no historical Swift implementation has been copied.
- WrapPin and later source-available Roam Control versions use noncommercial licensing; no code from them is included. The changes here are original modifications to Safe Location.

## Changes
- Route cancellation returns immediately after interrupted sleep and before another coordinate update; failed writes stop route progress rather than reporting completion.
- Restoration blocks new simulation updates and queued keepalive work; DVT status reads use the native engine queue.
- The last successful simulated coordinate is recorded locally in preferences; after relaunch the drawer offers explicit real-location restoration or acknowledgement after independent verification. It does not start a new simulation on launch.
- A successful restore removes the recovery record; failure leaves it for retry. Acknowledgement clears the local record only.
- Road route and imported track GPX export through the system file picker; stale routes are cleared on new planning attempts.

## Verification plan (not yet executed on iPhone)
1. On an owned test device, establish a fixed simulated location, terminate the app, reopen it, and verify recovery appears without automatically applying a new location. Restore while LocalDevVPN is connected; verify independently with Maps. Relaunch and verify the recovery panel is absent.
2. Repeat while LocalDevVPN is disconnected; verify recovery failure is shown and the record remains. Connect VPN and retry.
3. Start a route; stop during the 500 ms sleep, then verify no further route points are applied. Immediately start a new route and verify the old task cannot clear its state.
4. Restore while a route is active; verify no queued resend or route update re-applies simulated location. Repeat with joystick mode.
5. Export a planned route and a GPX import. Check .gpx extension and re-import; compare count, name and endpoints. Check a route name with ampersands and Chinese characters.
6. Request a valid route, then a failing route; verify the old route is not offered as the new result.
7. Run the repository quality checks and macOS Xcode build before distributing an IPA. Repeat map-panel regression tests at small/large detents.
8. Re-test Wi-Fi and 5G separately. This branch does not alter cellular tunnel logic, coordinate conversion or VPN protocol.

## Limitations
This is a source-level development change, not an iOS-tested release. iOS may suspend or kill the app; preferences are best-effort and are not proof of the OS location state. Existing installations that terminated before this version have no new recovery record. A restore failure must not be treated as successful. Acknowledgement requires independent verification. No location telemetry or new network dependency is introduced.
