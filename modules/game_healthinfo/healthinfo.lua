local topMenuButtons = {}

function init()
  -- O antigo painel HealthInfo (vida, mana, experiencia, fishing,
  -- condicoes, capacidade etc.) foi removido.
  -- Mantemos somente os atalhos centralizados no Top Menu.
  createButtons()
end

function terminate()
  destroyButtons()
end

-- ============================================================
-- PokeBank
-- ============================================================

function getPokeBank()
    -- Nova versao exporta como modules.game_pokebank
    if modules.game_pokebank then
        return modules.game_pokebank
    end
    -- Compatibilidade com versao antiga
    if modules.pokebank and modules.pokebank.PokeBank then
        return modules.pokebank.PokeBank
    end
    return nil
end

-- ============================================================
-- Botoes centralizados no Top Menu
-- ============================================================

function createButtons()
  local buttons = {
    {'order', 'Move se pokemon.\nAtalho: botao do meio do mouse.', 11},
    {'pokedex', 'Mostra informacoes do pokemon selecionado.\nAtalho: CTRL+F', 12},
    {'inventory', 'Abre sua mochila.\nAtalho: CTRL+I', 3},
    {'pokemons', 'Abre sua equipe Pokemon (6 slots).\nAtalho: Ctrl+Shift+P'},
    {'autoloot', 'Abre a lista do Autoloot.\nAtalho: Ctrl+Shift+A'},
    {'varas', 'Abre o equipamento de pesca (vara + isca).\nAtalho: Ctrl+Shift+F'},
    {'evolve', 'Evolui o pokemon selecionado.\nAtalho: CTRL+E.', 9},
    {'badge', 'Abre o painel de insignias.', 8},
    {'info', 'Abre Informacoes.\nAtalho: CTRL+D'}
  }

  for i = 1, #buttons do
    local data = buttons[i]
    local id = 'healthInfo_' .. data[1]
    local pathOn = '/modules/game_healthinfo/interface/' .. data[1]:lower() .. '.png'

    local button = modules.client_topmenu.addCenterGameButton(
      id,
      tr(data[2]),
      pathOn,
      function()
        if data[1] == 'inventory' or data[1] == 'badge' then
          local player = g_game.getLocalPlayer()
          if not player then return end

          local item = player:getInventoryItem(data[3])
          if item then
            if item:isContainer() then g_game.open(item) else g_game.useInventoryItem(item:getId()) end -- codex mochila livre
          end

        elseif data[1] == 'coin' then
          g_logger.info('[HealthInfo] Botao COIN clicado!')
          local pb = getPokeBank()

          if pb then
            g_logger.info('[HealthInfo] PokeBank encontrado! Abrindo...')
            pb.show()
          else
            g_logger.error('[HealthInfo] PokeBank nao esta carregado!')
            modules.game_textmessage.displayFailureMessage('[PokeBank] Modulo nao carregado.')
          end

        elseif data[1] == 'pokedex' then
          toggleDex()

        elseif data[1] == 'evolve' then
          toggleEvolve()

        elseif data[1] == 'order' then
          toggleOrder()

        elseif data[1] == 'pokemons' or data[1] == 'autoloot' or data[1] == 'varas' then
          local module = modules['game_' .. data[1]]
          if module and module.toggle then
            module.toggle()
          else
            modules.game_textmessage.displayFailureMessage('[' .. data[1] .. '] Modulo nao carregado.')
          end

        elseif data[1] == 'info' then
          if modules.game_pokemonmanager and modules.game_pokemonmanager.toggle then
            modules.game_pokemonmanager.toggle()
          elseif PokemonManager and PokemonManager.toggle then
            PokemonManager.toggle()
          else
            g_logger.error('[HealthInfo] Pokemon Manager nao esta carregado!')
            modules.game_textmessage.displayFailureMessage('[Pokemon Manager] Modulo nao carregado.')
          end
        end
      end
    )

    topMenuButtons[#topMenuButtons + 1] = button
  end
end

function destroyButtons()
  for i = #topMenuButtons, 1, -1 do
    local button = topMenuButtons[i]
    if button and not button:isDestroyed() then
      button:destroy()
    end
    topMenuButtons[i] = nil
  end
end


-- Funcoes restauradas para os botoes do Top Menu.
-- A janela antiga do HealthInfo continua removida.
currentSlot = 0

function startChooseItem(releaseCallback)
  if g_ui.isMouseGrabbed() then return end
  if not releaseCallback then
    error("No mouse release callback parameter set.")
  end
  local mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  connect(mouseGrabberWidget, { onMouseRelease = releaseCallback })
  mouseGrabberWidget:grabMouse()
  g_mouse.pushCursor('target')
end

function onClickWithMouse(self, mousePosition, mouseButton)
  local item = nil

  if mouseButton == MouseLeftButton or mouseButton == MouseMidButton then
    local clickedWidget = modules.game_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)

    if clickedWidget then
      if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
          if currentSlot == 1 then
            item = tile:getGround()
          else
            local thing = tile:getTopMoveThing()
            if thing and thing:isItem() then
              item = thing
            else
              item = tile:getTopCreature()
            end
          end
        end
      elseif clickedWidget:getClassName() == 'UICreatureButton' then
        item = clickedWidget:getCreature()
      end
    end
  end

  if item then
    local player = g_game.getLocalPlayer()
    if player then
      local inventoryItem = player:getInventoryItem(currentSlot)
      if inventoryItem then
        g_game.useInventoryItemWith(inventoryItem:getId(), item)
      end
    end
  end

  g_mouse.popCursor('target')
  self:ungrabMouse()
  return true
end

function toggleDex()
  currentSlot = 12
  startChooseItem(onClickWithMouse)
end

function toggleEvolve()
  currentSlot = 9
  startChooseItem(onClickWithMouse)
end

function toggleOrder()
  currentSlot = 11
  startChooseItem(onClickWithMouse)
end
