@echo off
setlocal DisableDelayedExpansion
texlua "%~dp0texlive-pkgassist.lua" %*
exit /b %errorlevel%
