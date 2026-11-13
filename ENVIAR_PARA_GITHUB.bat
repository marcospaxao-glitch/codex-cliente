@echo off
REM CODEX - envia este projeto para o seu repositorio privado no GitHub.
REM Precisa do "Git for Windows" instalado (https://git-scm.com/download/win).
REM Na primeira vez o Git abre uma janela para voce entrar na sua conta do GitHub.
cd /d "%~dp0"
where git >nul 2>nul || (echo Instale o Git for Windows primeiro: https://git-scm.com/download/win & pause & exit /b 1)
git remote remove origin >nul 2>nul
git remote add origin https://github.com/marcospaxao-glitch/codex-cliente.git
git branch -M main
git push -u origin main
if errorlevel 1 (echo. & echo Nao foi possivel enviar. Confira se o repositorio codex-cliente existe e esta vazio. & pause & exit /b 1)
echo.
echo PRONTO! Abra o repositorio no GitHub, aba Actions, "Codex - compilar".
pause
