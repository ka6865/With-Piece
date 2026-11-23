import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

// 사진첩 사진을 고르는 중에 크게 본다. 좌우로 넘기고 두 손가락으로 확대하며, 이 화면에서도
// 고르거나 뺀다. 기기 안의 사진만 읽고 서버로 보내지 않는다(설계 3.4)
class LocalPhotoViewerPage extends StatefulWidget {
  const LocalPhotoViewerPage({
    super.key,
    required this.ids,
    required this.initialIndex,
    required this.selected,
    required this.onChanged,
  });

  // 화면 긴 변에 맞춰 충분히 선명하고 원본보다 가볍다
  static const side = 1600;

  // 테스트가 사진첩 없이 바꿔 끼운다
  @visibleForTesting
  static Future<Uint8List?> Function(String id) loader = (id) =>
      AssetEntity.fromId(
        id,
      ).then((a) => a?.thumbnailDataWithSize(const ThumbnailSize(side, side)));

  final List<String> ids;
  final int initialIndex;
  final Set<String> selected;
  // null이면 고를 수 없다(올리는 중)
  final ValueChanged<Set<String>>? onChanged;

  @override
  State<LocalPhotoViewerPage> createState() => _LocalPhotoViewerPageState();
}

class _LocalPhotoViewerPageState extends State<LocalPhotoViewerPage> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late var _index = widget.initialIndex;
  late var _selected = widget.selected;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _toggle() {
    final id = widget.ids[_index];
    setState(
      () => _selected = _selected.contains(id)
          ? _selected.difference({id})
          : {..._selected, id},
    );
    widget.onChanged!(_selected);
  }

  @override
  Widget build(BuildContext context) {
    final picked = _selected.contains(widget.ids[_index]);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.ids.length}'),
        actions: [
          if (widget.onChanged != null)
            IconButton(
              tooltip: picked ? '고르기 해제' : '고르기',
              icon: Icon(
                picked ? Icons.check_circle : Icons.radio_button_unchecked,
              ),
              onPressed: _toggle,
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.ids.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (context, index) => InteractiveViewer(
          maxScale: 5,
          child: _LargeImage(id: widget.ids[index]),
        ),
      ),
    );
  }
}

class _LargeImage extends StatefulWidget {
  const _LargeImage({required this.id});

  final String id;

  @override
  State<_LargeImage> createState() => _LargeImageState();
}

class _LargeImageState extends State<_LargeImage> {
  late final Future<Uint8List?> _bytes = LocalPhotoViewerPage.loader(
    widget.id,
  ).catchError((Object _) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _bytes,
    builder: (context, snapshot) => switch (snapshot) {
      AsyncSnapshot(data: final bytes?) => Image.memory(
        bytes,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
      AsyncSnapshot(connectionState: ConnectionState.done) => const Center(
        child: Text('사진을 열 수 없어요', style: TextStyle(color: Colors.white)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    },
  );
}
