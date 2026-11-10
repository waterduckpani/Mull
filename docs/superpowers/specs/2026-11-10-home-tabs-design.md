# Home: the group screen's bar, app-wide

Date: 2026-11-10. Bharat picked option B from three home directions, then
approved the four tabs as mocked (`Mull/.superpowers/brainstorm/59805-1794287685/content/home-b-tabs.html`):
"Yes looks very good. Make sure you are missing nothing and then build it out."

## Why

The group screen got one home per action and a bar at the bottom, and Bharat
wanted "some of that UX magic" on home. Today's home stacks every pending
card above huge group cards (one and a half groups visible), hides Friends and
Profile behind corner icons, keeps People below the fold, and gives "New
group" and "Add expense" equal weight at the bottom.

## What it is

The home screen becomes four tabs under the same floating bar as a group:
**Home · Groups · + · People · You**. Same look and behaviour as `GroupBar`
(fixed-width tabs, open tab's name under its icon on a soft pill, + dead
centre, long-press on + reserved for voice). Opening a group pushes the group
screen with its own bar over the top; Back returns to the home bar.

- **Home**: the all-in number; the sync-trouble line; friend requests; one
  **Needs you · N** stack (net-offs, claims for you, your claims waiting,
  bills asked of you, due schedules) showing the first card with the rest
  stacked behind, expanding in place when tapped; **Recent**: the last five
  expenses or payments across every group, each opening what it is.
  "And ₹X is owed to you · see who" switches to People.
- **Groups**: title with **+ New group**; compact rows in the existing order
  (you owe, then owed to you, then settled, biggest first); settled groups
  under a **Settled** eyebrow; long-press keeps today's ledger actions.
  One-to-one ledgers are not here (People has them, as today).
- **People**: title with **+ Add a friend**; friend requests; **You owe** rows
  with **Pay**, **Owes you** rows with **Nudge**; people you are square with
  folded into one **Square · N** line that expands; a **Friends** row opening
  today's friends sheet (requests, report, block, blocked list, invite).
  Tapping a person opens today's person sheet.
- **You**: the profile sheet as a page: name, UPI ID, Pay with, How it works,
  Appearance (System / Light / Dark), the account block (signed in as, Sign
  out, Delete account, Privacy · Terms · Help).

The **+** opens today's quick add (pick a group, then the add-expense form).
With no groups yet it starts a group.

## Where everything on today's home and profile goes

| Today | After |
|---|---|
| Wordmark | Top of every tab |
| Friends icon (top right) | People tab: **+ Add a friend** and the **Friends** row |
| Profile initial (top right) | You tab |
| Notices bell + unread dot | Top right of every tab |
| All-in number, "owed to you · see who" | Home; "see who" switches to People |
| Sync-trouble line | Home, under the number |
| Friend requests card | Home (first thing a new user sees) and top of People |
| Net-off, claim, waiting-claim, bill-asked, due cards | Home's **Needs you** stack |
| Group cards (roomy/medium/compact) | Groups tab, compact rows |
| Long-press on a group | Same, on Groups rows |
| PEOPLE section | People tab |
| "N people to square up with" footer and who-owes-who sheet | People tab replaces both |
| New group button | Groups tab **+ New group**; empty Home's chips |
| Add expense button | The **+** |
| Empty home ("Who paid. Who owes. Sorted.", chips, How settling up works) | Home tab when there are no groups; its pinned "Start a group" goes, the + starts one |
| Pull to refresh | Every tab |
| Profile: name, UPI ID, Pay with, How it works, Appearance, account block | You tab |
| Profile: Friends row | People tab's **Friends** row |
| Friends sheet: Blocked list | Stays in the friends sheet *(ruling: the mock put Blocked under You; it already lives in the friends sheet with Unblock, so nothing is rebuilt and nothing is lost)* |

## Rules carried over

- Android Back: from Groups, People or You, go to Home; from Home, leave the
  app as today. iOS has no Back.
- Every tab keeps its own scroll position; the app opens on Home.
- Toasts sit above the bar on these tabs too.
- Monochrome tokens only; works in light and dark.
- Sample numbers unchanged (₹3,850 all-in etc. per `logic_test.dart`).

## Not in this change

Voice, several payers, currencies, search, export (each needs its own design).
