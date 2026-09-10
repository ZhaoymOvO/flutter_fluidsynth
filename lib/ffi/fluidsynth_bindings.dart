import 'dart:ffi';
import 'package:ffi/ffi.dart';

// Opaque FluidSynth structures
final class FluidSettings extends Opaque {}
final class FluidSynth extends Opaque {}
final class FluidAudioDriver extends Opaque {}
final class FluidPlayer extends Opaque {}
final class FluidSFont extends Opaque {}

// Player status enum matching fluidsynth/midi.h
abstract class FluidPlayerStatus {
  static const int ready = 0;
  static const int playing = 1;
  static const int stopping = 2;
  static const int done = 3;
}

/// Dart FFI Bindings for FluidSynth C API
class FluidSynthBindings {
  final DynamicLibrary lib;

  // Settings
  late final Pointer<FluidSettings> Function() newFluidSettings;
  late final void Function(Pointer<FluidSettings>) deleteFluidSettings;
  late final int Function(Pointer<FluidSettings>, Pointer<Utf8>, Pointer<Utf8>) fluidSettingsSetStr;
  late final int Function(Pointer<FluidSettings>, Pointer<Utf8>, int) fluidSettingsSetInt;
  late final int Function(Pointer<FluidSettings>, Pointer<Utf8>, double) fluidSettingsSetNum;

  // Synth
  late final Pointer<FluidSynth> Function(Pointer<FluidSettings>) newFluidSynth;
  late final void Function(Pointer<FluidSynth>) deleteFluidSynth;
  late final int Function(Pointer<FluidSynth>, Pointer<Utf8>, int) fluidSynthSfLoad;
  late final int Function(Pointer<FluidSynth>, int, int) fluidSynthSfUnload;
  late final void Function(Pointer<FluidSynth>, double) fluidSynthSetGain;
  late final int Function(Pointer<FluidSynth>, int, int, int) fluidSynthNoteOn;
  late final int Function(Pointer<FluidSynth>, int, int) fluidSynthNoteOff;
  late final int Function(Pointer<FluidSynth>, int) fluidSynthAllNotesOff;
  late final int Function(Pointer<FluidSynth>, int) fluidSynthAllSoundsOff;
  late final int Function(Pointer<FluidSynth>) fluidSynthSystemReset;

  // Audio Driver
  late final Pointer<FluidAudioDriver> Function(Pointer<FluidSettings>, Pointer<FluidSynth>) newFluidAudioDriver;
  late final void Function(Pointer<FluidAudioDriver>) deleteFluidAudioDriver;

  // Player
  late final Pointer<FluidPlayer> Function(Pointer<FluidSynth>) newFluidPlayer;
  late final void Function(Pointer<FluidPlayer>) deleteFluidPlayer;
  late final int Function(Pointer<FluidPlayer>, Pointer<Utf8>) fluidPlayerAdd;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerPlay;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerStop;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerJoin;
  late final int Function(Pointer<FluidPlayer>, int) fluidPlayerSeek;
  late final int Function(Pointer<FluidPlayer>, int) fluidPlayerSetLoop;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerGetStatus;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerGetCurrentTick;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerGetTotalTicks;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerGetBpm;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerGetDivision;
  late final int Function(Pointer<FluidPlayer>) fluidPlayerGetMidiTempo;

  // Version
  late final Pointer<Utf8> Function() fluidVersionStr;

  FluidSynthBindings(this.lib) {
    // Settings
    newFluidSettings = lib
        .lookup<NativeFunction<Pointer<FluidSettings> Function()>>('new_fluid_settings')
        .asFunction();

    deleteFluidSettings = lib
        .lookup<NativeFunction<Void Function(Pointer<FluidSettings>)>>('delete_fluid_settings')
        .asFunction();

    fluidSettingsSetStr = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSettings>, Pointer<Utf8>, Pointer<Utf8>)>>('fluid_settings_setstr')
        .asFunction();

    fluidSettingsSetInt = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSettings>, Pointer<Utf8>, Int32)>>('fluid_settings_setint')
        .asFunction();

    fluidSettingsSetNum = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSettings>, Pointer<Utf8>, Double)>>('fluid_settings_setnum')
        .asFunction();

    // Synth
    newFluidSynth = lib
        .lookup<NativeFunction<Pointer<FluidSynth> Function(Pointer<FluidSettings>)>>('new_fluid_synth')
        .asFunction();

    deleteFluidSynth = lib
        .lookup<NativeFunction<Void Function(Pointer<FluidSynth>)>>('delete_fluid_synth')
        .asFunction();

    fluidSynthSfLoad = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>, Pointer<Utf8>, Int32)>>('fluid_synth_sfload')
        .asFunction();

    fluidSynthSfUnload = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>, Int32, Int32)>>('fluid_synth_sfunload')
        .asFunction();

    fluidSynthSetGain = lib
        .lookup<NativeFunction<Void Function(Pointer<FluidSynth>, Float)>>('fluid_synth_set_gain')
        .asFunction();

    fluidSynthNoteOn = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>, Int32, Int32, Int32)>>('fluid_synth_noteon')
        .asFunction();

    fluidSynthNoteOff = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>, Int32, Int32)>>('fluid_synth_noteoff')
        .asFunction();

    fluidSynthAllNotesOff = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>, Int32)>>('fluid_synth_all_notes_off')
        .asFunction();

    fluidSynthAllSoundsOff = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>, Int32)>>('fluid_synth_all_sounds_off')
        .asFunction();

    fluidSynthSystemReset = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidSynth>)>>('fluid_synth_system_reset')
        .asFunction();

    // Audio Driver
    newFluidAudioDriver = lib
        .lookup<NativeFunction<Pointer<FluidAudioDriver> Function(Pointer<FluidSettings>, Pointer<FluidSynth>)>>('new_fluid_audio_driver')
        .asFunction();

    deleteFluidAudioDriver = lib
        .lookup<NativeFunction<Void Function(Pointer<FluidAudioDriver>)>>('delete_fluid_audio_driver')
        .asFunction();

    // Player
    newFluidPlayer = lib
        .lookup<NativeFunction<Pointer<FluidPlayer> Function(Pointer<FluidSynth>)>>('new_fluid_player')
        .asFunction();

    deleteFluidPlayer = lib
        .lookup<NativeFunction<Void Function(Pointer<FluidPlayer>)>>('delete_fluid_player')
        .asFunction();

    fluidPlayerAdd = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>, Pointer<Utf8>)>>('fluid_player_add')
        .asFunction();

    fluidPlayerPlay = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_play')
        .asFunction();

    fluidPlayerStop = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_stop')
        .asFunction();

    fluidPlayerJoin = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_join')
        .asFunction();

    fluidPlayerSeek = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>, Int32)>>('fluid_player_seek')
        .asFunction();

    fluidPlayerSetLoop = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>, Int32)>>('fluid_player_set_loop')
        .asFunction();

    fluidPlayerGetStatus = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_get_status')
        .asFunction();

    fluidPlayerGetCurrentTick = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_get_current_tick')
        .asFunction();

    fluidPlayerGetTotalTicks = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_get_total_ticks')
        .asFunction();

    fluidPlayerGetBpm = lib
        .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_get_bpm')
        .asFunction();

    try {
      fluidPlayerGetDivision = lib
          .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_get_division')
          .asFunction();
    } catch (_) {
      fluidPlayerGetDivision = (p) => 480;
    }

    try {
      fluidPlayerGetMidiTempo = lib
          .lookup<NativeFunction<Int32 Function(Pointer<FluidPlayer>)>>('fluid_player_get_midi_tempo')
          .asFunction();
    } catch (_) {
      fluidPlayerGetMidiTempo = (p) => 500000;
    }

    // Version
    fluidVersionStr = lib
        .lookup<NativeFunction<Pointer<Utf8> Function()>>('fluid_version_str')
        .asFunction();
  }
}
