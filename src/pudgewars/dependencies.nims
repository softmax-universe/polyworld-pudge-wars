proc dependencyDirectory(projectRoot, name: string): string =
  ## Finds a package in an explicit dependency root, workspace, or Nimby.
  let dependencyRoot = getEnv("PUDGEWARS_DEPS")
  if dependencyRoot.len > 0:
    return absolutePath(dependencyRoot) / name
  let sibling = projectRoot.parentDir / name
  if dirExists(sibling):
    return sibling
  getEnv("NIMBY_HOME", getHomeDir() / ".nimby") / "pkgs" / name

proc polyworldDirectory(projectRoot: string): string =
  ## Selects the same engine checkout for Nim modules and browser support.
  let checkout = getEnv("PUDGEWARS_POLYWORLD")
  if checkout.len > 0:
    return absolutePath(checkout)
  dependencyDirectory(projectRoot, "polyworld")
