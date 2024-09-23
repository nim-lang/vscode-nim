## Types for extension state, this should either get fleshed out or removed
import std/[options, times]
import platform/vscodeApi

from platform/languageClientApi import VscodeLanguageClient

type
  Backend* = cstring
  Timestamp* = cint
  NimsuggestId* = cstring

  PendingRequestState* = enum
    prsOnGoing = "OnGoing"
    prsCancelled = "Cancelled"
    prsComplete = "Complete"

  PendingRequestStatus* = object
    name*: cstring
    projectFile*: cstring
    time*: cstring
    state*: cstring

  NimSuggestStatus* = object
    projectFile*: cstring
    capabilities*: seq[cstring]
    version*: cstring
    path*: cstring
    port*: int32
    openFiles*: seq[cstring]
    unknownFiles*: seq[cstring]

  ProjectError* = object
    projectFile*: cstring
    errorMessage*: cstring
    lastKnownCmd*: cstring

  NimLangServerStatus* = object
    version*: cstring
    lspPath*: cstring
    nimsuggestInstances*: seq[NimSuggestStatus]
    openFiles*: seq[cstring]
    extensionCapabilities*: seq[cstring]
    pendingRequests*: seq[PendingRequestStatus]
    projectErrors*: seq[ProjectError]

  LspItem* = ref object of TreeItem
    instance*: Option[NimSuggestStatus]
    notification*: Option[Notification]

  Notification* = object
    message*: cstring
    kind*: cstring
    id*: cstring
    date*: DateTime

  NimLangServerStatusProvider* = ref object of JsObject
    status*: Option[NimLangServerStatus]
    notifications*: seq[Notification]
    lastId*: int32 # onDidChangeTreeData*: EventEmitter

  LSPVersion* = tuple[major: int, minor: int, patch: int]

  LspExtensionCapability* = enum #List of extensions the lsp server support.
    excNone = "None"
    excRestartSuggest = "RestartSuggest"

  ExtensionState* = ref object
    ctx*: VscodeExtensionContext
    config*: VscodeWorkspaceConfiguration
    channel*: VscodeOutputChannel
    lspChannel*: VscodeOutputChannel
    client*: VscodeLanguageClient
    installPerformed*: bool
    nimDir*: string
      # Nim used directory. Extracted on activation from nimble. When it's "", means nim in the PATH is used.
    statusProvider*: NimLangServerStatusProvider
    lspVersion*: LSPVersion
    lspExtensionCapabilities*: set[LspExtensionCapability]

# type
#   SolutionKind* {.pure.} = enum
#     skSingleFile, skFolder, skWorkspace

#   NimsuggestProcess* = ref object
#     process*: ChildProcess
#     rpc*: EPCPeer
#     startingPath*: cstring
#     projectPath*: cstring
#     backend*: Backend
#     nimble*: VscodeUri
#     updateTime*: Timestamp

#   ProjectKind* {.pure.} = enum
#     pkNim, pkNims, pkNimble

#   ProjectSource* {.pure.} = enum
#     psDetected, psUserDefined

#   Project* = ref object
#     uri*: VscodeUri
#     source*: ProjectSource
#     nimsuggest*: NimsuggestId
#     hasNimble*: bool
#     matchesNimble*: bool
#     case kind*: ProjectKind
#     of pkNim:
#       hasCfg*: bool
#       hasNims*: bool
#     of pkNims, pkNimble: discard

#   ProjectCandidateKind* {.pure.} = enum
#     pckNim, pckNims, pckNimble

#   ProjectCandidate* = ref object
#     uri*: VscodeUri
#     kind*: ProjectCandidateKind

proc getNimCmd*(state: ExtensionState): cstring =
  if state.nimDir == "":
    "nim ".cstring
  else:
    (state.nimDir & "/nim ").cstring
