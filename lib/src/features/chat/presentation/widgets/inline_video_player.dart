import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A self-contained inline video player widget that uses chewie for controls.
///
/// Displays a thumbnail-like preview with a play button. When tapped, opens
/// a full-screen chewie player. Disposes controllers automatically.
class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.filePath,
    this.filename = '',
    this.maxWidth = 240,
    this.maxHeight = 180,
  });

  final String filePath;
  final String filename;
  final double maxWidth;
  final double maxHeight;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _videoController;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final controller = VideoPlayerController.file(File(widget.filePath));
    _videoController = controller;
    try {
      await controller.initialize();
      if (mounted) {
        setState(() => _initialized = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildPlaceholder(
        context,
        icon: Icons.broken_image,
        label: widget.filename.isNotEmpty ? widget.filename : 'Video',
      );
    }

    if (!_initialized || _videoController == null) {
      return _buildPlaceholder(
        context,
        icon: Icons.videocam,
        label: widget.filename.isNotEmpty ? widget.filename : 'Loading...',
        showSpinner: true,
      );
    }

    final controller = _videoController!;
    final aspectRatio = controller.value.aspectRatio;

    return GestureDetector(
      onTap: () => _openFullScreenPlayer(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: widget.maxHeight,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
                child: VideoPlayer(controller),
              ),
              // Dark overlay
              Positioned.fill(
                child: Container(color: Colors.black38),
              ),
              // Play button
              const Icon(
                Icons.play_circle_fill,
                size: 48,
                color: Colors.white,
              ),
              // Filename at bottom
              if (widget.filename.isNotEmpty)
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: Text(
                    widget.filename,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Duration badge
              if (controller.value.duration.inSeconds > 0)
                Positioned(
                  top: 6,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(controller.value.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String label,
    bool showSpinner = false,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        maxHeight: widget.maxHeight,
      ),
      child: Container(
        width: widget.maxWidth,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showSpinner)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              Icon(icon, size: 32, color: Colors.white70),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreenPlayer(BuildContext context) {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenVideoPage(
          videoController: controller,
          title: widget.filename,
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

/// Full-screen page with chewie controls for a video.
class _FullScreenVideoPage extends StatefulWidget {
  const _FullScreenVideoPage({
    required this.videoController,
    required this.title,
  });

  final VideoPlayerController videoController;
  final String title;

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  late final ChewieController _chewieController;

  @override
  void initState() {
    super.initState();
    _chewieController = ChewieController(
      videoPlayerController: widget.videoController,
      autoPlay: true,
      looping: false,
      showControlsOnInitialize: true,
      allowFullScreen: false, // already full-screen
    );
  }

  @override
  void dispose() {
    // Only dispose chewie, NOT the video controller (owned by InlineVideoPlayer).
    _chewieController.dispose();
    // Pause when leaving the full-screen page.
    widget.videoController.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: Chewie(controller: _chewieController),
      ),
    );
  }
}
