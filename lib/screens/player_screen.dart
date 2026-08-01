import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';

import '../models/connection_info.dart';
import '../services/secure_client.dart';
import '../services/relay_server.dart';

class PlayerScreen extends StatefulWidget {
  final ConnectionInfo connection;
  final String relPath;
  final String name;
  final bool isVideo;

  const PlayerScreen({
    Key? key,
    required this.connection,
    required this.relPath,
    required this.name,
    required this.isVideo,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final SecureClient _secureClient;
  late final RelayServer _relay;

  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _secureClient = SecureClient(widget.connection);
    _relay = RelayServer(_secureClient);
    _setup();
  }

  Future<void> _setup() async {
    try {
      await _relay.start();
      final url = _relay.urlFor(widget.relPath);

      if (widget.isVideo) {
        final controller = VideoPlayerController.network(url);
        await controller.initialize();
        controller.play();
        setState(() {
          _videoController = controller;
          _loading = false;
        });
        controller.addListener(() => setState(() {}));
      } else {
        final player = AudioPlayer();
        await player.setUrl(url);
        player.play();
        setState(() {
          _audioPlayer = player;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Could not play this file.';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    _relay.stop();
    _secureClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
              : widget.isVideo
                  ? _buildVideo()
                  : _buildAudio(),
    );
  }

  Widget _buildVideo() {
    final controller = _videoController!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          VideoProgressIndicator(controller, allowScrubbing: true, padding: const EdgeInsets.all(12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 42,
                color: Colors.white,
                icon: Icon(controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                onPressed: () {
                  setState(() {
                    controller.value.isPlaying ? controller.pause() : controller.play();
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudio() {
    final player = _audioPlayer!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack, size: 100, color: Colors.pinkAccent),
            const SizedBox(height: 24),
            Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            StreamBuilder<Duration?>(
              stream: player.durationStream,
              builder: (context, durationSnap) {
                final duration = durationSnap.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, positionSnap) {
                    final position = positionSnap.data ?? Duration.zero;
                    return Column(
                      children: [
                        Slider(
                          value: position.inMilliseconds
                              .clamp(0, duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds)
                              .toDouble(),
                          max: duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds.toDouble(),
                          onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
                        ),
                        StreamBuilder<PlayerState>(
                          stream: player.playerStateStream,
                          builder: (context, stateSnap) {
                            final playing = stateSnap.data?.playing ?? false;
                            return IconButton(
                              iconSize: 56,
                              color: Colors.white,
                              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                              onPressed: () => playing ? player.pause() : player.play(),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
