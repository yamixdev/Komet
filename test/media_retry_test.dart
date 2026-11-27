import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/core/storage/app_database.dart';
import 'package:komet/frontend/screens/chats/chat/chat_controller.dart';
import 'package:komet/frontend/screens/chats/chat/chat_media_send_controller.dart';
import 'package:komet/frontend/screens/chats/chat/upload_status.dart';
import 'package:komet/models/attachment.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const int _me = 101;
const int _chatId = 303;

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SyntheticPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _PhotoSource implements File {
  _PhotoSource(this.file, this.onRead);

  final File file;
  final VoidCallback onRead;

  @override
  String get path => file.path;

  @override
  Future<bool> exists() => file.exists();

  @override
  Future<Uint8List> readAsBytes() {
    onRead();
    return file.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _PhotoSourceOverrides extends IOOverrides {
  _PhotoSourceOverrides(this.source);

  final File source;

  @override
  File createFile(String path) =>
      path == source.path ? source : super.createFile(path);
}

CachedMessage _failed(
  List<MessageAttachment> attachments, {
  String status = 'error',
  int e2ee = CachedMessage.e2eeNone,
}) => CachedMessage(
  id: 'temp_1_1',
  accountId: _me,
  chatId: _chatId,
  senderId: _me,
  time: 1700000000000,
  status: status,
  attachments: attachments,
  e2ee: e2ee,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var mounted = true;
  final chat = ChatController()
    ..myId = _me
    ..chatId = _chatId;
  final media = ChatMediaSendController(
    chatController: chat,
    showAttachmentPanel: ValueNotifier(false),
    uploadStatus: ValueNotifier(const UploadStatus()),
    bumpMessages: () {},
    scrollToBottom: () {},
    setLastSentId: (_) {},
    notify: (_) {},
    isMounted: () => mounted,
    encryptionEnabled: () => false,
    encryptOutgoing: (text, {notify = true}) async => text,
    confirmSend: () async => true,
    markHasScheduled: () {},
    takeReply: () => null,
  );

  test(
    'closing the chat during photo preparation keeps the failed row',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic_retry',
      );
      final originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
      addTearDown(() async {
        await AppDatabase.close();
        PathProviderPlatform.instance = originalPathProvider;
        await directory.delete(recursive: true);
        chat.messages = [];
        mounted = true;
      });
      await AppDatabase.init();
      await AppDatabase.saveProfile(ProfileData.stub(_me));
      await AppDatabase.saveChats([
        {'id': _chatId, 'account_id': _me, 'type': 'CHAT', 'cached_at': 0},
      ]);
      final file = File(
        '${directory.path}${Platform.pathSeparator}synthetic.jpg',
      );
      await file.writeAsBytes([0]);
      final failed = _failed([PhotoAttachment(localPath: file.path)]);
      chat.addMessage(failed);
      await AppDatabase.saveMessages([failed.toDbRow()]);

      await IOOverrides.runWithIOOverrides(
        () => media.retry(failed),
        _PhotoSourceOverrides(_PhotoSource(file, () => mounted = false)),
      );

      expect(mounted, isFalse);
      expect(chat.byId(failed.id)?.status, 'error');
      final stored = await AppDatabase.loadMessage(_me, _chatId, failed.id);
      expect(stored?['status'], 'error');
    },
  );

  test('media with its source on the device can be sent again', () {
    expect(
      media.canRetry(_failed([const PhotoAttachment(localPath: '/tmp/a.jpg')])),
      isTrue,
    );
    expect(
      media.canRetry(
        _failed([
          const VideoAttachment(videoType: 1, localPath: '/tmp/note.mp4'),
        ]),
      ),
      isTrue,
    );
    expect(
      media.canRetry(_failed([const AudioAttachment(localPath: '/tmp/v.ogg')])),
      isTrue,
    );
    expect(
      media.canRetry(
        _failed([const FileAttachment(localPath: '/tmp/doc.pdf')]),
      ),
      isTrue,
    );
  });

  test('a file already on the server is sent again by its id', () {
    expect(media.canRetry(_failed([const FileAttachment(fileId: 7)])), isTrue);
  });

  test('stickers, contacts and places are rebuilt from the attachment', () {
    expect(
      media.canRetry(_failed([const StickerAttachment(stickerId: '12')])),
      isTrue,
    );
    expect(
      media.canRetry(_failed([const ContactAttachment(contactId: 900301)])),
      isTrue,
    );
    expect(
      media.canRetry(
        _failed([const LocationAttachment(latitude: 55.7, longitude: 37.6)]),
      ),
      isTrue,
    );
  });

  test('nothing to send again is not offered', () {
    expect(media.canRetry(_failed([const AudioAttachment()])), isFalse);
    expect(media.canRetry(_failed([const FileAttachment()])), isFalse);
    expect(
      media.canRetry(
        _failed([
          const PhotoAttachment(localPath: '/tmp/a.jpg'),
          const PhotoAttachment(),
        ]),
      ),
      isFalse,
    );
    expect(media.canRetry(_failed(const [])), isFalse);
  });

  test('only failed unencrypted messages are offered', () {
    const photo = PhotoAttachment(localPath: '/tmp/a.jpg');
    expect(media.canRetry(_failed([photo], status: 'sending')), isFalse);
    expect(media.canRetry(_failed([photo], status: 'sent')), isFalse);
    expect(
      media.canRetry(_failed([photo], e2ee: CachedMessage.e2eeFile)),
      isFalse,
    );
  });
}
