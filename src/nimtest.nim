import platform/vscodeApi
import std/[strformat, jsconsole, tables, options, sequtils]
import spec, nimLsp
import platform/js/jsNodeFs
import nimProjects
import nimUtils

var testController: VscodeTestController
var runProfile: VscodeTestRunProfile = nil

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

proc isSuite(test: VscodeTestItem): bool =
  return test.children.size() > 0

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


proc renderTestProjectResult(projectResult: RunTestProjectResult, run: VscodeTestRun, testCol: Option[VscodeTestItemCollection]) =
  for suite in projectResult.suites:
    for testResult in suite.testResults:
      if testCol.isSome:
        # Find the child test item that matches this result
        testCol.get.forEach(proc(childTest: VscodeTestItem) =
          if childTest.id == testResult.name:
            renderTestResult(childTest, testResult, run)
          childTest.children.forEach(proc(childChildTest: VscodeTestItem) =
            if childChildTest.id == testResult.name:
              renderTestResult(childChildTest, testResult, run)
          )
          )

proc runSingleTest(test: VscodeTestItem, run: VscodeTestRun) = 
  let state = ext
  let entryPoint = state.config.getStrArray("test.entryPoints")[0]  
  run.started(test)
  console.log("Running test: ", test.id)
  var runTestParams = RunTestParams(entryPoints: @[entryPoint])
  if test.isSuite:
    runTestParams.suiteName = test.id
  else:
    runTestParams.testNames = @[test.id]

  let runTestRes = requestRunTest(state, runTestParams)
  runTestRes.then(proc(res: RunTestProjectResult) =
    if test.isSuite:
      renderTestProjectResult(res, run, some test.children)
    else:
      renderTestResult(test, res.suites[0].testResults[0], run)
    run.`end`()
  )
  runTestRes.catch(proc(err: ref Exception) =
    console.log("Run test error: ", err)
    run.failed(test, VscodeTestMessage(message: err.msg), duration = 0)
    run.`end`()
  )

proc runAllTests(request: VscodeTestRunRequest) =
  let run: VscodeTestRun = testController.createTestRun(request)
  let state = ext
  let entryPoint = state.config.getStrArray("test.entryPoints")[0]  
  testController.getItems().forEach(proc(item: VscodeTestItem) =
    run.started(item)
    item.children.forEach(proc(child: VscodeTestItem) =
      run.started(child)
    )
  )
  var runTestParams = RunTestParams(entryPoints: @[entryPoint])
  let runTestRes = requestRunTest(state, runTestParams)
  runTestRes.then(proc(res: RunTestProjectResult) =
    console.log("Run test result: ", res)
    renderTestProjectResult(res, run, some testController.getItems())
    run.`end`()
  )
  runTestRes.catch(proc(err: ref Exception) =
    console.log("Run test error: ", err)
    testController.getItems().forEach(proc(item: VscodeTestItem) =
      run.failed(item, VscodeTestMessage(message: err.msg), duration = 0)
    )
    run.`end`())
    
proc runHandler(request: VscodeTestRunRequest, token: VscodeCancellationToken) =
  console.log("Running tests...", request)
  let isRunAll = request.include.isUndefined
  console.log("Is run all: ", isRunAll)
  if isRunAll:
    runAllTests(request)
  else:
    let run: VscodeTestRun = testController.createTestRun(request)
    for item in request.include:
      runSingleTest(item,run)

    console.log("Include array: ", request.include)


proc loadTests(state: ExtensionState, isRefresh: bool = false): Future[void] {.async.} =
  if excRunTests notin state.lspExtensionCapabilities:
    console.log("Run tests capability not found")
    return
    
  let entryPoint = state.config.getStrArray("test.entryPoints")[0]
  console.log("Entry point: ", entryPoint)
  
  let listTestsParams = ListTestsParams(entryPoints: @[entryPoint])
  testController.getItems().clear()
  let listTestsRes = await fetchListTests(state, listTestsParams)
  
  
  if listTestsRes.projectInfo.error != nil:
    vscode.window.showErrorMessage(listTestsRes.projectInfo.error)
    # Remove the run profile if it exists
    if not runProfile.isNil:
      runProfile.dispose()
      runProfile = nil
    return

  # Create run profile only if it doesn't exist
  if runProfile.isNil:
    runProfile = testController.createRunProfile(
      "Run Tests",
      VscodeTestRunProfileKind.Run,
      runHandler,
      true
    )

  if isRefresh:
    vscode.window.showInformationMessage("Tests refreshed successfully")
  else:
    vscode.window.showInformationMessage("Tests loaded successfully")

  if listTestsRes.projectInfo.suites.keys.toSeq.len == 0:
    vscode.window.showInformationMessage("No tests found for entry point: " & entryPoint)
    # Don't return here, let it continue to clear any existing error items
  
  # Load test items
  for key, suite in listTestsRes.projectInfo.suites:
    let suiteItem = testController.createTestItem(suite.name, suite.name)
    for test in suite.tests:
      let testItem = testController.createTestItem(test.name, test.name)
      suiteItem.children.add(testItem)
    testController.getItems().add(suiteItem)

proc refreshTests*() {.async.} =
  if testController.isNil:
    vscode.window.showErrorMessage("Test controller not initialized")
    return
    
  try:
    let state = ext
    await loadTests(state, true)
  except:
    let msg = getCurrentExceptionMsg()
    vscode.window.showErrorMessage("Failed to refresh tests: " & msg)

proc initializeTests*(context: VscodeExtensionContext, state: ExtensionState) =
  proc onExtensionReady() =
    proc inner() {.async.} =
      testController = vscode.tests.createTestController("nim-tests".cstring, "Nim Tests".cstring)
      
      testController.refreshHandler = proc() =
        discard refreshTests()
      
      await loadTests(state)
      
      # Initial run profile creation moved to loadTests
    discard inner()

  state.onExtensionReadyHooks.add(onExtensionReady)
