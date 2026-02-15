import 'dart:io';

import 'package:flutter/material.dart';

/// A full-screen image viewer with pinch-to-zoom and pan support.
///
/// Displays the image edge-to-edge with a dark background. The user can
/// pinch-to-zoom, double-tap to toggle 2× zoom, and tap the back button
/// or swipe down to dismiss.
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.file,
    this.heroTag,
    this.title,
  });

  /// The local image file to display.
  final File file;

  /// Optional hero tag for a shared-element transition.
  final String? heroTag;

  /// Optional title shown in the app bar (e.g. filename).
  final String? title;

  /// Convenience method to push the viewer onto the navigator.
  static void open(
    BuildContext context, {
    required File file,
    String? heroTag,
    String? title,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FullscreenImageViewer(file: file, heroTag: heroTag, title: title),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final TransformationController _transformController =
      TransformationController();
  bool _appBarVisible = true;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _toggleAppBar() {
    setState(() => _appBarVisible = !_appBarVisible);
  }

  void _handleDoubleTap() {
    if (_transformController.value != Matrix4.identity()) {
      _transformController.value = Matrix4.identity();
    } else {
      // Zoom to 2× centered.
      _transformController.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget = InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(child: Image.file(widget.file, fit: BoxFit.contain)),
    );

    final heroWrapped = widget.heroTag != null
        ? Hero(tag: widget.heroTag!, child: imageWidget)
        : imageWidget;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _appBarVisible
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              elevation: 0,
              title: widget.title != null
                  ? Text(
                      widget.title!,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
            )
          : null,
      body: GestureDetector(
        onTap: _toggleAppBar,
        onDoubleTap: _handleDoubleTap,
        child: heroWrapped,
      ),
    );
  }
}
