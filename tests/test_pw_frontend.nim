import
  std/strutils,
  polyworld/rooms,
  ../examples/pudge_wars/[content, homes, lobbies, presets]

echo "Pudge Wars player and room names"
doAssert not confirmedPlayerName("")
doAssert not confirmedPlayerName("  player  ")
doAssert confirmedPlayerName("Player", explicit = true)
doAssert not confirmedPlayerName("Player\nTwo", explicit = true)
doAssert not confirmedPlayerName("Player\nTwo")
doAssert not confirmedPlayerName("\xff")
doAssert confirmedPlayerName("  Pudge  ")
doAssert confirmedPlayerName("Écorcheur")
doAssert confirmedPlayerName(repeat('a', 64))
doAssert not confirmedPlayerName(repeat('a', 65))
doAssert defaultRoomName("Pudge") == "Pudge's game"
doAssert defaultRoomName("Player") == ""
doAssert roomNameValid(repeat('r', 96))
doAssert not roomNameValid(repeat('r', 97))

echo "Pudge Wars invitation parsing"
doAssert not opensMultiplayer(" \t")
doAssert opensMultiplayer("room42")
doAssert parseInvite(" room42 ") == ("", "room42")
doAssert parseInvite("polyworld://join?server=wss%3A%2F%2Frelay.test" &
  "%2Fws&room=room42#unused") == ("wss://relay.test/ws", "room42")
for invalid in ["", "https://play.test?server=local", "room\n42", repeat('X', 65)]:
  try:
    discard parseInvite(invalid)
    doAssert false, "Accepted invalid invite " & invalid
  except RoomsError:
    discard

echo "Pudge Wars seat cards retain their bank and position across resizing"
var config = defaultConfig()
for teamSize in 1 .. MaxTeamSize:
  config.teamSize = teamSize
  doAssert not config.seatEnabled(-1)
  doAssert not config.seatEnabled(MaxPudgeCount)
  for i in 0 ..< MaxTeamSize:
    let enabled = i < teamSize
    doAssert config.seatEnabled(i) == enabled
    doAssert config.seatEnabled(i + MaxTeamSize) == enabled

echo "Both banks can start with sparse seats"
var seats: array[MaxPudgeCount, Seat]
seats[0] = Seat(owner: 1, kind: HumanSeat, name: "Pudge")
seats[6] = Seat(owner: 2, kind: BotSeat, name: "Human")
config.teamSize = 2
doAssert config.opposingBanks(seats)
doAssert config.excludedSeat(seats) == -1
config.teamSize = 1
doAssert not config.opposingBanks(seats)
doAssert config.excludedSeat(seats) == 6

echo "A claim racing a bank shrink must be cleared or included again"
seats[5] = Seat(owner: 3, kind: HumanSeat, name: "East player")
doAssert config.opposingBanks(seats)
doAssert config.excludedSeat(seats) == 6
try:
  config.validateRoster(seats)
  doAssert false, "An occupied inactive seat cannot start a match"
except RoomsError:
  discard
config.teamSize = 2
config.validateRoster(seats)
doAssert config.excludedSeat(seats) == -1
config.teamSize = 1
seats[6] = Seat()
doAssert config.excludedSeat(seats) == -1
config.validateRoster(seats)

when not defined(headless):
  import std/tables, silky

  echo "Pudge Wars menu artwork packs with the shared sprite names"
  let builder = newAtlasBuilder(2048, 4)
  builder.addPudgeHomeAssets()
  doAssert "home-shade" in builder.atlas.entries
  for key in MenuImages:
    doAssert "home-" & key in builder.atlas.entries
