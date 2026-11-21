when defined(emscripten):
  import std/[os, strutils]

  include "../../src/pudgewars/dependencies.nims"

  let
    gameDir = thisDir()
    projectRoot = gameDir.parentDir.parentDir
    engine = polyworldDirectory(projectRoot)
    outputDir = gameDir / "emscripten"
    stagedArt = projectRoot / "build" / "polyworld_art"
    defaultArt =
      if dirExists(stagedArt):
        stagedArt
      else:
        projectRoot.parentDir / "polyworld_art"
    artDir = absolutePath(getEnv("POLYWORLD_ART", defaultArt))
    webInputs = engine / "src" / "polyworld" / "webinputs.js"

  mkDir(outputDir)
  switch("nimcache", outputDir / "tmp")
  switch("out", outputDir / (projectName() & ".html"))
  switch("threads", "off")
  switch("os", "linux")
  switch("cpu", "wasm32")
  switch("cc", "clang")
  let compiler = when defined(windows): "emcc.bat" else: "emcc"
  switch("clang.exe", compiler)
  switch("clang.linkerexe", compiler)
  switch("mm", "arc")
  switch("exceptions", "goto")
  switch("define", "noSignalHandler")
  switch("define", "noAutoGLerrorCheck")
  switch("passL", "--pre-js " & quoteShell(webInputs) &
    " --shell-file " & quoteShell(gameDir / "webshell.html"))
  for line in readFile(gameDir / "webdata.txt").splitLines():
    let entry = line.strip()
    if entry.len > 0 and not entry.startsWith("#"):
      switch("passL", "--preload-file " &
        quoteShell(artDir / entry & "@/polyworld_art/" & entry))
  switch("passL", "-s ASYNCIFY -s FETCH -s EXIT_RUNTIME=1 " &
    "-s USE_WEBGL2=1 -s MAX_WEBGL_VERSION=2 -s MIN_WEBGL_VERSION=2 " &
    "-s FULL_ES3=1 -s GL_ENABLE_GET_PROC_ADDRESS=1 " &
    "-s ALLOW_MEMORY_GROWTH -s STACK_SIZE=8388608 " &
    "-s INITIAL_MEMORY=134217728 --profiling")
  switch("passL", "-s EXPORTED_FUNCTIONS=" &
    "_main,_malloc,_free,_windy_websocket_open_callback," &
    "_windy_websocket_message_callback,_windy_websocket_error_callback," &
    "_windy_websocket_close_callback")
  switch("passL", "-s EXPORTED_RUNTIME_METHODS=" &
    "FS_createPath,FS_createDataFile,addRunDependency,removeRunDependency")
  when not defined(debug):
    switch("passL", "-O3")
  if paramStr(1) in ["run", "r"]:
    setCommand("c")
    echo "To run the Emscripten build, use:"
    echo "emrun " & outputDir / (projectName() & ".html")
