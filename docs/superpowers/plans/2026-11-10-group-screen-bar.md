# Group Screen Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the group screen's stacked destination cards, ⋯ menu and separate Settle up screen with one group screen holding four tabs (Overview, Ledger, Recurring, People) under a floating bottom bar with a centred +, and show "your share" on ledger rows.

**Architecture:** A new `GroupScreen` route owns the open tab and stacks the four tab pages in an `IndexedStack`, with a `GroupBar` positioned over them, so the bar never moves between tabs. Each tab stays a `MullPage` of its own (own scroll, own glow, same back button), given extra bottom padding to clear the bar. `SettleUpScreen` and the settings sheet are folded into the Overview tab and a small edit-group sheet.

**Tech Stack:** Flutter (Cupertino routes, custom `MullIcon` painter), `flutter_test` widget tests, `integration_test` tours on the iOS simulator.

**Spec:** `docs/superpowers/specs/2026-11-10-group-screen-design.md`

## Global Constraints

- Work on a branch, not `main`: `git checkout -b group-screen-bar`.
- Monochrome only. Every colour comes from `context.c` (`lib/ui/tokens.dart`); nothing new is hard-coded. Must render in `MullColors.dark` and `MullColors.light`.
- No borders and no rules except the ledger's existing row hairline.
- The + always means "add an expense" (`showAddExpense(context, group)`). Its long-press stays unassigned (reserved for voice).
- Tabs, in order: Overview · Ledger · + · Recurring · People. Inactive tab = glyph only. Open tab = glyph plus its name under it, on a soft pill. Tab widths are fixed, so neither the + nor any icon moves when switching.
- A group always opens on Overview.
- Copy, verbatim from the spec: "Just you so far", "Who's in?", "Add the people you're splitting with, and Mull starts working out who owes whom.", "Add people", "Nothing spent yet.", "Tap + to add the first expense", "Add someone first", "your share ₹X", "not yours", "Send summary on WhatsApp", "Money never moves through Mull.\nPay over UPI, then say it went through.", "Leave group", "Delete group", "Delete this ledger", "Add a recurring cost", "Add someone not on Mull".
- Sample-data numbers must still hold: all-in ₹3,850, Flat you owe ₹6,250, Goa you get back ₹2,400 (`test/logic_test.dart`).
- Test command: `flutter test <file>`; whole suite `flutter test`; lint `flutter analyze` must stay clean.
- Commit message style matches `git log`: a plain sentence, no `feat:` prefix, ending with the `Co-Authored-By` line the session gives.
- `integration_test` runs: a target that fails to compile silently runs the previous build. Check the console shows the new test names before trusting a pass.

## Review Focus

- **The group disappears while it's open** (deleted or left on another phone, then synced). The screen must not throw. Each tab already renders nothing for a missing group, and the bar must do the same. Test in Task 3.
- **The last row of a long tab sits under the bar.** The final ledger row must scroll fully clear of the bar's top edge. Test in Task 1.
- **Large accessibility text.** At text scale 1.5, the label under the open tab's icon must not overflow its fixed-width tab, and the + must stay centred. Test in Task 2.
- **Who can edit the header.** For a non-admin, or in a one-to-one ledger, tapping the group's name or badge does nothing. Test in Task 7.
- **Light mode.** The bar and every tab render under `MullColors.light` without exceptions. Test in Task 3.

---

### Task 1: Bottom clearance on `MullPage`

**Files:**
- Modify: `lib/ui/page.dart` (`MullPage` constructor and the `SliverPadding` at ~155)
- Test: `test/page_test.dart`

**Interfaces:**
- Produces: `MullPage({..., double bottomInset = 0})`. The value is added to the scroll content's bottom padding, after the existing `ctaBottom + _bottomHeight + 24`.

- [ ] **Step 1: Write the failing test** `'bottomInset keeps the last row clear of a bar laid over the page'`. Pump a `MullPage(bottomInset: 60, children: [20 rows of SizedBox(height: 80, child: Text('row $i'))])` at 390×844 inside a `Stack` whose second child is a `Positioned(left: 0, right: 0, bottom: ShellMetrics.ctaBottom(ctx), height: 60, child: ColoredBox(key: Key('bar')))`. Drag the scrollable to the end, then:
  ```dart
  expect(t.getRect(find.text('row 19')).bottom, lessThanOrEqualTo(t.getRect(find.byKey(const Key('bar'))).top));
  ```
- [ ] **Step 2:** Run `flutter test test/page_test.dart`. Expected: FAIL (`bottomInset` isn't defined).
- [ ] **Step 3:** Add `final double bottomInset;` to `MullPage` and add it to the `SliverPadding` bottom.
- [ ] **Step 4:** Run `flutter test test/page_test.dart`. Expected: PASS, and the existing footer tests still pass.
- [ ] **Step 5: Commit** "MullPage can leave room for a bar laid over it".

### Task 2: Glyphs and `GroupBar`

**Files:**
- Modify: `lib/ui/icons.dart` (add `MullGlyph.overview`, `MullGlyph.ledger` and their paths in `_GlyphPainter`)
- Create: `lib/screens/groups/group_bar.dart`
- Test: `test/group_bar_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum GroupTab { overview, ledger, recurring, people }  // .label: 'Overview' | 'Ledger' | 'Recurring' | 'People'
  class GroupBar extends StatelessWidget {
    const GroupBar({super.key, required GroupTab current, required ValueChanged<GroupTab> onSelect,
                    required VoidCallback onAdd, bool addEnabled = true});
    static const double height = 60;
  }
  ```
  Glyphs: overview = `MullGlyph.overview` (a circle with clock hands, as in the mockup), ledger = `MullGlyph.ledger` (three left-aligned lines, the last shorter), recurring = `MullGlyph.repeat`, people = `MullGlyph.groups`. Draw them in the same 24×24 stroke style as their neighbours in `icons.dart`.

- [ ] **Step 1: Write the failing tests** in `test/group_bar_test.dart`. Pump the bar at 390 wide in `MaterialApp(theme: buildTheme(MullColors.dark))`, aligned to the bottom.
  - `'only the open tab shows its name'`: with `current: GroupTab.ledger`, `find.text('Ledger')` finds one widget, and `'Overview'`, `'Recurring'` and `'People'` find none.
  - `'the + sits dead centre whichever tab is open'`: for each `GroupTab`, `t.getCenter(find.bySemanticsLabel('Add an expense')).dx` is within 0.5 of `195`.
  - `'icons do not move when the tab changes'`: the centres of the four tab hit areas (`find.bySemanticsLabel(RegExp('^Overview'))` and so on) are identical with `current: overview` and with `current: people`.
  - `'tapping a tab selects it'`: tapping the People tab calls `onSelect(GroupTab.people)`.
  - `'a disabled + says why and adds nothing'`: with `addEnabled: false`, tapping + doesn't call `onAdd`, and `find.text('Add someone first')` finds one widget once the toast has pumped.
  - `'large text does not overflow the open tab'`: wrap in `MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(1.5)))`, then `expect(t.takeException(), isNull)` and the + is still within 0.5 of centre.
  - `'tabs announce themselves'`: the Ledger tab's semantics label is `'Ledger, tab 2 of 4'` and it is marked selected when current.
- [ ] **Step 2:** Run `flutter test test/group_bar_test.dart`. Expected: FAIL (`group_bar.dart` doesn't exist yet).
- [ ] **Step 3: Implement `GroupBar`.** It's a `Row` of two `Expanded` halves around the +. Each half `spaceAround`s two tabs of fixed width 58 × 50, so nothing depends on which tab is open.
  - **Bar surface:** height 60, horizontal gutter 16, fully rounded, filled with the `c.sheetTop → c.sheetBottom` gradient plus the `c.shadowFocal` shadow (blur 50, offset 0/23).
  - **Inactive tab:** 21pt glyph in `c.ink3`.
  - **Open tab:** glyph in `c.ink`, name under it at Ranade 10, on a radius-18 pill filled with `c.quiet`. Animate the pill and label with `AnimatedContainer`/`AnimatedOpacity` over 220 ms, and play a selection haptic on change.
  - **The + (enabled):** a 48pt circle in `c.pill` with `MullGlyph.plus` in `c.pillInk`, wrapped in `Pressable` with `semanticLabel: 'Add an expense'`.
  - **The + (disabled):** `c.quiet` fill with an `ink3` glyph. Tapping it calls `Toast.show(context, 'Add someone first')`.
  - Wrap each label in `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2)` so the large-text test holds.
- [ ] **Step 4:** Run `flutter test test/group_bar_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** "A floating bar for the group screen, with the + held dead centre".

### Task 3: `GroupScreen` shell

**Files:**
- Create: `lib/screens/groups/group_screen.dart`
- Test: `test/group_screen_test.dart`

**Interfaces:**
- Consumes: `GroupBar`, `GroupTab`, `GroupBar.height`, `MullPage.bottomInset`.
- Produces:
  ```dart
  class GroupScreen extends StatefulWidget {
    const GroupScreen({super.key, required String groupId, GroupTab initialTab = GroupTab.overview});
  }
  ```
  `GroupScreen` passes each tab `onSelectTab: ValueChanged<GroupTab>` (used by Overview in Task 7). For now the four children are the existing `GroupDetailScreen`, `LedgerScreen`, `RecurringScreen` and `GroupMembersScreen`, each given `bottomInset: GroupBar.height`. Add that optional parameter to each of the four and pass it through to their `MullPage`.

- [ ] **Step 1: Write the failing tests** in `test/group_screen_test.dart`, using a sample-data store (`MullStore.memory()..loadSample()`). Push `GroupScreen(groupId: flat.id)` on top of a `Placeholder(key: Key('home'))` home.
  - `'opens on Overview'`: `find.text('₹6,250').hitTestable()` finds one widget.
  - `'tapping Ledger shows the ledger and keeps the bar'`: tap `find.bySemanticsLabel(RegExp('^Ledger'))`, then `find.text('Expenses').hitTestable()` finds one widget and `find.byType(GroupBar)` still finds exactly one.
  - `'back from another tab goes to Overview, then out'`: open Ledger, `await t.binding.handlePopRoute()`, and Overview's `'₹6,250'` is hit-testable again. Call `handlePopRoute()` again, and `find.byKey(Key('home'))` is hit-testable.
  - `'a group deleted while open leaves nothing to crash on'`: `store.deleteGroup(flat)`, pump, then `expect(t.takeException(), isNull)`.
  - `'light mode renders'`: pump with `buildTheme(MullColors.light)`, switch through all four tabs, then `expect(t.takeException(), isNull)`.
  - `'the + is greyed while you are alone'`: for `store.addGroup('Goa trip', [])`, tapping + shows `'Add someone first'`.
- [ ] **Step 2:** Run `flutter test test/group_screen_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement `GroupScreen`.**
  - Hold `GroupTab _tab` in state.
  - Lay out a `Stack` of an `IndexedStack(index: _tab.index)` and the bar, `Positioned(left: 0, right: 0, bottom: ShellMetrics.ctaBottom(context))`. Behind the bar, draw a non-interactive fade strip from transparent to `c.screen` (44pt), so rows passing under it don't collide with it.
  - Bar settings: `addEnabled: group.seated.length >= 2`, and `onAdd: () => showAddExpense(context, group)`.
  - Back handling: `PopScope(canPop: _tab == GroupTab.overview, onPopInvokedWithResult: (didPop, _) { if (!didPop) setState(() => _tab = GroupTab.overview); })`.
  - Missing group (`store.groupById(groupId) == null`): render `SizedBox.shrink()`.
- [ ] **Step 4:** Run `flutter test test/group_screen_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** "GroupScreen: four tabs under one bar".

### Task 4: Ledger tab, with your share on every row

**Files:**
- Modify: `lib/screens/groups/ledger_screen.dart`
- Test: `test/ledger_tab_test.dart`

**Interfaces:**
- Produces: `ExpenseRow` and `SettlementRow`, made public from `_ExpenseRow` and `_SettlementRow` with the same constructors, for Overview's Latest in Task 7. `_Row` gains `final InlineSpan? under;`, drawn under the amount.

- [ ] **Step 1: Write the failing tests.** Set up `completeOnboarding(name: 'Bharat')` and `g = addGroup('Flat', ['Sahil'])`, then add three expenses:
  - Dinner: `amount: 10000`, `payerId: me`, `shares: {me: 9000, sahil: 1000}`, `method: SplitMethod.percent`.
  - Groceries: `amount: 6700`, `payerId: sahil`, `shares: {me: 2345, sahil: 4355}`, `method: SplitMethod.percent`.
  - Sahil's cab: `amount: 600`, `payerId: me`, `shares: {sahil: 600}`.

  Pump `LedgerScreen(groupId: g.id)`, then:
  - `'a row shows the total and your share'`: `find.text('₹10,000')` and `find.textContaining('your share ₹9,000', findRichText: true)` each find one widget. Groceries shows `'₹6,700'` and `'your share ₹2,345'`.
  - `'a row with no share of yours says so, even if you paid'`: Sahil's cab shows `'not yours'`.
  - `'the ledger has no add button of its own'`: `find.text('Add an expense')` finds nothing.
  - `'the group name sits above the title'`: `find.text('Flat')` finds one widget above `find.text('Ledger')` (compare `top`).
- [ ] **Step 2:** Run `flutter test test/ledger_tab_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement the ledger changes.**
  - **Under the amount:** `ExpenseRow` passes `under`. If `expense.shares[group.you?.id] ?? 0` is above 0, it's `'your share '` in `ink3` followed by `inr(share)` in `ink2`. If it's 0, it's `'not yours'` in `ink3`, at `MullType.caption(size: 11.5)`.
  - **Header:** replace `PageTitle('Ledger')` with a caption line `group.title` (`MullType.caption(c.ink3, size: 12.5)`) above `PageTitle('Ledger', padding: top 2)`.
  - **Bottom:** remove `bottom:`. Move the `footnote:` text inline as a `Footnote` at the end of the children.
  - **Left caption:** keep it as it is. Whether to spell out percentages there is the builder's call (spec), but the caption must stay on one line at 390pt.
- [ ] **Step 4:** Run `flutter test test/ledger_tab_test.dart`, then `flutter test`. Expected: PASS.
- [ ] **Step 5: Commit** "Ledger rows say your share of the total".

### Task 5: Recurring tab

**Files:**
- Modify: `lib/screens/groups/recurring_screen.dart:44-55` and the empty-state card
- Test: `test/group_screen_test.dart` (add to it)

- [ ] **Step 1: Write the failing tests.**
  - `'Recurring keeps its add button inline'`: open the Recurring tab on sample Flat. `find.text('Add a recurring cost')` scrolled into view is hit-testable, and its rect's bottom sits above the `GroupBar`'s top.
  - `'and the empty state offers it once'`: on a fresh two-person group, `find.text('Add a recurring cost')` finds exactly one widget.
- [ ] **Step 2:** Run the tests. Expected: FAIL (the button is pinned and sits under the bar).
- [ ] **Step 3: Implement the Recurring changes.**
  - Remove `bottom:`.
  - When there are schedules, add `SecondaryButton('Add a recurring cost', glyph: MullGlyph.plus, onTap: () => showRecurringEditor(context, group))` after the last list, at the card gutter with 30pt above it.
  - When there are none, put the same button inside the "Nothing repeating yet" card as its action.
  - Add the group-name caption above the `PageTitle`, the same way as in Task 4.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5: Commit** "Recurring: add a cost from inside the tab".

### Task 6: People tab, with Leave and Delete at the foot

**Files:**
- Modify: `lib/screens/groups/members_screen.dart`
- Test: `test/group_screen_test.dart` (add to it)

**Interfaces:**
- Produces: `Future<void> addPeopleFromFriends(BuildContext context, Group group)`, the existing `addFromFriends` closure lifted to the top level unchanged. Overview uses it in Task 7.

- [ ] **Step 1: Write the failing tests** on the People tab.
  - `'an admin can add, leave and delete from People'`: sample Goa (you're the admin) shows `'Add people'`, `'Add someone not on Mull'`, `'Leave group'` and `'Delete group'`.
  - `'a member sees Leave but not Delete'`: set `g.you!.role = MemberRole.member` (as `sync_merge_test.dart` does), and it shows `'Leave group'` and not `'Delete group'`.
  - `'deleting from People closes the group'`: tap `'Delete group'`, confirm, and the home placeholder is hit-testable.
  - `'a one-to-one ledger offers Delete this ledger'`: a `GroupKind.direct` group shows `'Delete this ledger'` and no `'Add people'`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement the People changes.**
  - Remove `bottom:`. Put the admin's `'Add people'` (`SecondaryButton` with `MullGlyph.plus`, calling `addPeopleFromFriends`) under the member list, followed by the existing "Add someone not on Mull" row.
  - At the foot, keep the existing role explainer, then add quiet `SecondaryButton`s:
    - `'Leave group'` for non-direct groups.
    - For admins, `'Delete group'`, or `'Delete this ledger'` when `isDirect`, using `confirmDeleteGroup`.
  - After a leave or delete is confirmed, `Navigator.of(context).pop()` **once**, because the tab lives inside `GroupScreen`'s route.
  - Add the group-name caption above the title, the same way as in Task 4.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5: Commit** "People: add, leave and delete live in one tab".

### Task 7: Overview tab, with Settle up folded in

**Files:**
- Move: `lib/screens/groups/group_detail_screen.dart` → `lib/screens/groups/overview_tab.dart` (`git mv`), renaming the class `GroupDetailScreen` → `OverviewTab`
- Create: `lib/screens/groups/settle_up_section.dart` (`_TransferCard` moved from `settle_up_screen.dart`, unchanged)
- Modify: `lib/screens/groups/group_sheets.dart` (replace `showGroupSettings`/`_GroupSettingsSheet` with `showEditGroup`)
- Test: `test/overview_tab_test.dart`

**Interfaces:**
- Consumes: `addPeopleFromFriends` (Task 6), `ExpenseRow`/`SettlementRow` (Task 4), `GroupTab` (Task 2).
- Produces:
  ```dart
  class OverviewTab extends StatelessWidget {
    const OverviewTab({super.key, required String groupId, required ValueChanged<GroupTab> onSelectTab, double bottomInset = 0});
  }
  class SettleUpSection extends StatelessWidget { const SettleUpSection({super.key, required Group group}); }
  Future<void> showEditGroup(BuildContext context, Group group);   // name field + IconWell, from the old settings sheet
  ```

- [ ] **Step 1: Write the failing tests** in `test/overview_tab_test.dart`, pumping `OverviewTab` with a no-op `onSelectTab` (or recording it).
  - `'alone: one card and nothing else'`: in `addGroup('Goa trip', [])`, `'Just you so far'` and `'Add people'` find one widget each. `'Nothing spent yet.'`, `'Settle up'` and `'You owe'` find none.
  - `'people but nothing spent: points at the +'`: `addGroup('Goa trip', ['Ananya'])` shows `'2 people'`, `'Nothing spent yet.'` and `'Tap + to add the first expense'`. `'Settle up'` finds nothing.
  - `'in use: hero, then settle up with its summary button'`: sample Flat shows `'You owe'` and `'₹6,250'`, then the Settle up eyebrow, `'Send summary on WhatsApp'` and the footnote `'Money never moves through Mull.'` (`textContaining`).
  - `'a claim waiting on you is a card at the top'`: sample Goa shows `textContaining('says they sent you')` above the Settle up eyebrow.
  - `'square while others are not: one quiet line, no section'`: build a three-person group where only the other two owe each other. `textContaining('Other people here still owe each other')` finds one widget, and `'Send summary on WhatsApp'` finds none.
  - `'Latest shows three and See all opens the ledger'`: sample Flat shows at most three `ExpenseRow`/`SettlementRow` widgets, and tapping `'See all'` calls `onSelectTab(GroupTab.ledger)`.
  - `'only an admin can open the edit sheet'`: tapping the title opens the sheet (find the `'Name'` hint) for an admin. It doesn't for a member, or for a `GroupKind.direct` ledger.
  - `'no ⋯ and no destination cards'`: `find.bySemanticsLabel('Group settings')`, `find.text('Change icon')` and `find.text('Recurring')` all find nothing.
- [ ] **Step 2:** Run `flutter test test/overview_tab_test.dart`. Expected: FAIL.
- [ ] **Step 3: Build `OverviewTab` from the old body.**
  - **Header:** keep the badge and title row.
    - Subtitle: plain text, `'Just you two'` for direct ledgers, `'Just you so far'` when `seated.length < 2`, otherwise `'N people'`.
    - Tapping the badge or title calls `showEditGroup` when `group.youAreAdmin && !group.isDirect`, and does nothing otherwise.
    - Remove the "Change icon" caption, the ⋯ `trailing`, the `bottom:` pill and the `_Destination` cards.
  - **Alone state:** the existing focal card, with eyebrow `"Who's in?"`, the spec copy, and an `InlineButton('Add people')` calling `addPeopleFromFriends`.
  - **No-expenses state:** `PageStatement('Nothing spent yet.', body: …)`, plus the hint. To place the hint, wrap the `MullPage` in a `Stack` and pin the hint's `Column` (caption plus a down-arrow glyph, both `ink3`) at `bottom: ShellMetrics.ctaBottom(context) + GroupBar.height + 14`.
  - **In-use state:**
    - `HeroAmount` as today, then the claim and due cards as today.
    - `SettleUpSection(group: group)`.
    - The Latest eyebrow with `store.activity(group).take(3)` as `ExpenseRow`/`SettlementRow`, and a `'See all'` text button calling `onSelectTab(GroupTab.ledger)`.
    - The existing "₹X spent between N people" footnote.
  - **`SettleUpSection`:**
    - When `group.yourTransfers` or `group.placeholderTransfers` is non-empty, show an eyebrow `'Settle up'`, then the transfer cards. The first one is `Lift.focal` unless a claim or due card is already focal. Then the placeholder caption and cards, `SecondaryButton('Send summary on WhatsApp', onTap: () => shareGroupSummary(context, group))`, and the money footnote.
    - When both lists are empty and `!group.isSettled`, show only the existing `othersOpen` sentence as a caption.
    - Otherwise show nothing.
  - **`showEditGroup`:** the old settings sheet's `IconWell` + `BigField` row only, with header `'Group'` and the same `_apply` on change.
- [ ] **Step 4:** Point `GroupScreen`'s first child at `OverviewTab(onSelectTab: …)`. Run `flutter test test/overview_tab_test.dart test/group_screen_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** "Overview: where you stand and what to do about it, Settle up included".

### Task 8: Entry points, and the old screens out

**Files:**
- Modify: `lib/screens/home_screen.dart` (~50, ~291, ~1165), `lib/screens/notices_sheet.dart:49`, `lib/ui/page.dart:189`
- Delete: `lib/screens/groups/settle_up_screen.dart`
- Test: `test/home_test.dart` (add to it)

- [ ] **Step 1: Write the failing test** `'Settle up from a group's long-press opens the group on Overview'`. On sample data, long-press the Flat row on home, tap `'Settle up'`, and `find.byType(GroupScreen)` plus `find.text('Send summary on WhatsApp')` each find one widget.
- [ ] **Step 2:** Run `flutter test test/home_test.dart`. Expected: FAIL.
- [ ] **Step 3: Repoint the entry points.** Replace every `GroupDetailScreen(groupId: …)` and `SettleUpScreen(groupId: …)` push with `GroupScreen(groupId: …)`. Delete `settle_up_screen.dart` and any import left dangling. Confirm with `grep -rn "SettleUpScreen\|GroupDetailScreen\|showGroupSettings" lib test`: expected no output.
- [ ] **Step 4:** Run `flutter test` and `flutter analyze`. Expected: all pass, "No issues found!".
- [ ] **Step 5: Commit** "Every way into a group lands on the new group screen".

### Task 9: Tours and a look on the simulator

**Files:**
- Modify: `integration_test/tour_test.dart` (~98–150), `integration_test/reel_tour_test.dart` (~88–92), `integration_test/changes_test.dart` (~10, ~94)

- [ ] **Step 1: Repoint the tour steps.** Where the tours used `tapText(t, 'People' | 'Ledger' | 'Recurring')`, tap the tab by semantics label instead: add a `tapTab(t, String name)` helper using `find.bySemanticsLabel(RegExp('^$name'))`. The old "Settle up" step becomes a scroll on Overview to the Settle up eyebrow. `changes_test`'s greyed-Settle-up check becomes "no Settle up section on a group with nothing to settle".
- [ ] **Step 2: Run the screenshot tour.** Use `flutter test integration_test/tour_test.dart -d "iPhone 17"` with `--dart-define=MULL_SAMPLE=true`. Confirm the console lists the new test names, not a stale build. Expected: PASS, with fresh shots in `screenshots/`.
- [ ] **Step 3: Check the shots by eye against the approved mockups.**
  - The bar floats with the + centred, only the open tab is named, and there is no ⋯.
  - Ledger rows read "your share".
  - An empty group shows one card.
  - Look at the dark and light runs.
- [ ] **Step 4: Commit** "Tours walk the group screen's tabs".
