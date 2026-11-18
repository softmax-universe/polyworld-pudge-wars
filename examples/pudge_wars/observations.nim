## Fog-filtered observations and action receipts for local JSON policies.

import
  std/[json, math, tables],
  polyworld/pathing,
  content, maps, sim, replays, fog

type ObservationEcho* = object
  lastAccepted: seq[JsonNode]
  sentKeys: seq[Table[string, bool]]
  rotMatched: seq[bool]

proc tileCoord(p: WorldPoint): tuple[x, y: float] =
  ## Convert a simulation position to tile coordinates.
  (
    float(p.x) / float(WorldScale) + float(GridTiles div 2),
    float(p.z) / float(WorldScale) + float(GridTiles div 2)
  )

proc fogCanSee(world: World, team: Team, position: WorldPoint): bool =
  ## Check the visibility of a position for an entire bank.
  fogCanSeeTeam(world, team.ord, position)

proc pudgeJson(game: Game, pudge: Pudge, slot: int): JsonNode =
  ## Serialize a butcher and its last printed line.
  let
    world = game.world
    pos = tileCoord(pudge.position)
    home = pudge.spawnTile
    blinkReady =
      pudge.blinkCooldown <= 0 and pudge.windupTicks <= 0 and
      pudge.hookedBy == 0 and not world.rotAffected(pudge)
    buffOrd =
      if pudge.buffTicks > 0: int(pudge.buffKind.ord) + 1 else: 0
  var upgrades = newJArray()
  for kind in UpgradeKind:
    upgrades.add %pudge.upgrades[kind]
  var itemRanks = newJArray()
  for item in ShopBoots .. ShopWard:
    itemRanks.add %pudge.itemRank[item]
  # Preserve the print line and its tick for policy and replay analysis.
  var sayNode = newJNull()
  var sayTick = -1'i32
  if slot >= 0 and slot < game.botSpeech.len and
      game.botSpeech[slot].text.len > 0:
    sayNode = %game.botSpeech[slot].text
    sayTick = game.botSpeech[slot].tick
  result = %*{
    "id": pudge.id,
    "slot": slot,
    "team": pudge.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "hp": max(pudge.hp, 0),
    "max_hp": pudge.maxHp,
    "alive": pudge.state == Alive,
    "hooked": pudge.hookedBy != 0,
    "shield": max(pudge.shieldTicks, 0),
    "hook_ready": pudge.hookCooldown <= 0 and pudge.windupTicks <= 0,
    "blink_ready": blinkReady,
    "rot": pudge.rotOn,
    "layer": pudge.layer,
    "gold": pudge.gold,
    "points": pudge.points,
    "in_shop": pudge.inOwnShop,
    "kills": pudge.kills,
    "in_river": pudge.inRiver,
    "home_x": home.x,
    "home_y": home.z,
    "upgrades": upgrades,
    "item_ranks": itemRanks,
    "items": itemRanks,
    "ward_restock": max(pudge.wardCooldown, 0),
    "buff": buffOrd,
    "say": sayNode,
    "say_tick": sayTick
  }

proc hookJson(world: World, hook: Hook): JsonNode =
  ## Serialize a visible hook and its owner.
  let
    pos = tileCoord(hook.position)
    owner = world.pudgeIndex(hook.ownerId)
    ownerSlot = if owner >= 0: owner else: 0
  %*{
    "owner": ownerSlot,
    "owner_id": hook.ownerId,
    "team": hook.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "victim": hook.victimId,
    "flying": hook.phase == HookFlying,
    "lightning": hook.lightning
  }

proc fireJson(patch: FirePatch): JsonNode =
  ## Serialize one lightning fire patch.
  let pos = tileCoord(patch.position)
  %*{
    "owner_id": patch.ownerId,
    "team": patch.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "ticks": patch.ticksLeft
  }

proc runeJson(rune: Rune): JsonNode =
  ## Serialize one visible rune.
  let pos = tileCoord(rune.position)
  %*{
    "id": rune.id,
    "kind": rune.kind.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3)
  }

proc runeNextJson(world: World): JsonNode =
  ## Public drop clock. Same numbers BASIC `runeSoon` / `runeNext*` see.
  let soon = runeSoonTicks(world)
  if soon <= 0:
    return %*{"soon": 0, "kind": -1, "x": -1, "y": -1}
  %*{
    "soon": soon,
    "kind": world.nextRuneKind.ord,
    "x": RiverCenterX,
    "y": world.nextRuneZTile
  }

proc propJson(prop: Prop): JsonNode =
  ## Serialize a visible wall, mine or ward.
  let pos = tileCoord(prop.propCenter)
  %*{
    "id": prop.id,
    "kind":
      case prop.kind
      of PropWall: "wall"
      of PropMine: "mine"
      of PropWard: "ward",
    "team": prop.team.ord,
    "x": round(pos.x, 3),
    "y": round(pos.y, 3),
    "hp": max(prop.hp, 0)
  }

proc scoreNode(world: World): JsonNode =
  ## Serialize the scores for both banks.
  %*{
    "west": world.teamKills[WestTeam.ord],
    "east": world.teamKills[EastTeam.ord]
  }

proc winnerName(world: World): string =
  ## Give the winning bank name once the match reaches the goal.
  if not world.gameOver:
    return ""
  if world.winner == WestTeam: "west" else: "east"

proc intentActionKey(kind: IntentKind): string =
  ## Map result kinds to the corresponding JSON action keys.
  case kind
  of IntentWalk: "walk_to"
  of IntentHook, IntentHookFine: "hook_to"
  of IntentBlink, IntentBlinkFine: "blink_to"
  of IntentGrapple, IntentGrappleFine: "grapple_to"
  of IntentAttack: "attack_target"
  of IntentBuy: "buy_upgrade"
  of IntentBuyPower: "buy_power"
  of IntentStop: "halt"
  of IntentPing: "ping"
  of IntentPlaceWall: "place_wall"
  of IntentPlaceMine: "place_mine"
  of IntentPlaceWard: "place_ward"
  of IntentRot: "rot"
  of IntentCheat: ""

proc hookInFlight(world: World, ownerId: int32): bool =
  ## Check whether the butcher owns an active hook.
  for hook in world.hooks:
    if hook.ownerId == ownerId and hook.phase != HookIdle:
      return true
  false

proc intentRejectReason(game: Game, slot: int, kind: IntentKind, itemId = 0'i32): string =
  ## Classify a rejected intent from the butcher state after the attempt.
  if slot < 0 or slot >= game.world.pudges.len:
    return "rejected"
  let hero = game.world.pudges[slot]
  if hero.state == Dying:
    return "dead"
  case kind
  of IntentHook, IntentHookFine:
    if hero.windupTicks > 0: "casting"
    elif hookInFlight(game.world, hero.id): "flight"
    elif hero.hookCooldown > 0: "cooldown"
    else: "rejected"
  of IntentBlink, IntentBlinkFine:
    if game.world.rotAffected(hero): "rot"
    elif hero.windupTicks > 0: "casting"
    elif hero.hookedBy != 0: "hooked"
    elif hero.blinkCooldown > 0: "cooldown"
    else: "rejected"
  of IntentGrapple, IntentGrappleFine:
    if hero.windupTicks > 0: "casting"
    elif hookInFlight(game.world, hero.id): "flight"
    elif hero.grappleCooldown > 0: "cooldown"
    else: "rejected"
  of IntentBuy:
    if hero.points <= 0: "points"
    else: "maxed"
  of IntentBuyPower:
    if not hero.inOwnShop: "shop"
    elif itemId == int32(ShopWard.ord):
      if hero.wardCooldown > 0: "cooldown"
      elif hero.itemRank[ShopWard] >= WardChargeMax: "held"
      else: "rejected"
    elif hero.gold <= 0: "gold"
    else: "rejected"
  of IntentPlaceWall, IntentPlaceMine:
    if hero.inRiver: "river"
    else: "rejected"
  of IntentPlaceWard:
    "rejected"
  of IntentRot:
    "rejected"
  else:
    "rejected"

proc sizeEchoState(echo: var ObservationEcho, seats: int) =
  ## Allocate independent receipts for the current roster.
  if echo.lastAccepted.len != seats:
    echo.lastAccepted.setLen(seats)
  if echo.sentKeys.len != seats:
    echo.sentKeys.setLen(seats)
  if echo.rotMatched.len != seats:
    echo.rotMatched.setLen(seats)

proc markSent(echo: var ObservationEcho, seats, slot: int, key: string,
              isArray: bool) =
  ## Remember which action key the seat sent and whether it was an array.
  sizeEchoState(echo, seats)
  if slot >= 0 and slot < echo.sentKeys.len:
    echo.sentKeys[slot][key] = isArray

proc snapshotAccepted*(game: Game, echo: var ObservationEcho) =
  ## Capture results for the actions each seat sent this tick.
  ## Auto-acquired targets and orders replaced by later orders stay silent.
  let seats = game.world.pudges.len
  sizeEchoState(echo, seats)
  for i in 0 ..< seats:
    echo.lastAccepted[i] = newJObject()
  for res in game.intentResults:
    let
      key = intentActionKey(res.kind)
      slot = int(res.slot)
    if key.len == 0 or slot < 0 or slot >= seats:
      continue
    if key notin echo.sentKeys[slot]:
      continue
    let answer =
      if res.accepted: %true
      else: %intentRejectReason(game, slot, res.kind, res.a)
    if echo.sentKeys[slot][key]:
      if not echo.lastAccepted[slot].hasKey(key):
        echo.lastAccepted[slot][key] = newJArray()
      echo.lastAccepted[slot][key].add answer
    else:
      echo.lastAccepted[slot][key] = answer
  for slot in 0 ..< seats:
    if echo.rotMatched[slot] and not echo.lastAccepted[slot].hasKey("rot"):
      # rot:<bool> already matched the sim state; nothing was queued,
      # but the ask is satisfied.
      echo.lastAccepted[slot]["rot"] = %true
    echo.rotMatched[slot] = false
    echo.sentKeys[slot].clear()

proc acceptedEcho(echo: ObservationEcho, slot: int): JsonNode =
  ## Return the last tick's receipt for a seat.
  if slot >= 0 and slot < echo.lastAccepted.len and echo.lastAccepted[slot] != nil:
    echo.lastAccepted[slot]
  else:
    newJObject()

proc printEcho(game: Game, slot: int): JsonNode =
  ## Return the most recent line printed by a seat.
  if slot >= 0 and slot < game.botSpeech.len and
      game.botSpeech[slot].text.len > 0:
    %game.botSpeech[slot].text
  else:
    newJNull()

proc observation*(game: Game, slot: int, echo = ObservationEcho(),
                  final = false, fogOn = true): JsonNode =
  ## Report the seat perspective with the same visibility rules as BASIC.
  let
    world = game.world
    viewer = world.pudges[slot]
    teamOrd = if fogOn: viewer.team.ord else: -1
  var visiblePudges = newJArray()
  var visibleHooks = newJArray()
  var visibleRunes = newJArray()
  var visibleProps = newJArray()
  var visibleFires = newJArray()
  for i, pudge in world.pudges:
    if fogShownPudgeTeam(world, teamOrd, pudge):
      visiblePudges.add pudgeJson(game, pudge, i)
  for hook in world.hooks:
    if hook.phase == HookIdle:
      continue
    if teamOrd >= 0 and not fogCanSee(world, viewer.team, hook.position):
      continue
    visibleHooks.add hookJson(world, hook)
  for rune in world.runes:
    if teamOrd >= 0 and not fogCanSee(world, viewer.team, rune.position):
      continue
    visibleRunes.add runeJson(rune)
  for prop in world.props:
    if not prop.alive:
      continue
    if teamOrd >= 0 and not propVisibleTo(prop, viewer.team):
      continue
    if prop.kind == PropWall and teamOrd >= 0 and
        not fogCanSee(world, viewer.team, prop.propCenter):
      continue
    visibleProps.add propJson(prop)
  for patch in world.firePatches:
    # Lightning fire shows through fog of war, matching the renderer.
    visibleFires.add fireJson(patch)
  # The same flat, fog-clipped list BASIC objectCount/objectAt walks:
  # own team in roster order, then visible props. kind matches BASIC
  # objectKind (1 butcher, 2 wall, 3 mine, 4 ward).
  var objectsNode = newJArray()
  var worldObject: WorldObject
  for i in 0 ..< worldObjectCount(world, viewer.id):
    if not worldObjectAt(world, viewer.id, i, worldObject):
      continue
    let objPos = tileCoord(worldObject.position)
    objectsNode.add %*{
      "id": worldObject.id,
      "kind": worldObject.kind,
      "team": worldObject.team.ord,
      "x": round(objPos.x, 3),
      "y": round(objPos.y, 3),
      "hp": max(worldObject.hp, 0),
      "alive": worldObject.alive,
      "layer": worldObject.layer,
      "hooked": worldObject.hooked,
      "shielded": worldObject.shielded,
      "rot": worldObject.rotting
    }
  var pingNode = newJNull()
  var ping: Ping
  if world.latestTeamPing(viewer.team, ping):
    pingNode = %*{
      "x": ping.x,
      "y": ping.y,
      "by": ping.byId,
      "tick": ping.tick,
      "age": max(world.tick - ping.tick, 0)
    }
  result = %*{
    "type": if final: "final" else: "observation",
    "game_version": ReplayGameVersion,
    "slot": slot,
    "tick": world.tick,
    "max_ticks": game.maximumTicks,
    "kill_goal": world.killGoal,
    "width": GridTiles,
    "height": GridTiles,
    "river_west": RiverWestX,
    "river_east": RiverEastX,
    "play_west_max": PlayWestMax,
    "play_east_min": PlayEastMin,
    "fog": fogOn,
    "self": pudgeJson(game, viewer, slot),
    "accepted": acceptedEcho(echo, slot),
    "print": printEcho(game, slot),
    "visible": {
      "pudges": visiblePudges,
      "hooks": visibleHooks,
      "runes": visibleRunes,
      "props": visibleProps,
      "fires": visibleFires
    },
    "objects": objectsNode,
    "ally_ping": pingNode,
    "rune_next": runeNextJson(world),
    "score": scoreNode(world),
    "done": final or world.gameOver,
    "winner": winnerName(world)
  }

proc toFine(value: float): int32 =
  ## Convert a JSON coordinate to a fine aim coordinate.
  int32(round(value * float(FineAimScale)))

proc toTile(value: float): int32 =
  ## Round a JSON coordinate to the nearest tile.
  int32(round(value))

proc queueIntents(game: Game, echo: var ObservationEcho, slot: int,
                  kind: IntentKind, node: JsonNode, key: string) =
  ## Queue one numbered upgrade or item per integer in the action.
  if not node.hasKey(key):
    return
  let value = node[key]
  markSent(echo, game.world.pudges.len, slot, key, value.kind == JArray)
  proc one(item: JsonNode) =
    ## Queue a single upgrade or item.
    queueIntent(
      game,
      HumanIntent(slot: int32(slot), kind: kind, a: int32(item.getInt))
    )
  if value.kind == JArray:
    for item in value:
      one(item)
  else:
    one(value)

proc applyAction*(game: Game, echo: var ObservationEcho, slot: int,
                  node: JsonNode) =
  ## Queue the supported JSON actions for a seat on the next simulation tick.
  if slot < 0 or slot >= game.world.pudges.len:
    return
  if node.kind != JObject:
    return
  if node.hasKey("halt") and node["halt"].getBool:
    markSent(echo, game.world.pudges.len, slot, "halt", false)
    queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentStop))
    return
  queueIntents(game, echo, slot, IntentBuy, node, "buy_upgrade")
  queueIntents(game, echo, slot, IntentBuyPower, node, "buy_power")
  if node.hasKey("blink_to") and node["blink_to"].kind == JArray and
      node["blink_to"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "blink_to", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentBlinkFine,
        a: toFine(node["blink_to"][0].getFloat),
        b: toFine(node["blink_to"][1].getFloat)
      )
    )
  if node.hasKey("walk_to") and node["walk_to"].kind == JArray and
      node["walk_to"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "walk_to", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentWalk,
        a: toTile(node["walk_to"][0].getFloat),
        b: toTile(node["walk_to"][1].getFloat)
      )
    )
  if node.hasKey("hook_to") and node["hook_to"].kind == JArray and
      node["hook_to"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "hook_to", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentHookFine,
        a: toFine(node["hook_to"][0].getFloat),
        b: toFine(node["hook_to"][1].getFloat)
      )
    )
  if node.hasKey("attack_target"):
    markSent(echo, game.world.pudges.len, slot, "attack_target", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentAttack,
        a: int32(node["attack_target"].getInt)
      )
    )
  if node.hasKey("rot"):
    if node["rot"].getBool != game.world.pudges[slot].rotOn:
      markSent(echo, game.world.pudges.len, slot, "rot", false)
      queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentRot))
    else:
      # Already in the asked state: nothing to queue, nothing to
      # flicker. The next accepted echo still answers rot=true.
      sizeEchoState(echo, game.world.pudges.len)
      echo.rotMatched[slot] = true
  elif node.hasKey("rot_toggle") and node["rot_toggle"].getBool:
    markSent(echo, game.world.pudges.len, slot, "rot", false)
    queueIntent(game, HumanIntent(slot: int32(slot), kind: IntentRot))
  if node.hasKey("print") and node["print"].kind == JString:
    let line = node["print"].getStr
    if line.len > 0:
      if game.botSpeech.len <= slot:
        game.botSpeech.setLen(slot + 1)
      game.botSpeech[slot] = BotSpeech(text: line, tick: game.world.tick)
  if node.hasKey("place_wall") and node["place_wall"].kind == JArray and
      node["place_wall"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "place_wall", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPlaceWall,
        a: toTile(node["place_wall"][0].getFloat),
        b: toTile(node["place_wall"][1].getFloat)
      )
    )
  if node.hasKey("place_mine") and node["place_mine"].kind == JArray and
      node["place_mine"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "place_mine", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPlaceMine,
        a: toTile(node["place_mine"][0].getFloat),
        b: toTile(node["place_mine"][1].getFloat)
      )
    )
  if node.hasKey("place_ward") and node["place_ward"].kind == JArray and
      node["place_ward"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "place_ward", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPlaceWard,
        a: toTile(node["place_ward"][0].getFloat),
        b: toTile(node["place_ward"][1].getFloat)
      )
    )
  if node.hasKey("ping") and node["ping"].kind == JArray and
      node["ping"].len >= 2:
    markSent(echo, game.world.pudges.len, slot, "ping", false)
    queueIntent(
      game,
      HumanIntent(
        slot: int32(slot),
        kind: IntentPing,
        a: toTile(node["ping"][0].getFloat),
        b: toTile(node["ping"][1].getFloat)
      )
    )
