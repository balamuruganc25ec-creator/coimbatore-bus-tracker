# Coimbatore Transit — full-stack website starter

This is a database-backed bus route, timetable, fleet, and GPS location application. It is more than a static mockup, but **it is not operational until you connect your own Supabase project, create an administrator, enter verified route data, and place a GPS-enabled device with the bus**.

## What's included

- `index.html` — responsive website UI, route planner, stop-by-stop ETA calculations, map, route/stop/route-sequence/schedule/bus management, sign-in, and GPS location sharing.
- `supabase_setup.sql` — database tables, indexes, row-level security policies, GPS-write authorization function, and initial sample Coimbatore route.

## Free-to-start architecture

- **Frontend:** GitHub Pages (public static site).
- **Database and authentication:** Supabase project.
- **Map:** Leaflet with OpenStreetMap tiles.
- **Live location:** browser geolocation on a phone carried with/installed in the bus; an authenticated admin or assigned driver account can send GPS updates.

Free service plans have quotas/limits and may change. This project does not include a paid domain, official transit feed, dedicated GPS hardware, or a guarantee of continuous availability.

## Setup — in order

### 1. Create Supabase project

1. Open https://supabase.com and create a project.
2. In the project dashboard, open **SQL Editor**.
3. Open `supabase_setup.sql`, copy its full contents, paste into SQL Editor, and run it.
4. The script creates tables with Row Level Security enabled. Public visitors can read active route and schedule data; mutations are restricted to admin accounts. GPS writes go through a database function that checks whether the signed-in account is an administrator or is assigned to that bus.

### 2. Create the first administrator account

1. In Supabase, open **Authentication → Users** and add a user with an email and password. Confirm the account if the dashboard offers that option.
2. In **SQL Editor**, replace `admin@example.com` in the SQL below with the exact email used in step 1, then run it:

```sql
insert into public.admin_users (user_id)
select id from auth.users where lower(email) = lower('admin@example.com')
on conflict (user_id) do nothing;
```

3. Sign in using that email/password in the site's top-right sign-in fields. The management panels should become available.
4. Do not expose an account password in source control or in screenshots.

### 3. Connect `index.html` to Supabase

Open `index.html` in a text editor. Near the bottom, find:

```js
const SUPABASE_URL = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY';
```

Replace these with the **Project URL** and the **publishable key** (or legacy `anon` public key) from the Supabase project's API settings. A browser app may contain a publishable/anon key only when database policies are configured correctly. **Never put a `service_role` key or any secret key in `index.html` or in GitHub.**

### 4. Publish on GitHub Pages

1. Create a **public** GitHub repository, e.g. `coimbatore-transit`.
2. Upload `index.html` to the repository root. `README.md` and `supabase_setup.sql` can also be uploaded.
3. Open **Settings → Pages**; set the source to **Deploy from a branch**, branch `main`, folder `/(root)`, and save.
4. Wait for GitHub Pages to publish, then open the URL shown in Settings → Pages.
5. Test the page using HTTPS. Browser GPS access generally requires a secure context and user permission.

## How to use the website

### Public journey planner

- Select an active route.
- Select a boarding stop and a destination later in the configured route sequence.
- Choose the intended start/departure time and press **Calculate ETA**.
- The website calculates an estimate from distance, baseline speed, traffic multiplier, configured extra delay, and boarding dwell times. If a fresh bus location reports a usable speed, that speed is used as the current speed input for the estimate.

### Admin management

Sign in with an account listed in `public.admin_users` to add, update, deactivate, and delete:

- routes (code, name, description, active/public status)
- stops (code, name, latitude, longitude)
- ordered route-stop links (order, distance from previous stop, boarding minutes, traffic multiplier, extra delay)
- departure schedules (service name, time, operating weekdays, active status, notes)
- buses (bus code, assigned route, active status)

For map markers, enter **verified** coordinates for stops. This starter does not guess coordinates from stop names.

### Enable GPS from a driver phone

1. Create a normal Auth account for the driver phone in Supabase Authentication.
2. Copy that user's UUID from Authentication → Users.
3. In SQL Editor, assign the user to a bus. Replace the UUID and bus code:

```sql
insert into public.bus_assignments (bus_id, user_id)
select b.id, 'PASTE-DRIVER-USER-UUID-HERE'::uuid
from public.buses b
where b.bus_code = 'CBT-101'
on conflict (bus_id, user_id) do nothing;
```

4. Open the deployed HTTPS website on the phone, sign in with the driver account, go to **Fleet & GPS**, select the assigned bus, and press **Start GPS sharing**. Allow location permission.
5. The browser sends a GPS update when the device location changes. Stop sharing when tracking is no longer authorized or required.

A device in a location that differs from the bus will publish that device's location, not the bus's true location. Get informed consent and permission before enabling tracking.

## Important limitations before real deployment

- The seeded distances, traffic factor, extra delays, and 09:00 sample schedule are **illustrative**, not verified road distances or an official Coimbatore bus timetable. Edit or replace them with verified data.
- There is no built-in official Coimbatore bus feed. Live tracking works only after a device assigned to a bus starts sharing GPS, or after you implement another authorized GPS provider.
- The ETA method is a transparent rule-based estimate, **not a trained machine-learning model**. It does not yet incorporate road-network routing, turn-by-turn paths, congestion API results, GPS map matching, or audited prediction accuracy.
- GPS accuracy depends on the phone/device, permissions, internet connectivity, and its placement. Updates are not guaranteed continuous.
- Public routes, stops, schedules, and last bus locations are readable from the public website by design. Do not store private passenger information in those tables.
- Before an actual public transport deployment, test RLS with different accounts, validate location-write permissions, replace sample data, add backups/monitoring, and confirm that service usage stays within provider limits.

## Troubleshooting

- **“Database not configured”**: check the two Supabase constants in `index.html`.
- **“relation does not exist”**: run all of `supabase_setup.sql` successfully.
- **Sign-in works but no admin tools show**: run the administrator promotion SQL and make sure the email matches the signed-in user.
- **Route manager save fails**: check the error banner; route codes and stop names must be unique, and every route-stop order must be unique within that route.
- **GPS write denied**: the signed-in user must be an admin or have a matching `bus_assignments` record for that bus.
- **Map has no route line**: edit stops and enter real latitude/longitude values.

## Editing / extending

The app is deliberately kept in a single `index.html` for easier GitHub Pages publishing. As it grows, consider moving to a framework and adding automated database tests, a dedicated driver experience, role-based admin screens, historic location retention, route geometry, and an ETA model validated against actual arrival observations.
