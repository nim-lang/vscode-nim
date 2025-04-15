import platform/vscodeApi
import std/[strformat, jsconsole, tables, options, sequtils]
import spec, nimLsp
import platform/js/jsNodeFs
import nimProjects
import nimUtils

var testController: VscodeTestController

#[
run.started(test) - Mark a test as running
run.passed(test, ?message) - Mark a test as passed
run.failed(test, ?message) - Mark a test as failed
run.errored(test, ?message) - Mark a test as errored
run.skipped(test) - Mark a test as skipped
run.appendOutput(content) - Add output text to the test run
run.end() - Complete the test run
]#

#Basically in nim you will be able to run all tests a suite, or a single test

proc renderTestResult(test: VscodeTestItem, result: RunTestResult, run: VscodeTestRun) =
  console.log("Rendering test result: ", result)
  let duration = result.time * 1000
  console.log("Duration: ", duration)
  if result.failure.isNull:
    run.passed(test, duration = duration)
    run.appendOutput(&"[{test.label}] Test passed in {duration:.4f}ms\n")
  else:
    run.failed(test, VscodeTestMessage(message: result.failure), duration = duration)  # Use time directly
    run.appendOutput(&"[{test.label}] Test failed with error:\n")    
    run.appendOutput(result.failure)
    run.appendOutput(&"[{test.label}] Test failed in {duration:.4f}ms\n")

proc runSingleTest(test: VscodeTestItem, run: VscodeTestRun) = 
  let state = ext
  let entryPoint = state.config.getStrArray("test.entryPoints")[0]
      
  run.started(test)
  console.log("Running test: ", test.id)
  let runTestParams = RunTestParams(testNames: @[test.id], entryPoints: @[entryPoint])
  let runTestRes = requestRunTest(state, runTestParams)
  runTestRes.then(proc(res: RunTestProjectResult) =
    console.log("Run test result: ", res)
    renderTestResult(test, res.suites[0].testResults[0], run)
    run.`end`()
  )
  # runTestRes.catch(proc(err: ref Exception) =
  #   console.log("Run test error: ", err)
  #   run.failed(test, VscodeTestMessage(message: err.msg), duration = 0)
  #   run.`end`()
  # )
  
  


# proc runSingleTest(test: VscodeTestItem) =
#   let run = testController.createTestRun(test)
#   run.started(test)
#   console.log("Running test: ", test.id)
  
#   if test.children.size() == 0:
#     run.appendOutput(&"\n[{test.label}] Starting test...\n")
    
#     global.setTimeout(proc() =
#       if test.id == "test2":
#         run.appendOutput(&"[{test.label}] Test failed with error:\n")
#         run.appendOutput("Expected 42 but got 41\n")
#         run.failed(test, "Failed test".cstring)
#       else:
#         run.appendOutput(&"[{test.label}] Test completed successfully\n")
#         run.appendOutput("All assertions passed\n")
#         run.passed(test, "Passed test".cstring)
    
#     , 1000)
#   else:
#     console.log("Running suite: ", test.id)
#     run.appendOutput(&"\n=== Running Suite: {test.label} ===\n")
#     test.children.forEach(proc(child: VscodeTestItem) =
#       runSingleTest(child)
#     )

proc runHandler(request: VscodeTestRunRequest, token: VscodeCancellationToken) =
  console.log("Running tests...", request)
  let isRunAll = request.include.isUndefined
  console.log("Is run all: ", isRunAll)
  if isRunAll:
      let items = testController.getItems()
      items.forEach(proc(item: VscodeTestItem) =
        let run: VscodeTestRun = testController.createTestRun(request)
        runSingleTest(item, run)
      )
  else:
    let run: VscodeTestRun = testController.createTestRun(request)
    for item in request.include:
      runSingleTest(item,run)

    console.log("Include array: ", request.include)


proc initializeTests*(context: VscodeExtensionContext, state: ExtensionState) =
  proc onExtensionReady()  =
    proc inner() {.async.} = 
      if excRunTests notin state.lspExtensionCapabilities:
        console.log("Run tests capability not found")
        return      
      #Only one for now
      var entryPoint = state.config.getStrArray("test.entryPoints")[0]
      
      
      console.log("Entry point: ", entryPoint)
      let listTestsParams = ListTestsParams(entryPoints: @[entryPoint])
      let listTestsRes = await fetchListTests(state, listTestsParams)
      testController = vscode.tests.createTestController("nim-tests".cstring, "Nim Tests".cstring)
      #show message is there are not tests:
      if listTestsRes.projectInfo.suites.keys.toSeq.len == 0:
        vscode.window.showInformationMessage("No tests found for entry point: " & entryPoint)
        return


      for key, suite in listTestsRes.projectInfo.suites:
        let suiteItem = testController.createTestItem(suite.name, suite.name)
        for test in suite.tests:
          let testItem = testController.createTestItem(test.name, test.name)
          suiteItem.children.add(testItem)
        testController.getItems().add(suiteItem)

      discard testController.createRunProfile(
        "Run Tests",
        VscodeTestRunProfileKind.Run,
        runHandler,
        true
      )
      


      # console.log("Creating test controller...")
      
      
      # # Add a dummy test item to verify everything works
      # let dummyTest = testController.createTestItem(
      #   "test1".cstring,
      #   "Sample Test".cstring
      # )
      
      # # Use the add method instead of push
      # testController.getItems().add(dummyTest)

      # let dummyFailingTest = testController.createTestItem(
      #   "test2".cstring,
      #   "Failing Test".cstring
      # )

      # testController.getItems().add(dummyFailingTest)
      
      # console.log("Created dummy test item")
      
      # # Create a run profile that will show up in the test explorer
      # discard testController.createRunProfile(
      #   "Run Tests",
      #   VscodeTestRunProfileKind.Run,
      #   runHandler,
      #   true
      # )
      
      # console.log("Test initialization complete")

      # let suite = testController.createTestItem(
      #   "suite1".cstring,
      #   "My Test Suite".cstring
      # )

      # let testInSuite = testController.createTestItem(
      #   "test-in-suite1".cstring,
      #   "Test In Suite".cstring
      # )
      # let testInSuite2 = testController.createTestItem(
      #   "test-in-suite2".cstring,
      #   "Test In Suite 2".cstring
      # )

      # suite.children.add(testInSuite)
      # suite.children.add(testInSuite2)

      # testController.getItems().add(suite)
    discard inner()

  state.onExtensionReadyHooks.add(onExtensionReady)