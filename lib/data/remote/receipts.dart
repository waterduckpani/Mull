import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'backend.dart';

/// Photos of bills: kept on the phone, and in the private `receipts` bucket
/// when there is a backend.
///
/// The storage key doubles as the path of the phone's copy, so a bill you
/// attached never needs downloading back, and one somebody else attached is
/// fetched once.
class Receipts {
  static const _bucket = 'receipts';

  static Future<File> _local(String key) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/receipts/$key');
  }

  /// Stores [bytes] as the bill for [expense] and returns its key.
  ///
  /// Uploaded before the key is handed back, so an expense never points
  /// everyone else's phones at a photo that is still only on this one. Throws
  /// [ReceiptException] when that upload fails, and nothing is attached.
  static Future<String> save(Group group, Expense expense, Uint8List bytes) async {
    final key = '${group.id}/${expense.id}/${newId()}.jpg';
    if (Backend.isAvailable && Backend.isSignedIn) {
      try {
        await Backend.client.storage
            .from(_bucket)
            .uploadBinary(key, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      } on StorageException catch (e) {
        debugPrint('mull: receipt upload failed (${e.statusCode} ${e.message})');
        throw ReceiptException(
          e.statusCode == '404' || e.message.contains('Bucket not found')
              ? "Bills can't be attached yet. The server needs an update."
              : "Couldn't upload the bill. Try again in a moment.",
        );
      } catch (e) {
        debugPrint('mull: receipt upload failed ($e)');
        throw const ReceiptException("Couldn't upload the bill. Check your connection.");
      }
    }
    final file = await _local(key);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return key;
  }

  /// The bill on this phone, downloading it first if it is not here yet.
  /// Null when it cannot be had right now.
  static Future<File?> load(String key) async {
    final file = await _local(key);
    if (await file.exists()) return file;
    if (!(Backend.isAvailable && Backend.isSignedIn)) return null;
    try {
      final bytes = await Backend.client.storage.from(_bucket).download(key);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('mull: receipt download failed ($e)');
      return null;
    }
  }

  /// Takes the photo off the server and the phone. Best effort: the expense
  /// has already stopped pointing at it, which is what anybody sees.
  static Future<void> delete(String key) async {
    try {
      final file = await _local(key);
      if (await file.exists()) await file.delete();
      if (Backend.isAvailable && Backend.isSignedIn) {
        await Backend.client.storage.from(_bucket).remove([key]);
      }
    } catch (e) {
      debugPrint('mull: receipt delete failed ($e)');
    }
  }
}

class ReceiptException implements Exception {
  const ReceiptException(this.message);

  final String message;

  @override
  String toString() => message;
}
