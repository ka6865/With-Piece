import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/supabase/supabase_providers.dart';

import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/comment_repository.dart';
import 'album_providers.dart';
import 'comments.dart';
import 'pinch_columns.dart';

// 썸네일 격자. 서명 URL은 이 화면의 사진만 한 번에 묶어 받는다(설계 8.2)
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({
    super.key,
    required this.photos,
    this.onLongPress,
    this.allowSave = false,
  });

  final List<PhotoRecord> photos;
  final void Function(PhotoRecord photo)? onLongPress;
  final bool allowSave;

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
      builder: (context, snapshot) => PinchColumns(
        kind: 'album',
        defaultColumns: 3,
        builder: (context, columns) => GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (final (index, photo) in photos.indexed)
              Semantics(
                button: true,
                label: '사진 ${index + 1}',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FullPhotoPage(
                        photos: photos,
                        initialIndex: index,
                        userId: userId,
                        allowSave: allowSave,
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
              ),
          ],
        ),
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
    this.allowSave = false,
  });

  final List<PhotoRecord> photos;
  final int initialIndex;
  final String userId;
  final bool allowSave;

  @override
  ConsumerState<FullPhotoPage> createState() => _FullPhotoPageState();
}

class _FullPhotoPageState extends ConsumerState<FullPhotoPage> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;
  bool _saving = false;

  Future<void> _save(PhotoRecord photo) async {
    setState(() => _saving = true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final url = (await ref.read(signedUrlCacheProvider).urls([
        photo.fullPath,
      ]))[photo.fullPath];
      if (url == null) throw StateError('사진 주소가 없어요');
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('사진을 가져오지 못했어요');
      }
      final builder = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (builder.length + chunk.length > 10 * 1024 * 1024) {
          throw const HttpException('사진 파일이 너무 커요');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (!mounted || ref.read(sessionUserIdProvider) != widget.userId) return;
      await const MethodChannel(
        'kr.wooripiece/photo_export',
      ).invokeMethod<void>('save', bytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사진첩에 저장했어요')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사진을 저장하지 못했어요')));
      }
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _saving = false);
    }
  }

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
      appBar: AppBar(
        title: Text('${_index + 1} / $total'),
        actions: [
          if (widget.allowSave && Platform.isIOS)
            IconButton(
              tooltip: '사진첩에 저장',
              onPressed: _saving ? null : () => _save(widget.photos[_index]),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
            ),
          IconButton(
            tooltip: '사진 신고',
            onPressed: () => reportAlbumContent(
              context,
              ref,
              'photo',
              widget.photos[_index].id,
            ),
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
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
