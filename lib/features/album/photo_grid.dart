import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';

import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/comment_repository.dart';
import 'album_providers.dart';
import 'comments.dart';

// 썸네일 격자. 서명 URL은 이 화면의 사진만 한 번에 묶어 받는다(설계 8.2)
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({super.key, required this.photos, this.onLongPress});

  final List<PhotoRecord> photos;
  final void Function(PhotoRecord photo)? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionUserIdProvider);
    if (userId == null || photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('아직 올린 사진이 없어요')),
      );
    }
    return FutureBuilder<Map<String, String>>(
      key: ValueKey(userId),
      future: ref.watch(signedUrlCacheProvider).urls([
        for (final p in photos) p.thumbPath,
      ]),
      builder: (context, snapshot) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: [
          for (final (index, photo) in photos.indexed)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullPhotoPage(
                    photos: photos,
                    initialIndex: index,
                    userId: userId,
                  ),
                ),
              ),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(photo),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: RemoteImage(url: snapshot.data?[photo.thumbPath]),
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

// 사진을 옆으로 넘겨 보고, 그 사진의 댓글을 바로 아래에 늘 보인다
class FullPhotoPage extends ConsumerStatefulWidget {
  const FullPhotoPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.userId,
  });

  final List<PhotoRecord> photos;
  final int initialIndex;
  final String userId;

  @override
  ConsumerState<FullPhotoPage> createState() => _FullPhotoPageState();
}

class _FullPhotoPageState extends ConsumerState<FullPhotoPage> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(sessionUserIdProvider) != widget.userId) {
      return const Scaffold(body: Center(child: Text('계정이 바뀌어 사진을 닫았어요')));
    }
    final total = widget.photos.length;
    return Scaffold(
      appBar: AppBar(title: Text('${_index + 1} / $total')),
      body: PageView.builder(
        controller: _pages,
        itemCount: total,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) {
          final photo = widget.photos[index];
          return ListView(
            children: [
              ColoredBox(
                color: Colors.black,
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.55,
                  child: FutureBuilder<Map<String, String>>(
                    key: ValueKey((widget.userId, photo.id)),
                    future: ref.watch(signedUrlCacheProvider).urls([
                      photo.fullPath,
                    ]),
                    builder: (context, snapshot) => InteractiveViewer(
                      child: RemoteImage(
                        url: snapshot.data?[photo.fullPath],
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: CommentSection(
                  kind: CommentKind.photo,
                  targetId: photo.id,
                  coupleId: photo.coupleId,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
