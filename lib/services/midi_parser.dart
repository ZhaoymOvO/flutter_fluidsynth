import 'dart:io';
import 'dart:typed_data';

class TempoPoint {
  final int tick;
  final int microsecondsPerBeat;
  final double timeInSeconds;

  const TempoPoint({
    required this.tick,
    required this.microsecondsPerBeat,
    required this.timeInSeconds,
  });
}

class MidiFileInfo {
  final int division; // PPQ (ticks per quarter note)
  final List<TempoPoint> tempoPoints;
  final int format;
  final int trackCount;

  const MidiFileInfo({
    required this.division,
    required this.tempoPoints,
    required this.format,
    required this.trackCount,
  });

  /// Converts a tick count to elapsed seconds accurately based on the tempo map
  double tickToSeconds(int tick) {
    if (tick <= 0 || division <= 0) return 0.0;
    if (tempoPoints.isEmpty) {
      // Default: 120 BPM = 500,000 microseconds per beat
      return (tick * 0.5) / division;
    }

    // Binary search or linear scan for the latest tempo point at or before `tick`
    TempoPoint current = tempoPoints.first;
    for (int i = 1; i < tempoPoints.length; i++) {
      if (tempoPoints[i].tick <= tick) {
        current = tempoPoints[i];
      } else {
        break;
      }
    }

    final deltaTicks = tick - current.tick;
    final additionalSeconds = (deltaTicks * current.microsecondsPerBeat) / (division * 1000000.0);
    return current.timeInSeconds + additionalSeconds;
  }

  /// Converts seconds to ticks
  int secondsToTick(double seconds) {
    if (seconds <= 0 || division <= 0) return 0;
    if (tempoPoints.isEmpty) {
      return (seconds * division / 0.5).round();
    }

    TempoPoint current = tempoPoints.first;
    for (int i = 1; i < tempoPoints.length; i++) {
      if (tempoPoints[i].timeInSeconds <= seconds) {
        current = tempoPoints[i];
      } else {
        break;
      }
    }

    final deltaSeconds = seconds - current.timeInSeconds;
    final deltaTicks = (deltaSeconds * division * 1000000.0) / current.microsecondsPerBeat;
    return (current.tick + deltaTicks).round();
  }

  /// Parses a MIDI file from disk
  static Future<MidiFileInfo> parseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const MidiFileInfo(division: 480, tempoPoints: [], format: 1, trackCount: 1);
      }
      final bytes = await file.readAsBytes();
      return parseBytes(bytes);
    } catch (_) {
      return const MidiFileInfo(division: 480, tempoPoints: [], format: 1, trackCount: 1);
    }
  }

  /// Parses a MIDI file from raw bytes
  static MidiFileInfo parseBytes(Uint8List bytes) {
    if (bytes.length < 14) {
      return const MidiFileInfo(division: 480, tempoPoints: [], format: 1, trackCount: 1);
    }

    // Header Chunk 'MThd'
    if (bytes[0] != 0x4D || bytes[1] != 0x54 || bytes[2] != 0x68 || bytes[3] != 0x64) {
      return const MidiFileInfo(division: 480, tempoPoints: [], format: 1, trackCount: 1);
    }

    final headerLen = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
    final format = (bytes[8] << 8) | bytes[9];
    final tracks = (bytes[10] << 8) | bytes[11];
    int division = (bytes[12] << 8) | bytes[13];

    // Check if PPQ (bit 15 is 0) or SMPTE (bit 15 is 1)
    if ((division & 0x8000) != 0) {
      final fps = -(bytes[12].toSigned(8));
      final subFrames = bytes[13];
      division = fps * subFrames;
    }
    if (division <= 0) division = 480;

    final List<_RawTempoEvent> rawEvents = [];
    int offset = 8 + headerLen;
    int trackIndex = 0;

    while (offset + 8 <= bytes.length && trackIndex < tracks) {
      if (bytes[offset] == 0x4D &&
          bytes[offset + 1] == 0x54 &&
          bytes[offset + 2] == 0x72 &&
          bytes[offset + 3] == 0x6B) {
        // 'MTrk' chunk
        final trackLen = (bytes[offset + 4] << 24) |
            (bytes[offset + 5] << 16) |
            (bytes[offset + 6] << 8) |
            bytes[offset + 7];
        final trackEnd = (offset + 8 + trackLen).clamp(0, bytes.length);
        int ptr = offset + 8;
        int currentTick = 0;
        int runningStatus = 0;

        while (ptr < trackEnd) {
          // Read variable length delta time
          int delta = 0;
          while (ptr < trackEnd) {
            final b = bytes[ptr++];
            delta = (delta << 7) | (b & 0x7F);
            if ((b & 0x80) == 0) break;
          }
          currentTick += delta;

          if (ptr >= trackEnd) break;

          int status = bytes[ptr];
          if ((status & 0x80) != 0) {
            ptr++;
            runningStatus = status;
          } else {
            status = runningStatus;
          }

          if (status == 0xFF) {
            // Meta event
            if (ptr >= trackEnd) break;
            final metaType = bytes[ptr++];
            int metaLen = 0;
            while (ptr < trackEnd) {
              final b = bytes[ptr++];
              metaLen = (metaLen << 7) | (b & 0x7F);
              if ((b & 0x80) == 0) break;
            }

            if (metaType == 0x51 && metaLen == 3 && ptr + 3 <= trackEnd) {
              // Set Tempo: 3 bytes microseconds per quarter note
              final mpq = (bytes[ptr] << 16) | (bytes[ptr + 1] << 8) | bytes[ptr + 2];
              rawEvents.add(_RawTempoEvent(currentTick, mpq));
            }

            ptr += metaLen;
          } else if (status == 0xF0 || status == 0xF7) {
            // SysEx event
            int sysexLen = 0;
            while (ptr < trackEnd) {
              final b = bytes[ptr++];
              sysexLen = (sysexLen << 7) | (b & 0x7F);
              if ((b & 0x80) == 0) break;
            }
            ptr += sysexLen;
          } else {
            // Standard MIDI Channel Voice/Mode event
            final type = status & 0xF0;
            if (type == 0xC0 || type == 0xD0) {
              ptr += 1; // Program change, Channel pressure
            } else {
              ptr += 2; // Note on/off, Poly key pressure, CC, Pitch bend
            }
          }
        }
        offset = trackEnd;
        trackIndex++;
      } else {
        offset++;
      }
    }

    // Sort tempo events by tick
    rawEvents.sort((a, b) => a.tick.compareTo(b.tick));

    // Build timeline of TempoPoints
    final List<TempoPoint> points = [];
    int lastTick = 0;
    double accumulatedSeconds = 0.0;
    int currentMpq = 500000; // default 120 BPM

    if (rawEvents.isEmpty || rawEvents.first.tick > 0) {
      points.add(TempoPoint(tick: 0, microsecondsPerBeat: currentMpq, timeInSeconds: 0.0));
    }

    for (var ev in rawEvents) {
      if (ev.tick > lastTick) {
        accumulatedSeconds += ((ev.tick - lastTick) * currentMpq) / (division * 1000000.0);
        lastTick = ev.tick;
      }
      currentMpq = ev.microsecondsPerBeat;
      points.add(TempoPoint(
        tick: ev.tick,
        microsecondsPerBeat: currentMpq,
        timeInSeconds: accumulatedSeconds,
      ));
    }

    return MidiFileInfo(
      division: division,
      tempoPoints: points,
      format: format,
      trackCount: tracks,
    );
  }
}

class _RawTempoEvent {
  final int tick;
  final int microsecondsPerBeat;
  _RawTempoEvent(this.tick, this.microsecondsPerBeat);
}
