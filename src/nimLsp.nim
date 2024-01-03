import std/jsconsole
import platform/[vscodeApi, languageClientApi]

import platform/js/[jsNodeFs, jsNodePath, jsNodeCp, jsNodeUtil]

from std/strformat import fmt
from tools/nimBinTools import getNimbleExecPath, getBinPath
from spec import ExtensionState

proc handleLspVersion(nimlangserver: cstring) =
  var isDone = false
  proc onExec(error: ExecError, stdout: cstring, stderr: cstring) = 
    let ver = ($stdout).split(".")
    let (major, minor, patch) = (ver[0].cstring, ver[1].cstring, ver[2].cstring)
    console.log("Major: ", major, " Minor: ", minor, " Patch: ", patch)
    isDone = true
    #TODO check the version with the latest released one
  
  var process: ChildProcess
  proc onLspTimeout() = 
    if isDone: return #the process already quit
    #Running 0.2.0 kill the started nimlangserver process and notify the user is running an old version of the lsp
    kill(process)
    #TODO check the version with the latest released one

  global.setTimeout(onLspTimeout, 250)
  process = cp.exec((nimlangserver & " --version"), ExecOptions(), onExec)    



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
    handleLspVersion(nimlangserver)

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
