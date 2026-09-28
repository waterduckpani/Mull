import 'package:flutter_test/flutter_test.dart';
import 'package:mull/data/remote/receipts.dart';
void main() {
  test('keys', () {
    const u = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';
    expect(Receipts.isKey('$u/$u/$u.jpg'), isTrue);
    expect(Receipts.isKey('$u/../../mull.json'), isFalse);
    expect(Receipts.isKey('$u/$u/$u.jpg/../x'), isFalse);
    expect(Receipts.isKey(null), isFalse);
  });
}
