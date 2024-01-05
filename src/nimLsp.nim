import std/[jsconsole, strutils, jsfetch, asyncjs, sugar, sequtils, options, strformat]
import platform/[vscodeApi, languageClientApi]

import platform/js/[jsNodeFs, jsNodePath, jsNodeCp, jsNodeUtil]

from std/strformat import fmt
from tools/nimBinTools import getNimbleExecPath, getBinPath
from spec import ExtensionState

type LSPVersion = tuple[major: int, minor: int, patch: int]
const MinimalLSPVersion = (1, 0, 0)

proc `$` (v: LSPVersion):string = &"v{v.major}.{v.minor}.{v.patch}"

proc `>`(v1, v2: LSPVersion): bool =
  if v1.major != v2.major: v1.major > v2.major
  elif v1.minor != v2.minor:  v1.minor > v2.minor
  else: v1.patch > v2.patch

proc `==`(v1, v2: LSPVersion): bool = 
  v1.major == v2.major and v1.minor == v2.minor and 
  v1.patch == v2.patch

proc parseVersion(version: string): Option[LSPVersion] = 
  #expected version = vMajor.Minor.Patch
  var ver = version.split(".")
  if ver.len != 3: return none(LSPVersion)
  ver[0] = ver[0].replace("v", "")
  var versions = newSeq[int]()
  for v in ver:
    try:
      versions.add(parseInt(v.strip()))
    except CatchableError: 
      console.error("Error parsing version", v.cstring)
      console.error(getCurrentExceptionMsg().cstring)
      return none(LSPVersion)
  some (versions[0], versions[1], versions[2])

proc getLatestVersion(versions: seq[LSPVersion]): LSPVersion = 
  result = versions[0]
  for v in versions:
    if v > result: result = v

proc getLatestReleasedLspVersion(default: LSPVersion): Future[LSPVersion] {.async.} = 
  type 
    Tag = object of JsObject
      name: cstring
  proc toTags(obj: JsObject): seq[Tag] {.importjs: ("#").}
  let url = " https://api.github.com/repos/nim-lang/langserver/tags".cstring
  var failed = false
  let res = await fetch(url)
    .then((res: Response) => res.json())
    .then((json: JsObject) => json)
    .catch(proc(err: Error): JsObject = 
      console.error("Nimlangserver request to GitHub failed", err)
      failed = true
    )
  if failed: 
    return default
  else: 
    return res
    .toTags
    .mapIt(parseVersion($it.name))
    .filterIt(it.isSome)
    .mapIt(it.get)
    .getLatestVersion()

proc notifyUserOnTheLSPVersion(current, latest: LSPVersion) = 
  if latest > current:
    let msg = &"""
There is a new Nim langserver version available ({latest}). 
You can install it by running: nimble install nimlangserver"""
    vscode.window.showInformationMessage(msg.cstring)
  else:
    console.log("Your lsp version is updated")

proc handleLspVersion(nimlangserver: cstring, latestVersion: LSPVersion) =
  var isDone = false
  proc onExec(error: ExecError, stdout: cstring, stderr: cstring) = 
      let ver = parseVersion($stdout)
      if ver.isNone():
        console.error("Unexpected output from nimlangserver: ", stdout)
      else:
        isDone = true
        notifyUserOnTheLSPVersion(ver.get, latestVersion) 

  var process: ChildProcess
  proc onLspTimeout() = 
    if isDone: return #the process already quit and the user is already notified
    #Running 0.2.0 kill the started nimlangserver process and notify the user is running an old version of the lsp
    kill(process)
    notifyUserOnTheLSPVersion(MinimalLSPVersion, latestVersion)

  global.setTimeout(onLspTimeout, 1000)
  process = cp.exec((nimlangserver & " --version"), ExecOptions(), onExec)    

proc getLspPath(): cstring = 
  var lspPath = vscode.workspace.getConfiguration("nim").getStr("lsp.path")
  if lspPath.isNil or lspPath == "":
    lspPath = getBinPath("nimlangserver")
  console.log("Attempting to use nimlangserver at " & lspPath)
  lspPath

proc startLanguageServer(tryInstall: bool, state: ExtensionState) {.async.} =
  let rawPath = getLspPath()
  if rawPath.isNil or not fs.existsSync(path.resolve(rawPath)):
    console.log("nimlangserver not found on path")
    if tryInstall and not state.installPerformed:
      let command = getNimbleExecPath() & " install nimlangserver --accept"
      vscode.window.showInformationMessage(
        cstring(fmt "Unable to find nimlangserver, trying to install it via '{command}'"))
      state.installPerformed = true
      discard cp.exec(
        command,
        ExecOptions{},
        proc(err: ExecError, stdout: cstring, stderr: cstring): void {.async.} =
          console.log("Nimble install finished, validating by checking if nimlangserver is present.")
          await startLanguageServer(false, state))
    else:
      vscode.window.showInformationMessage("Unable to find/install `nimlangserver`.")
  else:
    let nimlangserver = path.resolve(rawPath);
    console.log(fmt"nimlangserver found: {nimlangserver}".cstring)
    console.log("Starting nimlangserver.")
    let latestVersion = await getLatestReleasedLspVersion(MinimalLSPVersion)
    handleLspVersion(nimlangserver, latestVersion)

    let
      serverOptions = ServerOptions{
        run: Executable{command: nimlangserver, transport: TransportKind.stdio },
        debug: Executable{command: nimlangserver, transport: TransportKind.stdio }
      }
      clientOptions = LanguageClientOptions{
        documentSelector: @[DocumentFilter(scheme: cstring("file"),
                                           language: cstring("nim"))]
      }

    state.client = vscodeLanguageClient.newLanguageClient(
       cstring("nimlangserver"),
       cstring("Nim Language Server"),
       serverOptions,
       clientOptions)
    await state.client.start()

export startLanguageServer

proc stopLanguageServer(state: ExtensionState) {.async.} =
  await state.client.stop()

export stopLanguageServer
