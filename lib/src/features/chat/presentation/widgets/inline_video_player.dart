import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

/// A self-contained inline video player widget.
///
/// Displays a lightweight thumbnail placeholder with a play button. When
/// tapped, opens a full-screen player that creates its own
/// [VideoPlayerController]. This avoids allocating expensive native video
/// decoders for every video visible in a chat list, preventing OOM crashes
/// on mid-range devices.
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
  double? _thumbnailAspect;
  Uint8List? _thumbnailBytes;
  bool _thumbnailFailed = false;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  @override
  void didUpdateWidget(covariant InlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumbnailAspect = null;
      _thumbnailBytes = null;
      _thumbnailFailed = false;
      _generateThumbnail();
    }
  }

  /// Uses [video_thumbnail] to extract a JPEG thumbnail and a short-lived
  /// [VideoPlayerController] solely to read aspect ratio.  Both are cheap
  /// and disposed immediately, keeping native decoder lifetime minimal.
  Future<void> _generateThumbnail() async {
    VideoPlayerController? tempController;
    try {
      // 1. Extract thumbnail bytes (native, no persistent decoder).
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: widget.filePath,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: widget.maxWidth.toInt() * 2, // 2x for sharpness
        quality: 75,
      );

      // 2. Read aspect ratio via a short-lived controller.
      tempController = VideoPlayerController.file(File(widget.filePath));
      await tempController.initialize();
      final aspect = tempController.value.aspectRatio;
      await tempController.dispose();
      tempController = null;

      if (!mounted) return;
      setState(() {
        _thumbnailBytes = bytes;
        _thumbnailAspect = aspect;
      });
    } catch (_) {
      await tempController?.dispose();
      if (mounted) setState(() => _thumbnailFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailFailed) {
      return _buildPlaceholder(
        context,
        icon: Icons.broken_image,
        label: widget.filename.isNotEmpty ? widget.filename : 'Video',
      );
    }

    final aspect = _thumbnailAspect;
    if (aspect == null) {
      return _buildPlaceholder(
        context,
        icon: Icons.videocam,
        label: widget.filename.isNotEmpty ? widget.filename : 'Loading...',
        showSpinner: true,
      );
    }

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
                aspectRatio: aspect > 0 ? aspect : 16 / 9,
                child: _thumbnailBytes != null
                    ? Image.memory(
                        _thumbnailBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(color: Colors.black),
              ),
              // Play button
              const Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
              // Filename at bottom
              if (widget.filename.isNotEmpty)
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: Text(
                    widget.filename,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullScreenVideoPage(
          filePath: widget.filePath,
          title: widget.filename,
        ),
      ),
    );
  }
}

/// Full-screen page with custom controls for a video.
///
/// Creates and owns its own [VideoPlayerController] — the controller is
/// allocated when the page opens and fully disposed when it closes, so no
/// native video decoder lives longer than this route.
class _FullScreenVideoPage extends StatefulWidget {
  const _FullScreenVideoPage({required this.filePath, required this.title});

  final String filePath;
  final String title;

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final vc = VideoPlayerController.file(File(widget.filePath));
    _controller = vc;
    try {
      await vc.initialize();
      if (!mounted) {
        await vc.dispose();
        return;
      }
      vc.addListener(_onVideoUpdate);
      await vc.play();
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final vc = _controller;
    if (vc == null) return;
    final playing = vc.value.isPlaying;
    if (playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    } else {
      // Rebuild for position updates.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final vc = _controller;

    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        ),
        body: const Center(
          child: Text(
            'Unable to play video',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (vc == null || !vc.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final value = vc.value;
    final duration = value.duration;
    final position = value.position;
    final aspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;

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
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;

          if (isLandscape) {
            // ── Landscape: fullscreen video with overlay controls ──
            return SafeArea(
              child: GestureDetector(
                onTap: _toggleControls,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    // Video fills the screen
                    Center(
                      child: AspectRatio(
                        aspectRatio: aspect,
                        child: VideoPlayer(vc),
                      ),
                    ),

                    // Overlay controls (shown on tap) - only darken the bottom section
                    if (_showControls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.5),
                          child: _buildControls(vc, duration, position),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          // ── Portrait: video + controls centered as a group ──
          return SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Video — use Flexible + ConstrainedBox so it shrinks
                // when the screen is too short, preventing bottom overflow.
                Flexible(
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: Container(
                      color: Colors.black,
                      child: VideoPlayer(vc),
                    ),
                  ),
                ),

                // Controls immediately below video
                _buildControls(vc, duration, position),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls(
    VideoPlayerController vc,
    Duration duration,
    Duration position,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrubbing bar
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 3,
            ),
            child: Slider(
              min: 0,
              max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
              value: position.inMilliseconds.toDouble().clamp(
                0,
                duration.inMilliseconds.toDouble(),
              ),
              onChanged: (v) {
                vc.seekTo(Duration(milliseconds: v.toInt()));
              },
            ),
          ),

          // Time + play/pause row
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: () {
                  _isPlaying ? vc.pause() : vc.play();
                },
              ),
              const SizedBox(width: 4),
              Text(
                '${_fmt(position)} / ${_fmt(duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
