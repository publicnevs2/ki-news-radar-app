import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

// Globale Instanz des Audio Handlers
late AudioHandler audioHandler;

/// Initialisiert den AudioService und verbindet ihn mit unserem AudioPlayerHandler.
Future<void> initAudioHandler() async {
  audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'de.sven.ki_news_radar.audio',
      androidNotificationChannelName: 'KI-News-Radar Wiedergabe',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

/// Diese Klasse verwaltet die eigentliche Audio-Logik.
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  AudioPlayerHandler() {
    // Leite die Player-Status-Änderungen an den AudioService weiter,
    // damit die UI und die Systembenachrichtigung aktualisiert werden.
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    // Speichere das aktuelle Item, damit die UI es anzeigen kann.
    this.mediaItem.add(mediaItem);
    try {
      await _player.setUrl(mediaItem.id); // Die URL ist die ID
      play();
    } catch (e) {
      print("Error loading audio source: $e");
    }
  }

  /// Transformiert die Events von `just_audio` in ein Standardformat für `audio_service`.
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.pause,
        MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.playPause,
      },
      androidCompactActionIndices: const [0, 1],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
