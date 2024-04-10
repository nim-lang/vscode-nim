import std/[jsconsole, strutils, jsfetch, asyncjs, sugar, sequtils, options, strformat]
import platform/[vscodeApi, languageClientApi]

import platform/js/[jsNodeFs, jsNodePath, jsNodeCp, jsNodeUtil, jsNodeOs]
import nimutils
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
  if versions.len == 0: 
    console.warn("No versions found")
    return MinimalLSPVersion
  result = versions[0]
  for v in versions:
    if v > result: result = v


proc isSomeSafe(self: Option[LSPVersion]): bool {.inline.} =  
  #hack to fix https://github.com/nim-lang/vscode-nim/issues/47
  var wrap {.exportc.} = self
  var test {.importcpp: ("('has' in wrap)").}: bool
  if test: self.isSome()
  else: false

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
    .filterIt(it.isSomeSafe)
    .mapIt(it.get())
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
  var gotError: ExecError
  var gotStdout: cstring
  var gotStderr: cstring

  proc onExec(error: ExecError, stdout: cstring, stderr: cstring) = 
    # showing VS code user dialog messages does not appear to work from within this callback function,
    # so we save what we've got here and show all messages in onLspTimeout()
    isDone = true
    gotError = error
    gotStdout = stdout
    gotStderr = stderr

  var process: ChildProcess
  proc onLspTimeout() = 
    if isDone:
      let ver = parseVersion($gotStdout)
      if ver.isNone():
        console.error("Unexpected output from nimlangserver: ", gotStdout, gotStderr)
        vscode.window.showErrorMessage("Error starting nimlangserver: " & gotStdout & gotStderr)
      else:
        notifyUserOnTheLSPVersion(ver.get, latestVersion)
    else:
      #Running 0.2.0 kill the started nimlangserver process and notify the user is running an old version of the lsp
      kill(process)
      notifyUserOnTheLSPVersion(MinimalLSPVersion, latestVersion)

  global.setTimeout(onLspTimeout, 1000)
  process = cp.exec((nimlangserver & " --version"), ExecOptions(), onExec)    

proc isValidLspPath(lspPath: cstring): bool = 
  result = not lspPath.isNil and lspPath != "" and fs.existsSync(path.resolve(lspPath))  
  if lspPath.isNil: 
    console.log("lspPath is nil")
  else:
    console.log(fmt"isValidLspPath({lspPath}) = {result}".cstring)


proc getLocalLspDir(): cstring = 
  #The lsp is installed inside the user directory because the user 
  #storage of the extension seems to be too long and the installation fails
  result = path.join(nodeOs.homedir, ".vscode-nim")
  if not fs.existsSync(result):
    fs.mkdirSync(result)


proc getLspPath(state: ExtensionState): cstring = 
  #[
    We first try to use the path from the nim.lsp.path setting.
    If path is not set, we try to use the local nimlangserver binary.
    If the local binary is not found, we try to use the global nimlangserver binary.
  ]#
  result = vscode.workspace.getConfiguration("nim").getStr("lsp.path")
  if not isValidLspPath(result):
    var langserverExec = "nimlangserver"
    if process.platform == "win32":
      langserverExec.add ".cmd"
    result = path.join(getLocalLspDir(), "nimbledeps", "bin", langserverExec)
    if not isValidLspPath(result):
      result = getBinPath("nimlangserver")
   
  outputLine(("Using nimlangserver from path: " & result))

proc startLanguageServer(tryInstall: bool, state: ExtensionState) {.async.} =
  let rawPath = getLspPath(state)
  if not isValidLspPath(rawPath):
    console.log("nimlangserver not found on path")
    if tryInstall and not state.installPerformed:
      let command = getNimbleExecPath() & " install nimlangserver --accept -l"
      vscode.window.showInformationMessage(
        cstring(fmt "Unable to find nimlangserver. Do you want me to attempt to install it via '{command}'?"),
        VscodeMessageOptions(
          detail: cstring(""),
          modal: false
        ),
        VscodeMessageItem(title: cstring("Yes"), isCloseAffordance: false),
        VscodeMessageItem(title: cstring("No"), isCloseAffordance: true))
      .then(
        onfulfilled = proc(value: JsRoot): JsRoot =
          if value.JsObject.to(VscodeMessageItem).title == "Yes":
            if not state.installPerformed:
              state.installPerformed = true
              vscode.window.showInformationMessage(
                cstring(fmt "Trying to install nimlangserver via '{command}'"))
              let args: seq[cstring] = @["install nimlangserver", "--accept", "-l"]
              var process = cp.spawn(
                  getNimbleExecPath(), args, 
                  SpawnOptions(shell: true, cwd: getLocalLspDir()))
              process.stdout.onData(proc(data: Buffer) =
                outputLine(data.toString())
              )
              process.stderr.onData(proc(data: Buffer) =
                let msg =  $data.toString()
                if msg.contains("Warning: "):
                  outputLine(("[Warning]" & msg).cstring)
                else:
                  outputLine(("[Error]" & msg).cstring)
              )
              process.onClose(proc(code: cint, signal: cstring): void =
                if code == 0:
                  outputLine("Nimble install successfully")
                  discard startLanguageServer(false, state)
                  console.log("Nimble install finished, validating by checking if nimlangserver is present.")
                else:
                  outputLine("Nimble install failed.")
              )
          value
        ,
        onrejected = proc(reason: JsRoot): JsRoot =
          reason
      )
    else:
      let cantInstallInfoMesssage: cstring = "Unable to find/install `nimlangserver`. You can attempt to install it by running `nimble install nimlangserver` or downloading the binaries from https://github.com/nim-lang/langserver/releases."
      vscode.window.showInformationMessage(cantInstallInfoMesssage)
  else:
    let nimlangserver = path.resolve(rawPath);
    outputLine(fmt"nimlangserver found: {nimlangserver}".cstring)
    outputLine("Starting nimlangserver.")
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
    outputLine("Nim Language Server started")

export startLanguageServer

proc stopLanguageServer(state: ExtensionState) {.async.} =
  await state.client.stop()

export stopLanguageServer
