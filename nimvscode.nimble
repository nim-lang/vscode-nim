import std/strformat
# Package

version = "1.6.0"
author = "saem"
description = "Nim language support for Visual Studio Code written in Nim"
license = "MIT"
backend = "js"
srcDir = "src"
binDir = "out"
bin = @["nimvscode"]

# Deps

requires "nim == 2.0.12"

import std/os

proc initialNpmInstall() =
  if not dirExists "node_modules":
    exec "npm install"

let compiler = "~/.nimble/nimbinaries/nim-2.0.12/bin/nim"
# let compiler = "nim"

# Tasks
task main, "This compiles the vscode Nim extension":
  echo "Nim compiler is ", selfExe()
  # exec "nimble shell"
  # let compiler = "nim"
  exec &"{compiler} js --outdir:out --checks:on --sourceMap src/nimvscode.nim"

task release, "This compiles a release version":
  exec &"{compiler} js -d:release -d:danger --outdir:out --checks:off --sourceMap src/nimvscode.nim"

task vsix, "Build VSIX package":
  initialNpmInstall()
  var cmd = "npm exec -c 'vsce package --out out/nimvscode-" & version & ".vsix'"
  when defined(windows):
    cmd = "powershell.exe " & cmd
  exec cmd

task installVsix, "Install the VSIX package":
  initialNpmInstall()
  exec "code --install-extension out/nimvscode-" & version & ".vsix"

# Tasks for maintenance
task auditNodeDeps, "Audit Node.js dependencies":
  initialNpmInstall()
  exec "npm audit"
  echo "NOTE: 'engines' versions in 'package.json' need manually audited"


task upgradeNodeDeps, "Upgrade Node.js dependencies":
  initialNpmInstall()
  exec "npm exec -c 'ncu -ui'"
  exec "npm install"
  echo "NOTE: 'engines' versions in 'package.json' need manually upgraded"

task anotherTask, "This is another task":
  echo "This is another task"
