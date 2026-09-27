import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/remote/receipts.dart';
import '../../data/store.dart';
import '../../ui/sheet.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets.dart';
import 'group_sheets.dart';
import 'icon_picker.dart';
import 'recurring_sheets.dart';

// ------------------------------------------------------------- one expense

/// One expense, read rather than edited: who paid, who owes what, the note,
/// and the bill.
///
/// Tapping an expense used to open the edit form, which was the only place its
/// note appeared, in a one-line field that showed the first few words. And
/// somebody who had ₹500 put on them had no way to see what it was for.
Future<void> showExpenseDetail(BuildContext context, Group group, Expense expense) => showMullSheet(
  context,
  height: 760,
  builder: (_) => _ExpenseDetail(groupId: group.id, expenseId: expense.id),
);

class _ExpenseDetail extends StatefulWidget {
  const _ExpenseDetail({required this.groupId, required this.expenseId});

  final String groupId;
  final String expenseId;

  @override
  State<_ExpenseDetail> createState() => _ExpenseDetailState();
}

class _ExpenseDetailState extends State<_ExpenseDetail> {
  bool _uploading = false;

  Future<void> _attach(Group group, Expense expense) async {
    final source = await _pickSource(context);
    if (source == null || !mounted) return;
    final store = context.readStore;
    final XFile? photo;
    try {
      // A bill is text on paper. 1600px keeps the small print legible and the
      // file a few hundred kilobytes.
      photo = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 72);
    } on PlatformException {
      if (mounted) {
        Toast.show(
          context,
          source == ImageSource.camera
              ? 'Mull needs the camera. Allow it in Settings.'
              : 'Mull needs your photos. Allow it in Settings.',
        );
      }
      return;
    }
    if (photo == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final key = await Receipts.save(group, expense, await photo.readAsBytes());
      store.attachReceipt(group, expense, key);
      HapticFeedback.mediumImpact();
    } on ReceiptException catch (e) {
      if (mounted) Toast.show(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _request(Group group, Expense expense) {
    context.readStore.requestReceipt(group, expense);
    HapticFeedback.mediumImpact();
    final payer = group.memberById(expense.payerId);
    Toast.show(context, 'Asked ${payer == null ? 'them' : context.readStore.shortName(payer)} for the bill');
  }

  void _removeBill(Group group, Expense expense) {
    final key = expense.receipt;
    if (key == null) return;
    context.readStore.removeReceipt(group, expense);
    Receipts.delete(key);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final store = context.store;
    final group = store.groupById(widget.groupId);
    final expense = group?.expenses.where((e) => e.id == widget.expenseId).firstOrNull;
    if (group == null || expense == null) {
      // Deleted from under the sheet — by this phone's Delete, or a pull.
      return const SizedBox.shrink();
    }

    final payer = group.memberById(expense.payerId);
    final me = group.you?.id;
    final youPaid = expense.payerId == me;
    final asker = expense.receiptRequestedBy == null ? null : group.memberById(expense.receiptRequestedBy!);
    final schedule = expense.recurringId == null ? null : group.recurringById(expense.recurringId!);
    String name(Member? m) => m == null ? 'Someone' : store.shortName(m);

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      Future.delayed(const Duration(milliseconds: 160), action);
    }

    final shares = expense.shares.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(expense.description),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(30, 8, 30, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(inr(expense.amount), style: MullType.sheetAmount(c.ink)),
                const SizedBox(height: 12),
                Text(
                  [
                    '${name(payer)} paid',
                    shortDateWithYear(expense.date, store.now()),
                    if (expense.isRecurring) 'repeats',
                  ].join(' · '),
                  style: MullType.caption(c.ink3, size: 12.5),
                ),

                const Eyebrow('Split', size: 10.5, tracking: .18, padding: EdgeInsets.only(top: 30, bottom: 6)),
                CardRows(
                  children: [
                    for (final share in shares)
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name(group.memberById(share.key)),
                                style: ranade(15, color: share.key == me ? c.ink : c.ink2),
                              ),
                            ),
                            Text(inr(share.value), style: MullType.listAmount(share.key == me ? c.ink : c.ink2)),
                          ],
                        ),
                      ),
                  ],
                ),

                if (expense.note case final note?) ...[
                  const Eyebrow('Note', size: 10.5, tracking: .18, padding: EdgeInsets.only(top: 30, bottom: 10)),
                  SelectableText(note, style: MullType.body(c.ink)),
                ],

                const Eyebrow('Bill', size: 10.5, tracking: .18, padding: EdgeInsets.only(top: 30, bottom: 12)),
                if (expense.receipt case final key?)
                  _ReceiptThumb(
                    receiptKey: key,
                    onRemove: youPaid ? () => _removeBill(group, expense) : null,
                  )
                else if (_uploading)
                  const _BillLine(text: 'Uploading the bill…', busy: true)
                else ...[
                  if (expense.receiptRequested)
                    _BillLine(
                      text: youPaid
                          ? '${name(asker)} asked to see the bill.'
                          : asker?.id == me
                          ? 'You asked ${name(payer)} for the bill. It shows up here once they add it.'
                          : '${name(asker)} asked ${name(payer)} for the bill.',
                    )
                  else
                    const _BillLine(text: 'No photo of the bill on this one.'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: InlineButton(
                          youPaid && expense.receiptRequested ? 'Add the bill' : 'Add a photo',
                          height: 48,
                          expand: true,
                          filled: youPaid || !store.canRequestReceipt(group, expense),
                          onTap: () => _attach(group, expense),
                        ),
                      ),
                      if (store.canRequestReceipt(group, expense)) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: InlineButton(
                            'Ask for the bill',
                            height: 48,
                            expand: true,
                            onTap: () => _request(group, expense),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                const SizedBox(height: 30),
                CardRows(
                  children: [
                    SheetAction('Edit', onTap: () => run(() => showAddExpense(context, group, existing: expense))),
                    if (schedule != null)
                      SheetAction(
                        'The schedule behind it',
                        detail: schedule.frequency.shortLabel,
                        onTap: () => run(() => showRecurringEditor(context, group, existing: schedule)),
                      ),
                    SheetAction(
                      'Delete',
                      destructive: true,
                      onTap: () => run(() {
                        store.removeExpense(group, expense);
                        Toast.show(
                          context,
                          'Deleted ${expense.description}',
                          action: 'Undo',
                          onAction: () => store.restoreExpense(group, expense),
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A quiet sentence in the bill section.
class _BillLine extends StatelessWidget {
  const _BillLine({required this.text, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        if (busy) ...[
          SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.ink3)),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(text, style: MullType.body(c.ink3))),
      ],
    );
  }
}

/// Camera or library. Asked every time: a bill is as often a screenshot of a
/// Swiggy order as it is paper on a table.
Future<ImageSource?> _pickSource(BuildContext context) => showMullSheet<ImageSource>(
  context,
  fitContent: true,
  builder: (sheet) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add the bill', style: MullType.screenTitle(sheet.c.ink)),
        const SizedBox(height: 16),
        CardRows(
          children: [
            SheetAction('Take a photo', onTap: () => Navigator.of(sheet).pop(ImageSource.camera)),
            SheetAction('Choose from photos', onTap: () => Navigator.of(sheet).pop(ImageSource.gallery)),
          ],
        ),
      ],
    ),
  ),
);

/// The bill, small, loading from the phone or the server. Tap for full size.
class _ReceiptThumb extends StatefulWidget {
  const _ReceiptThumb({required this.receiptKey, this.onRemove});

  final String receiptKey;
  final VoidCallback? onRemove;

  @override
  State<_ReceiptThumb> createState() => _ReceiptThumbState();
}

class _ReceiptThumbState extends State<_ReceiptThumb> {
  late Future<File?> _file = Receipts.load(widget.receiptKey);

  @override
  void didUpdateWidget(_ReceiptThumb old) {
    super.didUpdateWidget(old);
    if (old.receiptKey != widget.receiptKey) _file = Receipts.load(widget.receiptKey);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const _BillLine(text: 'Loading the bill…', busy: true);
        }
        if (file == null) {
          return Pressable(
            onTap: () => setState(() => _file = Receipts.load(widget.receiptKey)),
            child: const _BillLine(text: "Couldn't load the bill. Tap to try again."),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Pressable(
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                PageRouteBuilder(
                  opaque: true,
                  pageBuilder: (_, _, _) => _ReceiptViewer(file: file),
                  transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
                ),
              ),
              scale: .98,
              semanticLabel: 'Photo of the bill. Open full size.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: 220,
                  color: c.quiet,
                  child: Image.file(file, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
            ),
            if (widget.onRemove != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  onTap: widget.onRemove,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Remove the photo', style: ranade(13, color: c.ink3)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReceiptViewer extends StatelessWidget {
  const _ReceiptViewer({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(file)),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 16,
            child: CloseButtonCircle(onTap: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- quick add

/// Adds an expense from the home screen: which ledger first, then the usual
/// form.
///
/// Opening a group to add a chai was two screens of travel for the thing
/// people do most. With one ledger there is nothing to ask.
Future<void> showQuickAdd(BuildContext context) async {
  final store = context.readStore;
  final ledgers = [...store.namedGroups, ...store.directLedgers];
  if (ledgers.isEmpty) return;
  final group = ledgers.length == 1
      ? ledgers.single
      : await showMullSheet<Group>(
          context,
          fitContent: ledgers.length <= 6,
          builder: (sheet) => _LedgerPicker(ledgers: ledgers),
        );
  if (group == null || !context.mounted) return;
  // Let the picker finish leaving before the form rises.
  await Future.delayed(const Duration(milliseconds: 160));
  if (context.mounted) await showAddExpense(context, group);
}

class _LedgerPicker extends StatelessWidget {
  const _LedgerPicker({required this.ledgers});

  final List<Group> ledgers;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = CardRows(
      children: [
        for (final g in ledgers)
          Pressable(
            onTap: () => Navigator.of(context).pop(g),
            scale: .985,
            semanticLabel: g.title,
            child: SizedBox(
              height: 64,
              child: Row(
                children: [
                  GroupBadge(group: g, size: 36, glyphSize: 17),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      g.title,
                      style: ranade(16, color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    g.isDirect ? 'just you two' : '${g.members.length} people',
                    style: MullType.caption(c.ink3),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add it to', style: MullType.screenTitle(c.ink)),
          const SizedBox(height: 16),
          if (ledgers.length <= 6) rows else Expanded(child: SingleChildScrollView(child: rows)),
        ],
      ),
    );
  }
}
