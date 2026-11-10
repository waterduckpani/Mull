import 'package:flutter_test/flutter_test.dart';
import 'package:mull/core/split.dart';
import 'package:mull/data/models.dart';
import 'package:mull/screens/groups/split_editor.dart';

/// Who paid and who it was for: one list, equal unless somebody's share is
/// typed in.
void main() {
  final you = Member(name: 'You', isYou: true);
  final dev = Member(name: 'Dev');
  final raj = Member(name: 'Raj');
  final flat = Group(name: 'Flat', members: [you, dev, raj]);
  final pair = Group(name: 'Neel', members: [you, dev]);
  String name(Member m) => m.isYou ? 'you' : m.name;

  group('a new expense', () {
    test('is split equally between everyone', () {
      final model = SplitModel(group: flat, amount: 300);
      expect(model.shares, {you.id: 100, dev.id: 100, raj.id: 100});
      expect(model.method, SplitMethod.equal);
      expect(model.isEven, isTrue);
      expect(model.summary(name), 'Dev and Raj owe you ₹100 each.');
    });

    test('"they owe all of it" takes whoever paid out of the split', () {
      final model = SplitModel(group: pair, amount: 200)..othersOweAll();
      expect(model.shares, {dev.id: 200});
      expect(model.isOthersOweAll, isTrue);
      expect(model.isEven, isFalse);
      expect(model.summary(name), 'Dev owes you ₹200.');
    });

    test('unticking yourself is the same thing', () {
      final model = SplitModel(group: pair, amount: 200)..toggle(you.id);
      expect(model.shares, {dev.id: 200});
      expect(model.isOthersOweAll, isTrue);
    });

    test('changing who paid keeps "they owe all of it"', () {
      final model = SplitModel(group: pair, amount: 200)
        ..othersOweAll()
        ..setPayer(dev.id);
      expect(model.shares, {you.id: 200});
      expect(model.summary(name), 'You owe Dev ₹200.');
    });

    test('the whole bill on whoever paid is flagged, and still allowed', () {
      final model = SplitModel(group: pair, amount: 200)..toggle(dev.id);
      expect(model.shares, {you.id: 200});
      expect(model.allOnPayer, isTrue);
      expect(model.isValid, isTrue, reason: 'a just-yours expense is rare, not wrong');
      expect(model.summary(name), isNull);
    });
  });

  group('typing a share', () {
    test('splits what is left between the others', () {
      final model = SplitModel(group: flat, payerId: dev.id, amount: 300);
      model.fields[you.id]!.text = '150';
      expect(model.shares, {you.id: 150, dev.id: 75, raj.id: 75});
      expect(model.method, SplitMethod.exact);
      expect(model.isTyped(you.id), isTrue);
      expect(model.isTyped(dev.id), isFalse);
      expect(model.summary(name), 'You owe Dev ₹150. Raj owes Dev ₹75.');
    });

    test('more than the bill does not resolve', () {
      final model = SplitModel(group: flat, amount: 300);
      model.fields[dev.id]!.text = '400';
      expect(model.shares, isEmpty);
      expect(model.problem, '₹100 more than the bill.');
    });

    test('when every share is typed they have to add up', () {
      final model = SplitModel(group: pair, amount: 200);
      model.fields[you.id]!.text = '100';
      model.fields[dev.id]!.text = '50';
      expect(model.shares, isEmpty);
      expect(model.problem, '₹50 still to share out.');
      model.fields[dev.id]!.text = '100';
      expect(model.shares, {you.id: 100, dev.id: 100});
    });

    test('a share of nothing leaves them out', () {
      final model = SplitModel(group: pair, amount: 200);
      model.fields[you.id]!.text = '0';
      expect(model.shares, {dev.id: 200});
    });

    test('ticking someone in or out starts again from equal', () {
      final model = SplitModel(group: flat, amount: 300);
      model.fields[you.id]!.text = '150';
      model.toggle(raj.id);
      expect(model.fields[you.id]!.text, isEmpty);
      expect(model.shares, {you.id: 150, dev.id: 150});
    });
  });

  group('an expense being edited', () {
    test('a 2:1 split reopens with its amounts, and saves unchanged', () {
      final saved = splitByWeight(3000, {you.id: 2, dev.id: 1});
      final model = SplitModel(group: flat, method: SplitMethod.shares, shares: saved, amount: 3000);

      expect(model.fields[you.id]!.text, '2000');
      expect(model.fields[dev.id]!.text, '1000');
      expect(model.included, {you.id, dev.id});
      expect(model.shares, saved);
      expect(model.method, SplitMethod.shares, reason: 'untouched, it is still what it was');
    });

    test('an old percent split still scales with the bill until it is edited', () {
      final model = SplitModel(
        group: flat,
        method: SplitMethod.percent,
        shares: {you.id: 700, dev.id: 300},
        amount: 1000,
      )..amount = 2000;
      expect(model.shares, {you.id: 1400, dev.id: 600});
      expect(model.fields[you.id]!.text, '1400', reason: 'the fields show what will be saved');
    });

    test('an equal split re-splits when the amount changes', () {
      final model = SplitModel(group: flat, shares: splitEqually(300, [you.id, dev.id]), amount: 300)
        ..amount = 400;
      expect(model.shares, {you.id: 200, dev.id: 200});
      expect(model.fields[you.id]!.text, isEmpty);
    });

    test('exact amounts that no longer add up are not a split', () {
      final model = SplitModel(
        group: flat,
        method: SplitMethod.exact,
        shares: {you.id: 2000, dev.id: 1000},
        amount: 3000,
      )..amount = 3300;
      expect(model.shares, isEmpty);
      expect(model.problem, '₹300 still to share out.');
    });
  });

  test('a rupee of rounding is "about", not three sentences', () {
    final model = SplitModel(group: flat, amount: 200)..othersOweAll();
    expect(model.shares, {dev.id: 100, raj.id: 100});
    model.amount = 201;
    expect(model.summary(name), 'Dev and Raj owe you about ₹101 each.');
  });

  test('a big group says how many, not every name', () {
    final big = Group(name: 'Trip', members: [you, for (final n in ['A', 'B', 'C', 'D']) Member(name: n)]);
    final model = SplitModel(group: big, amount: 500);
    expect(model.summary(name), '4 people owe you ₹100 each.');
  });
}
