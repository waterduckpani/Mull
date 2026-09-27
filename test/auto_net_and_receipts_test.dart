import 'package:flutter_test/flutter_test.dart';
import 'package:mull/core/split.dart';
import 'package:mull/data/models.dart';
import 'package:mull/data/store.dart';

void main() {
  group('netting off happens on its own', () {
    late MullStore store;
    late Group goa;
    late Group flat;

    // You owe Ananya 2,000 on Goa; she owes you 3,000 on the flat.
    void build({String? herAccount, String? yourAccount}) {
      store = MullStore.memory();
      store.completeOnboarding(name: 'Bharat');
      goa = store.addGroup('Goa', ['Ananya']);
      flat = store.addGroup('Flat', ['Ananya']);
      for (final g in [goa, flat]) {
        g.members.firstWhere((m) => !m.isYou)
          ..email = 'ananya@example.com'
          ..userId = herAccount;
        g.you!.userId = yourAccount;
      }
      final herA = goa.members.firstWhere((m) => !m.isYou).id;
      store.addExpense(
        goa,
        description: 'Villa',
        amount: 4000,
        payerId: herA,
        shares: splitEqually(4000, [goa.you!.id, herA]),
      );
      final herB = flat.members.firstWhere((m) => !m.isYou).id;
      store.addExpense(
        flat,
        description: 'Rent',
        amount: 6000,
        payerId: flat.you!.id,
        shares: splitEqually(6000, [flat.you!.id, herB]),
      );
    }

    String her(Group g) => g.members.firstWhere((m) => !m.isYou).id;

    test('the smaller side cancels in both ledgers, and the net is untouched', () {
      build();
      expect(goa.pairBalance(goa.you!.id, her(goa)), 0);
      expect(flat.pairBalance(flat.you!.id, her(flat)), 1000);
      expect(store.standings.single.amount, 1000);
      expect(goa.settlements.single.offset, isTrue);
      expect(goa.settlements.single.status, SettlementStatus.confirmed);
    });

    test('the home screen is told once, until it is acknowledged', () {
      build();
      final news = store.unseenNetOffs.single;
      expect(news.amount, 2000);
      expect(news.groups.map((g) => g.name), unorderedEquals(['Goa', 'Flat']));
      store.acknowledgeNetOff(news);
      expect(store.unseenNetOffs, isEmpty);
    });

    test('netting by hand is not announced back to the person who did it', () {
      store = MullStore.memory()..autoNet = false;
      store.completeOnboarding(name: 'Bharat');
      final a = store.addGroup('A', ['Kabir']);
      final b = store.addGroup('B', ['Kabir']);
      for (final g in [a, b]) {
        g.members.firstWhere((m) => !m.isYou).email = 'kabir@example.com';
      }
      final ka = a.members.firstWhere((m) => !m.isYou).id;
      final kb = b.members.firstWhere((m) => !m.isYou).id;
      store.addExpense(a, description: 'x', amount: 1000, payerId: ka, shares: splitEqually(1000, [a.you!.id, ka]));
      store.addExpense(
        b,
        description: 'y',
        amount: 1000,
        payerId: b.you!.id,
        shares: splitEqually(1000, [b.you!.id, kb]),
      );
      store.netOff(store.standings.single);
      expect(store.unseenNetOffs, isEmpty);
    });

    test('only one of the two phones writes it', () {
      // Her account sorts first, so her phone nets; yours leaves it alone
      // rather than writing a second copy of the same offsets.
      build(herAccount: 'aaaa', yourAccount: 'zzzz');
      expect(goa.settlements, isEmpty);
      expect(goa.pairBalance(goa.you!.id, her(goa)), -2000);

      build(herAccount: 'zzzz', yourAccount: 'aaaa');
      expect(goa.settlements.single.offset, isTrue);
    });

    test('money already claimed as paid is not netted a second time', () {
      store = MullStore.memory()..autoNet = false;
      store.completeOnboarding(name: 'Bharat');
      goa = store.addGroup('Goa', ['Ananya']);
      flat = store.addGroup('Flat', ['Ananya']);
      for (final g in [goa, flat]) {
        g.members.firstWhere((m) => !m.isYou).email = 'ananya@example.com';
      }
      store.addExpense(
        goa,
        description: 'Villa',
        amount: 4000,
        payerId: her(goa),
        shares: splitEqually(4000, [goa.you!.id, her(goa)]),
      );
      store.addExpense(
        flat,
        description: 'Rent',
        amount: 6000,
        payerId: flat.you!.id,
        shares: splitEqually(6000, [flat.you!.id, her(flat)]),
      );
      // She says she has sent 2,500 of the 3,000 on the flat.
      flat.settlements.add(Settlement(fromId: her(flat), toId: flat.you!.id, amount: 2500));

      expect(store.netOffAmount(store.standings.single), 500);
      store.autoNet = true;
      store.refresh();
      expect(goa.pairBalance(goa.you!.id, her(goa)), -1500);
    });

    test('a file from before announcements treats its offsets as seen', () {
      build();
      final saved = store.toJson()..remove('seenOffsets');
      final reopened = MullStore.memory()..debugRestore(saved);
      expect(reopened.unseenNetOffs, isEmpty);
    });
  });

  group('bills', () {
    late MullStore store;
    late Group g;
    late String kabir;
    late Expense dinner;
    final sent = <Notice>[];

    setUp(() {
      sent.clear();
      store = MullStore.memory()..onNotice = sent.add;
      store.completeOnboarding(name: 'Bharat');
      g = store.addGroup('Dinner club', ['Kabir']);
      kabir = g.members.firstWhere((m) => !m.isYou).id;
      g.memberById(kabir)!.userId = 'u-kabir';
      dinner = store.addExpense(
        g,
        description: 'Dinner',
        amount: 1000,
        payerId: kabir,
        shares: splitEqually(1000, [g.you!.id, kabir]),
      );
      sent.clear();
    });

    test('you can ask for the bill on something somebody else put on you', () {
      expect(store.canRequestReceipt(g, dinner), isTrue);
      store.requestReceipt(g, dinner);
      expect(dinner.receiptRequestedBy, g.you!.id);
      expect(sent.single.kind, NoticeKind.receiptRequested);
      expect(sent.single.to, ['u-kabir']);
      // Asked once is asked.
      expect(store.canRequestReceipt(g, dinner), isFalse);
    });

    test('before paying, every open bill of theirs is one request and one notice', () {
      final cab = store.addExpense(
        g,
        description: 'Cab',
        amount: 400,
        payerId: kabir,
        shares: splitEqually(400, [g.you!.id, kabir]),
      );
      sent.clear();
      final seats = {g.id: kabir};
      expect(store.billsToAskFor(seats).map((e) => e.$2), [dinner, cab]);

      expect(store.requestReceipts(store.billsToAskFor(seats)), 2);
      expect(sent.single.title, 'Bharat asked for the bills for Dinner and Cab');
      expect(sent.single.amount, 1400);
      expect(store.billsToAskFor(seats), isEmpty);
      expect(store.billsAskedFor(seats).length, 2);
    });

    test('settled expenses are not offered: nobody is about to pay for them', () {
      // Kabir has said it arrived.
      store.settleUp(g, fromId: g.you!.id, toId: kabir, amount: 500).status = SettlementStatus.confirmed;
      final seats = {g.id: kabir};
      expect(store.billsToAskFor(seats), isEmpty);
    });

    test('you cannot ask yourself for a bill you paid', () {
      final mine = store.addExpense(
        g,
        description: 'Cab',
        amount: 400,
        payerId: g.you!.id,
        shares: splitEqually(400, [g.you!.id, kabir]),
      );
      expect(store.canRequestReceipt(g, mine), isFalse);
    });

    test('attaching the bill answers the request and tells whoever asked', () {
      // You paid for the cab, and Kabir's phone asked to see it.
      final cab = store.addExpense(
        g,
        description: 'Cab',
        amount: 400,
        payerId: g.you!.id,
        shares: splitEqually(400, [g.you!.id, kabir]),
      );
      cab.receiptRequestedBy = kabir;
      sent.clear();

      expect(store.receiptRequestsForYou.single.$2, cab);
      store.attachReceipt(g, cab, '${g.id}/${cab.id}/x.jpg');
      expect(cab.receipt, isNotNull);
      expect(cab.receiptRequestedBy, isNull);
      expect(store.receiptRequestsForYou, isEmpty);
      expect(sent.single.kind, NoticeKind.receiptAdded);
      expect(sent.single.to, ['u-kabir']);
    });

    test('an expense with no bill keeps the print it was synced with', () {
      // Adding the fields to every print would make every row on every phone
      // dirty the moment the app updated, and push the whole ledger again.
      final plain = Expense(description: 'Chai', amount: 40, payerId: 'a', shares: {'a': 40});
      expect(plain.syncPrint, isNot(contains('null, null]')));
      plain.receipt = 'g/e/x.jpg';
      expect(plain.syncPrint, contains('g/e/x.jpg'));
    });

    test('the bill and the request survive a save', () {
      store.requestReceipt(g, dinner);
      final back = Expense.fromJson(dinner.toJson());
      expect(back.receiptRequestedBy, g.you!.id);
    });
  });
}
