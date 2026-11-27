import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:komet/core/media/audio_file_metadata.dart';
import 'package:komet/core/utils/media_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SyntheticPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cacheName = 'synthetic-audio.mp3';
  late File source;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp(
      'synthetic_audio_metadata',
    );
    final originalPathProvider = PathProviderPlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = originalPathProvider;
      MediaCache.resetForTesting();
      AudioFileMetadata.resetForTesting();
      await directory.delete(recursive: true);
    });
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    source = await File(
      'test/fixtures/audio_metadata.mp3',
    ).copy('${directory.path}${Platform.pathSeparator}$cacheName');
  });

  test(
    'reads title, artist, album and embedded cover from an audio file',
    () async {
      final metadata = await AudioFileMetadata.read(
        source,
        cacheName: cacheName,
      );

      expect(metadata, isNotNull);
      expect(metadata!.title, 'Synthetic Track');
      expect(metadata.artist, 'Synthetic Artist');
      expect(metadata.album, 'Synthetic Album');
      expect(metadata.artworkUri, isNotNull);
      final artwork = File.fromUri(metadata.artworkUri!);
      expect(await artwork.exists(), isTrue);
      final decoded = img.decodeImage(await artwork.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 160);
      expect(decoded.height, 160);
      expect(AudioFileMetadata.parseCountForTesting, 1);

      await source.setLastModified(
        DateTime.now().add(const Duration(seconds: 1)),
      );
      final cached = await AudioFileMetadata.read(source, cacheName: cacheName);
      expect(cached?.title, 'Synthetic Track');
      expect(cached?.artworkUri, metadata.artworkUri);
      expect(AudioFileMetadata.parseCountForTesting, 1);
    },
  );

  test('regenerates artwork evicted while the audio file is cached', () async {
    final metadata = await AudioFileMetadata.read(source, cacheName: cacheName);
    final artwork = File.fromUri(metadata!.artworkUri!);
    await artwork.delete();

    final results = await Future.wait([
      AudioFileMetadata.read(source, cacheName: cacheName),
      AudioFileMetadata.read(source, cacheName: cacheName),
    ]);

    for (final result in results) {
      expect(result?.artworkUri, artwork.uri);
    }
    expect(await artwork.exists(), isTrue);
    expect(AudioFileMetadata.parseCountForTesting, 2);
  });
}
