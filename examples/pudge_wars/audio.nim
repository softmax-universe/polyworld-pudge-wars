## Pudge Wars combat effects use Polyworld's shared device and mix settings.

import
  polyworld/[sounddevices, sounds],
  content

type
  GameSound* = enum
    SndHookThrow
    SndHookLatch
    SndHookClash
    SndMelee
    SndKill
    SndDeath

const
  EffectFiles: array[GameSound, string] = [
    "hook_throw",
    "hook_latch",
    "hook_clash",
    "melee",
    "kill",
    "death"
  ]
  FirstGameSoundBuffer = SoundBufferLimit - EffectFiles.len

static:
  doAssert SoundClips.len <= FirstGameSoundBuffer

proc initGameAudio*(muted: bool) =
  ## Preloads Pudge's recordings before the shared mixer seals its buffers.
  setSoundMuted(muted)
  if not openSoundDevice():
    return
  for kind in GameSound:
    let path = soundPath(EffectFiles[kind])
    if not loadSoundBuffer(FirstGameSoundBuffer + kind.ord, path):
      echo "Cannot load sound: ", path
  initSounds()

proc closeGameAudio*() =
  ## Releases the application's shared audio device.
  closeSounds()

proc stopGameAudio*() =
  ## Stops active effects between matches.
  stopSounds()

proc tickGameAudio*() =
  ## Updates the shared mixer after an audio device interruption.
  updateSounds()

proc gameAudioMuted*(): bool =
  ## Reports the shared mute state.
  soundsMuted()

proc toggleGameAudioMute*() =
  ## Changes session mute without changing saved volume levels.
  setSoundMuted(not soundsMuted())

proc playGameSound*(kind: GameSound, gain = 1.0'f) =
  ## Plays the recorded clip using the shared effects volume.
  discard startSoundVoice(FirstGameSoundBuffer + kind.ord, gain, 0, ui = false)
