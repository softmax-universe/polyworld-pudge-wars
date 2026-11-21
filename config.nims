import std/[os, strutils]

include "src/pudgewars/dependencies.nims"

let projectRoot = thisDir()
switch("path", projectRoot / "src")
switch("path", polyworldDirectory(projectRoot) / "src")
for line in readFile(projectRoot / "nimby.lock").splitLines():
  let fields = line.splitWhitespace()
  if fields.len == 0 or fields[0] == "polyworld":
    continue
  let
    name = fields[0]
    directory = dependencyDirectory(projectRoot, name)
    source =
      if dirExists(directory / "src"):
        directory / "src"
      else:
        directory
  switch("path", getEnv(name.toUpperAscii() & "_PATH", source))

switch("define", "nimTypeNames")
switch("define", "flatty64")
when not defined(emscripten):
  switch("define", "bassyNative")

when not defined(debug):
  switch("define", "release")
  switch("define", "noAutoGLerrorCheck")
