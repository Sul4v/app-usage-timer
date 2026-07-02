# Enabling the live Dynamic Island capsule (APNs)

The capsule updates in real time by having the monitor extension ask a
Supabase Edge Function to push the new value to the Live Activity via Apple
Push Notification service. Everything is built and deployed — it only needs
your APNs auth key, which is the one thing that can't be created
programmatically.

## 1. Create an APNs auth key (one-time, ~2 min)

1. Go to <https://developer.apple.com/account/resources/authkeys/list>
2. Click **+**, name it "Capsule APNs", tick **Apple Push Notifications
   service (APNs)**, Continue → Register.
3. **Download** the `AuthKey_XXXXXXXXXX.p8` (you can only download it once).
   The `XXXXXXXXXX` part is the **Key ID**.

## 2. Give the key to the Edge Functions

From the repo root (Supabase CLI already linked to the `capsule` project):

```bash
supabase secrets set APNS_KEY_ID=XXXXXXXXXX --project-ref ubglgtworopygeenbnvb
supabase secrets set APNS_KEY="$(cat ~/Downloads/AuthKey_XXXXXXXXXX.p8)" --project-ref ubglgtworopygeenbnvb
```

`APNS_TEAM_ID` (6LYZDNCM4M), `APNS_BUNDLE_ID` (com.sodhera.capsule) and
`APNS_HOST` (sandbox) are already set.

That's it — the capsule will start updating live within a minute of using a
tracked app. Verify with:

```bash
# after the app has run once on your phone so a token is registered
curl -s -X POST "https://ubglgtworopygeenbnvb.supabase.co/functions/v1/capsule-push" \
  -H "Authorization: Bearer <anon-key>" -H "Content-Type: application/json" \
  -d '{"device_id":"<your device_id>","app_nickname":"Instagram","used_minutes":20,"limit_minutes":45}'
# → {"ok":true}  and the capsule on your phone jumps to 20m
```

Settings ▸ Capsule diagnostics shows `pushed · Nm · just now` (green) when
it's working, or the APNs error if something's off.

## Dev vs production APNs

- **Dev builds run through Xcode** use the **sandbox** APNs host
  (`api.sandbox.push.apple.com`) — already set. The app entitlement is
  `aps-environment: development`.
- **TestFlight / App Store** builds use production. Before shipping, change
  the entitlement to `production` and:
  ```bash
  supabase secrets set APNS_HOST=api.push.apple.com --project-ref ubglgtworopygeenbnvb
  ```

## How it scales

The same APNs auth key serves your whole user base — Apple's push
infrastructure handles the fan-out. Server cost is just the Edge Function
invocations (~one per tracked-minute per active user); at 10k users that's a
few tens of dollars/month, and the push JWT is cached ~30 min to stay well
under APNs rate limits.
