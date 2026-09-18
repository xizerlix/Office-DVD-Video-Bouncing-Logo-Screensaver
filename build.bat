@echo off
setlocal

REM ----------------------------------------------------------------------
REM  Builds DVD Screensaver using the in-box .NET Framework C# compiler.
REM  No Visual Studio, no .NET SDK needed.
REM ----------------------------------------------------------------------

set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" (
    echo ERROR: csc.exe not found at %CSC%
    echo .NET Framework 4.x is required.
    exit /b 1
)

pushd "%~dp0"

if not exist "bin" mkdir bin

set SOURCES=src\Program.cs
set OUT=bin\DvdScreensaver.exe
set REFS=/r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll

echo Compiling %SOURCES% -^> %OUT%
"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ ^
    /out:%OUT% %REFS% %SOURCES%
if errorlevel 1 (
    echo BUILD FAILED.
    popd
    exit /b 1
)

echo.
echo BUILD OK: %OUT%
popd
endlocal
