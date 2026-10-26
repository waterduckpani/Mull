import 'package:flutter_test/flutter_test.dart';
import 'package:mull/core/split.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';
import 'package:mull/screens/groups/split_editor.dart';

void main() {
  MullStore signedIn() => MullStore.memory()..completeOnboarding(name: 'Ananya');

  group('taking out someone not on Mull', () {
    // Ritu, added by name, had a share of dinner you paid for.
    (MullStore, Group, Member) owing() {
      final s = signedIn();
      final g = s.addGroup('Flat', ['Ritu', 'Dev']);
      final ritu = g.members.firstWhere((m) => m.name == 'Ritu');
      s.addExpense(
        g,
        description: 'Dinner',
        amount: 600,
        payerId: g.you!.id,
        shares: splitEqually(600, [g.you!.id, ritu.id]),
      );
      return (s, g, ritu);
    }

    test('not while they still owe', () {
      final (s, g, ritu) = owing();
      expect(s.canRemoveMember(g, ritu), isFalse);
      expect(s.whyMemberStays(g, ritu), contains('money open'));
    });

    test('once settled, even with history, and the history stays', () async {
      final (s, g, ritu) = owing();
      s.settleUp(g, fromId: ritu.id, toId: g.you!.id, amount: 300);
      expect(s.whyMemberStays(g, ritu), isNull);
      expect(s.canRemoveMember(g, ritu), isTrue);

      expect(await s.removeMemberEverywhere(g, ritu), isNull);
      expect(g.members, contains(ritu), reason: 'the dinner still names her seat');
      expect(ritu.removed, isTrue);
      expect(g.seated.map((m) => m.name), ['Ananya', 'Dev']);
      expect(g.expenses.single.shares.keys, contains(ritu.id));
      expect(g.youAreSquare, isTrue);
      expect(s.standings.map((st) => st.member.name), isNot(contains('Ritu')));
      expect(s.canRemoveMember(g, ritu), isFalse, reason: 'already out');
    });

    test('square overall is not enough: pair by pair', () {
      final s = signedIn();
      final g = s.addGroup('Trip', ['Ritu', 'Dev']);
      final ritu = g.members.firstWhere((m) => m.name == 'Ritu');
      final dev = g.members.firstWhere((m) => m.name == 'Dev');
      // Ritu owes you 100 and Dev owes Ritu 100.
      s.addExpense(g, description: 'Cab', amount: 100, payerId: g.you!.id, shares: {ritu.id: 100});
      s.addExpense(g, description: 'Chai', amount: 100, payerId: ritu.id, shares: {dev.id: 100});
      expect(g.balances[ritu.id], 0);
      expect(s.canRemoveMember(g, ritu), isFalse);
    });

    test('not while a repeating expense still bills them', () {
      final s = signedIn();
      final g = s.addGroup('Flat', ['Ritu']);
      final ritu = g.members.firstWhere((m) => m.name == 'Ritu');
      s.addRecurring(
        g,
        description: 'Rent',
        amount: 1000,
        payerId: g.you!.id,
        shares: splitEqually(1000, [g.you!.id, ritu.id]),
        startsOn: DateTime(2026, 11, 1),
      );
      expect(s.whyMemberStays(g, ritu), contains('repeating'));
    });

    test('someone on Mull with history leaves for themselves', () {
      final s = signedIn();
      final g = s.addGroup('Flat', []);
      final kabir = s.addFriendAsMember(g, userId: newId(), name: 'Kabir')!;
      s.addExpense(g, description: 'Chai', amount: 100, payerId: kabir.id, shares: {kabir.id: 100});
      expect(s.whyMemberStays(g, kabir), contains('only they can leave'));
    });

    test('signed in, it waits for the server, and says so when it cannot reach it', () async {
      final (s, g, ritu) = owing();
      s.settleUp(g, fromId: ritu.id, toId: g.you!.id, amount: 300);
      g.syncedAt = DateTime.now();
      String? asked;
      s.onRemoveMember = (groupId, memberId) async {
        asked = memberId;
        return false;
      };
      expect(await s.removeMemberEverywhere(g, ritu), contains('Check your connection'));
      expect(asked, ritu.id);
      expect(ritu.removed, isFalse);

      s.onRemoveMember = (_, _) async => true;
      expect(await s.removeMemberEverywhere(g, ritu), isNull);
      expect(ritu.removed, isTrue);
    });

    test('a seat nothing refers to is still deleted outright', () async {
      final (s, g, _) = owing();
      final dev = g.members.firstWhere((m) => m.name == 'Dev');
      expect(await s.removeMemberEverywhere(g, dev), isNull);
      expect(g.members.map((m) => m.name), isNot(contains('Dev')));
    });

    test('a new split leaves them out; editing an old one keeps their share', () async {
      final (s, g, ritu) = owing();
      s.settleUp(g, fromId: ritu.id, toId: g.you!.id, amount: 300);
      await s.removeMemberEverywhere(g, ritu);

      final fresh = SplitModel(group: g, amount: 300);
      expect(fresh.people.map((m) => m.name), ['Ananya', 'Dev']);
      expect(fresh.included, isNot(contains(ritu.id)));

      final dinner = g.expenses.single;
      final editing = SplitModel(group: g, payerId: dinner.payerId, shares: dinner.shares, amount: dinner.amount);
      expect(editing.people, contains(ritu));
      expect(editing.shares, dinner.shares);
    });

    test('survives being saved to the phone and read back', () async {
      final (s, g, ritu) = owing();
      s.settleUp(g, fromId: ritu.id, toId: g.you!.id, amount: 300);
      await s.removeMemberEverywhere(g, ritu);
      final back = Group.fromJson(g.toJson());
      expect(back.memberById(ritu.id)!.removed, isTrue);
    });
  });

  group('asking for a bill', () {
    (MullStore, Group, Member) paidBy({String? userId}) {
      final s = signedIn();
      final g = s.addGroup('Goa', ['Ritu']);
      final ritu = g.members.firstWhere((m) => m.name == 'Ritu')..userId = userId;
      s.addExpense(
        g,
        description: 'Villa',
        amount: 4000,
        payerId: ritu.id,
        shares: splitEqually(4000, [g.you!.id, ritu.id]),
      );
      return (s, g, ritu);
    }

    test('from someone on Mull goes through Mull', () {
      final (s, g, ritu) = paidBy(userId: newId());
      final villa = g.expenses.single;
      expect(s.canRequestReceipt(g, villa), isTrue);
      expect(s.canAskOffMull(g, villa), isFalse);
      expect(s.billsToAskFor({g.id: ritu.id}), hasLength(1));
      s.requestReceipt(g, villa);
      expect(s.receiptAwaited(g, villa), isTrue);
      expect(s.billsAskedFor({g.id: ritu.id}), hasLength(1));
    });

    test('from someone not on Mull goes on WhatsApp, and is never left waiting', () {
      final (s, g, ritu) = paidBy();
      final villa = g.expenses.single;
      expect(s.canRequestReceipt(g, villa), isFalse);
      expect(s.canAskOffMull(g, villa), isTrue);
      expect(s.billsToAskFor({g.id: ritu.id}), isEmpty);
      expect(s.billsToAskOffMull({g.id: ritu.id}), hasLength(1));
      expect(
        s.billAskMessage('Ritu', s.billsToAskOffMull({g.id: ritu.id})),
        'Hey Ritu, could you send me the bill for Villa (₹4,000)?',
      );
    });

    test('a request an older version left on a placeholder stops waiting', () {
      final (s, g, ritu) = paidBy();
      final villa = g.expenses.single..receiptRequestedBy = g.you!.id;
      expect(s.receiptAwaited(g, villa), isFalse);
      expect(s.billsAskedFor({g.id: ritu.id}), isEmpty);
      expect(s.canAskOffMull(g, villa), isTrue);
    });

    test('several bills in one message', () {
      final (s, g, ritu) = paidBy();
      s.addExpense(g, description: 'Cab', amount: 600, payerId: ritu.id, shares: splitEqually(600, [g.you!.id, ritu.id]));
      expect(
        s.billAskMessage('Ritu', s.billsToAskOffMull({g.id: ritu.id})),
        startsWith('Hey Ritu, could you send me the bills for '),
      );
    });
  });
}
