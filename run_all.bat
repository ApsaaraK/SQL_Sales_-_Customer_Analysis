@echo off
REM Rebuilds the database, runs every query, exports results\, and verifies them with pandas.
REM Run from the project root in Command Prompt. psql must be on your PATH
REM (typically C:\Program Files\PostgreSQL\<version>\bin).
REM Set these first, or psql will ask for the password on every command:
REM    set PGUSER=postgres
REM    set PGPASSWORD=your_password
set DB=retail
psql -d postgres -c "CREATE DATABASE %DB%" 2>nul
psql -d %DB% -q -f sql\01_schema.sql 2>nul
psql -d %DB% -q -f sql\02_load.sql || goto :error
if not exist results mkdir results
for %%f in (sql\queries\q*.sql) do (
  psql -d %DB% --csv -f %%f -o results\%%~nf.csv || goto :error
  echo ran %%~nf
)
psql -d %DB% --csv -f sql\03_reconciliation.sql -o results\reconciliation.csv || goto :error
python verification\verify_with_pandas.py
goto :eof
:error
echo Something failed. Read the message above.
exit /b 1
