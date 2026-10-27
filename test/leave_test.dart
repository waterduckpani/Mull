import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/store.dart';

void main() {
  MullStore signedIn() => MullStore.memory()..completeOnboarding(name: 'Ananya');

  // A server from before 2026-10-27 handed a group back to the creator who had
  // left it, with no seat in it for them. Leaving it said "Couldn't reach Mull"
  // forever, because there was nobody to take out.
  test('a group handed back with no seat of yours leaves this phone', () async {
    final s = signedIn();
    final g = s.addGroup('Flat', ['Ritu']);
    g.members.removeWhere((m) => m.isYou);
    g.syncedAt = DateTime(2026, 10, 1);
    expect(g.you, isNull);
    final asked = <String>[];
    s.onLeave = (id) async {
      asked.add(id);
      return true;
    };

    expect(await s.leaveGroupEverywhere(g), isTrue);
    expect(s.groupById(g.id), isNull);
    // Asked, so the server stops handing it back.
    expect(asked, [g.id]);
  });

  group('adding a friend who was already added by name', () {
    test('the same address is the same person', () {
      final s = signedIn();
      final g = s.addGroup('Flat', ['Ritu']);
      final ritu = g.members.firstWhere((m) => m.name == 'Ritu')..email = 'ritu@x.in';
      final match = s.seatWaitingFor(g, name: 'Ritu Sharma', email: 'Ritu@X.in');
      expect(match?.seat, same(ritu));
      expect(match?.sure, isTrue);
    });

    test('the same name is only a guess', () {
      final s = signedIn();
      final g = s.addGroup('Flat', ['Ritu']);
      final match = s.seatWaitingFor(g, name: ' ritu ', email: 'ritu@x.in');
      expect(match?.sure, isFalse);
    });

    test('a seat with someone else\'s address is not offered', () {
      final s = signedIn();
      final g = s.addGroup('Flat', ['Ritu']);
      g.members.firstWhere((m) => m.name == 'Ritu').email = 'other@x.in';
      expect(s.seatWaitingFor(g, name: 'Ritu', email: 'ritu@x.in'), isNull);
    });

    test('handing the seat over puts their address on it, history intact', () {
      final s = signedIn();
      final g = s.addGroup('Flat', ['Ritu']);
      final ritu = g.members.firstWhere((m) => m.name == 'Ritu');
      s.addExpense(g, description: 'Rent', amount: 100, payerId: ritu.id, shares: {g.you!.id: 100});
      s.handSeatTo(g, ritu, ' Ritu@X.in ');
      expect(ritu.email, 'ritu@x.in');
      expect(g.members.length, 2, reason: 'no second seat');
      expect(g.pairBalance(g.you!.id, ritu.id), -100);
    });
  });
}
