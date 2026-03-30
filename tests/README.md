# WinInit Tests

## Running Tests

### Run all test files

```powershell
.\tests\Run-AllTests.ps1
```

### Dry-run only (no admin/system state tests)

```powershell
.\tests\Run-AllTests.ps1 -DryRun
```

### Run a single test file directly

```powershell
.\tests\Test-Common.ps1
```

### Run a specific suite within a test file

```powershell
.\tests\Test-Common.ps1 -Suite json
```

### Get JUnit XML output

```powershell
.\tests\Run-AllTests.ps1 -JUnit results.xml
```

## How It Works

`Run-AllTests.ps1` discovers all `Test-*.ps1` files in the `tests/` directory, runs each one in sequence, and aggregates results into a summary table. Each test file should follow the same conventions as `devscripts\test.ps1` -- accepting `-DryRun`, `-Verbose`, `-Suite`, and `-JUnit` parameters, and returning the failure count as its exit code.

## Parameters

| Parameter  | Description                                      |
|------------|--------------------------------------------------|
| `-DryRun`  | Passed through to each test file (skip state tests) |
| `-Verbose` | Passed through to each test file (show details)  |
| `-Suite`   | Passed through to each test file (filter suites)  |
| `-JUnit`   | Merge all JUnit XML outputs into a single file    |
| `-Quick`   | Skip slow test files                              |
