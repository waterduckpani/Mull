# Google Play listing

Everything Play Console asks for, ready to paste. The iOS version is
`../listing.md`. Keep the two saying the same things.

Files in this folder:

- `play-icon-512.png`: App icon (512×512)
- `feature-graphic.png`: Feature graphic (1024×500), from `tool/play_feature.html`
- `screenshots/01–06.png`: Phone screenshots (1440×2560). Play takes only 16:9 or 9:16, so the iOS set can't be reused; these are the iOS layout widened with extra field. All three are rendered by `tool/store_shots.sh`.

## Create app

| Field | Value |
|---|---|
| App name (30) | **Mull: Split Bills & Settle** |
| Default language | English (India) – en-IN |
| App or game | App |
| Free or paid | Free (permanent: a free app can never become paid) |
| Package name | `in.mull.app` (fixed by the first upload; same as the iOS bundle ID) |

## Main store listing

**Short description (80):**

> Split bills with flatmates, trips and friends. Settle up over UPI in a tap.

**Full description (4000):** paste the iOS *Description* from `../listing.md`
as it is. Play allows no emoji walls or keyword lists, and it has none.

| Field | Value |
|---|---|
| Category | Finance |
| Tags | Budgeting, Personal finance (pick the closest offered) |
| Email | mullapp.official@gmail.com |
| Website | https://www.mullapp.in/ |
| Privacy policy | https://www.mullapp.in/privacy.html |

## Countries

Production → Countries/regions → **India only**, same as iOS.

## App content (Policy → App content)

- **Privacy policy:** the URL above.
- **Ads:** No.
- **App access:** "All or some functionality is restricted". Add the review
  login: username `review@mull.oblunestudio.com`, password from
  `.secrets/review-account`. Instructions: paste the App Review notes from
  `../listing.md`, swapping "profile (top right)" wording only if it changed.
- **Content rating (IARC):** category *Utility, Productivity, Communication or
  Other*. Answer No to violence, sex, language, drugs, gambling. **Users can
  interact / exchange content: Yes** (expense names and notes are seen by the
  group), **shares location: No**, **digital purchases: No**. Expect
  *Everyone* / *3+*. Report and block exist (Friends → ··· → Report / Block).
- **Target audience:** 16–17 and 18 and over. Not 18+ alone: Play warns that
  an 18+-only app may be held back from accounts it believes are under 18,
  and the terms already let under-18s use Mull with a parent's or guardian's
  permission. Nothing below 16 (13–15 adds teen rules; under 13 pulls in the
  Families policy). "Could it appeal to children?": No. Ads: No.
  IARC came out 12+ / Teen (users interact), which bars picking under 13 anyway.
- **News app:** No.
- **Government app:** No.
- **Financial features:** Mull doesn't move money. Pick *"My app doesn't
  provide any financial features"* if offered, or else the closest option:
  "Other", described as *"Records shared expenses between people and opens
  the user's own UPI app with a payment pre-filled. Mull never processes,
  holds or transfers money."*
- **Health:** none.
- **Data safety:** below.

## Data safety

Collected: **Yes**. Shared with third parties: **No** (Supabase and Resend are
service providers, which Play doesn't count as sharing). Encrypted in transit:
**Yes**. Users can request deletion: **Yes**: in the app (profile → Delete
account) and by email.

| Data type | Collected | Optional? | Purpose |
|---|---|---|---|
| Personal info → Name | Yes | Required | App functionality, Account management |
| Personal info → Email address | Yes | Required | App functionality, Account management |
| Personal info → User IDs | Yes | Required | App functionality, Account management |
| Financial info → Other financial info (UPI ID) | Yes | Optional | App functionality |
| Photos and videos → Photos (bill photos) | Yes | Optional | App functionality |
| App activity → Other user-generated content (groups, expenses, notes) | Yes | Required | App functionality |
| App info and performance → Crash logs | Yes | Required | Analytics (not linked to the account) |
| Device or other IDs (the push token, through Firebase Cloud Messaging) | Yes | Optional (only if notifications are allowed) | App functionality |

Everything else: not collected. Phone number included: no screen asks for one since
the first TestFlight round (the `phone` column is a leftover). No data is processed ephemerally only; no data
is used for ads or tracking.

## Release

1. `./tool/play.sh` → `build/app/outputs/bundle/release/app-release.aab`
2. Testing → Internal testing → Create release → upload the .aab → add
   yourself as a tester. Opt in from the link it gives you, install from Play.
3. **If the developer account is a personal one made after Nov 2023,** Play
   requires a closed test with at least 12 testers opted in for 14 days in a
   row before it will allow Production. Start that closed test the same day:
   Testing → Closed testing → same .aab → testers by email list or Google
   Group → share the opt-in link.
4. After the 14 days: Dashboard → Apply for production → then Production →
   Create release → same build → India.

Play App Signing: accept the default (Google keeps the app signing key). The
key `tool/android-keystore.sh` made is only the upload key.
