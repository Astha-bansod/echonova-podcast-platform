# ECHONOVA (JCOET community podcast platform)
Static frontend (`index.html`) + Supabase (Auth, Postgres, Storage, RLS). Independent community project; not officially JCOET.

## Setup
1. Create a Supabase project.
2. SQL Editor: run `supabase/schema.sql`.
3. Authentication > Providers > Phone: enable it and connect an SMS provider (Twilio, MessageBird, Vonage or TextLocal). Needs a provider account; India sends need DLT registration. Without this, OTP will NOT send (no simulation).
4. Authentication > Rate limits: keep the SMS limit low to prevent abuse. Add CAPTCHA (Auth > Attack protection).
5. Copy `config.example.js` to `config.js`; paste Project URL and anon key (Settings > API).
6. Sign up once in the app, then run the commented `admin_roles` insert at the bottom of schema.sql with your number.
7. Auth > URL Configuration: add your deployed URL as Site URL.
8. Local test: `python3 -m http.server 8000`, open http://localhost:8000.
9. Deploy: Netlify, Vercel or GitHub Pages (commit config.js on the host, since the anon key is public by design; RLS is the protection).

## Design notes / limits
- One private bucket `media` (50 MB limit, MIME allow-list enforced by Storage server-side). Files are served by short-lived signed URLs; RLS on storage.objects mirrors post visibility.
- File metadata lives in `media_posts` (merged instead of a separate `media_files` table).
- Uploads are standard, not resumable (TUS) yet; files over ~6 MB benefit from adding resumable uploads. Per-user upload rate limiting is not implemented; add an Edge Function or pg trigger.
- Editing an existing post's text/visibility has no UI yet (RLS allows it); delete and draft/publish work.
- Not implemented: avatar upload UI, suspending via UI beyond reports, email-based verification.
- Privacy Policy text is a placeholder: replace before launch.

## Testing checklist (NOT yet run; I had no Supabase project or SMS provider)
[ ] OTP signup  [ ] reopen app stays logged in  [ ] login existing number (no duplicate profile)  [ ] logout/login
[ ] upload audio, publish, appears on home  [ ] play audio  [ ] upload video + photo  [ ] share / copy link  [ ] open link logged out (public) and logged out (community => denied)
[ ] refresh / second device  [ ] other user cannot edit/delete private or others' posts  [ ] non-admin cannot see Admin or reports
