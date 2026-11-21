## Pudge Wars WAV clips load through the engine sound module.

import
  polyworld/sounddevices,
  ../examples/pudge_wars/content

echo "Testing recorded clips upload when a device exists"
if openSoundDevice():
  for index, name in ["hook_throw", "hook_latch", "splash", "voice_laugh"]:
    doAssert loadSoundBuffer(index, soundPath(name)),
      "failed to load " & soundPath(name)
  closeSoundDevice()
  echo "  uploaded hook, latch, splash, and voice"
else:
  echo "  no output device, skipped upload"

echo "test_pw_audio: all checks passed"
