-- ============================================================
-- ICONES DAS MOVES (Codex)
-- Cada icone = fundo com a cor do tipo + simbolo escolhido pelo nome.
--
-- Icone proprio para uma move: coloque um PNG 36x36 em
--   moves_icon/custom/<nome da move em minusculo>.png
--   (ex: moves_icon/custom/razor leaf.png)
-- Ele substitui fundo + simbolo daquela move.
-- ============================================================

local ICON_DIR = '/modules/game_pokemonmoves/moves_icon/'

-- Regras em ordem: a primeira que bater define o simbolo.
-- "palavra"  = palavra inteira do nome
-- "pref*"    = palavra que comeca com pref (ex: "psy*" pega psybeam, psyshock)
-- "a b"      = trecho do nome (pode ter espaco ou hifen)
-- "=nome"    = so o nome exato da move
local RULES = {
  {'sleep', {'sleep powder', 'hypnosis', 'yawn', '=rest', 'dream eater', 'dark void', 'bad dreams', '=sing', 'lovely kiss', 'nightmare'}},
  {'web', {'string shot', 'spider web', 'sticky web', '=web'}},
  {'weather', {'sandstorm', 'rain dance', 'sunny day', '=hail', 'weather ball', 'electric terrain', 'misty terrain', 'grassy terrain', 'psychic terrain', 'gravity'}},
  {'heal', {'heal*', 'recover', 'roost', 'synthesis', 'moonlight', 'morning sun', 'milk drink', 'soft-boiled', '=wish', 'life dew', 'refresh', 'aromatherapy', 'lunar blessing', 'ingrain', 'aqua ring', 'slack off', '=rest', 'shore up', 'jungle healing'}},
  {'heart', {'charm', 'attract', 'draining kiss', 'sweet kiss', 'present', 'helping hand', 'follow me'}},
  {'shield', {'protect', 'detect', 'endure', 'reflect', 'barrier', 'light screen', 'wide guard', 'spiky shield', 'king\'s shield', 'baneful bunker', 'harden', 'withdraw', 'iron defense', 'acid armor', 'defense curl', 'cotton guard', 'guard swap', 'mirror coat', '=counter', 'metal burst', 'defense order'}},
  {'buff', {'swords dance', 'dragon dance', 'quiver dance', 'bulk up', 'nasty plot', 'agility', 'calm mind', 'focus energy', 'rock polish', 'shift gear', 'coil', '=charge', 'shell smash', '=growth', 'autotomize', 'cosmic power', 'tailwind', 'power-up punch', 'work up', 'hone claws', 'minimize', 'double team', 'stored power', 'power swap', 'magnet rise', '=curse'}},
  {'debuff', {'leer', 'tail whip', 'scary face', 'fake tears', 'feather dance', 'eerie impulse', 'smokescreen', 'sand attack', 'torment', 'disable', 'growl', 'screech', 'metal sound', 'supersonic', 'confuse ray', 'teeter dance', 'imprison', 'taunt', 'will-o-wisp', 'thunder wave', 'stun spore', 'poison powder', 'toxic', 'poison gas', 'scald'}},
  {'sound', {'hyper voice', 'echoed voice', 'disarming voice', 'boomburst', 'uproar', '=round', 'perish song', 'chatter', 'snarl', 'sparkling aria', '=roar', 'roar of time', 'bug buzz', 'relic song', 'overdrive'}},
  {'fist', {'punch', 'mach punch', 'arm thrust', 'hammer arm', 'karate chop', 'cross chop', 'dual chop', 'brick break', 'focus punch', 'drain punch', 'dynamic punch', 'force palm', 'seismic toss', 'vital throw', 'rock smash', 'close combat', 'superpower', 'reversal', 'revenge', 'wake-up slap', 'smelling salts', 'double slap', 'pound', 'crush grip', 'body press', 'raging fury'}},
  {'kick', {'kick', 'stomp', 'stomping tantrum', 'low sweep', 'triple kick', 'rolling kick', 'blaze kick', 'axe kick', 'high jump kick', 'low kick', 'double kick'}},
  {'fang', {'fang', 'bite', 'crunch', 'super fang', 'jaw lock', 'hyper fang', 'leech life', 'bug bite'}},
  {'claw', {'claw', 'slash', 'scratch', '=cut', 'cutter', 'scissor', 'x-scissor', 'blade', 'blades', 'fury cutter', 'razor shell', 'night slash', 'psycho cut', 'false surrender', 'dire claw', 'stone axe', 'aqua cutter', 'precipice blades', 'shadow claw', 'crush claw', 'metal claw', 'dragon claw', 'leaf blade', 'air slash', 'spacial rend', 'chip away', '=feint', 'fake out', 'slap', 'throat chop', 'knock off'}},
  {'horn', {'=horn', 'horn drill', 'megahorn', '=drill', 'drill run', 'pin missile', 'needle arm', 'twineedle', 'poison sting', 'fell stinger', 'icicle spear', 'icicle crash', 'ice shard', 'poison jab', 'smart strike', 'barb barrage', '=spike', 'spikes', 'dragon darts', 'guillotine', 'bone rush', 'bonemerang', 'bone club', 'shadow bone'}},
  {'wing', {'wing', 'wing attack', 'steel wing', 'dual wingbeat', 'peck', 'drill peck', 'aerial ace', '=fly', 'bounce', 'sky attack', 'brave bird', 'dragon ascent', 'aeroblast', 'acrobatics'}},
  {'tornado', {'gust', 'twister', 'hurricane', 'whirlwind', 'tornado', 'silver wind', 'ominous wind', 'icy wind', 'fairy wind', 'air cutter', 'mountain gale', 'leaf tornado', 'whirlpool', 'fire spin', 'sand tomb', 'magma storm', 'leaf storm', 'diamond storm', 'petal blizzard', 'rapid spin', 'infestation', 'wrap'}},
  {'beam', {'beam', 'hyper beam', 'solar beam', 'charge beam', 'ice beam', 'psybeam', 'aurora beam', 'signal beam', 'bubble beam', 'flash cannon', 'zap cannon', 'hydro pump', 'water gun', 'water spout', 'dragon breath', 'flamethrower', 'tri attack', 'night shade', 'origin pulse', 'water pulse', 'dark pulse', 'dragon pulse', 'heal pulse', 'luster purge', 'prismatic laser', 'octazooka', 'mirror shot', 'psystrike', 'psywave', 'discharge', 'eruption', 'steam eruption', 'make it rain', 'hyperspace hole'}},
  {'orb', {'ball', 'sphere', 'aura sphere', 'shadow ball', 'energy ball', 'electro ball', 'gyro ball', 'pyro ball', 'mist ball', 'weather ball', 'sludge bomb', 'seed bomb', 'mud bomb', 'egg bomb', 'power gem', 'ancient power', 'focus blast', 'moonblast', 'future sight', 'doom desire', 'mystical fire', 'hex', 'struggle bug'}},
  {'star', {'meteor mash', 'meteor assault', 'swift', 'cosmic power', 'metronome', 'hidden power', 'me first', 'sketch*'}},
  {'quake', {'earthquake', 'earth power', 'fissure', 'bulldoze', '=dig', 'magnitude', 'mud shot', 'mud-slap', 'muddy water', 'high horsepower', 'precipice', 'stomping', 'heavy slam', 'body slam'}},
  {'rock', {'rock', 'stone', 'rollout', 'head smash', 'rock wrecker', 'smack down', 'stone edge', 'rock tomb', 'rock slide', 'rock blast', 'rock throw'}},
  {'bolt', {'thunder*', 'shock', 'thunder shock', 'shock wave', 'spark', 'volt*', 'zap*', 'electro*', '=electric', 'wild charge', 'nuzzle', 'plasma fists'}},
  {'flame', {'=fire', 'flame*', 'flare', 'flare blitz', 'ember', 'burn up', 'heat wave', 'inferno', 'overheat', 'incinerate', 'lava plume', 'sacred fire', 'blast burn', 'fire blast', 'raging fury'}},
  {'wave', {'=surf', 'water*', 'aqua*', '=wave', 'wave crash', 'brine', 'dive', 'waterfall', 'liquidation', 'crabhammer', 'water shuriken', 'hydro*', 'scald', 'splash'}},
  {'bubbles', {'=bubble', 'sludge*', '=acid', 'acid spray', 'gunk shot', 'smog', 'belch', 'venoshock', 'cross poison', 'poison tail', 'clear smog', 'toxic spikes'}},
  {'snow', {'ice*', 'icy', 'blizzard', 'powder snow', 'sheer cold', 'freeze-dry', 'frost*', '=hail', 'aurora*', 'avalanche'}},
  {'leaf', {'leaf*', 'leafage', 'razor leaf', 'magical leaf', 'vine whip', 'power whip', 'petal*', 'seed*', 'bullet seed', 'absorb', 'mega drain', 'giga drain', 'leech seed', 'wood hammer', 'grass*', 'needle arm', 'solar*', 'trop kick', 'spore'}},
  {'eye', {'psy*', 'psychic', 'confusion', 'kinesis', 'extrasensory', 'zen headbutt', 'psycho boost', 'mystical power', 'hyperspace fury', 'stored power', 'teleport', 'miracle eye', 'foresight', 'lock-on', 'mind reader', 'amnesia'}},
  {'ghost', {'shadow*', '=ghost', 'lick', 'astonish', 'phantom force', 'shadow force', 'spirit shackle', 'rage fist', 'spite', 'destiny bond'}},
  {'moon', {'night*', 'dark*', 'foul play', 'sucker punch', 'feint attack', 'payback', 'punishment', 'assurance', 'thief', 'darkest lariat', 'pursuit', 'beat up'}},
  {'sparkle', {'dazzling gleam', 'play rough', 'strange steam', 'aromatic mist', 'fairy*', 'sweet*', 'baby-doll eyes', 'moonblast'}},
  {'gear', {'gear grind', 'iron*', 'metal*', 'steel*', 'bullet punch', 'magnet*', 'anchor shot'}},
  {'dragon', {'dragon*', 'outrage', 'draco meteor', 'dual chop', 'clanging*', 'dragon rush', 'dragon tail', 'dragon rage'}},
  {'bug', {'bug*', 'attack order', 'defense order', 'u-turn', 'lunge', 'pollen puff'}},
  {'burst', {'tackle', 'headbutt', 'take down', 'double-edge', 'giga impact', 'self-destruct', 'explosion', 'extreme speed', 'quick attack', 'thrash', 'facade', 'flail', 'double hit', 'raging bull', 'horn attack', 'pay day', 'struggle'}},
}

local TYPE_GLYPH = {
  fire = 'flame', water = 'wave', electric = 'bolt', grass = 'leaf', ice = 'snow',
  fighting = 'fist', poison = 'bubbles', ground = 'quake', flying = 'wing', psychic = 'eye',
  bug = 'bug', rock = 'rock', ghost = 'ghost', dragon = 'dragon', dark = 'moon',
  steel = 'gear', fairy = 'sparkle', normal = 'burst'
}

local GLYPH_TYPE = {
  flame = 'fire', wave = 'water', bolt = 'electric', leaf = 'grass', snow = 'ice',
  fist = 'fighting', kick = 'fighting', bubbles = 'poison', quake = 'ground', wing = 'flying',
  tornado = 'flying', eye = 'psychic', bug = 'bug', web = 'bug', rock = 'rock', ghost = 'ghost',
  dragon = 'dragon', moon = 'dark', gear = 'steel', sparkle = 'fairy', heart = 'fairy'
}

-- simbolos com cor clara de fundo: simbolo escuro fica mais legivel
local LIGHT_TYPES = {electric = true}

-- monta as regras em tabelas de busca
local compiled = {}
for _, rule in ipairs(RULES) do
  local entry = {glyph = rule[1], words = {}, prefixes = {}, phrases = {}}
  for _, key in ipairs(rule[2]) do
    if key:sub(1, 1) == '=' then
      entry.exact = entry.exact or {}
      entry.exact[key:sub(2)] = true
    elseif key:sub(-1) == '*' then
      table.insert(entry.prefixes, key:sub(1, -2))
    elseif key:find('[ %-\']') then
      table.insert(entry.phrases, key)
    else
      entry.words[key] = true
    end
  end
  table.insert(compiled, entry)
end

local cache = {}

local function glyphFor(name)
  local tokens = {}
  for word in name:gmatch('[^%s%-]+') do tokens[#tokens + 1] = word end
  for _, entry in ipairs(compiled) do
    if entry.exact and entry.exact[name] then return entry.glyph end
    for _, phrase in ipairs(entry.phrases) do
      if name == phrase or name:find(phrase, 1, true) then return entry.glyph end
    end
    for _, word in ipairs(tokens) do
      if entry.words[word] then return entry.glyph end
      for _, prefix in ipairs(entry.prefixes) do
        if word:sub(1, #prefix) == prefix then return entry.glyph end
      end
    end
  end
  return nil
end

-- devolve {type, background, glyph, glyphColor, custom}
function getMoveIcon(moveName)
  local name = tostring(moveName or ''):lower()
  if cache[name] then return cache[name] end
  local moveType = MOVE_TYPES and MOVE_TYPES[name] or nil
  local glyph = glyphFor(name)
  if not moveType then
    moveType = (glyph and GLYPH_TYPE[glyph]) or 'normal'
  end
  -- simbolo generico do proprio tipo quando o nome nao diz nada
  if not glyph then
    glyph = TYPE_GLYPH[moveType] or 'burst'
  end
  local icon = {
    type = moveType,
    background = ICON_DIR .. 'fundo/' .. moveType .. '.png',
    glyph = ICON_DIR .. 'simbolo/' .. glyph .. '.png',
    glyphName = glyph,
    glyphColor = LIGHT_TYPES[moveType] and '#0a1320' or '#ffffff',
    custom = nil
  }
  local customPath = ICON_DIR .. 'custom/' .. name .. '.png'
  if g_resources and g_resources.fileExists and g_resources.fileExists(customPath) then
    icon.custom = customPath
  end
  cache[name] = icon
  return icon
end

-- ============================================================
-- Para outros modulos (Pokemon Manager, Pokedex...):
--   modules.game_pokemonmoves.applyMoveIcon(widget, 'razor leaf', 32)
-- Poe o icone da move no widget (icone proprio da pasta custom, ou
-- fundo do tipo + simbolo). Devolve true se deu certo.
-- ============================================================
function applyMoveIcon(widget, moveName, size)
  if not widget then return false end
  local icon = getMoveIcon(moveName)
  size = tonumber(size) or widget:getWidth()
  local glyph = widget:getChildById('codexGlyph')
  if icon.custom then
    widget:setImageSource(icon.custom)
    if glyph then glyph:setVisible(false) end
  else
    widget:setImageSource(icon.background)
    if not glyph then
      glyph = g_ui.createWidget('UIWidget', widget)
      glyph:setId('codexGlyph')
      glyph:setPhantom(true)
      glyph:setFocusable(false)
      glyph:fill('parent')
    end
    glyph:setImageSource(icon.glyph)
    glyph:setImageColor(icon.glyphColor)
    glyph:setImageSize({width = size, height = size})
    glyph:setVisible(true)
  end
  widget:setImageSize({width = size, height = size})
  return true
end

-- caminho de uma imagem unica (para quem so aceita um arquivo)
function getMoveIconPath(moveName)
  local icon = getMoveIcon(moveName)
  return icon.custom or icon.background
end
