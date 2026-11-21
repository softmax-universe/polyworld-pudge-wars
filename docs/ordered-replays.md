# Ordered Pudge Wars replays

Replay format 7 and game version 39 store gameplay commands, chat, and control
changes in one ordered action stream. Chat records preserve the sender name,
roster slot, speaker team, text, and simulation tick. The visible chat ring is
a projection of that stream and does not change combat hashes.

Offline recordings store the resolved actions already executed by the game.
Network recordings mark admitted human and bot commands and retain their order
within each authoritative packet, including interleaved chat. Live play and
replay both dispatch those inputs through the same rotating hero-turn phases.
This preserves existing command execution and automatic target acquisition;
replay never invokes a bot VM. Control changes precede the packet inputs, and
local match notices follow them.

Seeking restores the world checkpoint, rebuilds chat and controller state from
the same action prefix, and moves the single playback cursor past that tick.
Repeated seeks do not append to the recording or duplicate visible messages.
Offline typed chat waits for the next simulation tick, so paused or historical
playback cannot insert messages into an already recorded tick.

This development format rejects older tapes. Archived replay viewers and their
matching assets remain separate and unchanged.
