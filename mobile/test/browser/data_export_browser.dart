import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker/_internal/file_picker_web.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// The installed SDK registrar registers the existing file_picker web plugin.
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:personal_ledger/core/network/api_client.dart';
import 'package:personal_ledger/features/data_management/data/data_management_repository.dart';

@JS('document.querySelector')
external JSObject? _query(String selector);
@JS('fetch')
external JSPromise<JSObject> _fetch(String url);
@JS('document.addEventListener')
external void _listen(String type, JSFunction listener, bool capture);
@JS('document.removeEventListener')
external void _unlisten(String type, JSFunction listener, bool capture);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FilePickerWeb.registerWith(Registrar());
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('locked file_picker Web does not implement saveFile', () async {
    await expectLater(
      FilePicker.platform.saveFile(
        fileName: 'fixture.json',
        bytes: Uint8List.fromList([123, 125]),
      ),
      throwsUnimplementedError,
    );
  });

  test('download read failure dispatches no browser file request', () async {
    var downloadClicks = 0;
    final listener = ((JSObject event) {
      downloadClicks++;
      event.callMethod<JSAny?>('preventDefault'.toJS);
    }).toJS;
    _listen('click', listener, true);
    addTearDown(() => _unlisten('click', listener, true));
    await expectLater(
      DataManagementRepository(
        _DownloadClient(failDownload: true),
      ).downloadBackup(),
      throwsStateError,
    );
    expect(downloadClicks, 0);
  });

  test(
    'backup dispatches local blob download with exact bytes and decoded safe filename',
    () async {
      var downloadClicks = 0;
      final listener = ((JSObject event) {
        final target = event.getProperty<JSObject>('target'.toJS);
        if (target.getProperty<JSString>('tagName'.toJS).toDart == 'A') {
          downloadClicks++;
          // Observe dispatch without writing a synthetic file to user Downloads.
          event.callMethod<JSAny?>('preventDefault'.toJS);
        }
      }).toJS;
      _listen('click', listener, true);
      addTearDown(() => _unlisten('click', listener, true));
      final result = await DataManagementRepository(
        _DownloadClient(),
      ).downloadBackup();
      final anchor = _query('#__x_file_dom_element a');
      expect(anchor, isNotNull);
      expect(downloadClicks, 1);
      final download = anchor!.getProperty<JSString>('download'.toJS).toDart;
      final href = anchor.getProperty<JSString>('href'.toJS).toDart;
      expect(download, '账本 100%.json');
      expect(href, startsWith('blob:'));
      final response = await _fetch(href).toDart;
      final buffer = await response
          .callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS)
          .toDart;
      expect(buffer.toDart.asUint8List(), [123, 125]);
      expect(result.filename, '账本 100%.json');
      expect(result.path, isEmpty);
      expect(result.isCancelled, isFalse);
    },
  );
}

class _DownloadClient implements ApiClient {
  _DownloadClient({this.failDownload = false});
  final bool failDownload;
  @override
  Future<Response<List<int>>> getBytes(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (failDownload) throw StateError('合成读取失败');
    return Response(
      requestOptions: RequestOptions(path: path),
      data: [123, 125],
      headers: Headers.fromMap({
        'content-disposition': [
          "attachment; filename*=UTF-8''..%2F%E8%B4%A6%E6%9C%AC%20100%25.json",
        ],
      }),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
