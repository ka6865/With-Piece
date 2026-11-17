import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/photo_repository.dart';
import 'album_providers.dart';

// 썸네일 격자. 서명 URL은 이 화면의 사진만 한 번에 묶어 받는다(설계 8.2)
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({
    super.key,
    required this.photos,
    this.onLongPress,
    this.trailingFor,
  });

  final List<PhotoRecord> photos;
  final void Function(PhotoRecord photo)? onLongPress;
  final Widget? Function(PhotoRecord photo)? trailingFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('아직 올린 사진이 없어요')),
      );
    }
    return FutureBuilder<Map<String, String>>(
      future: ref.watch(signedUrlCacheProvider).urls([
        for (final p in photos) p.thumbPath,
      ]),
      builder: (context, snapshot) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (final photo in photos)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _FullPhotoPage(photo: photo),
                ),
              ),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(photo),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RemoteImage(url: snapshot.data?[photo.thumbPath]),
                  if (trailingFor?.call(photo) case final trailing?)
                    Align(alignment: Alignment.topRight, child: trailing),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class RemoteImage extends StatelessWidget {
  const RemoteImage({super.key, required this.url, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    final url = this.url;
    if (url == null) return placeholder;
    return Image.network(url, fit: fit, errorBuilder: (_, _, _) => placeholder);
  }
}

class _FullPhotoPage extends ConsumerWidget {
  const _FullPhotoPage({required this.photo});

  final PhotoRecord photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: FutureBuilder<Map<String, String>>(
        future: ref.watch(signedUrlCacheProvider).urls([photo.fullPath]),
        builder: (context, snapshot) => InteractiveViewer(
          child: RemoteImage(
            url: snapshot.data?[photo.fullPath],
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
  );
}
