import platform/vscodeApi
import std/[strformat, jsconsole]

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


proc runSingleTest(test: VscodeTestItem) =
  let run = testController.createTestRun(test)
  run.started(test)
  console.log("Running test: ", test.id)
  
  if test.children.size() == 0:
    run.appendOutput(&"\n[{test.label}] Starting test...\n")
    
    global.setTimeout(proc() =
      if test.id == "test2":
        run.appendOutput(&"[{test.label}] Test failed with error:\n")
        run.appendOutput("Expected 42 but got 41\n")
        run.failed(test, "Failed test".cstring)
      else:
        run.appendOutput(&"[{test.label}] Test completed successfully\n")
        run.appendOutput("All assertions passed\n")
        run.passed(test, "Passed test".cstring)
    
    , 1000)
  else:
    console.log("Running suite: ", test.id)
    run.appendOutput(&"\n=== Running Suite: {test.label} ===\n")
    test.children.forEach(proc(child: VscodeTestItem) =
      runSingleTest(child)
    )

proc runHandler(request: VscodeTestRunRequest, token: VscodeCancellationToken) =
  console.log("Running tests...", request)
  let isRunAll = request.include.isUndefined
  console.log("Is run all: ", isRunAll)
  if isRunAll:
      let items = testController.getItems()
      items.forEach(proc(item: VscodeTestItem) =
        runSingleTest(item)
      )
  else:
    let run = testController.createTestRun(request)
    for item in request.include:
      runSingleTest(item)

    console.log("Include array: ", request.include)

    global.setTimeout(proc() =
      run.`end`()
    , 3000)

proc initializeTests*(context: VscodeExtensionContext) =
  console.log("Creating test controller...")
  testController = vscode.tests.createTestController("nim-tests".cstring, "Nim Tests".cstring)
  
  # Add a dummy test item to verify everything works
  let dummyTest = testController.createTestItem(
    "test1".cstring,
    "Sample Test".cstring
  )
  
  # Use the add method instead of push
  testController.getItems().add(dummyTest)

  let dummyFailingTest = testController.createTestItem(
    "test2".cstring,
    "Failing Test".cstring
  )

  testController.getItems().add(dummyFailingTest)
  
  console.log("Created dummy test item")
  
  # Create a run profile that will show up in the test explorer
  discard testController.createRunProfile(
    "Run Tests",
    VscodeTestRunProfileKind.Run,
    runHandler,
    true
  )
  
  console.log("Test initialization complete")

  let suite = testController.createTestItem(
    "suite1".cstring,
    "My Test Suite".cstring
  )

  let testInSuite = testController.createTestItem(
    "test-in-suite1".cstring,
    "Test In Suite".cstring
  )
  let testInSuite2 = testController.createTestItem(
    "test-in-suite2".cstring,
    "Test In Suite 2".cstring
  )

  suite.children.add(testInSuite)
  suite.children.add(testInSuite2)

  testController.getItems().add(suite)