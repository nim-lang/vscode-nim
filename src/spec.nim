## Types for extension state, this should either get fleshed out or removed
import std/options
import platform/vscodeApi


from platform/languageClientApi import VscodeLanguageClient

type
  Backend* = cstring
  Timestamp* = cint
  NimsuggestId* = cstring

  NimSuggestStatus* = object
    projectFile*: cstring
    capabilities*: seq[cstring]
    version*: cstring
    path*: cstring
    port*: int32
    openFiles*: seq[cstring]
    unknownFiles*: seq[cstring]

  NimLangServerStatus* = object
    version*: cstring
    nimsuggestInstances*: seq[NimSuggestStatus]
    openFiles*: seq[cstring]

  StatusItem* = ref object of TreeItem
    instance*: Option[NimSuggestStatus]

  NimLangServerStatusProvider* = ref object of JsObject
    status*: Option[NimLangServerStatus]
    # onDidChangeTreeData*: EventEmitter

  ExtensionState* = ref object
    ctx*: VscodeExtensionContext
    config*: VscodeWorkspaceConfiguration
    channel*: VscodeOutputChannel
    client*: VscodeLanguageClient
    installPerformed*: bool
    nimDir*: string # Nim used directory. Extracted on activation from nimble. When it's "", means nim in the PATH is used.
    statusProvider*: NimLangServerStatusProvider

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