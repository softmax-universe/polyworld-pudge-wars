## The Pudge replay strip must contain the shared transport's real controls.

import
  vmath,
  polyworld/[gameuis, player],
  pudgewars/bottomhud

proc fitsInside(panel, bounds: GameUiPanel): bool =
  ## Checks the full drawing and hit rectangle, not only its origin.
  panel.size.x > 0 and panel.size.y > 0 and
    panel.origin.x >= bounds.origin.x and
    panel.origin.y >= bounds.origin.y and
    panel.origin.x + panel.size.x <= bounds.origin.x + bounds.size.x and
    panel.origin.y + panel.size.y <= bounds.origin.y + bounds.size.y

proc controlPanels(strip: GameUiPanel,
    showStats: bool): seq[GameUiPanel] =
  ## Uses the same shared geometry as drawPlayer, including scrub hit bounds.
  let controls = strip.transportPanels(showStats)
  result = @(controls.controls)
  result.add controls.loop
  result.add controls.speeds
  result.add [controls.scrub, controls.recorded, controls.scrubHit,
    controls.camera, controls.fullscreen, controls.tick]
  if showStats:
    result.add controls.stats

for size in [vec2(1280, 800), vec2(1920, 1080)]:
  let strip = compactTransportPanel(size)
  doAssert strip.size.y == TransportHeight
  doAssert strip == compactTransportPanel(size, transportStripHeight(true))
  doAssert strip.inside(size)
  doAssert strip.origin.y + strip.size.y == size.y
  for showStats in [false, true]:
    for control in strip.controlPanels(showStats):
      doAssert control.fitsInside(strip),
        $size & ": transport control escapes its reserved strip: " & $control
      doAssert control.inside(size),
        $size & ": transport control is outside the window: " & $control

    # This was the previous Pudge strip height. Applying the same real shared
    # controls must expose the original clipping, independent of the new alias.
    let oldStrip = compactTransportPanel(size, 20)
    var clipped = false
    for control in oldStrip.controlPanels(showStats):
      if not control.fitsInside(oldStrip) or not control.inside(size):
        clipped = true
    doAssert clipped, "Regression fixture no longer reproduces clipped controls"

  let hidden = compactTransportPanel(size, transportStripHeight(false))
  doAssert transportStripHeight(false) == 0
  doAssert hidden.size == vec2(size.x, 0)
  doAssert hidden.origin == vec2(0, size.y)
  doAssert hidden.inside(size)
  doAssert not hidden.contains(hidden.origin)

echo "Pudge replay controls fit their strip; hiding reserves no height"
