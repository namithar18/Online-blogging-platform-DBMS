# Tests

PowerShell scripts that test the running application and the database constraints. They need Windows PowerShell 5.1 or later, the database container and the dev server.

1. Start the database: `docker start blogdb_nextjs`
2. Start the app: `npm.cmd run dev`
3. Load the seed data in its known state: `powershell -ExecutionPolicy Bypass -File tests\reset-db.ps1` (this replaces all data in the database)
4. Run the tests: `powershell -ExecutionPolicy Bypass -File tests\run-all.ps1`

The run prints PASS or FAIL for every test case and writes the table to `docs/test_results.md`. The exit code is 1 if any test fails.

`-ExecutionPolicy Bypass` applies to that one run only, which is needed because script files are blocked by the default policy on some machines. The tests assume the seed users (`NAME@example.com`, password `Passw0rd!`) and the container name `blogdb_nextjs`; both are set at the top of `helpers.ps1`.