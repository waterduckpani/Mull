# Group screen: a bottom bar, one home for everything

Date: 2026-11-10. Agreed with Bharat over mockups in the brainstorm companion
(`Mull/.superpowers/brainstorm/59805-1794287685/content/`; the approved ones are
`bar-labels-v2.html`, section 1 option B and section 2 option A, and
`empty-and-people.html`).

## Why

People open a group for four things: add an expense, change who is in it, look
at the ledger, set up a recurring cost. Today each of those has two or three
doors and the screen shows doors that lead nowhere:

- An empty group says "Add the first expense" at the top, has an "Add an
  expense" pill at the bottom and an "Add people" card in the middle.
- Ledger, Recurring and People are cards below the fold, so you scroll to reach
  them.
- "Settle up" is shown even when it says "Nothing to settle yet".
- The ⋯ menu offers Add a recurring cost, People, rename and icon. Half of that
  is on the screen already. People alone has three doors (the "4 people ›" link,
  the People card, the ⋯ menu).

Separately, ledger rows mislead. A ₹10,000 dinner you paid, split 90/10, shows
as "₹10,000 · You paid", which reads as if the whole ₹10,000 was yours.

## Goals

- Every action has exactly one place to live.
- A floating bottom bar that never leaves the group: Overview, Ledger, +,
  Recurring, People.
- Ledger rows show the total and your share of it.
- A new group asks for one thing at a time.
- The + is where hold-to-speak (voice entry, a separate design) will live.

## Non-goals

- Voice entry. The + must leave long-press free for it, nothing more.
- Several payers on one expense. Mull records one payer; that stays.
- The home screen, the add-expense sheet, the recurring editor, the expense
  detail sheet, the data model and sync. None of them change.

## Anti-goals (it fails even if it works)

- Colour carrying meaning. The palette stays monochrome (`lib/ui/tokens.dart`).
- A + whose meaning changes from tab to tab.
- A card or section that exists only to say there is nothing in it.
- Moving Pay away from the place you see that you owe (see the
  surface-actions rule: actions go where the decision happens).

## Decided by Bharat

**The bar.** Layout A from the first round (the + in the middle), restyled to
float and match Mull's surfaces. Icons only; the open tab shows its name
*under* its icon, on a soft pill (option B of the label round). Every tab keeps
a fixed width, so neither the + nor the other icons move when you switch.

**Hold-to-speak** goes on the + later. Not in this build.

**Ledger rows** show the total as the big number with "your share ₹X" under it
(option A, "because it's a ledger"), not the Splitwise "you owe / you get back".

**Empty states, the People tab and the calls below** were shown together and
approved ("good"):

- Group name and icon are edited by tapping them at the top of Overview, which
  opens one small sheet holding both. That replaces the ⋯ menu, the "Change
  icon" caption and the "4 people ›" link.
- The + always means "add an expense", on every tab. Recurring has its own "Add
  a recurring cost" button; People has its own "Add people".
- When someone owes you, the Settle Up section lists them with Nudge instead of
  Pay, and "Send summary on WhatsApp" lives at the end of that section.
- A payment someone says they sent you ("Sahil says they sent you ₹800 ·
  Check") stays a card at the top of Overview.
- Leave and Delete move to the bottom of People.
- While you are alone in a group the + is greyed, and tapping it says "Add
  someone first".

## The bar

- Floats over the page: 16pt gutter each side, 60pt tall, fully rounded. Fill
  is the sheet gradient (`sheetTop` → `sheetBottom`) with the focal shadow. No
  border, no rule above it.
- Order: Overview · Ledger · **+** · Recurring · People. Two tabs each side of
  the +, each half the same width, so the + is always dead centre.
- Inactive tab: 21pt glyph in `ink3`, no label. Open tab: glyph in `ink`, its
  name under it at ~10pt, on a soft rounded pill (the `quiet`/low-surface
  fill). Switching animates the pill and label; nothing changes width.
- The +: 48pt circle in `pill` with the plus glyph in `pillInk`. Tap opens the
  existing add-expense sheet (`showAddExpense`). Long-press is reserved.
  Disabled look while `group.seated.length < 2`: quiet fill, `ink3` glyph.
- Works in light mode through the same tokens.
- Accessibility: each tab announces as a tab with its name and position; the +
  announces "Add an expense"; every target at least 44pt.

One-to-one ledgers (`GroupKind.direct`) get the same bar and tabs. Their
subtitle stays "Just you two", they never hit the "alone" state, and their
People tab is "The two of you".

## Navigation behaviour

- A group always opens on Overview.
- The bar stays still while tabs switch (no page push between tabs). Each tab
  keeps its scroll position while you are in the group.
- Every tab has the same back button top-left, which leaves the group.
- Android Back: from any other tab, go to Overview; from Overview, leave the
  group. *(my call)*
- Sheets open over the bar as they do over everything else.
- Page content gets enough bottom padding to scroll clear of the bar.

## Overview

Replaces the body of `GroupDetailScreen` **and** all of `SettleUpScreen`, which
is deleted.

Top: back button; group badge beside the title; subtitle "N people", or "Just
you so far" when alone (plain text, not a link). For an admin, tapping the
badge or the title opens the edit sheet (name + icon, reusing the existing name
field and `pickGroupIcon`). For anyone else the header does nothing *(my call;
today a non-admin is told "Only an admin can rename this group")*.

Then one of three states:

1. **Alone** (`seated.length < 2`). One focal card: eyebrow "Who's in?", body
   "Add the people you're splitting with, and Mull starts working out who owes
   whom.", button "Add people", which opens the same add-people flow the People
   tab uses, without switching tabs. Nothing else on the page.
2. **People, no expenses.** Statement "Nothing spent yet.", a short line under
   it, and a hint just above the bar, "Tap + to add the first expense", pointing
   at the +. No hero ₹0, no Settle Up, no Latest.
3. **In use.** In this order:
   - Hero amount: "You owe" / "You get back" / "You're square", plus today's
     "And you get back ₹X from someone else" line when both directions exist.
   - Claim cards (someone says they paid you), then due-schedule cards, exactly
     as today.
   - **Settle up** section, only when `yourTransfers` or
     `placeholderTransfers` is non-empty. One row per transfer: who, amount, and
     the action today's settle-up rows offer (Pay over UPI when you pay; Nudge
     when they owe you; Check when a claim waits on you; the not-on-Mull and
     no-UPI cases keep their current captions). The placeholder ("neither is on
     Mull, you keep the record") rows come after. The section ends with "Send
     summary on WhatsApp" and the footnote "Money never moves through Mull. Pay
     over UPI, then say it went through." When you are square but others in the
     group are not, one quiet line says so instead of the section (today's
     `othersOpen` copy).
   - **Latest**: the three most recent things from `store.activity(group)`,
     expenses shown like ledger rows (total, your share), settlements as one
     line. A "See all" that switches to the Ledger tab *(my call)*.
   - Footnote: "₹X spent between N people".

The home screen's long-press "Settle up" action now opens the group on
Overview, where the Settle up section is.

## Ledger tab

`LedgerScreen`'s content, with the group name as a small line above the
"Ledger" title, and without its own "Add an expense" pill (the + replaces it).
Expenses/Settlements switch, month eyebrows and hairline rows are unchanged.

Expense row, right-hand side:

- Big number: `expense.amount`, the total (as today).
- Under it, caption: "your share ₹X" from `expense.shares[you]`, the number in
  `ink2`.
- If your share is 0: "not yours". Applies even when you were the payer; the
  left caption already says "You paid" *(my call)*.

Left caption keeps "{payer} paid · {split method} · {date}". The mockup showed
"90% you, 10% Sahil" for a two-person percentage split; whether to spell out
percentages, or keep "by percentage", is the builder's call as long as it fits
on one line on a 6.1" phone.

Settled rows stay dimmed. Settlement rows are unchanged.

## Recurring tab

`RecurringScreen`'s content with the group name above its title. Its pinned
"Add a recurring cost" button can't sit at the bottom any more (the bar is
there), so it moves inline: under the list, or as the empty state's button when
there are no schedules *(my call)*.

## People tab

`GroupMembersScreen`'s content with the group name above its title. Its pinned
"Add people" (admins, not one-to-one ledgers) moves inline under the list, with
"Add someone not on Mull" beneath it. At the bottom, quiet buttons: "Leave
group", and for admins "Delete group" (moved from the settings sheet, same
confirm). One-to-one ledgers keep "The two of you" and "Delete this ledger".

## Removed

- `SettleUpScreen` (folded into Overview).
- The ⋯ button and `showGroupSettings` sheet (rename/icon go to the edit sheet;
  people, recurring, delete and leave go to their tabs).
- The destination cards, the "Change icon" caption and the "4 people ›" link.
- The pinned "Add an expense" pill on the group and ledger screens.

## Entry points to update

All of these push `GroupDetailScreen` today and should land on the new screen
on Overview: `home_screen.dart` (two places, plus the long-press Settle up at
~1165, which pushed `SettleUpScreen`), `notices_sheet.dart`, the friends sheet
in `ui/page.dart`. The integration tours (`tour_test.dart`, `reel_tour_test.dart`)
walk the old screens and need re-pointing.

## Left to the builder

- Widget structure (one group screen holding the four tabs, or another shape),
  as long as the bar never moves between tabs.
- Two new glyphs drawn in the `MullIcon` hand-drawn style: Overview and Ledger.
  `repeat` and `plus` exist; People may reuse `groups`.
- Animation timing and haptics for tab switches.
- Copy polish that keeps the meaning.
- Which tests to add; the sample-data numbers (`Flat ₹6,250`, `Goa +₹2,400`)
  must still hold.
