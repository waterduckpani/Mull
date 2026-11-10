/// Who paid, and who it was for.
///
/// Lifted out of the expense sheet because a standing expense asks exactly the
/// same question — rent is split the same way whether you are recording this
/// month's or describing every month's. Two copies of split maths is two places
/// for the rounding to disagree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/money.dart';
import '../../core/split.dart';
import '../../data/models.dart';
import '../../data/store.dart';
import '../../ui/icons.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';

/// The editable state behind [SplitFields].
///
/// There is one way to split now, not four. Everyone ticked shares the bill
/// equally, and typing somebody's share fixes theirs while the others split
/// whatever is left. Equally, Exact, Shares and % made people pick a kind of
/// maths before they could say who owed what, and the commonest mistake —
/// "I paid it, so 100% me" — saved an expense that moved no money at all.
///
/// A [ChangeNotifier] rather than widget state, because the sheet around it
/// needs to know whether the split currently resolves — that is what enables
/// the save button — and passing that back up through callbacks meant every
/// keystroke rebuilding the sheet from the outside in.
class SplitModel extends ChangeNotifier {
  SplitModel({
    required this.group,
    String? payerId,
    SplitMethod method = SplitMethod.equal,
    Map<String, int>? shares,
    int amount = 0,
  }) : payerId = payerId ?? group.you?.id ?? group.seated.first.id,
       people = _peopleFor(group, payerId, shares),
       _amount = amount,
       _original = shares == null ? null : Map.of(shares),
       _originalAmount = amount,
       _originalMethod = method,
       included = shares == null
           ? group.seated.map((m) => m.id).toSet()
           : {for (final e in shares.entries) if (e.value > 0) e.key} {
    for (final m in people) {
      // An uneven split reopens with everybody's amount typed in: those are
      // the numbers that were agreed, and the fields say so.
      final share = method == SplitMethod.equal ? null : shares?[m.id];
      fields[m.id] = TextEditingController(text: share == null || share <= 0 ? '' : '$share')
        ..addListener(_edited);
    }
  }

  /// The split as it was saved, for an expense being edited.
  ///
  /// Until somebody actually changes the split, it is the saved amounts that
  /// go back, not a re-derivation: editing the description of a 2:1 dinner
  /// used to reopen it as 1:1, and saving moved the money.
  final Map<String, int>? _original;
  final int _originalAmount;
  final SplitMethod _originalMethod;
  bool _touched = false;

  /// Set while the model writes into its own fields, which is not an edit.
  bool _writing = false;

  void _edited() {
    if (_writing) return;
    _touched = true;
    notifyListeners();
  }

  void _write(Map<String, String> texts) {
    _writing = true;
    try {
      texts.forEach((id, text) => fields[id]?.text = text);
    } finally {
      _writing = false;
    }
  }

  void _clearTyped() => _write({for (final id in fields.keys) id: ''});

  /// Splits saved by shares or by percentage, before there was one way to
  /// split. A standing electricity bill split 2:1 still comes round as 2:1
  /// of whatever this month's bill is, until somebody edits it.
  bool get _scales => _originalMethod == SplitMethod.shares || _originalMethod == SplitMethod.percent;

  final Group group;
  String payerId;

  /// Who can pay or be in the split: everyone still in the group, and anyone
  /// since taken out of it who is already in the expense being edited, so an
  /// edit does not quietly drop their share.
  final List<Member> people;

  static List<Member> _peopleFor(Group group, String? payerId, Map<String, int>? shares) => [
    for (final m in group.members)
      if (!m.removed || m.id == payerId || (shares?.containsKey(m.id) ?? false)) m,
  ];

  /// Everyone who could be ticked on a new split.
  Set<String> get _everyone => {for (final m in people) if (!m.removed) m.id};

  /// Who the bill is divided between — the whole group unless someone sat out.
  Set<String> included;

  /// A typed share per person, in rupees. Empty means "an equal part of what
  /// is left".
  final fields = <String, TextEditingController>{};

  int _amount;
  int get amount => _amount;
  set amount(int value) {
    if (_amount == value) return;
    _amount = value;
    final original = _original;
    if (original != null && !_touched && _scales && value > 0) {
      _write({for (final e in splitByWeight(value, original).entries) e.key: '${e.value}'});
    }
    notifyListeners();
  }

  /// Who paid. "They owe all of it" follows the payer: picking that and then
  /// fixing who paid should not put the payer back in.
  void setPayer(String id) {
    if (payerId == id) return;
    final owedInFull = isOthersOweAll;
    payerId = id;
    if (owedInFull) {
      othersOweAll();
    } else {
      notifyListeners();
    }
  }

  /// Ticking somebody in or out starts the split again from equal. Typed
  /// shares were made for the old set of people; keeping them would leave a
  /// rupee gap nobody asked for.
  void toggle(String id) {
    if (!included.remove(id)) included.add(id);
    _reset();
  }

  /// Everyone, equally.
  void evenly() {
    included = {..._everyone};
    _reset();
  }

  /// Whoever paid did it for everyone else: "Neel owes all of it".
  void othersOweAll() {
    included = {..._everyone}..remove(payerId);
    _reset();
  }

  void _reset() {
    _clearTyped();
    _touched = true;
    notifyListeners();
  }

  /// The share typed for [id], or null when there is none.
  int? _typed(String id) {
    final digits = fields[id]!.text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  bool isTyped(String id) => included.contains(id) && _typed(id) != null;

  bool get _anyTyped => included.any(isTyped);

  bool get isEven => !_anyTyped && setEquals(included, _everyone);

  bool get isOthersOweAll =>
      !_anyTyped && included.isNotEmpty && setEquals(included, {..._everyone}..remove(payerId));

  /// Typed shares as they stand and the rest split evenly between everyone
  /// ticked with no number, with what that leaves unassigned: positive is
  /// still to share out, negative is over the bill.
  (Map<String, int>, int) _resolve() {
    final ids = [for (final m in people) if (included.contains(m.id)) m.id];
    final typed = {for (final id in ids) id: ?_typed(id)};
    final open = [for (final id in ids) if (!typed.containsKey(id)) id];
    final left = _amount - typed.values.fold<int>(0, (s, v) => s + v);
    if (ids.isEmpty || left < 0 || (open.isEmpty && left != 0)) return (const {}, left);
    final even = splitEqually(left, open);
    final out = {for (final id in ids) id: typed[id] ?? even[id] ?? 0}..removeWhere((_, v) => v <= 0);
    return (out, 0);
  }

  /// The split as it currently stands, or an empty map if it does not resolve.
  Map<String, int> get shares {
    if (_amount <= 0) return const {};
    final original = _original;
    if (original != null && !_touched) {
      if (_amount == _originalAmount) return Map.of(original);
      if (_scales) return splitByWeight(_amount, original);
    }
    return _resolve().$1;
  }

  /// What gets saved alongside the shares, for the line in the ledger.
  SplitMethod get method {
    if (_original != null && !_touched) return _originalMethod;
    return _anyTyped ? SplitMethod.exact : SplitMethod.equal;
  }

  bool get isValid => shares.isNotEmpty;

  /// Why the split does not come out, or null when it does.
  String? get problem {
    if (_amount <= 0) return 'Put the amount in first.';
    if (shares.isNotEmpty) return null;
    if (included.isEmpty) return 'Tick at least one person.';
    final (_, left) = _resolve();
    return left < 0 ? '${inr(-left)} more than the bill.' : '${inr(left)} still to share out.';
  }

  /// The whole bill on whoever paid: an expense that moves no money. Allowed,
  /// because a just-yours expense in a trip's record is a real thing, but it
  /// is almost always "I paid, so 100% me", and the step says so.
  bool get allOnPayer {
    final s = shares;
    return s.length == 1 && s.containsKey(payerId);
  }

  /// What the split means, as a sentence: "Neel owes you ₹200." Null while it
  /// does not resolve or nobody owes anything.
  String? summary(String Function(Member) nameOf) {
    final s = shares;
    final payer = people.where((m) => m.id == payerId).firstOrNull;
    if (s.isEmpty || payer == null) return null;
    final owing = [for (final m in people) if (m.id != payerId && (s[m.id] ?? 0) > 0) m];
    if (owing.isEmpty) return null;
    // You first: "You and Raj owe Dev", not "Raj and you".
    final debtors = [...owing.where((m) => m.isYou), ...owing.where((m) => !m.isYou)];
    final to = payer.isYou ? 'you' : nameOf(payer);
    String who(Member m) => m.isYou ? 'You' : nameOf(m);
    String owes(Member m) => m.isYou ? 'owe' : 'owes';

    final amounts = {for (final m in debtors) s[m.id]!};
    if (amounts.length == 1) {
      final each = inr(amounts.single);
      if (debtors.length == 1) return '${who(debtors.single)} ${owes(debtors.single)} $to $each.';
      if (debtors.length <= 3) {
        final names = debtors.map(who).toList();
        return '${names.take(names.length - 1).join(', ')} and ${names.last} owe $to $each each.';
      }
      return debtors.first.isYou
          ? 'You and ${debtors.length - 1} others owe $to $each each.'
          : '${debtors.length} people owe $to $each each.';
    }
    if (debtors.length <= 3) {
      return debtors.map((m) => '${who(m)} ${owes(m)} $to ${inr(s[m.id]!)}.').join(' ');
    }
    if (debtors.first.isYou) {
      final rest = debtors.skip(1).fold(0, (t, m) => t + s[m.id]!);
      return 'You owe $to ${inr(s[debtors.first.id]!)}. ${debtors.length - 1} others owe ${inr(rest)} between them.';
    }
    final total = debtors.fold(0, (t, m) => t + s[m.id]!);
    return '${debtors.length} people owe $to ${inr(total)} between them.';
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Who paid, who it was for, and what that means in words.
class SplitFields extends StatelessWidget {
  const SplitFields({super.key, required this.model, this.payerQuestion});

  final SplitModel model;

  /// "Who paid the ₹200?" unless the sheet asks it its own way.
  final String? payerQuestion;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;

    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final shares = model.shares;
        final others = [for (final m in model.people) if (!m.removed && m.id != model.payerId) m];
        final owedInFull = others.length == 1
            ? (others.single.isYou ? 'You owe all of it' : '${store.shortName(others.single)} owes all of it')
            : 'The others owe all of it';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Question(payerQuestion ?? (model.amount > 0 ? 'Who paid the ${inr(model.amount)}?' : 'Who paid?')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in model.people)
                  NameChip(
                    store.shortName(m),
                    selected: m.id == model.payerId,
                    onTap: () => model.setPayer(m.id),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            const _Question('Who was it for?'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                NameChip('Split equally', selected: model.isEven, onTap: model.evenly),
                if (others.isNotEmpty)
                  NameChip(owedInFull, selected: model.isOthersOweAll, onTap: model.othersOweAll),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              "Each person's share. Type one in and the rest is shared out.",
              style: ranade(11.5, height: 1.5, color: c.ink3),
            ),
            const SizedBox(height: 4),
            for (final m in model.people)
              _SplitRow(
                key: ValueKey(m.id),
                name: store.displayName(m),
                included: model.included.contains(m.id),
                typed: model.isTyped(m.id),
                controller: model.fields[m.id]!,
                share: shares[m.id],
                onToggle: () => model.toggle(m.id),
              ),
            const SizedBox(height: 14),
            _Outcome(model: model, fix: owedInFull),
          ],
        );
      },
    );
  }
}

class _Question extends StatelessWidget {
  const _Question(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: ranade(17, color: context.c.ink)));
}

/// The sentence under the split: who owes whom, what is wrong with it, or
/// that it is all on whoever paid.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.model, required this.fix});

  final SplitModel model;

  /// The label for the one-tap fix when the whole bill sits on the payer.
  final String fix;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final problem = model.problem;
    if (problem != null) return Text(problem, style: ranade(12.5, color: c.ink3));

    final payer = model.people.where((m) => m.id == model.payerId).firstOrNull;
    final allOnPayer = model.allOnPayer;
    final sentence = allOnPayer
        ? (payer?.isYou ?? true
              ? "It's all yours, so nobody owes anything."
              : "It's all ${store.shortName(payer!)}'s, so nobody owes anything.")
        : model.summary(store.shortName);
    if (sentence == null) return const SizedBox.shrink();

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: c.quiet, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sentence, style: ranade(15.5, height: 1.4, color: c.ink)),
            if (allOnPayer) ...[
              const SizedBox(height: 12),
              InlineButton(fix, onTap: model.othersOweAll),
            ],
          ],
        ),
      ),
    );
  }
}

/// One person's line: in or out, and their share.
class _SplitRow extends StatelessWidget {
  const _SplitRow({
    super.key,
    required this.name,
    required this.included,
    required this.typed,
    required this.controller,
    required this.share,
    required this.onToggle,
  });

  final String name;
  final bool included;

  /// Whether their share was typed in rather than worked out.
  final bool typed;
  final TextEditingController controller;
  final int? share;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          // The tick and the name toggle; the amount is its own field, so a tap
          // meant for it never takes the person out.
          Expanded(
            child: Pressable(
              onTap: onToggle,
              scale: .99,
              semanticLabel: '$name, ${included ? 'in the split' : 'not in the split'}',
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Checkbox24(on: included),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      style: ranade(15.5, color: included ? c.ink : c.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (included)
            SizedBox(
              width: 96,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                style: excon(17, color: c.ink),
                keyboardAppearance: c.isDark ? Brightness.dark : Brightness.light,
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '₹',
                  prefixStyle: excon(17, color: c.ink),
                  // Worked out, not typed: grey, and replaced by whatever is.
                  hintText: share == null ? '₹0' : inr(share!),
                  hintStyle: excon(17, color: c.ink3),
                  border: UnderlineInputBorder(borderSide: BorderSide(color: c.inputLine)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: typed ? c.ink2 : c.inputLine)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.ink2)),
                  contentPadding: const EdgeInsets.only(bottom: 6),
                ),
              ),
            )
          else
            SizedBox(
              width: 96,
              child: Text('·', textAlign: TextAlign.right, style: excon(17, color: c.ink3)),
            ),
        ],
      ),
    );
  }
}

/// The tick used wherever something is in or out.
///
/// A filled circle with no outline, the same mark the selection rows use: the
/// design has no borders anywhere, so an empty one is a faint disc rather than
/// a ring drawn in a line.
class Checkbox24 extends StatelessWidget {
  const Checkbox24({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 180)),
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? c.ink : c.ink.withValues(alpha: .1),
        shape: BoxShape.circle,
      ),
      child: on ? MullIcon(MullGlyph.check, size: 13, color: c.screen, strokeWidth: 2.6) : null,
    );
  }
}

/// A labelled checkbox row — "Add it without asking".
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.on, required this.label, required this.onTap, this.help});

  final bool on;
  final String label;
  final String? help;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .99,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox24(on: on),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: ranade(15, color: on ? c.ink : c.ink2)),
              ),
            ],
          ),
          if (help != null && on)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 34),
              child: Text(help!, style: ranade(11.5, height: 1.6, color: c.ink3)),
            ),
        ],
      ),
    );
  }
}
