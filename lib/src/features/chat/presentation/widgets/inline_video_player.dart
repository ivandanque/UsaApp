import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A self-contained inline video player widget.
///
/// Displays a thumbnail-like preview with a play button. When tapped, opens
/// a full-screen player with custom controls. Disposes controllers automatically.
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
              Positioned.fill(child: Container(color: Colors.black38)),
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
              // Duration badge
              if (controller.value.duration.inSeconds > 0)
                Positioned(
                  top: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(controller.value.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
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

/// Full-screen page with custom controls for a video.
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
  bool _isPlaying = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    widget.videoController.addListener(_onVideoUpdate);
    // Auto-play on open.
    widget.videoController.play();
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final playing = widget.videoController.value.isPlaying;
    if (playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    } else {
      // Rebuild for position updates.
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.videoController.removeListener(_onVideoUpdate);
    widget.videoController.pause();
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
    final vc = widget.videoController;
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

                    // Overlay controls (shown on tap)
                    if (_showControls)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [_buildControls(vc, duration, position)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }

          // ── Portrait: video at top, controls right below ──
          return SafeArea(
            child: Column(
              children: [
                // Video centered in available space
                AspectRatio(
                  aspectRatio: aspect,
                  child: Container(color: Colors.black, child: VideoPlayer(vc)),
                ),

                // Controls immediately below video
                _buildControls(vc, duration, position),

                // Spacer to push everything up
                const Spacer(),
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
