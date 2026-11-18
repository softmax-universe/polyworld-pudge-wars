import
  std/strutils,
  polyworld/rooms,
  ../examples/pudge_wars/[content, homes, lobbies]

echo "Pudge Wars player and room names"
doAssert not confirmedPlayerName("")
doAssert not confirmedPlayerName("  player  ")
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
for before in 1 .. MaxTeamSize:
  for after in 1 .. MaxTeamSize:
    for seat in 0 ..< before * 2:
      let card = displaySeat(seat, before)
      doAssert lobbySeat(card, before) == seat
      let resized = lobbySeat(card, after)
      if seat mod before >= after:
        doAssert resized == -1
      else:
        doAssert resized div after == seat div before
        doAssert resized mod after == seat mod before

echo "Both banks can start with sparse seats"
let seats = [Seat(owner: 1), Seat(), Seat(), Seat(), Seat(), Seat(owner: 2)]
doAssert opposingBanks(seats, 3)
doAssert not opposingBanks(seats[0 .. 4], 3)
doAssert not opposingBanks([Seat(), Seat(owner: 2)], 1)

when not defined(headless):
  import std/tables, silky

  echo "Pudge Wars menu artwork packs with the shared sprite names"
  let builder = newAtlasBuilder(2048, 4)
  builder.addPudgeHomeAssets()
  doAssert "home-shade" in builder.atlas.entries
  for key in MenuImages:
    doAssert "home-" & key in builder.atlas.entries
