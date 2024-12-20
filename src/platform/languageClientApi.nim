import std/jsffi
import js/[jsPromise, jsNode]
import vscodeApi
export jsffi, jsPromise, jsNode

# shim for https://github.com/microsoft/vscode-languageserver-node

type
  VscodeLanguageClient* = ref VscodeLanguageClientObj
  VscodeLanguageClientObj {.importc.} = object of JsRoot

  TransportKind* {.pure.} = enum
    stdio = 0
    ipc = 1
    pipe = 2
    socket = 3

  ExecutableOptions* = ref ExecutableOptionsObj
  ExecutableOptionsObj {.importc.} = object of JsObject
    shell*: bool

  Executable* = ref ExecutableObj
  ExecutableObj {.importc.} = object of JsObject
    command*: cstring
    transport*: TransportKind
    options*: ExecutableOptions

  ServerOptions* = ref ServerOptionsObj
  ServerOptionsObj* {.importc.} = object of JsObject
    run*: Executable
    debug*: Executable

  DocumentFilter* = ref DocumentFilterObj
  DocumentFilterObj* {.importc.} = object of JsObject
    language*: cstring
    scheme*: cstring

  LanguageClientOptions* {.importc.} = ref LanguageClientOptionsObj
  LanguageClientOptionsObj* {.importc.} = object of JsObject
    documentSelector*: seq[DocumentFilter]
    outputChannel*: VscodeOutputChannel

proc newLanguageClient*(
  cl: VscodeLanguageClient,
  name: cstring,
  description: cstring,
  serverOptions: ServerOptions,
  clientOptions: LanguageClientOptions,
): VscodeLanguageClient {.importcpp: "(new #.LanguageClient(@))".}

proc newLanguageClient*(
  cl: VscodeLanguageClient,
  name: cstring,
  description: cstring,
  serverOptions: proc(): Future[ServerOptions],
  clientOptions: LanguageClientOptions,
): VscodeLanguageClient {.importcpp: "(new #.LanguageClient(@))".}

proc start*(s: VscodeLanguageClient): Promise[void] {.importcpp: "#.start()".}
proc stop*(s: VscodeLanguageClient): Promise[void] {.importcpp: "#.stop()".}
proc sendRequest*(
  s: VscodeLanguageClient, m: cstring, params: JsObject
): Future[JsObject] {.importcpp: "#.sendRequest(@)".}

proc onNotification*(
  s: VscodeLanguageClient, m: cstring, cb: proc(data: JsObject)
) {.importcpp: "#.onNotification(@)".}

var vscodeLanguageClient*: VscodeLanguageClient =
  require("vscode-languageclient/node").to(VscodeLanguageClient)
