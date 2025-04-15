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