# Codex — cliente (base OTClient Redemption)

Cliente do Codex Pokétibia migrado do OTClient antigo (edubart, 2019) para o
[OTClient Redemption](https://github.com/mehah/otclient). O mesmo código gera
Windows, navegador (WebAssembly) e Android.

## Como compilar (sem instalar nada no PC)
1. Aba **Actions** > **Codex - compilar** > **Run workflow**.
2. Escolha `windows`, `navegador` ou `os-dois`.
3. No fim, baixe o resultado em **Artifacts**.
   - A primeira compilação do Windows demora (~1 h); as próximas usam cache.

No Windows: extraia o `Codex-Windows`, copie o seu `Tibia.spr` para
`data/things/1098/` e abra o `Codex.exe`.

## Onde configurar
| O quê | Arquivo |
|---|---|
| Endereço do servidor (127.0.0.1 ou jogo.codexpoketibia.com.br), porta e versão | `init.lua` (`CODEX_SERVIDOR`, `CODEX_PORTA`, `CODEX_VERSAO`) |
| Opções do protocolo 10.98 do Codex | `modules/game_features/features.lua` (bloco `CODEX`) |
| Área de visão (16x8) e velocidade da animação dos itens | `data/setup.otml` |

## O que mudou em relação ao cliente antigo
- **Motor (C++)**: Redemption. Única mudança do Codex no C++: pilha até 1000
  (`protocolgameparse.cpp` / `protocolgamesend.cpp`, marcado com `CODEX`).
- **Aura por tipo** (skull 11–30): saiu do C++ e virou o módulo `game_codexaura`
  (shader de contorno na cor do tipo + efeito 823).
- **Módulos**: todos os módulos do Codex foram mantidos como estavam. Do
  Redemption ficaram só as bibliotecas: `corelib`, `gamelib` (com os slots extras
  e as categorias do mercado do Codex), `modulelib`, `startup`, `game_features`
  e `game_attachedeffects`.
- **`codex_compat`**: funções do cliente antigo que mudaram de nome ou saíram
  no Redemption, para os módulos funcionarem sem mexer neles.
- **`game_effect`**: shaders por área adaptados para a API do Redemption.
- Saíram: atualizador e pacote criptografado do cliente antigo (refazer depois
  para o PC), `client_stats` (mandava estatística para um site que não existe mais).

## Ainda não vai para o GitHub
- `data/things/1098/Tibia.spr` (577 MB, acima do limite de 100 MB).
