# Nim Extension

This extension adds language support for the Nim language to VS Code, including:

* Syntax Highlight (nim, nimble, nim.cfg)
* Code Completion
* Signature Help
* Goto Definition
* Find References
* File outline
* Build-on-save
* Workspace symbol search
* Quick info
* Problem Matchers for nim compiler and test output
* Nim check result reported in `Nim` output channel (great for macro development)
  ![output channel demo](https://github.com/nim-lang/vscode-nim/raw/HEAD/images/nim_vscode_output_demo.gif "Demo of macro evaluation in the output channel")</details>

## Using

First, you will need to install [Visual Studio Code](https://code.visualstudio.com/) `1.27.0` or higher.
In the command palette (`cmd-shift-p`) select `Install Extension` and choose `nim-lang.org`.

The following tools are required for the extension:

* Nim compiler - http://nim-lang.org

_Note_: It is recommended to turn `Auto Save` on in Visual Studio Code (`File -> Auto Save`) when using this extension.

### Options

The following Visual Studio Code settings are available for the Nim extension.  These can be set in user preferences (`cmd+,`) or workspace settings (`.vscode/settings.json`).

* `nim.buildOnSave` - perform build task from `tasks.json` file, to use this options you need declare build task according to [Tasks Documentation](https://code.visualstudio.com/docs/editor/tasks), for example:

  ```json
  {
      "taskName": "Run module.nim",
      "command": "nim",
      "args": ["c", "-o:bin/${fileBasenameNoExtension}", "-r", "${fileBasename}"],
      "options": {
          "cwd": "${workspaceRoot}"
      },
      "type": "shell",
      "group": {
          "kind": "build",
          "isDefault": true
      }
  }
  ```
* `nim.lintOnSave` - perform the project check for errors on save
* `nim.project` - optional array of projects file, if nim.project is not defined then all nim files will be used as separate project
* `nim.licenseString` - optional license text that will be inserted on nim file creation
* `nim.notificationTimeout` - optional the timeout in seconds for the Nim language server notifications. Use 0 to disable the timeout.

#### Example

```json
{
    "nim.buildOnSave": false,
    "nim.buildCommand": "c",
    "nim.lintOnSave": true,
    "nim.project": ["project.nim", "project2.nim"],
    "nim.licenseString": "# Copyright 2020.\n\n"
}
```

### Commands

The following commands are provided by the extension:

* `Nim: Run selected file` - compile and run selected file, it uses `c` compiler by default, but you can specify `cpp` in `nim.buildCommand` config parameter.
This command available from file context menu or by `F6` keyboard shortcut.

* `Nim: Restart nimsuggest` - restart `nimsuggest` process when using `nimsuggest`.
---

### Debugging

Visual Studio Code includes a powerful debugging system, and the Nim tooling can take advantage of that. However, in order to do so, some setup is required.

#### Setting up

First, install a debugging extension, such as [CodeLLDB](https://open-vsx.org/extension/vadimcn/vscode-lldb), and any native packages the extension may require (such as clang and LLDB).

Next, you need to create a `tasks.json` file for your project, under the `.vscode` directory of your project root. Here is an example for CodeLLDB:

```jsonc
// .vscode/tasks.json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "nim: build current file (for debugging)",
            "command": "nim",
            "args": [
                "compile",
                "-g",
                "--debugger:native",
                "-o:${workspaceRoot}/bin/${fileBasenameNoExtension}",
                "${relativeFile}"
            ],
            "options": {
                "cwd": "${workspaceRoot}"
            },
            "type": "shell",
        }
    ]
}
```

Then, you need to create a launch configuration in the project's launch.json file. Again, this example works with CodeLLDB:

```jsonc
// .vscode/launch.json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "lldb",
            "request": "launch",
            "name": "nim: debug current file",
            "preLaunchTask": "nim: build current file (for debugging)",
            "program": "${workspaceFolder}/bin/${fileBasenameNoExtension}",
            "args": [],
            "cwd": "${workspaceFolder}",
        }
    ]
}
```

You should be set up now to be able to debug from a given file in the native VS Code(ium) debugger.

![Debugger preview screenshot](https://github.com/nim-lang/vscode-nim/raw/HEAD/images/debugging-screenshot.png "debugger preview")

---

## Code Completion

This extension relies on the Nim Language Server for code completion. You can read more about it [here](https://github.com/nim-lang/langserver)

---

## Developing the Extension

* If this is the first time you're building the extension on your machine, do an npm install to get the dependencies
* You should also copy (or create a symlink to) the `nimsuggest` directory from the Nim compiler sources into `src/nimsuggest`
* Press `F5` or whatever your `Run -> Start Debugging` command short cut is
* If prompted choose launch `Extension`
* This launches a new VS Code Window which is running your patched extension
* You can open a Nim code base to try it out
  * If you want to try it out on the extension source itself, create a new workspace and add the source as a folder to the workspace so VS Code doesn't take you back to the development window

Alternatively, feel free to give side-loading a shot.

### Side-loading the Extension

* Run `nimble vsix` to build the extension package to `out/nimvscode-<version>.vsix`
* Run `nimble install_vsix` if you have VS Code on `PATH`, otherwise select `Install from VSIX` from the command palette (`cmd-shift-p`) and choose `out/nimvscode-<version>.vsix`.

---

## Acknowledgments

This extension started out as a fork of the @saem extension [vscode-nim](https://github.com/saem/vscode-nim) which was a port of an extension written in [TypeScript](https://marketplace.visualstudio.com/items?itemName=kosz78.nim) for the Nim language.

Thank you Saem for your work and letting us build on top of it.

## Roadmap

The roadmap is located [here](https://github.com/nim-lang/RFCs/issues/544)

## ChangeLog

ChangeLog is located [here](https://github.com/nim-lang/vscode-nim/blob/main/CHANGELOG.md)
