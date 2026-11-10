import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../../ui/sheet.dart';
import '../../ui/tab_bar.dart';
import '../../ui/tokens.dart';
import '../groups/create_group_flow.dart';
import '../groups/group_screen.dart';
import 'groups_tab.dart';
import 'home_tab.dart';
import 'people_tab.dart';

/// The four places at the top of the app, in the order the bar shows them.
enum HomeTab {
  home('Home', MullGlyph.home),
  groups('Groups', MullGlyph.grid),
  people('People', MullGlyph.groups),
  you('You', MullGlyph.person);

  const HomeTab(this.label, this.glyph);

  final String label;
  final MullGlyph glyph;
}

/// Lets a tab send you to another one: "see who" under the number goes to
/// People.
class HomeShellScope extends InheritedWidget {
  const HomeShellScope({super.key, required this.select, required super.child});

  final ValueChanged<HomeTab> select;

  static HomeShellScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HomeShellScope>()!;

  @override
  bool updateShouldNotify(HomeShellScope old) => false;
}

/// Mull's first screen: Home, Groups, People and You under the same bar a
/// group has.
///
/// The home screen used to be one long page that did everything, with
/// Friends and your profile behind small icons in the corner. Now each of
/// those has a tab, and the + sits where it sits inside a group.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = HomeTab.home});

  final HomeTab initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late HomeTab _tab = widget.initialTab;
  late final double _raiseBefore;

  @override
  void initState() {
    super.initState();
    // Notices sit above the bar, not on top of the +.
    _raiseBefore = Toast.raise;
    Toast.raise = MullTabBar.height + 12;
  }

  @override
  void dispose() {
    Toast.raise = _raiseBefore;
    super.dispose();
  }

  void _select(HomeTab tab) => setState(() => _tab = tab);

  Future<void> _start({String? name}) async {
    final group = await showCreateGroup(context, name: name);
    if (group != null && mounted) {
      await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => GroupScreen(groupId: group.id)));
    }
  }

  Widget _page(HomeTab tab) => SizedBox.expand(
    key: ValueKey('home-tab-${tab.name}'),
    child: switch (tab) {
      HomeTab.home => HomeTabPage(bottomInset: MullTabBar.height, onStart: _start),
      HomeTab.groups => GroupsTabPage(bottomInset: MullTabBar.height, onStart: _start),
      HomeTab.people => const PeopleTabPage(bottomInset: MullTabBar.height),
      _ => MullPage(bottomInset: MullTabBar.height, children: [PageTitle(tab.label)]),
    },
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final barBottom = ShellMetrics.ctaBottom(context);
    // Android's Back goes Home before it leaves the app; iOS has none.
    final android = defaultTargetPlatform == TargetPlatform.android;

    return HomeShellScope(
      select: _select,
      child: PopScope(
        canPop: _tab == HomeTab.home || !android,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _select(HomeTab.home);
        },
        child: Stack(
          children: [
            IndexedStack(
              index: _tab.index,
              sizing: StackFit.expand,
              children: [for (final tab in HomeTab.values) _page(tab)],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: barBottom + MullTabBar.height / 2 + 44,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [c.screen.withValues(alpha: 0), c.screen, c.screen],
                      stops: const [0, .55, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: barBottom,
              child: MullTabBar(
                items: [for (final tab in HomeTab.values) TabItem(tab.label, tab.glyph)],
                current: _tab.index,
                onSelect: (i) => _select(HomeTab.values[i]),
                onAdd: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}
