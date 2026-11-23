local PM_HELD_SLOTS = {held = true, equip = true, heldY = true, held3 = true, device = true}
PokemonManager = PokemonManager or {}

PokemonManager.opcode = 89
PokemonManager.respect = 0
PokemonManager.vitaminItems = {
  hp=38781, attack=38785, defense=38782, spattack=38779, spdefense=38786, speed=38780,
  ppmax=38783, ppup=38784, level=39332
}

function PokemonManager.requestVitaminUse(status, slot)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame(); if not proto then return end
  local itemId = PokemonManager.vitaminItems[status]
  if not itemId then return end
  proto:sendExtendedOpcode(PokemonManager.opcode, 'VITAMIN_USE|' .. tostring(slot or PokemonManager.selected) .. '|' .. tostring(itemId))
end

PokemonManager.opcodeRegistered = false
PokemonManager.window = nil
PokemonManager.retryEvent = nil
PokemonManager.pokemon = {}
PokemonManager.selected = 1
PokemonManager.cards = {}
PokemonManager.baseCards = {}
PokemonManager.evCards = {}
PokemonManager.partyCards = {}
PokemonManager.moves = {}
-- Pontos de skill pras Moves: 1 por level (total = level-1), gasto ao
-- aprender uma move. PokemonManager.movePoints[slot] = {total=.., spent=..}
PokemonManager.movePoints = {}
-- Combo de moves: combo[slot] = salvo no servidor, comboDraft[slot] = editando
PokemonManager.combo = {}
PokemonManager.comboDraft = {}
PokemonManager.COMBO_MAX = 15
PokemonManager.abilities = {}
PokemonManager.abilityDesc = {}
PokemonManager.currentPage = 'summary'
PokemonManager.profile = {
  id = 0, name = '', gold = 0, pokecoins = 0, donate = 0, tokens = 0, profession = 'Nenhuma',
  level = 1, experience = 0, levelPercent = 0,
  skills = {
    fishing = {level = 0, percent = 0}
  }
}
PokemonManager.incubators = {}
for i = 1, 6 do
  PokemonManager.incubators[i] = {
    unlocked = (i == 1),
    cost = (i <= 1) and 0 or (250 + ((i - 2) * 150)),
    eggId = 0,
    startedAt = 0
  }
end
PokemonManager.incubatorTimer = nil
PokemonManager.incubatorServerOffset = 0
PokemonManager.incubatorDuration = 86400
-- Incubacao por passos: espaco separado dos 6 slots normais, o ovo choca
-- andando PM_STEP_EGG_LIMIT (10000) passos em vez de esperar tempo.
PokemonManager.stepEgg = {eggId = 0, steps = 0, limit = 10000}
PokemonManager.incubatorItems = {
  [39335] = {duration = 86400, name = '24 Hrs', image = '/modules/game_pokemonmanager/images/incub01_01.png'},
  [39336] = {duration = 43200, name = '12 Hrs', image = '/modules/game_pokemonmanager/images/incub02_02.png'},
  [39337] = {duration = 28800, name = '8 Hrs', image = '/modules/game_pokemonmanager/images/incub03_03.png'},
  [39338] = {duration = 300, name = '5 MIN', image = '/modules/game_pokemonmanager/images/incub03_04.png'}
}

-- Aceita tanto o ID real do item (39335/39336/39337/39338) quanto 1/2/3/4,
-- e usa a duracao como fallback caso o servidor antigo nao envie incubatorId.
function PokemonManager.getIncubatorInfo(data)
  if not data then return nil end

  local id = tonumber(data.incubatorId) or 0
  if id == 1 then id = 39335 end
  if id == 2 then id = 39336 end
  if id == 3 then id = 39337 end
  if id == 4 then id = 39338 end

  local info = PokemonManager.incubatorItems[id]
  if info then return info end

  local duration = tonumber(data.duration) or 0
  if duration == 86400 then return PokemonManager.incubatorItems[39335] end
  if duration == 43200 then return PokemonManager.incubatorItems[39336] end
  if duration == 28800 then return PokemonManager.incubatorItems[39337] end
  if duration == 300 then return PokemonManager.incubatorItems[39338] end

  return nil
end
PokemonManager.incubatorCounts = {[39335] = 0, [39336] = 0, [39337] = 0, [39338] = 0}
-- ClientId real do sprite (o servidor resolve via ItemType:getClientId(), pois
-- o id do items.xml e o ID DE SERVIDOR e pode ser diferente do id de sprite
-- que o UIItem do client precisa). Preenchido ao receber INCUBATOR_EGG_COUNT.
PokemonManager.incubatorClientIds = {[39335] = 0, [39336] = 0, [39337] = 0, [39338] = 0}
PokemonManager.incubatorChooser = nil
-- ovos da Creche na mochila (escolha do ovo que vai para a incubadora)
PokemonManager.crecheEggs = {}
PokemonManager.incubEggChoice = 'random'
PokemonManager.pokeEggClientId = 0
PokemonManager.incubatorChoices = {}
PokemonManager.heldItems = {}
PokemonManager.friendship = {}
-- Cores progressivas por faixa de amizade (0-100 ate 900-1000), do azul frio
-- ate o dourado, reaproveitando tons ja usados no resto da UI para manter
-- consistencia visual. A faixa MAXIMA usa o dourado padrao da interface.
PokemonManager.friendshipStageColors = {
  [0] = '#5a7ca8', [1] = '#55aaff', [2] = '#67d5c9', [3] = '#67d56f', [4] = '#b8e667',
  [5] = '#ffd34d', [6] = '#ffb04d', [7] = '#ff8f6b', [8] = '#ff6b9d', [9] = '#ff91c8'
}
PokemonManager.friendshipMaxColor = '#f2c400'
-- Mesma cor por tipo de incubadora usada nos "chips" do cabecalho da pagina,
-- reaproveitada aqui para o rotulo de tempo embaixo de cada icone de escolha.
PokemonManager.incubatorItemColors = {
  [39335] = '#9bb6dc', [39336] = '#55aaff', [39337] = '#ffd34d', [39338] = '#ff5c5c'
}
PokemonManager.evPending = {0, 0, 0, 0, 0, 0}
PokemonManager.version = 'V6.6.2'
PokemonManager.moveIcons = {
  ['absorb'] = 'grass.png',
  ['acid'] = 'poison.png',
  ['acid armor'] = 'poison.png',
  ['acid spray'] = 'poison.png',
  ['aerial ace'] = 'flying.png',
  ['aeroblast'] = 'flying.png',
  ['agility'] = 'psychic.png',
  ['air cutter'] = 'flying.png',
  ['air slash'] = 'flying.png',
  ['amnesia'] = 'psychic.png',
  ['ancient power'] = 'rock.png',
  ['aqua cutter'] = 'water.png',
  ['aqua jet'] = 'water.png',
  ['aqua ring'] = 'water.png',
  ['aqua tail'] = 'water.png',
  ['arm thrust'] = 'fighting.png',
  ['aromatherapy'] = 'grass.png',
  ['aromatic mist'] = 'fairy.png',
  ['assurance'] = 'dark.png',
  ['astonish'] = 'ghost.png',
  ['attack order'] = 'bug.png',
  ['aura sphere'] = 'fighting.png',
  ['aurora beam'] = 'ice.png',
  ['autotomize'] = 'steel.png',
  ['axe kick'] = 'fighting.png',
  ['bad dreams'] = 'dark.png',
  ['barb barrage'] = 'poison.png',
  ['barrier'] = 'psychic.png',
  ['belch'] = 'poison.png',
  ['bite'] = 'dark.png',
  ['blaze kick'] = 'fire.png',
  ['blizzard'] = 'ice.png',
  ['body press'] = 'fighting.png',
  ['body slam'] = 'normal.png',
  ['bone club'] = 'ground.png',
  ['bone rush'] = 'ground.png',
  ['bonemerang'] = 'ground.png',
  ['boomburst'] = 'normal.png',
  ['bounce'] = 'flying.png',
  ['brick break'] = 'fighting.png',
  ['brine'] = 'water.png',
  ['bubble beam'] = 'water.png',
  ['bug bite'] = 'bug.png',
  ['bug buzz'] = 'bug.png',
  ['bug judgement'] = 'bug.png',
  ['bulk up'] = 'fighting.png',
  ['bulldoze'] = 'ground.png',
  ['bullet punch'] = 'steel.png',
  ['bullet seed'] = 'grass.png',
  ['burn up'] = 'fire.png',
  ['calm mind'] = 'psychic.png',
  ['charge'] = 'electric.png',
  ['charge beam'] = 'electric.png',
  ['charm'] = 'fairy.png',
  ['chatter'] = 'flying.png',
  ['chip away'] = 'normal.png',
  ['close combat'] = 'fighting.png',
  ['coil'] = 'poison.png',
  ['confuse ray'] = 'ghost.png',
  ['confusion'] = 'psychic.png',
  ['cosmic power'] = 'psychic.png',
  ['counter'] = 'fighting.png',
  ['crabhammer'] = 'water.png',
  ['cross chop'] = 'fighting.png',
  ['cross poison'] = 'poison.png',
  ['crunch'] = 'dark.png',
  ['crush claw'] = 'normal.png',
  ['crush grip'] = 'normal.png',
  ['curse'] = 'ghost.png',
  ['dark judgement'] = 'dark.png',
  ['dark pulse'] = 'dark.png',
  ['dark void'] = 'dark.png',
  ['darkest lariat'] = 'dark.png',
  ['dazzling gleam'] = 'fairy.png',
  ['defense curl'] = 'normal.png',
  ['defense order'] = 'bug.png',
  ['detect'] = 'fighting.png',
  ['diamond storm'] = 'rock.png',
  ['dig'] = 'ground.png',
  ['dire claw'] = 'poison.png',
  ['disable'] = 'normal.png',
  ['disarming voice'] = 'fairy.png',
  ['discharge'] = 'electric.png',
  ['dive'] = 'water.png',
  ['doom desire'] = 'steel.png',
  ['doom desire'] = 'steel.png',
  ['double hit'] = 'normal.png',
  ['double kick'] = 'fighting.png',
  ['double slap'] = 'normal.png',
  ['double team'] = 'normal.png',
  ['dragon ascent'] = 'flying.png',
  ['dragon breath'] = 'dragon.png',
  ['dragon claw'] = 'dragon.png',
  ['dragon dance'] = 'dragon.png',
  ['dragon darts'] = 'dragon.png',
  ['dragon judgement'] = 'dragon.png',
  ['dragon pulse'] = 'dragon.png',
  ['dragon rage'] = 'dragon.png',
  ['dragon rush'] = 'dragon.png',
  ['dragon tail'] = 'dragon.png',
  ['drain punch'] = 'fighting.png',
  ['draining kiss'] = 'fairy.png',
  ['dream eater'] = 'psychic.png',
  ['drill peck'] = 'flying.png',
  ['drill run'] = 'ground.png',
  ['dual chop'] = 'dragon.png',
  ['dual wingbeat'] = 'dragon.png',
  ['dynamic punch'] = 'fighting.png',
  ['dynamic punch'] = 'fighting.png',
  ['earth power'] = 'ground.png',
  ['earthquake'] = 'ground.png',
  ['echoed voice'] = 'normal.png',
  ['eerie impulse'] = 'electric.png',
  ['electric judgement'] = 'electric.png',
  ['electric terrain'] = 'electric.png',
  ['electro ball'] = 'electric.png',
  ['ember'] = 'fire.png',
  ['endure'] = 'normal.png',
  ['energy ball'] = 'grass.png',
  ['eruption'] = 'fire.png',
  ['eruption'] = 'fire.png',
  ['extrasensory'] = 'psychic.png',
  ['extreme speed'] = 'normal.png',
  ['facade'] = 'normal.png',
  ['fairy judgement'] = 'fairy.png',
  ['fairy wind'] = 'fairy.png',
  ['fake out'] = 'normal.png',
  ['fake tears'] = 'dark.png',
  ['false surrender'] = 'dark.png',
  ['feather dance'] = 'flying.png',
  ['feint'] = 'normal.png',
  ['feint attack'] = 'dark.png',
  ['fell stinger'] = 'bug.png',
  ['fighting judgement'] = 'fighting.png',
  ['fire blast'] = 'fire.png',
  ['fire fang'] = 'fire.png',
  ['fire judgement'] = 'fire.png',
  ['fire punch'] = 'fire.png',
  ['fire spin'] = 'fire.png',
  ['fissure'] = 'ground.png',
  ['flail'] = 'normal.png',
  ['flame charge'] = 'fire.png',
  ['flame wheel'] = 'fire.png',
  ['flamethrower'] = 'fire.png',
  ['flare blitz'] = 'fire.png',
  ['flash cannon'] = 'steel.png',
  ['fly'] = 'flying.png',
  ['flying judgement'] = 'flying.png',
  ['focus energy'] = 'fighting.png',
  ['focus punch'] = 'fighting.png',
  ['follow me'] = 'normal.png',
  ['force palm'] = 'fighting.png',
  ['foul play'] = 'dark.png',
  ['freeze-dry'] = 'ice.png',
  ['fury cutter'] = 'bug.png',
  ['future sight'] = 'psychic.png',
  ['gear grind'] = 'steel.png',
  ['ghost judgement'] = 'ghost.png',
  ['giga drain'] = 'grass.png',
  ['giga impact'] = 'normal.png',
  ['grass judgement'] = 'grass.png',
  ['gravity'] = 'psychic.png',
  ['ground judgement'] = 'ground.png',
  ['growl'] = 'normal.png',
  ['guard swap'] = 'psychic.png',
  ['guillotine'] = 'normal.png',
  ['gunk shot'] = 'poison.png',
  ['gust'] = 'flying.png',
  ['gyro ball'] = 'steel.png',
  ['hail'] = 'ice.png',
  ['hammer arm'] = 'fighting.png',
  ['harden'] = 'normal.png',
  ['head smash'] = 'rock.png',
  ['headbutt'] = 'normal.png',
  ['heal pulse'] = 'psychic.png',
  ['healing wish'] = 'psychic.png',
  ['healing wish'] = 'psychic.png',
  ['heat wave'] = 'fire.png',
  ['heavy slam'] = 'steel.png',
  ['helping hand'] = 'normal.png',
  ['hex'] = 'ghost.png',
  ['hidden power'] = 'normal.png',
  ['high horsepower'] = 'ground.png',
  ['high jump kick'] = 'fighting.png',
  ['horn attack'] = 'normal.png',
  ['horn drill'] = 'normal.png',
  ['hurricane'] = 'flying.png',
  ['hydro pump'] = 'water.png',
  ['hyper beam'] = 'normal.png',
  ['hyper voice'] = 'normal.png',
  ['hyperspace fury'] = 'dark.png',
  ['hyperspace hole'] = 'psychic.png',
  ['hypnosis'] = 'psychic.png',
  ['ice beam'] = 'ice.png',
  ['ice fang'] = 'ice.png',
  ['ice judgement'] = 'ice.png',
  ['ice punch'] = 'ice.png',
  ['ice shard'] = 'ice.png',
  ['icicle crash'] = 'ice.png',
  ['icicle spear'] = 'ice.png',
  ['icy wind'] = 'ice.png',
  ['imprison'] = 'psychic.png',
  ['incinerate'] = 'fire.png',
  ['inferno'] = 'fire.png',
  ['infestation'] = 'bug.png',
  ['ingrain'] = 'grass.png',
  ['iron defense'] = 'steel.png',
  ['iron head'] = 'steel.png',
  ['iron tail'] = 'steel.png',
  ['karate chop'] = 'fighting.png',
  ['kinesis'] = 'psychic.png',
  ['knock off'] = 'dark.png',
  ['lava plume'] = 'fire.png',
  ['leaf blade'] = 'grass.png',
  ['leaf storm'] = 'grass.png',
  ['leaf tornado'] = 'grass.png',
  ['leafage'] = 'grass.png',
  ['leech life'] = 'bug.png',
  ['leech seed'] = 'grass.png',
  ['leer'] = 'normal.png',
  ['lick'] = 'ghost.png',
  ['life dew'] = 'water.png',
  ['light screen'] = 'psychic.png',
  ['liquidation'] = 'water.png',
  ['lock-on'] = 'normal.png',
  ['low kick'] = 'fighting.png',
  ['low sweep'] = 'fighting.png',
  ['lunar blessing'] = 'psychic.png',
  ['luster purge'] = 'psychic.png',
  ['mach punch'] = 'fighting.png',
  ['magical leaf'] = 'grass.png',
  ['magma storm'] = 'fire.png',
  ['magnet rise'] = 'electric.png',
  ['make it rain'] = 'steel.png',
  ['me first'] = 'normal.png',
  ['me first'] = 'normal.png',
  ['mega drain'] = 'grass.png',
  ['mega punch'] = 'normal.png',
  ['megahorn'] = 'bug.png',
  ['metal burst'] = 'steel.png',
  ['metal claw'] = 'steel.png',
  ['metal sound'] = 'steel.png',
  ['meteor assault'] = 'fighting.png',
  ['meteor mash'] = 'steel.png',
  ['metronome'] = 'normal.png',
  ['milk drink'] = 'normal.png',
  ['minimize'] = 'normal.png',
  ['mirror coat'] = 'psychic.png',
  ['mirror shot'] = 'steel.png',
  ['mist ball'] = 'psychic.png',
  ['misty terrain'] = 'fairy.png',
  ['moonblast'] = 'fairy.png',
  ['moonlight'] = 'fairy.png',
  ['mountain gale'] = 'ice.png',
  ['mud shot'] = 'ground.png',
  ['muddy water'] = 'water.png',
  ['mystical fire'] = 'fire.png',
  ['mystical power'] = 'psychic.png',
  ['nasty plot'] = 'dark.png',
  ['nature power'] = 'normal.png',
  ['needle arm'] = 'grass.png',
  ['night daze'] = 'dark.png',
  ['night shade'] = 'ghost.png',
  ['night slash'] = 'dark.png',
  ['nightmare'] = 'ghost.png',
  ['normal judgement'] = 'normal.png',
  ['octazooka'] = 'water.png',
  ['ominous wind'] = 'ghost.png',
  ['origin pulse'] = 'water.png',
  ['outrage'] = 'dragon.png',
  ['overheat'] = 'fire.png',
  ['pay day'] = 'normal.png',
  ['payback'] = 'dark.png',
  ['peck'] = 'flying.png',
  ['perish song'] = 'normal.png',
  ['petal blizzard'] = 'grass.png',
  ['petal dance'] = 'grass.png',
  ['phantom force'] = 'ghost.png',
  ['pin missile'] = 'bug.png',
  ['play rough'] = 'fairy.png',
  ['poison fang'] = 'poison.png',
  ['poison fang'] = 'poison.png',
  ['poison gas'] = 'poison.png',
  ['poison jab'] = 'poison.png',
  ['poison judgement'] = 'poison.png',
  ['poison powder'] = 'poison.png',
  ['poison sting'] = 'poison.png',
  ['poison tail'] = 'poison.png',
  ['pound'] = 'normal.png',
  ['powder snow'] = 'ice.png',
  ['power gem'] = 'rock.png',
  ['power swap'] = 'psychic.png',
  ['power whip'] = 'grass.png',
  ['power whip'] = 'grass.png',
  ['power-up punch'] = 'fighting.png',
  ['precipice blades'] = 'ground.png',
  ['present'] = 'normal.png',
  ['protect'] = 'normal.png',
  ['psybeam'] = 'psychic.png',
  ['psychic'] = 'psychic.png',
  ['psychic judgement'] = 'psychic.png',
  ['psycho boost'] = 'psychic.png',
  ['psycho cut'] = 'psychic.png',
  ['psyshock'] = 'psychic.png',
  ['psystrike'] = 'psychic.png',
  ['psywave'] = 'psychic.png',
  ['punishment'] = 'dark.png',
  ['pyro ball'] = 'fire.png',
  ['quick attack'] = 'normal.png',
  ['quiver dance'] = 'bug.png',
  ['rage fist'] = 'ghost.png',
  ['raging bull'] = 'normal.png',
  ['raging fury'] = 'fire.png',
  ['rain dance'] = 'water.png',
  ['rain dance'] = 'water.png',
  ['rapid spin'] = 'normal.png',
  ['razor leaf'] = 'grass.png',
  ['razor shell'] = 'water.png',
  ['recover'] = 'normal.png',
  ['reflect'] = 'psychic.png',
  ['refresh'] = 'normal.png',
  ['rest'] = 'psychic.png',
  ['revenge'] = 'fighting.png',
  ['reversal'] = 'fighting.png',
  ['roar of time'] = 'dragon.png',
  ['rock blast'] = 'rock.png',
  ['rock judgement'] = 'rock.png',
  ['rock polish'] = 'rock.png',
  ['rock slide'] = 'rock.png',
  ['rock smash'] = 'fighting.png',
  ['rock throw'] = 'rock.png',
  ['rock tomb'] = 'rock.png',
  ['rock wrecker'] = 'rock.png',
  ['rolling kick'] = 'fighting.png',
  ['rollout'] = 'rock.png',
  ['roost'] = 'flying.png',
  ['round'] = 'normal.png',
  ['sacred fire'] = 'fire.png',
  ['sand tomb'] = 'ground.png',
  ['sandstorm'] = 'rock.png',
  ['scary face'] = 'normal.png',
  ['scratch'] = 'normal.png',
  ['screech'] = 'normal.png',
  ['seed bomb'] = 'grass.png',
  ['seed flare'] = 'grass.png',
  ['seismic toss'] = 'fighting.png',
  ['self-destruct'] = 'normal.png',
  ['shadow ball'] = 'ghost.png',
  ['shadow bone'] = 'ghost.png',
  ['shadow claw'] = 'ghost.png',
  ['shadow force'] = 'ghost.png',
  ['shadow punch'] = 'ghost.png',
  ['shadow sneak'] = 'ghost.png',
  ['sheer cold'] = 'ice.png',
  ['shell smash'] = 'normal.png',
  ['shift gear'] = 'steel.png',
  ['shock wave'] = 'electric.png',
  ['signal beam'] = 'bug.png',
  ['silver wind'] = 'bug.png',
  ['sing'] = 'normal.png',
  ['sketch1'] = 'normal.png',
  ['sketch10'] = 'normal.png',
  ['sketch2'] = 'normal.png',
  ['sketch3'] = 'normal.png',
  ['sketch4'] = 'normal.png',
  ['sketch5'] = 'normal.png',
  ['sketch6'] = 'normal.png',
  ['sketch7'] = 'normal.png',
  ['sketch8'] = 'normal.png',
  ['sketch9'] = 'normal.png',
  ['sky attack'] = 'flying.png',
  ['slash'] = 'normal.png',
  ['slash'] = 'normal.png',
  ['sleep powder'] = 'grass.png',
  ['sludge'] = 'poison.png',
  ['sludge bomb'] = 'poison.png',
  ['sludge wave'] = 'poison.png',
  ['smelling salts'] = 'fighting.png',
  ['smog'] = 'poison.png',
  ['smokescreen'] = 'normal.png',
  ['snarl'] = 'dark.png',
  ['soft-boiled'] = 'normal.png',
  ['solar beam'] = 'grass.png',
  ['spacial rend'] = 'dragon.png',
  ['spark'] = 'electric.png',
  ['sparkling aria'] = 'water.png',
  ['spider web'] = 'bug.png',
  ['spiky shield'] = 'grass.png',
  ['spirit shackle'] = 'ghost.png',
  ['steamroller'] = 'bug.png',
  ['steel judgement'] = 'steel.png',
  ['steel wing'] = 'steel.png',
  ['stomp'] = 'normal.png',
  ['stomping tantrum'] = 'ground.png',
  ['stone axe'] = 'rock.png',
  ['stone edge'] = 'rock.png',
  ['stored power'] = 'psychic.png',
  ['strange steam'] = 'fairy.png',
  ['string shot'] = 'bug.png',
  ['struggle bug'] = 'bug.png',
  ['stun spore'] = 'grass.png',
  ['sucker punch'] = 'dark.png',
  ['sunny day'] = 'fire.png',
  ['sunny day'] = 'fire.png',
  ['super fang'] = 'normal.png',
  ['superpower'] = 'fighting.png',
  ['supersonic'] = 'normal.png',
  ['surf'] = 'water.png',
  ['swords dance'] = 'normal.png',
  ['synthesis'] = 'grass.png',
  ['tackle'] = 'normal.png',
  ['tail whip'] = 'normal.png',
  ['tailwind'] = 'flying.png',
  ['teeter dance'] = 'normal.png',
  ['testmove'] = 'psychic.png',
  ['thrash'] = 'normal.png',
  ['throat chop'] = 'dark.png',
  ['thunder'] = 'electric.png',
  ['thunder fang'] = 'electric.png',
  ['thunder punch'] = 'electric.png',
  ['thunder shock'] = 'electric.png',
  ['thunder wave'] = 'electric.png',
  ['thunderbolt'] = 'electric.png',
  ['torment'] = 'dark.png',
  ['toxic'] = 'poison.png',
  ['tri attack'] = 'normal.png',
  ['triple kick'] = 'fighting.png',
  ['twineedle'] = 'bug.png',
  ['twister'] = 'dragon.png',
  ['uproar'] = 'normal.png',
  ['venoshock'] = 'poison.png',
  ['vine whip'] = 'grass.png',
  ['vital throw'] = 'fighting.png',
  ['volt switch'] = 'electric.png',
  ['wake-up slap'] = 'fighting.png',
  ['water gun'] = 'water.png',
  ['water judgement'] = 'water.png',
  ['water pulse'] = 'water.png',
  ['water shuriken'] = 'water.png',
  ['water spout'] = 'water.png',
  ['waterfall'] = 'water.png',
  ['wave crash'] = 'water.png',
  ['weather ball'] = 'normal.png',
  ['whirlpool'] = 'water.png',
  ['wide guard'] = 'rock.png',
  ['wild charge'] = 'electric.png',
  ['will-o-wisp'] = 'ghost.png',
  ['wing attack'] = 'flying.png',
  ['withdraw'] = 'water.png',
  ['wood hammer'] = 'grass.png',
  ['wood hammer'] = 'grass.png',
  ['wrap'] = 'normal.png',
  ['x-scissor'] = 'bug.png',
  ['zap cannon'] = 'electric.png',
  ['zen headbutt'] = 'psychic.png',
}
PokemonManager.moveTypes = {
  ['absorb'] = 'GRASS',
  ['acid'] = 'POISON',
  ['acid armor'] = 'POISON',
  ['acid spray'] = 'POISON',
  ['aerial ace'] = 'FLYING',
  ['aeroblast'] = 'FLYING',
  ['agility'] = 'PSYCHIC',
  ['air cutter'] = 'FLYING',
  ['air slash'] = 'FLYING',
  ['amnesia'] = 'PSYCHIC',
  ['ancient power'] = 'ROCK',
  ['aqua cutter'] = 'WATER',
  ['aqua jet'] = 'WATER',
  ['aqua ring'] = 'WATER',
  ['aqua tail'] = 'WATER',
  ['arm thrust'] = 'FIGHTING',
  ['aromatherapy'] = 'GRASS',
  ['aromatic mist'] = 'FAIRY',
  ['assurance'] = 'DARK',
  ['astonish'] = 'GHOST',
  ['attack order'] = 'BUG',
  ['aura sphere'] = 'FIGHTING',
  ['aurora beam'] = 'ICE',
  ['autotomize'] = 'STEEL',
  ['axe kick'] = 'FIGHTING',
  ['bad dreams'] = 'DARK',
  ['barb barrage'] = 'POISON',
  ['barrier'] = 'PSYCHIC',
  ['belch'] = 'POISON',
  ['bite'] = 'DARK',
  ['blaze kick'] = 'FIRE',
  ['blizzard'] = 'ICE',
  ['body press'] = 'FIGHTING',
  ['body slam'] = 'NORMAL',
  ['bone club'] = 'GROUND',
  ['bone rush'] = 'GROUND',
  ['bonemerang'] = 'GROUND',
  ['boomburst'] = 'NORMAL',
  ['bounce'] = 'FLYING',
  ['brick break'] = 'FIGHTING',
  ['brine'] = 'WATER',
  ['bubble beam'] = 'WATER',
  ['bug bite'] = 'BUG',
  ['bug buzz'] = 'BUG',
  ['bug judgement'] = 'BUG',
  ['bulk up'] = 'FIGHTING',
  ['bulldoze'] = 'GROUND',
  ['bullet punch'] = 'STEEL',
  ['bullet seed'] = 'GRASS',
  ['burn up'] = 'FIRE',
  ['calm mind'] = 'PSYCHIC',
  ['charge'] = 'ELECTRIC',
  ['charge beam'] = 'ELECTRIC',
  ['charm'] = 'FAIRY',
  ['chatter'] = 'FLYING',
  ['chip away'] = 'NORMAL',
  ['close combat'] = 'FIGHTING',
  ['coil'] = 'POISON',
  ['confuse ray'] = 'GHOST',
  ['confusion'] = 'PSYCHIC',
  ['cosmic power'] = 'PSYCHIC',
  ['counter'] = 'FIGHTING',
  ['crabhammer'] = 'WATER',
  ['cross chop'] = 'FIGHTING',
  ['cross poison'] = 'POISON',
  ['crunch'] = 'DARK',
  ['crush claw'] = 'NORMAL',
  ['crush grip'] = 'NORMAL',
  ['curse'] = 'GHOST',
  ['dark judgement'] = 'DARK',
  ['dark pulse'] = 'DARK',
  ['dark void'] = 'DARK',
  ['darkest lariat'] = 'DARK',
  ['dazzling gleam'] = 'FAIRY',
  ['defense curl'] = 'NORMAL',
  ['defense order'] = 'BUG',
  ['detect'] = 'FIGHTING',
  ['diamond storm'] = 'ROCK',
  ['dig'] = 'GROUND',
  ['dire claw'] = 'POISON',
  ['disable'] = 'NORMAL',
  ['disarming voice'] = 'FAIRY',
  ['discharge'] = 'ELECTRIC',
  ['dive'] = 'WATER',
  ['doom desire'] = 'STEEL',
  ['double hit'] = 'NORMAL',
  ['double kick'] = 'FIGHTING',
  ['double slap'] = 'NORMAL',
  ['double team'] = 'NORMAL',
  ['dragon ascent'] = 'FLYING',
  ['dragon breath'] = 'DRAGON',
  ['dragon claw'] = 'DRAGON',
  ['dragon dance'] = 'DRAGON',
  ['dragon darts'] = 'DRAGON',
  ['dragon judgement'] = 'DRAGON',
  ['dragon pulse'] = 'DRAGON',
  ['dragon rage'] = 'DRAGON',
  ['dragon rush'] = 'DRAGON',
  ['dragon tail'] = 'DRAGON',
  ['drain punch'] = 'FIGHTING',
  ['draining kiss'] = 'FAIRY',
  ['dream eater'] = 'PSYCHIC',
  ['drill peck'] = 'FLYING',
  ['drill run'] = 'GROUND',
  ['dual chop'] = 'DRAGON',
  ['dual wingbeat'] = 'DRAGON',
  ['dynamic punch'] = 'FIGHTING',
  ['earth power'] = 'GROUND',
  ['earthquake'] = 'GROUND',
  ['echoed voice'] = 'NORMAL',
  ['eerie impulse'] = 'ELECTRIC',
  ['electric judgement'] = 'ELECTRIC',
  ['electric terrain'] = 'ELECTRIC',
  ['electro ball'] = 'ELECTRIC',
  ['ember'] = 'FIRE',
  ['endure'] = 'NORMAL',
  ['energy ball'] = 'GRASS',
  ['eruption'] = 'FIRE',
  ['extrasensory'] = 'PSYCHIC',
  ['extreme speed'] = 'NORMAL',
  ['facade'] = 'NORMAL',
  ['fairy judgement'] = 'FAIRY',
  ['fairy wind'] = 'FAIRY',
  ['fake out'] = 'NORMAL',
  ['fake tears'] = 'DARK',
  ['false surrender'] = 'DARK',
  ['feather dance'] = 'FLYING',
  ['feint'] = 'NORMAL',
  ['feint attack'] = 'DARK',
  ['fell stinger'] = 'BUG',
  ['fighting judgement'] = 'FIGHTING',
  ['fire blast'] = 'FIRE',
  ['fire fang'] = 'FIRE',
  ['fire judgement'] = 'FIRE',
  ['fire punch'] = 'FIRE',
  ['fire spin'] = 'FIRE',
  ['fissure'] = 'GROUND',
  ['flail'] = 'NORMAL',
  ['flame charge'] = 'FIRE',
  ['flame wheel'] = 'FIRE',
  ['flamethrower'] = 'FIRE',
  ['flare blitz'] = 'FIRE',
  ['flash cannon'] = 'STEEL',
  ['fly'] = 'FLYING',
  ['flying judgement'] = 'FLYING',
  ['focus energy'] = 'FIGHTING',
  ['focus punch'] = 'FIGHTING',
  ['follow me'] = 'NORMAL',
  ['force palm'] = 'FIGHTING',
  ['foul play'] = 'DARK',
  ['freeze-dry'] = 'ICE',
  ['fury cutter'] = 'BUG',
  ['future sight'] = 'PSYCHIC',
  ['gear grind'] = 'STEEL',
  ['ghost judgement'] = 'GHOST',
  ['giga drain'] = 'GRASS',
  ['giga impact'] = 'NORMAL',
  ['grass judgement'] = 'GRASS',
  ['gravity'] = 'PSYCHIC',
  ['ground judgement'] = 'GROUND',
  ['growl'] = 'NORMAL',
  ['guard swap'] = 'PSYCHIC',
  ['guillotine'] = 'NORMAL',
  ['gunk shot'] = 'POISON',
  ['gust'] = 'FLYING',
  ['gyro ball'] = 'STEEL',
  ['hail'] = 'ICE',
  ['hammer arm'] = 'FIGHTING',
  ['harden'] = 'NORMAL',
  ['head smash'] = 'ROCK',
  ['headbutt'] = 'NORMAL',
  ['heal pulse'] = 'PSYCHIC',
  ['healing wish'] = 'PSYCHIC',
  ['heat wave'] = 'FIRE',
  ['heavy slam'] = 'STEEL',
  ['helping hand'] = 'NORMAL',
  ['hex'] = 'GHOST',
  ['hidden power'] = 'NORMAL',
  ['high horsepower'] = 'GROUND',
  ['high jump kick'] = 'FIGHTING',
  ['horn attack'] = 'NORMAL',
  ['horn drill'] = 'NORMAL',
  ['hurricane'] = 'FLYING',
  ['hydro pump'] = 'WATER',
  ['hyper beam'] = 'NORMAL',
  ['hyper voice'] = 'NORMAL',
  ['hyperspace fury'] = 'DARK',
  ['hyperspace hole'] = 'PSYCHIC',
  ['hypnosis'] = 'PSYCHIC',
  ['ice beam'] = 'ICE',
  ['ice fang'] = 'ICE',
  ['ice judgement'] = 'ICE',
  ['ice punch'] = 'ICE',
  ['ice shard'] = 'ICE',
  ['icicle crash'] = 'ICE',
  ['icicle spear'] = 'ICE',
  ['icy wind'] = 'ICE',
  ['imprison'] = 'PSYCHIC',
  ['incinerate'] = 'FIRE',
  ['inferno'] = 'FIRE',
  ['infestation'] = 'BUG',
  ['ingrain'] = 'GRASS',
  ['iron defense'] = 'STEEL',
  ['iron head'] = 'STEEL',
  ['iron tail'] = 'STEEL',
  ['karate chop'] = 'FIGHTING',
  ['kinesis'] = 'PSYCHIC',
  ['knock off'] = 'DARK',
  ['lava plume'] = 'FIRE',
  ['leaf blade'] = 'GRASS',
  ['leaf storm'] = 'GRASS',
  ['leaf tornado'] = 'GRASS',
  ['leafage'] = 'GRASS',
  ['leech life'] = 'BUG',
  ['leech seed'] = 'GRASS',
  ['leer'] = 'NORMAL',
  ['lick'] = 'GHOST',
  ['life dew'] = 'WATER',
  ['light screen'] = 'PSYCHIC',
  ['liquidation'] = 'WATER',
  ['lock-on'] = 'NORMAL',
  ['low kick'] = 'FIGHTING',
  ['low sweep'] = 'FIGHTING',
  ['lunar blessing'] = 'PSYCHIC',
  ['luster purge'] = 'PSYCHIC',
  ['mach punch'] = 'FIGHTING',
  ['magical leaf'] = 'GRASS',
  ['magma storm'] = 'FIRE',
  ['magnet rise'] = 'ELECTRIC',
  ['make it rain'] = 'STEEL',
  ['me first'] = 'NORMAL',
  ['mega drain'] = 'GRASS',
  ['mega punch'] = 'NORMAL',
  ['megahorn'] = 'BUG',
  ['metal burst'] = 'STEEL',
  ['metal claw'] = 'STEEL',
  ['metal sound'] = 'STEEL',
  ['meteor assault'] = 'FIGHTING',
  ['meteor mash'] = 'STEEL',
  ['metronome'] = 'NORMAL',
  ['milk drink'] = 'NORMAL',
  ['minimize'] = 'NORMAL',
  ['mirror coat'] = 'PSYCHIC',
  ['mirror shot'] = 'STEEL',
  ['mist ball'] = 'PSYCHIC',
  ['misty terrain'] = 'FAIRY',
  ['moonblast'] = 'FAIRY',
  ['moonlight'] = 'FAIRY',
  ['mountain gale'] = 'ICE',
  ['mud shot'] = 'GROUND',
  ['muddy water'] = 'WATER',
  ['mystical fire'] = 'FIRE',
  ['mystical power'] = 'PSYCHIC',
  ['nasty plot'] = 'DARK',
  ['nature power'] = 'NORMAL',
  ['needle arm'] = 'GRASS',
  ['night daze'] = 'DARK',
  ['night shade'] = 'GHOST',
  ['night slash'] = 'DARK',
  ['nightmare'] = 'GHOST',
  ['normal judgement'] = 'NORMAL',
  ['octazooka'] = 'WATER',
  ['ominous wind'] = 'GHOST',
  ['origin pulse'] = 'WATER',
  ['outrage'] = 'DRAGON',
  ['overheat'] = 'FIRE',
  ['pay day'] = 'NORMAL',
  ['payback'] = 'DARK',
  ['peck'] = 'FLYING',
  ['perish song'] = 'NORMAL',
  ['petal blizzard'] = 'GRASS',
  ['petal dance'] = 'GRASS',
  ['phantom force'] = 'GHOST',
  ['pin missile'] = 'BUG',
  ['play rough'] = 'FAIRY',
  ['poison fang'] = 'POISON',
  ['poison gas'] = 'POISON',
  ['poison jab'] = 'POISON',
  ['poison judgement'] = 'POISON',
  ['poison powder'] = 'POISON',
  ['poison sting'] = 'POISON',
  ['poison tail'] = 'POISON',
  ['pound'] = 'NORMAL',
  ['powder snow'] = 'ICE',
  ['power gem'] = 'ROCK',
  ['power swap'] = 'PSYCHIC',
  ['power whip'] = 'GRASS',
  ['power-up punch'] = 'FIGHTING',
  ['precipice blades'] = 'GROUND',
  ['present'] = 'NORMAL',
  ['protect'] = 'NORMAL',
  ['psybeam'] = 'PSYCHIC',
  ['psychic'] = 'PSYCHIC',
  ['psychic judgement'] = 'PSYCHIC',
  ['psycho boost'] = 'PSYCHIC',
  ['psycho cut'] = 'PSYCHIC',
  ['psyshock'] = 'PSYCHIC',
  ['psystrike'] = 'PSYCHIC',
  ['psywave'] = 'PSYCHIC',
  ['punishment'] = 'DARK',
  ['pyro ball'] = 'FIRE',
  ['quick attack'] = 'NORMAL',
  ['quiver dance'] = 'BUG',
  ['rage fist'] = 'GHOST',
  ['raging bull'] = 'NORMAL',
  ['raging fury'] = 'FIRE',
  ['rain dance'] = 'WATER',
  ['rapid spin'] = 'NORMAL',
  ['razor leaf'] = 'GRASS',
  ['razor shell'] = 'WATER',
  ['recover'] = 'NORMAL',
  ['reflect'] = 'PSYCHIC',
  ['refresh'] = 'NORMAL',
  ['rest'] = 'PSYCHIC',
  ['revenge'] = 'FIGHTING',
  ['reversal'] = 'FIGHTING',
  ['roar of time'] = 'DRAGON',
  ['rock blast'] = 'ROCK',
  ['rock judgement'] = 'ROCK',
  ['rock polish'] = 'ROCK',
  ['rock slide'] = 'ROCK',
  ['rock smash'] = 'FIGHTING',
  ['rock throw'] = 'ROCK',
  ['rock tomb'] = 'ROCK',
  ['rock wrecker'] = 'ROCK',
  ['rolling kick'] = 'FIGHTING',
  ['rollout'] = 'ROCK',
  ['roost'] = 'FLYING',
  ['round'] = 'NORMAL',
  ['sacred fire'] = 'FIRE',
  ['sand tomb'] = 'GROUND',
  ['sandstorm'] = 'ROCK',
  ['scary face'] = 'NORMAL',
  ['scratch'] = 'NORMAL',
  ['screech'] = 'NORMAL',
  ['seed bomb'] = 'GRASS',
  ['seed flare'] = 'GRASS',
  ['seismic toss'] = 'FIGHTING',
  ['self-destruct'] = 'NORMAL',
  ['shadow ball'] = 'GHOST',
  ['shadow bone'] = 'GHOST',
  ['shadow claw'] = 'GHOST',
  ['shadow force'] = 'GHOST',
  ['shadow punch'] = 'GHOST',
  ['shadow sneak'] = 'GHOST',
  ['sheer cold'] = 'ICE',
  ['shell smash'] = 'NORMAL',
  ['shift gear'] = 'STEEL',
  ['shock wave'] = 'ELECTRIC',
  ['signal beam'] = 'BUG',
  ['silver wind'] = 'BUG',
  ['sing'] = 'NORMAL',
  ['sketch1'] = 'NORMAL',
  ['sketch10'] = 'NORMAL',
  ['sketch2'] = 'NORMAL',
  ['sketch3'] = 'NORMAL',
  ['sketch4'] = 'NORMAL',
  ['sketch5'] = 'NORMAL',
  ['sketch6'] = 'NORMAL',
  ['sketch7'] = 'NORMAL',
  ['sketch8'] = 'NORMAL',
  ['sketch9'] = 'NORMAL',
  ['sky attack'] = 'FLYING',
  ['slash'] = 'NORMAL',
  ['sleep powder'] = 'GRASS',
  ['sludge'] = 'POISON',
  ['sludge bomb'] = 'POISON',
  ['sludge wave'] = 'POISON',
  ['smelling salts'] = 'FIGHTING',
  ['smog'] = 'POISON',
  ['smokescreen'] = 'NORMAL',
  ['snarl'] = 'DARK',
  ['soft-boiled'] = 'NORMAL',
  ['solar beam'] = 'GRASS',
  ['spacial rend'] = 'DRAGON',
  ['spark'] = 'ELECTRIC',
  ['sparkling aria'] = 'WATER',
  ['spider web'] = 'BUG',
  ['spiky shield'] = 'GRASS',
  ['spirit shackle'] = 'GHOST',
  ['steamroller'] = 'BUG',
  ['steel judgement'] = 'STEEL',
  ['steel wing'] = 'STEEL',
  ['stomp'] = 'NORMAL',
  ['stomping tantrum'] = 'GROUND',
  ['stone axe'] = 'ROCK',
  ['stone edge'] = 'ROCK',
  ['stored power'] = 'PSYCHIC',
  ['strange steam'] = 'FAIRY',
  ['string shot'] = 'BUG',
  ['struggle bug'] = 'BUG',
  ['stun spore'] = 'GRASS',
  ['sucker punch'] = 'DARK',
  ['sunny day'] = 'FIRE',
  ['super fang'] = 'NORMAL',
  ['superpower'] = 'FIGHTING',
  ['supersonic'] = 'NORMAL',
  ['surf'] = 'WATER',
  ['swords dance'] = 'NORMAL',
  ['synthesis'] = 'GRASS',
  ['tackle'] = 'NORMAL',
  ['tail whip'] = 'NORMAL',
  ['tailwind'] = 'FLYING',
  ['teeter dance'] = 'NORMAL',
  ['testmove'] = 'PSYCHIC',
  ['thrash'] = 'NORMAL',
  ['throat chop'] = 'DARK',
  ['thunder'] = 'ELECTRIC',
  ['thunder fang'] = 'ELECTRIC',
  ['thunder punch'] = 'ELECTRIC',
  ['thunder shock'] = 'ELECTRIC',
  ['thunder wave'] = 'ELECTRIC',
  ['thunderbolt'] = 'ELECTRIC',
  ['torment'] = 'DARK',
  ['toxic'] = 'POISON',
  ['tri attack'] = 'NORMAL',
  ['triple kick'] = 'FIGHTING',
  ['twineedle'] = 'BUG',
  ['twister'] = 'DRAGON',
  ['uproar'] = 'NORMAL',
  ['venoshock'] = 'POISON',
  ['vine whip'] = 'GRASS',
  ['vital throw'] = 'FIGHTING',
  ['volt switch'] = 'ELECTRIC',
  ['wake-up slap'] = 'FIGHTING',
  ['water gun'] = 'WATER',
  ['water judgement'] = 'WATER',
  ['water pulse'] = 'WATER',
  ['water shuriken'] = 'WATER',
  ['water spout'] = 'WATER',
  ['waterfall'] = 'WATER',
  ['wave crash'] = 'WATER',
  ['weather ball'] = 'NORMAL',
  ['whirlpool'] = 'WATER',
  ['wide guard'] = 'ROCK',
  ['wild charge'] = 'ELECTRIC',
  ['will-o-wisp'] = 'GHOST',
  ['wing attack'] = 'FLYING',
  ['withdraw'] = 'WATER',
  ['wood hammer'] = 'GRASS',
  ['wrap'] = 'NORMAL',
  ['x-scissor'] = 'BUG',
  ['zap cannon'] = 'ELECTRIC',
  ['zen headbutt'] = 'PSYCHIC',
}

function PokemonManager.loadCustomFonts()
  -- o Manager usa so as fontes padrao do cliente (verdana-11px-rounded / antialised)
end

function init()
  PokemonManager.loadCustomFonts()
  connect(g_game, { onGameStart = PokemonManager.onGameStart, onGameEnd = PokemonManager.onGameEnd }, true)
  local root = modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
  g_keyboard.bindKeyPress('Ctrl+D', PokemonManager.toggle, root)
  modules.game_pokemonmanager = PokemonManager
  g_logger.info('[PokemonManager V6.6.2] Modulo carregado. OPCODE=89')
  PokemonManager.tryRegisterOpcode()
end

function terminate()
  local root = modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
  g_keyboard.unbindKeyPress('Ctrl+D', root)
  if PokemonManager.retryEvent then removeEvent(PokemonManager.retryEvent) PokemonManager.retryEvent = nil end
  PokemonManager.destroy()
  if PokemonManager.opcodeRegistered then
    pcall(function() ProtocolGame.unregisterExtendedOpcode(PokemonManager.opcode) end)
  end
  PokemonManager.opcodeRegistered = false
  modules.game_pokemonmanager = nil
end

function PokemonManager.tryRegisterOpcode()
  if PokemonManager.opcodeRegistered or not g_game.isOnline() then return PokemonManager.opcodeRegistered end
  local proto = g_game.getProtocolGame()
  if not proto then return false end
  local ok, err = pcall(function() ProtocolGame.registerExtendedOpcode(PokemonManager.opcode, PokemonManager.onExtendedOpcode) end)
  if ok then
    PokemonManager.opcodeRegistered = true
    g_logger.info('[PokemonManager V6.6.2] Opcode 89 registrado.')
    return true
  end
  g_logger.error('[PokemonManager V6.6.2] Erro ao registrar Opcode 89: ' .. tostring(err))
  if not PokemonManager.retryEvent then
    PokemonManager.retryEvent = scheduleEvent(function() PokemonManager.retryEvent=nil PokemonManager.tryRegisterOpcode() end, 1000)
  end
  return false
end

function PokemonManager.onGameStart()
  PokemonManager.opcodeRegistered = false
  PokemonManager.pokemon = {}
  PokemonManager.moves = {}
  PokemonManager.movePoints = {}
  PokemonManager.combo = {}
  PokemonManager.comboDraft = {}
  PokemonManager.abilities = {}
  PokemonManager.abilityDesc = {}
  PokemonManager.heldItems = {}
  PokemonManager.selected = 1
  PokemonManager.currentPage = 'summary'
PokemonManager.evPending = {0, 0, 0, 0, 0, 0}
PokemonManager.version = 'V6.6.2'
  PokemonManager.tryRegisterOpcode()
end

function PokemonManager.onGameEnd()
  if PokemonManager.retryEvent then
    removeEvent(PokemonManager.retryEvent)
    PokemonManager.retryEvent = nil
  end

  -- O registro do Extended Opcode sobrevive ao logout neste client.
  -- Libera o 89 aqui para o proximo login poder registra-lo novamente.
  if PokemonManager.opcodeRegistered then
    pcall(function()
      ProtocolGame.unregisterExtendedOpcode(PokemonManager.opcode)
    end)
  end

  PokemonManager.destroy()
  PokemonManager.opcodeRegistered = false
end

function PokemonManager.destroy()
  PokemonManager.incubatorChoices = {}
  PokemonManager.incubatorChooser = nil
  if PokemonManager.window and not PokemonManager.window:isDestroyed() then PokemonManager.window:destroy() end
  PokemonManager.window=nil
  PokemonManager.cards={}
  PokemonManager.baseCards={}
  PokemonManager.evCards={}
  PokemonManager.partyCards={}
  PokemonManager.heldItems={}
  PokemonManager.friendCards={}
  PokemonManager.pokemon={}
  PokemonManager.selected=1
end

function PokemonManager.bindBaseCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.baseCards = {}
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('baseTeam' .. i)
    PokemonManager.baseCards[i] = card
    if card then
      card:setPhantom(false)
      local icon = card:recursiveGetChildById('icon')
      local level = card:recursiveGetChildById('level')
      if icon then icon:setPhantom(true) end
      if level then level:setPhantom(true) end
      card.onClick = function() PokemonManager.selectBaseSlot(i) end
    end
  end
end

function PokemonManager.bindEVCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.evCards = {}
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('evTeam' .. i)
    PokemonManager.evCards[i] = card
    if card then
      card:setPhantom(false)
      local icon = card:recursiveGetChildById('icon')
      local level = card:recursiveGetChildById('level')
      if icon then icon:setPhantom(true) end
      if level then level:setPhantom(true) end
      card.onClick = function() PokemonManager.selectEVSlot(i) end
    end
  end
end

function PokemonManager.refreshEVSelection()
  for i = 1, 6 do
    local card = PokemonManager.evCards[i]
    if card and not card:isDestroyed() then
      if PokemonManager.pokemon[i] then
        card:setVisible(true)
        if i == PokemonManager.selected then
          card:setBackgroundColor('#263b59')
          card:setBorderColor('#ffd24a')
        else
          card:setBackgroundColor('#111c2c')
          card:setBorderColor('#263b59')
        end
      else
        card:setVisible(false)
      end
    end
  end
end

function PokemonManager.selectEVSlot(slot)
  local p = PokemonManager.pokemon[slot]
  if not p then return end
  PokemonManager.selected = slot
  PokemonManager.resetEVPending()
  PokemonManager.refreshEVSelection()
  PokemonManager.updateBaseUI()
end

function PokemonManager.updateEVCardData()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.evCards < 6 then PokemonManager.bindEVCards() end
  for i = 1, 6 do
    local card = PokemonManager.evCards[i]
    local p = PokemonManager.pokemon[i]
    if card then
      if p then
        card:setVisible(true)
        local icon = card:recursiveGetChildById('icon')
        local level = card:recursiveGetChildById('level')
        if icon then
          local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png'
          pcall(function() icon:setImageSource(path); icon:setImageSize({width=64,height=64}) end)
        end
        if level then level:setText('Lv.' .. tostring(p.level)) end
      else
        card:setVisible(false)
      end
    end
  end
  PokemonManager.refreshEVSelection()
end

function PokemonManager.requestIncubators()
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode, 'INCUBATOR_REQUEST')
end

function PokemonManager.formatIncubatorTime(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local days = math.floor(seconds / 86400)
  seconds = seconds % 86400
  local hours = math.floor(seconds / 3600)
  seconds = seconds % 3600
  local minutes = math.floor(seconds / 60)
  local secs = seconds % 60
  if days > 0 then
    return string.format('%02dd %02dh %02dm', days, hours, minutes)
  end
  return string.format('%02dh %02dm %02ds', hours, minutes, secs)
end

-- Cor do estado atual de cada slot (usada na barra de destaque na
-- lateral do card e no texto de status), pra dar um retorno visual
-- rapido sem precisar ler o texto: cinza=bloqueado, dourado=livre pra
-- escolher, azul=incubando, verde=pronto pra chocar.
PokemonManager.incubatorStateColors = {
  locked = '#3a5170',
  choose = '#f2c400',
  incubating = '#5aa9e6',
  ready = '#72e6a0'
}
PokemonManager.incubatorStateLabels = {
  locked = 'BLOQUEADO',
  choose = 'LIVRE',
  incubating = 'INCUBANDO',
  ready = 'PRONTO'
}
PokemonManager.incubatorStateBorders = {
  locked = '#1c3350',
  choose = '#6b5a1a',
  incubating = '#294765',
  ready = '#2c5a4a'
}

local function pmSetIncubatorAccent(panel, colorKey)
  local accent = panel:recursiveGetChildById('accent')
  local color = PokemonManager.incubatorStateColors[colorKey] or PokemonManager.incubatorStateColors.locked
  if accent then accent:setBackgroundColor(color) end
  panel:setBorderColor(PokemonManager.incubatorStateBorders[colorKey] or '#1c3350')
  panel:setBackgroundColor(colorKey == 'locked' and '#0a1524' or '#0c1828')
  local tag = panel:recursiveGetChildById('stateTag')
  if tag then
    tag:setText(PokemonManager.incubatorStateLabels[colorKey] or '')
    tag:setColor(color == '#3a5170' and '#7f94b1' or color)
  end
  local slotNumber = panel:recursiveGetChildById('slotNumber')
  if slotNumber then slotNumber:setColor(colorKey == 'locked' and '#7f94b1' or '#f2c400') end
  return color
end

function PokemonManager.getIncubatorSlotState(data)
  if not data or not data.unlocked then return 'locked' end
  if data.eggId and data.eggId > 0 and data.startedAt and data.startedAt > 0 then
    local now = os.time() + (PokemonManager.incubatorServerOffset or 0)
    local info = PokemonManager.getIncubatorInfo(data)
    local duration = tonumber(data.duration) or (info and info.duration) or PokemonManager.incubatorDuration
    if now - data.startedAt >= duration then return 'ready' end
    return 'incubating'
  end
  return 'choose'
end

function PokemonManager.updateIncubatorSlot(slot)
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local data = PokemonManager.incubators[slot]
  local panel = PokemonManager.window:recursiveGetChildById('incubatorSlot' .. slot)
  if not panel then return end

  local state = panel:recursiveGetChildById('state')
  local timer = panel:recursiveGetChildById('timer')
  local action = panel:recursiveGetChildById('action')
  local background = panel:recursiveGetChildById('slotBackground')
  local egg = panel:recursiveGetChildById('egg')
  local iconFrame = panel:recursiveGetChildById('iconFrame')
  local progressTrack = panel:recursiveGetChildById('progressTrack')
  local progressFill = panel:recursiveGetChildById('progressFill')

  if not PokemonManager.incubatorChoices[slot] then
    PokemonManager.createIncubatorChoices(slot, panel)
  end

  local function setProgress(ratio, color)
    if not progressTrack or not progressFill then return end
    if not ratio then
      progressTrack:setVisible(false)
      return
    end
    progressTrack:setVisible(true)
    local tw = progressTrack:getWidth()
    if not tw or tw <= 0 then
      local pw = panel:getWidth()
      if not pw or pw <= 0 then pw = 248 end
      tw = pw - 32
    end
    progressFill:setWidth(math.max(0, math.floor(tw * math.max(0, math.min(1, ratio)))))
    progressFill:setBackgroundColor(color)
  end

  if not data or not data.unlocked then
    PokemonManager.updateIncubatorChoiceItems(slot, false)
    if background then background:setVisible(false) end
    if egg then egg:setVisible(false) end
    if iconFrame then
      iconFrame:setVisible(true)
      iconFrame:setBorderColor('#1c3350')
    end
    local color = pmSetIncubatorAccent(panel, 'locked')
    local cost = tonumber(data and data.cost) or 0
    if state then state:setVisible(true); state:setText('SLOT BLOQUEADO'); state:setColor('#7f94b1'); state:setTooltip('') end
    if timer then
      timer:setVisible(true)
      timer:setText(cost > 0 and ('CUSTO: ' .. tostring(cost) .. ' POKECOINS') or 'DESBLOQUEIO COM POKECOINS')
      timer:setColor('#f2c400')
    end
    setProgress(nil)
    if action then
      action:setText('DESBLOQUEAR')
      action:setColor('#ffd24a')
      action:setVisible(true)
      action:setEnabled(true)
    end
    return
  end

  if data.eggId and data.eggId > 0 and data.startedAt and data.startedAt > 0 then
    PokemonManager.updateIncubatorChoiceItems(slot, false)
    if egg then egg:setVisible(false) end

    local now = os.time() + (PokemonManager.incubatorServerOffset or 0)
    local elapsed = math.max(0, now - data.startedAt)
    local duration = tonumber(data.duration) or (PokemonManager.getIncubatorInfo(data) and PokemonManager.getIncubatorInfo(data).duration) or PokemonManager.incubatorDuration
    local remaining = math.max(0, duration - elapsed)
    local info = PokemonManager.getIncubatorInfo(data)
    local itemId = PokemonManager.getIncubatorItemId(data)
    local itemColor = PokemonManager.incubatorItemColors[itemId] or '#5aa9e6'

    if iconFrame then iconFrame:setVisible(true) end
    if background then
      if info and info.image then
        pcall(function()
          background:setImageSource(info.image)
          background:setImageSize({width = 32, height = 32})
          background:setVisible(true)
        end)
      else
        background:setVisible(false)
      end
    end

    if state then state:setVisible(true) end
    if timer then timer:setVisible(true) end
    -- "Inicio" vira tooltip no status pra quem quiser conferir.
    local startedTooltip = 'Iniciado em ' .. os.date('%d/%m %H:%M', data.startedAt)

    if remaining > 0 then
      pmSetIncubatorAccent(panel, 'incubating')
      if iconFrame then iconFrame:setBorderColor(itemColor) end
      if state then
        state:setText(data.crecheName and ('OVO DE ' .. string.upper(data.crecheName)) or ('INCUBANDO - ' .. tostring(info and info.name or '')))
        state:setColor(itemColor)
        state:setTooltip(startedTooltip .. (data.crecheName and ('\nIncubadora ' .. tostring(info and info.name or '')) or ''))
      end
      if timer then
        timer:setText('FALTAM ' .. PokemonManager.formatIncubatorTime(remaining))
        timer:setColor('#dce8f5')
      end
      setProgress(duration > 0 and (elapsed / duration) or 0, itemColor)
      if action then
        action:setText('EM ANDAMENTO')
        action:setColor('#8ff09a')
        action:setVisible(true)
        action:setEnabled(false)
      end
    else
      local color = pmSetIncubatorAccent(panel, 'ready')
      if iconFrame then iconFrame:setBorderColor(color) end
      if state then
        state:setText(data.crecheName and (string.upper(data.crecheName) .. ' PRONTO') or 'PRONTO PARA CHOCAR')
        state:setColor(color); state:setTooltip(startedTooltip)
      end
      if timer then
        timer:setText('INCUBADORA ' .. tostring(info and info.name or ''))
        timer:setColor('#7f94b1')
      end
      setProgress(1, color)
      if action then
        action:setText('CHOCAR')
        action:setColor('#8ff09a')
        action:setVisible(true)
        action:setEnabled(true)
      end
    end
  else
    -- Slot livre: as linhas de escolha ocupam o espaco do icone/status.
    PokemonManager.updateIncubatorChoiceItems(slot, true)
    if background then background:setVisible(false) end
    if egg then egg:setVisible(false) end
    if iconFrame then iconFrame:setVisible(false) end
    pmSetIncubatorAccent(panel, 'choose')
    if state then state:setVisible(false) end
    if timer then timer:setVisible(false) end
    setProgress(nil)
    if action then
      action:setVisible(false)
      action:setEnabled(false)
    end
  end
end

function PokemonManager.updateIncubatorSummary()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local counts = {ready = 0, incubating = 0, choose = 0, locked = 0}
  for slot = 1, 6 do
    local st = PokemonManager.getIncubatorSlotState(PokemonManager.incubators[slot])
    counts[st] = (counts[st] or 0) + 1
  end
  local labels = {
    {'incubCountReady', 'PRONTOS', counts.ready, '#72e6a0'},
    {'incubCountIncubating', 'INCUBANDO', counts.incubating, '#5aa9e6'},
    {'incubCountFree', 'LIVRES', counts.choose, '#f2c400'},
    {'incubCountLocked', 'BLOQUEADOS', counts.locked, '#7f94b1'}
  }
  for _, def in ipairs(labels) do
    local w = PokemonManager.window:recursiveGetChildById(def[1])
    if w then
      w:setText(def[2] .. ' ' .. tostring(def[3]))
      w:setColor(def[3] > 0 and def[4] or '#5f7596')
    end
  end
  local accent = PokemonManager.window:recursiveGetChildById('incubatorStatsAccent')
  if accent then accent:setBackgroundColor(counts.ready > 0 and '#72e6a0' or '#f2c400') end

  local chips = {incubChip24h = 39335, incubChip12h = 39336, incubChip8h = 39337, incubChip5min = 39338}
  for chipId, itemId in pairs(chips) do
    local chip = PokemonManager.window:recursiveGetChildById(chipId)
    local count = tonumber(PokemonManager.incubatorCounts[itemId]) or 0
    if chip then chip:setBorderColor(count > 0 and '#294765' or '#1c3350') end
    local countLabel = PokemonManager.window:recursiveGetChildById(chipId .. 'Count')
    if countLabel then
      countLabel:setText('x' .. tostring(count))
      countLabel:setColor(count > 0 and '#ffffff' or '#5f7596')
    end
  end
end

function PokemonManager.updateIncubators()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  for slot = 1, 6 do PokemonManager.updateIncubatorSlot(slot) end
  PokemonManager.updateIncubatorSummary()
  PokemonManager.updateStepEggUI()
  if PokemonManager.currentPage == 'incubators' then
    if PokemonManager.incubatorTimer then removeEvent(PokemonManager.incubatorTimer) end
    PokemonManager.incubatorTimer = scheduleEvent(function()
      PokemonManager.incubatorTimer = nil
      PokemonManager.updateIncubators()
    end, 1000)
  end
end

-- Formata um numero inteiro com separador de milhar (padrao pt-BR: ponto),
-- ex: 3240 -> "3.240". Usado pra deixar a contagem de passos mais legivel.
local function pmFormatThousands(n)
  n = math.floor(tonumber(n) or 0)
  local sign, digits = '', tostring(math.abs(n))
  if n < 0 then sign = '-' end
  local reversed = digits:reverse():gsub('(%d%d%d)', '%1.'):reverse()
  reversed = reversed:gsub('^%.', '')
  return sign .. reversed
end

function PokemonManager.updateStepEggUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window
  local status = win:recursiveGetChildById('stepEggStatus')
  local statusChip = win:recursiveGetChildById('stepEggStatusChip')
  local accent = win:recursiveGetChildById('stepEggAccent')
  local iconFrame = win:recursiveGetChildById('stepEggIconFrame')
  local icon = win:recursiveGetChildById('stepEggIcon')
  local fill = win:recursiveGetChildById('stepEggFill')
  local back = win:recursiveGetChildById('stepEggBack')
  local percent = win:recursiveGetChildById('stepEggPercent')
  local action = win:recursiveGetChildById('stepEggAction')

  local data = PokemonManager.stepEgg or {eggId = 0, steps = 0, limit = 10000}
  local hasEgg = (tonumber(data.eggId) or 0) > 0
  local steps = math.max(0, tonumber(data.steps) or 0)
  local limit = tonumber(data.limit) or 10000
  if limit <= 0 then limit = 10000 end
  local ready = hasEgg and steps >= limit
  local ratio = math.min(steps, limit) / limit

  local color
  if not hasEgg then
    color = '#3a5170'
  elseif ready then
    color = '#72e6a0'
  else
    color = PokemonManager.lerpColor('#5a7ca8', '#f2c400', ratio)
  end

  -- CODEX: 36570 e o id do SERVIDOR; o desenho usa o clientId que o servidor manda
  -- junto da lista da Creche (INCUBATOR_CRECHE_LIST). Sem ele, nao mostra sprite errado.
  local eggClientId = tonumber(PokemonManager.pokeEggClientId) or 0
  if icon then
    if eggClientId > 0 then icon:setItemId(eggClientId) end
    icon:setVisible(hasEgg and eggClientId > 0)
  end
  if iconFrame then iconFrame:setBorderColor(hasEgg and color or '#1c3350') end
  if accent then accent:setBackgroundColor(color) end
  if fill then
    local backWidth = back and back:getWidth() or 0
    fill:setWidth(hasEgg and math.floor(ratio * math.max(0, backWidth - 2)) or 0)
    fill:setBackgroundColor(color)
  end
  -- Mostra a contagem real de passos dentro da barra (nao so a
  -- porcentagem), pra ficar claro quanto falta em numeros.
  if percent then
    percent:setText(pmFormatThousands(math.min(steps, limit)) .. ' / ' .. pmFormatThousands(limit) .. ' PASSOS')
    percent:setColor(hasEgg and '#ffffff' or '#7f94b1')
  end

  local statusText, statusColor
  if not hasEgg then
    statusText, statusColor = 'SEM OVO', '#9bb6dc'
    if action then action:setText('COLOCAR OVO'); action:setEnabled(true) end
  elseif ready then
    statusText, statusColor = 'PRONTO PARA CHOCAR', '#72e6a0'
    if action then action:setText('CHOCAR'); action:setEnabled(true) end
  else
    statusText, statusColor = 'ANDANDO - ' .. tostring(math.floor(ratio * 100)) .. '%', color
    if action then action:setText('ANDANDO...'); action:setEnabled(false) end
  end
  if status then
    status:setText(statusText)
    status:setColor(statusColor)
  end
  if statusChip then statusChip:setBorderColor(hasEgg and statusColor or '#3a5170') end
end

function PokemonManager.getIncubatorItemId(data)
  if not data then return 0 end

  local id = tonumber(data.incubatorId) or 0
  if id == 1 then return 39335 end
  if id == 2 then return 39336 end
  if id == 3 then return 39337 end
  if id == 4 then return 39338 end
  if PokemonManager.incubatorItems[id] then return id end

  local duration = tonumber(data.duration) or 0
  if duration == 86400 then return 39335 end
  if duration == 43200 then return 39336 end
  if duration == 28800 then return 39337 end
  if duration == 300 then return 39338 end
  return 0
end

function PokemonManager.destroyIncubatorChoices(slot)
  local choices = PokemonManager.incubatorChoices and PokemonManager.incubatorChoices[slot]
  if not choices then return end

  for _, widgets in pairs(choices) do
    -- widgets.row e o container do item/label/botao; destruir ele ja
    -- destroi os filhos junto.
    local row = (type(widgets) == 'table' and widgets.row) or widgets
    if row and not row:isDestroyed() then
      row:destroy()
    end
  end
  PokemonManager.incubatorChoices[slot] = nil
end

function PokemonManager.startIncubator(slot, incubatorId)
  if not g_game.isOnline() then return end

  local data = PokemonManager.incubators[slot]
  if not data or not data.unlocked then return end
  if data.eggId and data.eggId > 0 and data.startedAt and data.startedAt > 0 then return end

  local count = tonumber(PokemonManager.incubatorCounts[incubatorId]) or 0
  if count <= 0 then
    modules.game_textmessage.displayFailureMessage('[PokemonManager] Voce nao possui esta incubadora.')
    return
  end

  local proto = g_game.getProtocolGame()
  if not proto then return end

  -- O item escolhido ja representa a velocidade da incubadora.
  -- O servidor continua sendo a autoridade: ele valida o item, remove o ovo
  -- e grava a duracao correspondente.
  local egg = PokemonManager.incubEggChoice or 'random'
  proto:sendExtendedOpcode(PokemonManager.opcode, 'INCUBATOR_START|' .. slot .. '|' .. incubatorId ..
    (egg ~= 'random' and ('|' .. egg) or ''))
end

-- faixa "OVO PARA INCUBAR": Pokemon Egg (aleatorio) + ovos da Creche
function PokemonManager.updateIncubEggPicker()
  local win = PokemonManager.window
  local box = win and win:recursiveGetChildById('incubEggChoices')
  if not box then return end
  box:destroyChildren()
  local found = PokemonManager.incubEggChoice == 'random'
  for _, e in ipairs(PokemonManager.crecheEggs) do
    if e.id == PokemonManager.incubEggChoice then found = true end
  end
  if not found then PokemonManager.incubEggChoice = 'random' end
  local function nice(name)
    return (tostring(name or ''):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  local options = {{id = 'random', name = 'Pokemon Egg', clientId = PokemonManager.pokeEggClientId,
    sub = 'Aleatorio  x' .. tostring(PokemonManager.pokeEggCount or 0)}}
  for _, e in ipairs(PokemonManager.crecheEggs) do
    options[#options + 1] = {id = e.id, name = nice(e.species), clientId = e.clientId, poke = e.species,
      sub = (e.gender == 'M' and 'M' or (e.gender == 'F' and 'F' or '-')) .. '  IV ' .. e.pct .. '%'}
  end
  -- paginas: quantos cabem na faixa
  local width = box:getWidth()
  if not width or width <= 0 then width = 560 end
  local perPage = math.max(1, math.floor((width + 4) / (128 + 4)))
  local pages = math.max(1, math.ceil(#options / perPage))
  PokemonManager.incubEggPage = math.max(1, math.min(PokemonManager.incubEggPage or 1, pages))
  local page = PokemonManager.incubEggPage
  local prev, nextB = win:recursiveGetChildById('incubEggPrev'), win:recursiveGetChildById('incubEggNext')
  if prev then
    prev:setEnabled(page > 1)
    prev.onClick = function() PokemonManager.incubEggPage = page - 1 PokemonManager.updateIncubEggPicker() return true end
  end
  if nextB then
    nextB:setEnabled(page < pages)
    nextB.onClick = function() PokemonManager.incubEggPage = page + 1 PokemonManager.updateIncubEggPicker() return true end
  end
  local shown = {}
  for i = (page - 1) * perPage + 1, math.min(#options, page * perPage) do shown[#shown + 1] = options[i] end
  for _, o in ipairs(shown) do
    local w = g_ui.createWidget('PMIncubEggChoice', box)
    w:setId('incubEgg_' .. o.id)
    w:setPhantom(false)
    local sel = o.id == PokemonManager.incubEggChoice
    if o.clientId and o.clientId > 0 then w:getChildById('item'):setItemId(o.clientId) end
    if o.poke then
      pcall(function()
        w:getChildById('poke'):setImageSource('/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(o.poke) .. '.png')
      end)
    end
    w:getChildById('name'):setText(o.name)
    w:getChildById('sub'):setText(o.sub)
    w:setBorderColor(sel and '#f2c400' or '#294765')
    w:setBackgroundColor(sel and '#263b59' or '#102138')
    w:setTooltip(o.poke and ('Ovo da Creche: ' .. o.name .. '\nEscolha e clique em USAR numa incubadora livre.') or
      'Pokemon Egg: nasce um Pokemon aleatorio.')
    w.onClick = function()
      PokemonManager.incubEggChoice = o.id
      PokemonManager.updateIncubEggPicker()
      return true
    end
  end
end

function PokemonManager.createIncubatorChoices(slot, panel)
  if not panel then return end

  PokemonManager.incubatorChoices = PokemonManager.incubatorChoices or {}
  PokemonManager.destroyIncubatorChoices(slot)
  PokemonManager.incubatorChoices[slot] = {}

  local ids = {39335, 39336, 39337, 39338}
  -- 4 linhas (icone + tempo + estoque + botao USAR), empilhadas logo abaixo
  -- do "SLOT N", ocupando a area do icone/status (escondidos nesse estado).
  local rowHeight, rowGap, startTop, sideMargin = 25, 4, 26, 12

  for i, id in ipairs(ids) do
    local info = PokemonManager.incubatorItems[id]
    if info then
      local row = g_ui.createWidget('Panel', panel)
      row:setId('incubatorChoiceRow' .. id)
      row:setHeight(rowHeight)
      row:addAnchor(AnchorTop, 'parent', AnchorTop)
      row:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      row:addAnchor(AnchorRight, 'parent', AnchorRight)
      row:setMarginTop(startTop + ((i - 1) * (rowHeight + rowGap)))
      row:setMarginLeft(sideMargin)
      row:setMarginRight(sideMargin)
      row:setFocusable(false)
      row:setBackgroundColor('#0a1422')
      row:setBorderWidth(1)
      row:setBorderColor('#1c3350')

      local item = g_ui.createWidget('UIItem', row)
      item:setId('incubatorItem' .. id)
      item:setWidth(18)
      item:setHeight(18)
      item:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      item:addAnchor(AnchorTop, 'parent', AnchorTop)
      item:setMarginLeft(5)
      item:setMarginTop(math.floor((rowHeight - 18) / 2))
      local spriteId = PokemonManager.incubatorClientIds[id]
      if spriteId and spriteId > 0 then
        item:setItemId(spriteId)
        item:setVisible(true)
      else
        -- ClientId real ainda nao chegou do servidor (INCUBATOR_EGG_COUNT).
        -- Mantem escondido em vez de mostrar o icone "desconhecido" quebrado;
        -- a reconciliacao ao receber o pacote chama setItemId + mostra.
        item:setVisible(false)
      end
      item:setPhantom(true)
      item:setFocusable(false)

      local durationLabel = g_ui.createWidget('Label', row)
      durationLabel:setId('incubatorDuration' .. id)
      durationLabel:setWidth(52)
      durationLabel:setHeight(14)
      durationLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      durationLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
      durationLabel:setMarginLeft(30)
      durationLabel:setMarginTop(math.floor((rowHeight - 14) / 2))
      durationLabel:setText(tostring(info.name or ''))
      durationLabel:setFont('verdana-11px-antialised')
      durationLabel:setColor(PokemonManager.incubatorItemColors[id] or '#9bb6dc')
      durationLabel:setPhantom(true)
      durationLabel:setFocusable(false)

      local countLabel = g_ui.createWidget('Label', row)
      countLabel:setId('incubatorCount' .. id)
      countLabel:setWidth(50)
      countLabel:setHeight(14)
      countLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      countLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
      countLabel:setMarginLeft(88)
      countLabel:setMarginTop(math.floor((rowHeight - 14) / 2))
      countLabel:setFont('verdana-11px-antialised')
      countLabel:setPhantom(true)
      countLabel:setFocusable(false)

      local useButton = g_ui.createWidget('PMSkinButtonWide', row)
      useButton:setId('incubatorUse' .. id)
      useButton:setWidth(58)
      useButton:setHeight(19)
      useButton:setFont('verdana-11px-antialised')
      useButton:addAnchor(AnchorRight, 'parent', AnchorRight)
      useButton:addAnchor(AnchorTop, 'parent', AnchorTop)
      useButton:setMarginRight(3)
      useButton:setMarginTop(3)
      useButton:setText('USAR')
      useButton:setFocusable(false)
      useButton.onClick = function()
        PokemonManager.startIncubator(slot, id)
      end

      item.onClick = function()
        PokemonManager.startIncubator(slot, id)
      end

      PokemonManager.incubatorChoices[slot][id] = {row = row, item = item, label = durationLabel, count = countLabel, useButton = useButton}
    end
  end
  PokemonManager.updateIncubatorChoiceItems(slot, false)
end

function PokemonManager.updateIncubatorChoiceItems(slot, visible)
  local choices = PokemonManager.incubatorChoices and PokemonManager.incubatorChoices[slot]
  if not choices then return end

  for id, widgets in pairs(choices) do
    local row, item, useButton, countLabel, label = widgets.row, widgets.item, widgets.useButton, widgets.count, widgets.label
    if row and not row:isDestroyed() then
      local count = tonumber(PokemonManager.incubatorCounts[id]) or 0
      local hasStock = count > 0
      local spriteId = PokemonManager.incubatorClientIds[id]
      local spriteReady = spriteId and spriteId > 0
      row:setVisible(visible)
      row:setBorderColor(hasStock and '#294765' or '#1c3350')
      -- So mostra o icone quando o clientId real ja foi resolvido pelo
      -- servidor; senao ficaria visivel o sprite "desconhecido" quebrado.
      if item and not item:isDestroyed() then
        item:setVisible(visible and spriteReady and true or false)
        item:setOpacity(hasStock and 1.0 or 0.4)
      end
      if label and not label:isDestroyed() then
        label:setColor(hasStock and (PokemonManager.incubatorItemColors[id] or '#9bb6dc') or '#5f7596')
      end
      if countLabel and not countLabel:isDestroyed() then
        countLabel:setText('x' .. tostring(count))
        countLabel:setColor(hasStock and '#c8d6ec' or '#5f7596')
      end
      if useButton and not useButton:isDestroyed() then useButton:setEnabled(visible and hasStock) end
      if item and item.setItemCount then
        pcall(function() item:setItemCount(count) end)
      end
    end
  end
end

function PokemonManager.bindIncubatorControls()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  PokemonManager.incubatorChoices = PokemonManager.incubatorChoices or {}

  local headerIcons = {
    incubChip24hIcon = 39335,
    incubChip12hIcon = 39336,
    incubChip8hIcon = 39337,
    incubChip5minIcon = 39338
  }
  for iconId, itemId in pairs(headerIcons) do
    local icon = PokemonManager.window:recursiveGetChildById(iconId)
    if icon then
      icon:setItemId(itemId)
      icon:setPhantom(true)
      icon:setFocusable(false)
    end
  end

  for slot = 1, 6 do
    local panel = PokemonManager.window:recursiveGetChildById('incubatorSlot' .. slot)
    if panel then
      PokemonManager.createIncubatorChoices(slot, panel)

      local action = panel:recursiveGetChildById('action')
      if action then
        action.onClick = function()
          local data = PokemonManager.incubators[slot]
          if not data then return end

          if not data.unlocked then
            local proto = g_game.getProtocolGame()
            if proto then
              proto:sendExtendedOpcode(PokemonManager.opcode, 'INCUBATOR_UNLOCK|' .. slot)
            end
            return
          end

          if data.eggId and data.eggId > 0 and data.startedAt and data.startedAt > 0 then
            local now = os.time() + (PokemonManager.incubatorServerOffset or 0)
            local duration = tonumber(data.duration) or PokemonManager.incubatorDuration
            if now - data.startedAt >= duration then
              local proto = g_game.getProtocolGame()
              if proto then
                proto:sendExtendedOpcode(PokemonManager.opcode, 'INCUBATOR_HATCH|' .. slot)
              end
            end
            return
          end

          -- O botao antigo nao abre mais uma janela. As proprias incubadoras
          -- exibidas no slot fazem a selecao diretamente.
        end
      end
    end
  end

  local stepEggAction = PokemonManager.window:recursiveGetChildById('stepEggAction')
  if stepEggAction then
    stepEggAction.onClick = function()
      local proto = g_game.getProtocolGame()
      if not proto then return end
      local data = PokemonManager.stepEgg or {}
      local hasEgg = tonumber(data.eggId or 0) > 0
      local ready = hasEgg and (tonumber(data.steps) or 0) >= (tonumber(data.limit) or 10000)
      if not hasEgg then
        proto:sendExtendedOpcode(PokemonManager.opcode, 'STEPEGG_START')
      elseif ready then
        proto:sendExtendedOpcode(PokemonManager.opcode, 'STEPEGG_HATCH')
      end
    end
  end
  PokemonManager.updateStepEggUI()
end

function PokemonManager.showPage(page)
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  PokemonManager.currentPage = page

  -- IMPORTANT:
  -- Todas as telas usam a mesma area do manager. Primeiro desligamos TODAS,
  -- depois ligamos somente a pagina solicitada. Isso evita sobreposicao entre
  -- Habilidades, Moves, Atributos, Vitaminas e Resumo.
  local ids = {
    'profileView',
    'dashboardView',
    'baseView',
    'movesView',
    'abilitiesView',
    'heldView',
    'friendView',
    'incubatorView',
    'evolutionView',
    'selectedCard',
    'listCard'
  }

  for _, id in ipairs(ids) do
    local widget = PokemonManager.window:recursiveGetChildById(id)
    if widget then
      widget:setVisible(false)
    end
  end

  local vitaminasView = PokemonManager.window:recursiveGetChildById('vitaminasView')
  if vitaminasView then
    vitaminasView:setVisible(false)
  end

  local title = PokemonManager.window:recursiveGetChildById('contentTitle')
  local count = PokemonManager.window:recursiveGetChildById('pokemonCount')
  if title then title:setVisible(false) end
  if count then count:setVisible(false) end

  -- Elementos internos do Atributos + EV.
  local baseTitle = PokemonManager.window:recursiveGetChildById('baseTitle')
  local baseSubtitle = PokemonManager.window:recursiveGetChildById('baseSubtitle')
  local basePointsBox = PokemonManager.window:recursiveGetChildById('basePointsBox')
  local baseTeam = PokemonManager.window:recursiveGetChildById('baseTeam')
  local statsLayout = PokemonManager.window:recursiveGetChildById('statsLayout')

  local ivQualityBox = PokemonManager.window:recursiveGetChildById('ivQualityBox')

  if baseTitle then baseTitle:setVisible(false) end
  if baseSubtitle then baseSubtitle:setVisible(false) end
  if basePointsBox then basePointsBox:setVisible(false) end
  if ivQualityBox then ivQualityBox:setVisible(false) end
  if baseTeam then baseTeam:setVisible(false) end
  if statsLayout then statsLayout:setVisible(false) end

  if page == 'profile' then
    local view = PokemonManager.window:recursiveGetChildById('profileView')
    if view then
      view:setVisible(true)
    end
    PokemonManager.updatePlayerId()
    PokemonManager.updatePlayerName()
    PokemonManager.updatePlayerId()
    PokemonManager.updateEconomy()
    PokemonManager.updateProfileStats()
    return
  end

  if page == 'abilities' then
    local view = PokemonManager.window:recursiveGetChildById('abilitiesView')
    if view then view:setVisible(true) end

    PokemonManager.updateAbilitiesUI()
    return
  end

  if page == 'moves' then
    local view = PokemonManager.window:recursiveGetChildById('movesView')
    if view then view:setVisible(true) end

    PokemonManager.updateMovesUI()
    return
  end

  if page == 'held' then
    local view = PokemonManager.window:recursiveGetChildById('heldView')
    if view then view:setVisible(true) end
    PokemonManager.updateHeldUI()
    PokemonManager.requestHeldItems()
    return
  end

  if page == 'friend' then
    local view = PokemonManager.window:recursiveGetChildById('friendView')
    if view then view:setVisible(true) end
    PokemonManager.updateFriendUI()
    return
  end
  if page == 'evolution' then
    local view = PokemonManager.window:recursiveGetChildById('evolutionView')
    if view then view:setVisible(true) end
    PokemonManager.updateEvolutionUI()
    PokemonManager.requestEvolution()
    return
  end
  if page == 'incubators' then
    local view = PokemonManager.window:recursiveGetChildById('incubatorView')
    if view then view:setVisible(true) end
    PokemonManager.updateIncubators()
    PokemonManager.requestIncubators()
    return
  end

  if page == 'base' or page == 'ev' then
    local view = PokemonManager.window:recursiveGetChildById('baseView')
    if view then view:setVisible(true) end

    if baseTitle then baseTitle:setVisible(true) end
    if baseSubtitle then baseSubtitle:setVisible(true) end
    if basePointsBox then basePointsBox:setVisible(true) end
    if ivQualityBox then ivQualityBox:setVisible(true) end
    if baseTeam then baseTeam:setVisible(true) end
    if statsLayout then statsLayout:setVisible(true) end

    PokemonManager.updateBaseUI()
    return
  end

  if page == 'vitamins' then
    -- vitaminasView fica dentro do baseView no OTUI.
    local view = PokemonManager.window:recursiveGetChildById('baseView')
    if view then view:setVisible(true) end

    if vitaminasView then vitaminasView:setVisible(true) end
    PokemonManager.updateVitaminsUI()
    return
  end

  -- Resumo / pagina inicial.
  local dashboard = PokemonManager.window:recursiveGetChildById('dashboardView')
  if dashboard then dashboard:setVisible(true) end

  PokemonManager.updateDashboard()
  PokemonManager.updateSelectedUI()
end

function PokemonManager.selectBaseSlot(slot)
  local p = PokemonManager.pokemon[slot]
  if not p then return end
  PokemonManager.selected = slot
  PokemonManager.updateBaseUI()
  PokemonManager.updateSelectedUI()
end

function PokemonManager.updateBaseCardData()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.baseCards < 6 then PokemonManager.bindBaseCards() end

  for i = 1, 6 do
    local card = PokemonManager.baseCards[i]
    local p = PokemonManager.pokemon[i]

    if card then
      if p then
        card:setVisible(true)

        local icon = card:recursiveGetChildById('icon')
        local level = card:recursiveGetChildById('level')
        local slot = card:recursiveGetChildById('slot')

        if icon then
          local path = '/modules/game_pokemonbar/bar_icon/' ..
            PokemonManager.sanitizeIconName(p.name) .. '.png'
          pcall(function()
            icon:setImageSource(path)
            icon:setImageSize({width = 54, height = 54})
          end)
        end

        if level then level:setText('Lv.' .. tostring(p.level or '--')) end
        if slot then slot:setText('#' .. tostring(i)) end
      else
        card:setVisible(false)
      end
    end
  end
end

function PokemonManager.refreshBaseSelection()
  for i = 1, 6 do
    local card = PokemonManager.baseCards[i]
    if card and not card:isDestroyed() then
      if PokemonManager.pokemon[i] then
        card:setVisible(true)
        local isSelected = i == PokemonManager.selected
        card:setBackgroundColor('#00000000')
        card:setImageSource('/modules/game_pokemonmanager/v2/' .. (isSelected and 'kx_slot_on' or 'kx_slot'))
        local level = card:recursiveGetChildById('level')
        if level then level:setColor(isSelected and '#ffd24a' or '#9bb6dc') end
      else
        card:setVisible(false)
      end
    end
  end
end

-- comp (opcional) = {base, iv, evCur, evEff, vit, scale}: ganhos de cada
-- fonte no VALOR, usados na barra de composicao. evCur = ganho do EV ja
-- aplicado, evEff = ganho com o ajuste pendente somado.
function PokemonManager.setBaseStatRow(row, value, ivValue, evValue, vitaminValue, previewValue, currentEV, comp)
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  local color = (PokemonManager.summaryStatColors and PokemonManager.summaryStatColors[row]) or '#9bb6dc'
  local pendingValue = PokemonManager.evPending[row] or 0
  evValue = tonumber(evValue) or 0
  currentEV = tonumber(currentEV) or evValue

  local statPanel = PokemonManager.window:recursiveGetChildById('statRow' .. row)
  if statPanel then
    local base = statPanel:recursiveGetChildById('statBase')
    local iv = statPanel:recursiveGetChildById('statIV')
    local ev = statPanel:recursiveGetChildById('statEV')
    local vitamin = statPanel:recursiveGetChildById('statVitamin')
    local statValue = statPanel:recursiveGetChildById('statValue')
    local statDelta = statPanel:recursiveGetChildById('statDelta')
    local accent = statPanel:recursiveGetChildById('statAccent')
    local name = statPanel:recursiveGetChildById('statName')

    if base then
      local bm = comp and comp.nature or 1 -- codex nature: base verde/vermelho
      base:setText(tostring(value or 0))
      base:setColor(bm > 1 and '#5fd35f' or (bm < 1 and '#ff7070' or '#FFFFFF'))
    end
    if iv then
      local ivNum = tonumber(ivValue) or 0
      iv:setText(tostring(ivNum))
      iv:setColor('#FFFFFF') -- codex visual: numeros brancos
    end
    if ev then ev:setText(tostring(evValue)) end
    if vitamin then
      local vitNum = tonumber(vitaminValue) or 0
      vitamin:setText(tostring(vitNum))
      vitamin:setColor('#FFFFFF')
    end
    if statValue then
      statValue:setText(tostring(previewValue or 0))
      local bonus = comp and comp.bonus or 0
      local natM = comp and comp.nature or 1 -- codex nature
      statValue:setColor(natM > 1 and '#5fd35f' or (natM < 1 and '#ff7070' or '#FFCC29'))
      statValue:setTooltip(natM ~= 1 and ('Natureza/Tera: ' .. (natM > 1 and '+' or '') .. tostring(math.floor((natM - 1) * 100 + 0.5)) .. '%') or '')
      local bonusW = statPanel:recursiveGetChildById('statBonus')
      if bonusW then
        bonusW:setText((bonus > 0 and '+' or '') .. tostring(bonus))
        bonusW:setColor('#FFFFFF')
      end
    end
    if accent then accent:setBackgroundColor(color) end
    if name then name:setColor(color) end
    -- codex visual: selo do icone na cor do atributo
    local badge = statPanel:recursiveGetChildById('statBadge')
    if badge and type(color) == 'string' and #color == 7 then
      pcall(function()
        badge:setBackgroundColor(color .. (pendingValue ~= 0 and '44' or '2e'))
        badge:setBorderColor(color .. '80')
      end)
    end

    local delta = comp and ((comp.evEff or 0) - (comp.evCur or 0)) or 0
    if statDelta then
      if delta > 0 then
        statDelta:setText('+' .. tostring(delta))
        statDelta:setColor('#f2c400')
      elseif delta < 0 then
        statDelta:setText(tostring(delta))
        statDelta:setColor('#ff9a9a')
      else
        statDelta:setText('')
      end
    end
    statPanel:setBorderColor(pendingValue ~= 0 and '#6b5a1a' or '#1c3350')

    -- Barra de composicao: Base | IV | EV | Vitamina | Pendente.
    local track = statPanel:recursiveGetChildById('statCompTrack')
    local trackW = track and track:getWidth() or 0
    if not trackW or trackW <= 0 then trackW = 230 end
    local scale = comp and math.max(1, comp.scale or 1) or 1
    local function segWidth(v) return math.max(0, math.floor(trackW * (tonumber(v) or 0) / scale)) end
    local widths = {
      segBase = comp and segWidth(comp.base) or 0,
      segIV = comp and segWidth(comp.iv) or 0,
      segEV = comp and segWidth(math.min(comp.evCur or 0, comp.evEff or 0)) or 0,
      segVit = comp and segWidth(comp.vit) or 0,
      segPending = comp and segWidth(math.max(0, (comp.evEff or 0) - (comp.evCur or 0))) or 0
    }
    local used = 0
    for _, id in ipairs({'segBase', 'segIV', 'segEV', 'segVit', 'segPending'}) do
      local seg = statPanel:recursiveGetChildById(id)
      local w = math.min(widths[id], trackW - used)
      used = used + w
      if seg then seg:setWidth(w) end
      if id == 'segBase' and seg then seg:setBackgroundColor(color) end
    end
    -- codex visual: explica a barra ao passar o mouse
    if track and comp then
      local bonus = comp.bonus or 0
      local tip = string.format('Base %d  +  IV %d  +  EV %d  +  Vitamina %d', comp.base or 0, comp.iv or 0, comp.evEff or 0, comp.vit or 0)
      if bonus ~= 0 then tip = tip .. '  +  Bonus ' .. bonus end
      tip = tip .. '  =  ' .. tostring(previewValue or 0)
      local d = (comp.evEff or 0) - (comp.evCur or 0)
      if d ~= 0 then tip = tip .. '\nAjuste pendente: ' .. (d > 0 and '+' or '') .. d .. ' (confirme em APLICAR EV)' end
      pcall(function() track:setTooltip(tip) end)
    end
  end

  -- Controle de EV (evRow1..evRow6 tem ids proprios).
  local evPanel = PokemonManager.window:recursiveGetChildById('evRow' .. row)
  if evPanel then
    local current = evPanel:recursiveGetChildById('evCurrent')
    local pending = evPanel:recursiveGetChildById('basePending' .. row)

    if current then
      current:setText(tostring(evValue) .. ' / 252')
      current:setColor(evValue >= 252 and '#f2c400' or (pendingValue ~= 0 and '#ffd24a' or '#c8d6ec'))
    end

    if pending then
      pending:setText((pendingValue >= 0 and '+' or '') .. tostring(pendingValue))
      pending:setColor(pendingValue > 0 and '#f2c400' or (pendingValue < 0 and '#ff9a9a' or '#5f7596'))
    end

    local barTrack = evPanel:recursiveGetChildById('evBarTrack')
    local barW = barTrack and barTrack:getWidth() or 0
    if not barW or barW <= 0 then barW = 110 end
    local barFill = evPanel:recursiveGetChildById('evBarFill')
    local barPending = evPanel:recursiveGetChildById('evBarPending')
    local solid = math.max(0, math.min(252, math.min(currentEV, evValue)))
    local extra = math.max(0, math.min(252, evValue) - solid)
    if barFill then
      barFill:setWidth(math.floor(barW * solid / 252))
      barFill:setBackgroundColor(color)
    end
    if barPending then barPending:setWidth(math.floor(barW * extra / 252)) end
  end
end

local function pmStatIVContribution(baseValue, ivValue)
  baseValue = tonumber(baseValue) or 0
  ivValue = math.max(0, math.min(31, tonumber(ivValue) or 0))
  return math.floor(baseValue * 0.15 * (ivValue / 31) + 0.5)
end

local function pmStatEVContribution(baseValue, evValue)
  baseValue = tonumber(baseValue) or 0
  evValue = math.max(0, math.min(252, tonumber(evValue) or 0))
  return math.floor(baseValue * 0.25 * (evValue / 252) + 0.5)
end

-- codex nature: mesmo multiplicador do servidor (newfunctions.lua)
-- ordem: 1 HP, 2 ATK, 3 DEF, 4 SP.ATK, 5 SP.DEF, 6 VEL
local PM_NATURE_MOD = {
  Lonely = {2, 3}, Adamant = {2, 4}, Naughty = {2, 5}, Brave = {2, 1},
  Bold = {3, 2}, Impish = {3, 4}, Lax = {3, 5}, Relaxed = {3, 1},
  Modest = {4, 2}, Mild = {4, 3}, Rash = {4, 5}, Quiet = {4, 1},
  Calm = {5, 2}, Gentle = {5, 3}, Careful = {5, 4}, Sassy = {5, 1},
  Timid = {1, 2}, Hasty = {1, 3}, Jolly = {1, 4}, Naive = {1, 5}
}
local PM_STAT_SHORT = {'HP', 'ATK', 'DEF', 'SP.ATK', 'SP.DEF', 'VEL'}
function pmNatureMult(nature, i)
  local m = PM_NATURE_MOD[tostring(nature or '')]
  if not m then return 1 end
  if m[1] == i then return 1.10 end
  if m[2] == i then return 0.90 end
  return 1
end
-- codex tera: 3o tipo + bonus de status (igual ao data/lib/core/codextera.lua)
local PM_TERA_ID = {[11]='normal',[12]='fire',[13]='fighting',[14]='water',[15]='flying',[16]='grass',
  [17]='poison',[18]='electric',[19]='ground',[20]='psychic',[21]='rock',[22]='ice',[23]='bug',
  [24]='dragon',[25]='ghost',[26]='dark',[27]='steel',[28]='fairy'}
local PM_TERA_STAT = {normal=1, grass=1, fighting=2, bug=2, dragon=2, ice=2, ground=3, rock=3, steel=3,
  fire=4, psychic=4, ghost=4, water=5, poison=5, fairy=5, flying=6, electric=6, dark=6}
PM_TERA_BONUS = 1.10
function pmTeraName(tera)
  local n = tonumber(tera)
  if n then return PM_TERA_ID[n] end
  local t = tostring(tera or ''):lower()
  if PM_TERA_STAT[t] then return t end
  return nil
end
function pmTeraMult(tera, i)
  local t = pmTeraName(tera)
  if t and PM_TERA_STAT[t] == i then return PM_TERA_BONUS end
  return 1
end

function pmNatureDesc(nature)
  local m = PM_NATURE_MOD[tostring(nature or '')]
  if not m then return 'NEUTRA' end
  return '+' .. PM_STAT_SHORT[m[1]] .. ' -' .. PM_STAT_SHORT[m[2]]
end

local function pmStatVitaminContribution(baseValue, vitaminValue)
  baseValue = tonumber(baseValue) or 0
  vitaminValue = math.max(0, math.min(10, tonumber(vitaminValue) or 0))
  return math.floor(baseValue * vitaminValue / 10 * 1.2)
end

function PokemonManager.updateBaseUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.baseCards < 6 then PokemonManager.bindBaseCards() end
  PokemonManager.updateBaseCardData()

  local win = PokemonManager.window
  local p = PokemonManager.pokemon[PokemonManager.selected]
  PokemonManager.refreshBaseSelection()

  local function get(id) return win:recursiveGetChildById(id) end
  local function trackWidth(id, fallback)
    local t = get(id)
    local w = t and t:getWidth() or 0
    if not w or w <= 0 then w = fallback end
    return w
  end

  local nameLabel = get('basePokemonName')
  if nameLabel then nameLabel:setText(p and string.upper(tostring(p.name or 'POKEMON')) or 'NENHUM POKEMON') end

  local points = get('basePointsValue')
  local availableLabel = get('evPointsAvailable')
  local pendingTotalLabel = get('basePendingTotal')
  local pointsAccent = get('basePointsAccent')
  local gaugeFill = get('baseGaugeFill')
  local gaugePending = get('baseGaugePending')
  local ivTotalLabel = get('ivTotalValue')
  local ivRatingLabel = get('ivRatingValue')
  local ivAccent = get('ivQualityAccent')
  local ivGaugeFill = get('ivGaugeFill')

  if not p then
    if points then points:setText('0 / 512 investido') end
    if availableLabel then
      availableLabel:setText('0')
      availableLabel:setColor('#7f94b1')
    end
    if pendingTotalLabel then pendingTotalLabel:setText('') end
    if pointsAccent then pointsAccent:setBackgroundColor('#3a5170') end
    if gaugeFill then gaugeFill:setWidth(0) end
    if gaugePending then gaugePending:setWidth(0) end
    if ivTotalLabel then ivTotalLabel:setText('0 / 186 IVs') end
    if ivRatingLabel then
      ivRatingLabel:setText('0.0% - SEM DADOS')
      ivRatingLabel:setColor('#7f94b1')
    end
    if ivAccent then ivAccent:setBackgroundColor('#3a5170') end
    if ivGaugeFill then ivGaugeFill:setWidth(0) end
    for i = 1, 6 do PokemonManager.setBaseStatRow(i, 0, 0, 0, 0, 0, 0, nil) end
    return
  end

  local baseValues = {
    tonumber(p.basehp) or 0, tonumber(p.baseatk) or 0, tonumber(p.basedef) or 0,
    tonumber(p.basespatk) or 0, tonumber(p.basespdef) or 0, tonumber(p.basespd) or 0
  }
  local ivValues = {
    tonumber(p.ivhp) or 0, tonumber(p.ivatk) or 0, tonumber(p.ivdef) or 0,
    tonumber(p.ivspatk) or 0, tonumber(p.ivspdef) or 0, tonumber(p.ivspeed) or 0
  }
  local evValues = {
    tonumber(p.evhp) or 0, tonumber(p.evatk) or 0, tonumber(p.evdef) or 0,
    tonumber(p.evspatk) or 0, tonumber(p.evspdef) or 0, tonumber(p.evspeed) or 0
  }
  local vitaminValues = {
    tonumber(p.vitHp) or 0, tonumber(p.vitAttack) or 0, tonumber(p.vitDefense) or 0,
    tonumber(p.vitSpAttack) or 0, tonumber(p.vitSpDefense) or 0, tonumber(p.vitSpeed) or 0
  }

  local totalEV, totalIV, pendingTotal = 0, 0, 0
  for i = 1, 6 do
    -- sem teto: pokemons editados no Painel ADM podem passar de 31 / 252
    ivValues[i] = math.max(0, ivValues[i])
    evValues[i] = math.max(0, evValues[i])
    totalEV = totalEV + evValues[i]
    totalIV = totalIV + ivValues[i]
    pendingTotal = pendingTotal + (tonumber(PokemonManager.evPending[i]) or 0)
  end

  -- Qualidade IV (mesma escala do Resumo).
  local ivPercent = math.min(100, (totalIV / 186) * 100)
  local ivRating, ivColor = PokemonManager.getIVRating(ivPercent)
  if ivTotalLabel then ivTotalLabel:setText(string.format('%d / 186 IVs', totalIV)) end
  if ivRatingLabel then
    ivRatingLabel:setText(string.format('%.1f%% - %s', ivPercent, ivRating))
    ivRatingLabel:setColor(ivColor)
  end
  if ivAccent then ivAccent:setBackgroundColor(ivColor) end
  if ivGaugeFill then
    ivGaugeFill:setWidth(math.floor(trackWidth('ivGaugeTrack', 351) * math.max(0, math.min(1, ivPercent / 100))))
    ivGaugeFill:setBackgroundColor(ivColor)
  end

  -- EV disponivel / investido / pendente.
  local availablePoints = math.max(0, (tonumber(p.evpoints) or 0) - pendingTotal)
  if points then points:setText(tostring(totalEV) .. ' / 512 investido') end
  if availableLabel then
    availableLabel:setText(tostring(availablePoints))
    availableLabel:setColor(availablePoints > 0 and '#ffffff' or '#7f94b1')
  end
  if pointsAccent then pointsAccent:setBackgroundColor(availablePoints > 0 and '#72e6a0' or '#3a5170') end
  -- codex: botoes do EV Add (26737)
  local evAddCount = p and (tonumber(p.evAddCount) or 0) or 0
  local evAddOne = get('evAddOneButton')
  local evAddAll = get('evAddAllButton')
  if evAddOne then
    evAddOne:setText('+1 EV ADD (x' .. tostring(evAddCount) .. ')')
    evAddOne:setEnabled(p ~= nil and evAddCount > 0)
    evAddOne.onClick = function() PokemonManager.sendEvAdd(1) end
  end
  if evAddAll then
    evAddAll:setEnabled(p ~= nil and evAddCount > 0)
    evAddAll.onClick = function() PokemonManager.sendEvAdd(0) end
  end
  if pendingTotalLabel then
    if pendingTotal > 0 then
      pendingTotalLabel:setText('+' .. tostring(pendingTotal) .. ' PENDENTE')
      pendingTotalLabel:setColor('#f2c400')
    elseif pendingTotal < 0 then
      pendingTotalLabel:setText(tostring(pendingTotal) .. ' PENDENTE')
      pendingTotalLabel:setColor('#ff9a9a')
    else
      pendingTotalLabel:setText('')
    end
  end
  local gaugeW = trackWidth('baseGaugeTrack', 351)
  local solidEV = math.max(0, math.min(512, totalEV + math.min(0, pendingTotal)))
  local extraEV = math.max(0, math.min(512 - solidEV, pendingTotal))
  if gaugeFill then gaugeFill:setWidth(math.floor(gaugeW * solidEV / 512)) end
  if gaugePending then gaugePending:setWidth(math.floor(gaugeW * extraEV / 512)) end

  -- Composicao de cada atributo. Escala compartilhada entre as 6 linhas
  -- pra que as barras sejam comparaveis entre si.
  local rows, scale = {}, 1
  for i = 1, 6 do
    local pending = tonumber(PokemonManager.evPending[i]) or 0
    local effectiveEV = evValues[i]
    if pending ~= 0 then
      effectiveEV = math.max(0, math.min(math.max(252, evValues[i]), evValues[i] + pending))
    end
    local r = {
      base = baseValues[i],
      iv = pmStatIVContribution(baseValues[i], ivValues[i]),
      evCur = pmStatEVContribution(baseValues[i], evValues[i]),
      evEff = pmStatEVContribution(baseValues[i], effectiveEV),
      vit = pmStatVitaminContribution(baseValues[i], vitaminValues[i]),
      effectiveEV = effectiveEV
    }
    -- "VALOR" = previa do nucleo Base + IV + EV + Vitaminas.
    -- Nature/Level/Boost/Love/Talisman continuam sendo calculados no servidor.
    r.bonus = (p.bonus and p.bonus[i]) or 0
    r.nature = pmNatureMult(p.nature, i) * pmTeraMult(p.tera, i) -- codex nature + tera
    r.preview = math.floor((r.base + r.iv + r.evEff + r.vit) * r.nature + 0.5) + r.bonus
    r.base = math.floor(baseValues[i] * r.nature + 0.5) -- codex: BASE ja com nature/tera
    local barTotal = r.base + r.iv + math.max(r.evCur, r.evEff) + r.vit
    if barTotal > scale then scale = barTotal end
    rows[i] = r
  end

  for i = 1, 6 do
    local r = rows[i]
    r.scale = scale
    PokemonManager.setBaseStatRow(i, r.base, ivValues[i], r.effectiveEV, vitaminValues[i], r.preview, evValues[i], r)
  end
end


function PokemonManager.bindDashboardCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('dashboardTeam' .. i)
    if card then
      card:setPhantom(false)
      card.onClick = function()
        if PokemonManager.pokemon[i] then
          PokemonManager.selectPokemon(i)
        end
      end
    end
  end

  -- Tiles do rodape do Resumo funcionam como atalho pras paginas.
  local routes = {
    dashboardTileHeld = {'navHeld', 'held'},
    dashboardTileEquip = {'navHeld', 'held'},
    dashboardTileMoves = {'navMoves', 'moves'},
    dashboardTilePassive = {'navAbilities', 'abilities'}
  }
  for tileId, route in pairs(routes) do
    local tile = PokemonManager.window:recursiveGetChildById(tileId)
    if tile then
      tile:setPhantom(false)
      tile.onClick = function()
        PokemonManager.selectMenuButton(route[1])
        PokemonManager.showPage(route[2])
        PokemonManager.softRefresh()
      end
    end
  end
end


function PokemonManager.getTypeColor(typeName)
  local t = tostring(typeName or ""):lower()
  local colors = {
    fire = "#ff5c5c",
    grass = "#67d56f",
    water = "#55aaff",
    electric = "#ffd34d",
    ice = "#79d9ff",
    fighting = "#ff8b62",
    poison = "#c77dff",
    ground = "#d6a86b",
    flying = "#9aa9ff",
    psychic = "#ff72b6",
    bug = "#a8d84f",
    rock = "#c6a66b",
    ghost = "#9b7acb",
    dragon = "#8f7cff",
    dark = "#9a8b9f",
    steel = "#aebbd0",
    fairy = "#ff9bd2",
    normal = "#c7c7b8"
  }
  return colors[t] or "#9bb6dc"
end

function PokemonManager.setTypeBadge(id, typeName)
  local widget = PokemonManager.window and PokemonManager.window:recursiveGetChildById(id)
  if not widget then return end
  local t = tostring(typeName or ''):lower()
  if t == '' or t == 'none' then
    widget:setVisible(false)
    return
  end
  local path = '/modules/game_pokemonmanager/images/' .. t .. '.png'
  widget:setImageSource(path)
  widget:setVisible(true)
end

function PokemonManager.updateTypeBadges(prefix, type1, type2)
  PokemonManager.setTypeBadge(prefix .. 'TypeBadge1', type1)
  PokemonManager.setTypeBadge(prefix .. 'TypeBadge2', type2)
end


-- Cores fixas por atributo (mesma ordem de HP, ATK, DEF, SP.ATK, SP.DEF, SPD).
PokemonManager.summaryStatColors = {'#72e6a0', '#ff8b62', '#ffd34d', '#55aaff', '#c77dff', '#ff72b6'}
PokemonManager.summaryStatNames = {'HP', 'ATK', 'DEF', 'SP.ATK', 'SP.DEF', 'SPD'}

-- Mesma escala de nota do Atributos/IV, pra manter consistencia entre paginas.
function PokemonManager.getIVRating(ivPercent)
  if ivPercent >= 96 then return 'PERFEITO', '#6ee7a8' end
  if ivPercent >= 86 then return 'EXCELENTE', '#8ff09a' end
  if ivPercent >= 71 then return 'BOM', '#f4c95d' end
  if ivPercent >= 51 then return 'REGULAR', '#ffb36b' end
  if ivPercent >= 31 then return 'RUIM', '#ff8f6b' end
  return 'MUITO RUIM', '#ff6b78'
end

local function pmShortText(text, maxLen)
  text = tostring(text or '')
  if #text > maxLen then return text:sub(1, maxLen - 2) .. '..' end
  return text
end

function PokemonManager.updateDashboard()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window

  local p = PokemonManager.pokemon[PokemonManager.selected]
  local view = win:recursiveGetChildById('dashboardView')
  if not view then return end

  local function get(id) return win:recursiveGetChildById(id) end
  local function setText(id, text, color)
    local w = get(id)
    if w then
      w:setText(text)
      if color then w:setColor(color) end
    end
  end
  local function setFill(id, ratio, color)
    local fill = get(id)
    if not fill then return end
    local back = fill:getParent()
    local width = back and back:getWidth() or 0
    if not width or width <= 0 then width = 286 end
    ratio = math.max(0, math.min(1, tonumber(ratio) or 0))
    fill:setWidth(math.floor(width * ratio))
    if color then fill:setBackgroundColor(color) end
  end

  -- Equipe.
  local teamCount = 0
  for i = 1, 6 do
    local card = get('dashboardTeam' .. i)
    local data = PokemonManager.pokemon[i]
    if data then teamCount = teamCount + 1 end
    if card then
      if data then
        card:setVisible(true)
        local icon = card:recursiveGetChildById('icon')
        local level = card:recursiveGetChildById('level')
        local slot = card:recursiveGetChildById('slot')
        if icon then
          local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(data.name) .. '.png'
          pcall(function()
            icon:setImageSource(path)
            icon:setImageSize({width = 54, height = 54})
          end)
        end
        local isSelected = i == PokemonManager.selected
        if level then
          level:setText('Lv.' .. tostring(data.level or '--'))
          level:setColor(isSelected and '#ffd24a' or '#9bb6dc')
        end
        if slot then slot:setText('#' .. tostring(i)) end
        card:setBackgroundColor('#00000000')
        card:setImageSource('/modules/game_pokemonmanager/v2/' .. (isSelected and 'kx_slot_on' or 'kx_slot'))
      else
        card:setVisible(false)
      end
    end
  end
  setText('dashboardTeamCount', tostring(teamCount) .. ' / 6 NA EQUIPE')

  local icon = get('dashboardIcon')
  if icon then
    if p then
      local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png'
      pcall(function()
        icon:setImageSource(path)
        icon:setImageSize({width = 132, height = 132})
      end)
      icon:setVisible(true)
    else
      icon:setVisible(false)
    end
  end

  -- Valores (zerados quando nao ha Pokemon).
  local t1 = p and tostring(p.type1 or 'none') or 'none'
  local t2 = p and tostring(p.type2 or 'none') or 'none'
  local typeColor = p and PokemonManager.getTypeColor(t1) or '#3a5170'

  local accent = get('dashboardHeroAccent')
  if accent then accent:setBackgroundColor(typeColor) end
  local portrait = get('dashboardPortrait')
  if portrait then portrait:setBorderColor(p and typeColor or '#2d4c6c') end

  setText('dashboardName', p and string.upper(tostring(p.name or 'POKEMON')) or 'NENHUM POKEMON')
  setText('dashboardSlotTag', p and ('SLOT #' .. tostring(p.index or PokemonManager.selected)) or 'SLOT #-')
  setText('dashboardLevel', 'Lv. ' .. (p and tostring(p.level or '--') or '--'))

  local boost = p and (tonumber(p.boost) or 0) or 0
  setText('dashboardBoost', '+' .. tostring(boost), boost > 0 and '#8fd3ff' or '#5f7596')
  local boostChip = get('dashboardBoostChip')
  if boostChip then boostChip:setBorderColor(boost > 0 and '#55aaff' or '#3a5170') end

  PokemonManager.updateTypeBadges('dashboard', t1, t2)

  local inUse = get('dashboardInUse')
  if inUse then inUse:setVisible(p ~= nil and p.isBeingUsed == true) end

  local nature = p and tostring(p.nature or '-') or '-'
  if nature == '' then nature = '-' end
  setText('dashboardNature', 'NATUREZA: ' .. string.upper(nature) .. (p and ('  (' .. pmNatureDesc(nature) .. ')') or '')) -- codex nature
  local tera = p and pmTeraName(p.tera) or 'none' -- codex tera: numero -> tipo
  if not tera then tera = 'none' end
  if tera == '' or tera == 'none' then
    setText('dashboardTera', 'TERA: -', '#7f94b1')
  else
    setText('dashboardTera', 'TERA: ' .. string.upper(tera) .. ' (+' .. ({'HP','ATK','DEF','SP.ATK','SP.DEF','VEL'})[PM_TERA_STAT[tera]] .. ')', PokemonManager.getTypeColor(tera))
  end

  -- Medidores: HP, Amizade e EV.
  local maxhp = p and (tonumber(p.maxhp) or 0) or 0
  local hp = p and (tonumber(p.hp) or 0) or 0
  local hpRatio = maxhp > 0 and math.max(0, math.min(1, hp / maxhp)) or 0
  local hpColor = hpRatio > 0.5 and '#72e6a0' or (hpRatio > 0.2 and '#ffd34d' or '#ff6b78')
  setFill('dashboardHPFill', hpRatio, hpColor)
  setText('dashboardHPValue', tostring(hp) .. ' / ' .. tostring(maxhp > 0 and maxhp or hp))

  local friendship = p and math.max(0, math.min(1000, tonumber(p.friendship) or 0)) or 0
  local stageIndex = math.min(9, math.floor(friendship / 100))
  local friendColor = friendship >= 1000 and PokemonManager.friendshipMaxColor
    or (PokemonManager.friendshipStageColors[stageIndex] or '#8fd3ff')
  setFill('dashboardFriendFill', friendship / 1000, friendColor)
  setText('dashboardFriendValue', tostring(friendship) .. ' / 1000')

  local baseValues = {0, 0, 0, 0, 0, 0}
  local ivValues = {0, 0, 0, 0, 0, 0}
  local evValues = {0, 0, 0, 0, 0, 0}
  local vitValues = {0, 0, 0, 0, 0, 0}
  if p then
    baseValues = {tonumber(p.basehp) or 0, tonumber(p.baseatk) or 0, tonumber(p.basedef) or 0,
      tonumber(p.basespatk) or 0, tonumber(p.basespdef) or 0, tonumber(p.basespd) or 0}
    ivValues = {tonumber(p.ivhp) or 0, tonumber(p.ivatk) or 0, tonumber(p.ivdef) or 0,
      tonumber(p.ivspatk) or 0, tonumber(p.ivspdef) or 0, tonumber(p.ivspeed) or 0}
    evValues = {tonumber(p.evhp) or 0, tonumber(p.evatk) or 0, tonumber(p.evdef) or 0,
      tonumber(p.evspatk) or 0, tonumber(p.evspdef) or 0, tonumber(p.evspeed) or 0}
    vitValues = {tonumber(p.vitHp) or 0, tonumber(p.vitAttack) or 0, tonumber(p.vitDefense) or 0,
      tonumber(p.vitSpAttack) or 0, tonumber(p.vitSpDefense) or 0, tonumber(p.vitSpeed) or 0}
  end

  local evTotal, ivTotal, baseTotal, maxBase, bestIndex = 0, 0, 0, 1, 0
  for i = 1, 6 do
    evTotal = evTotal + evValues[i]
    ivTotal = ivTotal + ivValues[i]
    baseTotal = baseTotal + baseValues[i]
    if baseValues[i] > maxBase then
      maxBase = baseValues[i]
      bestIndex = i
    end
  end

  setFill('dashboardEVFill', evTotal / 512, PokemonManager.lerpColor('#3a6ea5', '#f2c400', evTotal / 512))
  setText('dashboardEVValue', tostring(evTotal) .. ' / 512')

  -- Qualidade IV + mini grafico por atributo.
  local ivPercent = (ivTotal / 186) * 100
  local rating, ratingColor = PokemonManager.getIVRating(ivPercent)
  if not p then rating, ratingColor = 'SEM DADOS', '#7f94b1' end
  setText('dashboardGradePercent', string.format('%.1f%%', ivPercent), p and ratingColor or '#7f94b1')
  setText('dashboardGradeRating', rating .. (p and (' - ' .. tostring(ivTotal) .. '/186') or ''), ratingColor)
  local gradeBox = get('dashboardGradeBox')
  if gradeBox then gradeBox:setBorderColor(p and ratingColor or '#2d4c6c') end
  for i = 1, 6 do
    local fill = get('dashboardIVFill' .. i)
    if fill then
      local ratio = math.max(0, math.min(1, ivValues[i] / 31))
      fill:setHeight(math.floor(34 * ratio))
      fill:setBackgroundColor(PokemonManager.summaryStatColors[i])
    end
    local tag = get('dashboardIVTag' .. i)
    if tag then tag:setColor(ivValues[i] >= 31 and '#f2c400' or '#5f7596') end
  end

  -- Atributos.
  setText('dashboardBST', 'TOTAL ' .. tostring(baseTotal))
  for i = 1, 6 do
    local row = get('dashboardStatRow' .. i)
    if row then
      local color = PokemonManager.summaryStatColors[i]
      local name = row:recursiveGetChildById('name')
      local value = row:recursiveGetChildById('value')
      local fill = row:recursiveGetChildById('fill')
      local bar = row:recursiveGetChildById('bar')
      local iv = row:recursiveGetChildById('iv')
      local ev = row:recursiveGetChildById('ev')
      local vit = row:recursiveGetChildById('vit')
      local natM = p and (pmNatureMult(p.nature, i) * pmTeraMult(p.tera, i)) or 1 -- codex nature + tera
      if name then
        name:setText(PokemonManager.summaryStatNames[i] .. (natM > 1 and ' +' or (natM < 1 and ' -' or '')))
        name:setColor(natM > 1 and '#5fd35f' or (natM < 1 and '#ff7070' or color))
      end
      if value then
        value:setText(tostring(math.floor(baseValues[i] * natM + 0.5))) -- codex nature/tera
        value:setColor((p and i == bestIndex) and '#ffd24a' or '#ffffff')
      end
      if fill then
        local width = bar and bar:getWidth() or 0
        if not width or width <= 0 then width = 400 end
        fill:setWidth(math.floor(width * math.max(0, math.min(1, baseValues[i] / maxBase))))
        fill:setBackgroundColor(color)
      end
      if iv then
        iv:setText(tostring(ivValues[i]) .. ' / 31')
        iv:setColor(ivValues[i] >= 31 and '#f2c400' or PokemonManager.lerpColor('#5f7596', '#dce8f5', ivValues[i] / 31))
      end
      if ev then
        ev:setText(tostring(evValues[i]) .. ' / 252')
        ev:setColor(evValues[i] >= 252 and '#f2c400' or (evValues[i] > 0 and '#8fd3ff' or '#5f7596'))
      end
      if vit then
        vit:setText(vitValues[i] > 0 and ('+' .. tostring(vitValues[i])) or '-')
        vit:setColor(vitValues[i] > 0 and '#72e6a0' or '#5f7596')
      end
    end
  end

  -- Tiles de atalho.
  local function fillTile(id, label, value, hint, active, clientId, iconName)
    local tile = get(id)
    if not tile then return end
    local lbl = tile:recursiveGetChildById('tileLabel')
    local val = tile:recursiveGetChildById('tileValue')
    local hnt = tile:recursiveGetChildById('tileHint')
    local acc = tile:recursiveGetChildById('tileAccent')
    local item = tile:recursiveGetChildById('tileItem')
    local ico = tile:recursiveGetChildById('tileIcon')
    if lbl then lbl:setText(label) end
    if val then
      val:setText(value)
      val:setColor(active and '#ffffff' or '#7f94b1')
    end
    if hnt then hnt:setText(hint) end
    if acc then acc:setBackgroundColor(active and '#72e6a0' or '#3a5170') end
    tile:setImageSource('/modules/game_pokemonmanager/v2/' .. (active and 'pmx_card_green' or 'kx_card'))
    local cid = tonumber(clientId) or 0
    if item then
      item:setItemId(cid)
      item:setVisible(cid > 0)
    end
    if ico then
      if cid > 0 or not iconName then
        ico:setVisible(false)
      else
        ico:setImageSource(PokemonManager.navIconPath .. iconName .. '.png')
        ico:setVisible(true)
      end
    end
  end

  local held = p and tostring(p.held or '-') or '-'
  local hasHeld = held ~= '' and held ~= '-'
  fillTile('dashboardTileHeld', 'HELD ITEM', hasHeld and pmShortText(string.upper(held), 18) or 'SLOT LIVRE',
    hasHeld and 'EQUIPADO' or 'CLIQUE PARA EQUIPAR', hasHeld, hasHeld and p.heldClientId or 0, 'held')

  local equip = p and tostring(p.equip or '-') or '-'
  local hasEquip = equip ~= '' and equip ~= '-'
  fillTile('dashboardTileEquip', 'MEGA STONE', hasEquip and pmShortText(string.upper(equip), 18) or 'SLOT LIVRE',
    hasEquip and 'EQUIPADO' or 'CLIQUE PARA EQUIPAR', hasEquip, hasEquip and p.equipClientId or 0, 'held')

  local learned, totalMoves = 0, 0
  local list = p and PokemonManager.moves[p.index] or nil
  if list then
    for _, move in pairs(list) do
      totalMoves = totalMoves + 1
      if move.unlocked then learned = learned + 1 end
    end
  end
  local mp = p and PokemonManager.movePoints[p.index] or nil
  local available = mp and math.max(0, (tonumber(mp.total) or 0) - (tonumber(mp.spent) or 0)) or 0
  fillTile('dashboardTileMoves', 'MOVES', tostring(learned) .. ' / ' .. tostring(totalMoves) .. ' APRENDIDAS',
    available > 0 and (tostring(available) .. ' PONTO(S) LIVRE(S)') or 'SEM PONTOS LIVRES', learned > 0, 0, 'moves')
  local movesTile = get('dashboardTileMoves')
  if movesTile then
    local hint = movesTile:recursiveGetChildById('tileHint')
    if hint then hint:setColor(available > 0 and '#f2c400' or '#5f7596') end
  end

  local passive = p and PokemonManager.abilities[p.index] or nil
  local hasPassive = passive ~= nil and passive ~= ''
  fillTile('dashboardTilePassive', 'PASSIVA', hasPassive and pmShortText(string.upper(passive), 18) or 'NENHUMA',
    'RESPEITO: ' .. tostring(math.max(0, tonumber(PokemonManager.respect) or 0)), hasPassive, 0, 'habilidades')
end

-- Mapa: id do botao de clique -> {widget da imagem de fundo, label do texto,
-- widget do icone, nome base do arquivo do icone (sem .png)}.
PokemonManager.navVisualMap = {
  navProfile = {'profileVisual', 'profileText', 'profileIcon', 'perfil'},
  navSummary = {'summaryVisual', 'summaryText', 'summaryIcon', 'resumo'},
  navBase = {'trainBaseVisual', 'baseText', 'trainBaseIcon', 'ev'},
  navVitamins = {'vitaminsVisual', 'vitaminsText', 'vitaminsIcon', 'vitaminas'},
  navMoves = {'movesVisual', 'movesText', 'movesIcon', 'moves'},
  navAbilities = {'abilitiesVisual', 'abilitiesText', 'abilitiesIcon', 'habilidades'},
  navHeld = {'heldVisual', 'heldText', 'heldIcon', 'held'},
  navFriend = {'friendVisual', 'friendText', 'friendIcon', 'amizade'},
  navIncubators = {'incubatorsVisual', 'incubatorsText', 'incubatorsIcon', 'incubadora'},
  navEvolution = {'evolutionVisual', 'evolutionText', 'evolutionIcon', 'evolucao'}
}

PokemonManager.navIconPath = '/modules/game_pokemonmanager/menu/icons/'

function PokemonManager.selectMenuButton(id)
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  for buttonId, refs in pairs(PokemonManager.navVisualMap) do
    local visual = PokemonManager.window:recursiveGetChildById(refs[1])
    local label = PokemonManager.window:recursiveGetChildById(refs[2])
    local icon = PokemonManager.window:recursiveGetChildById(refs[3])
    local selected = (buttonId == id) or (id == 'navEV' and buttonId == 'navBase')

    if visual then
      if selected then
        visual:setImageSource('/modules/game_pokemonmanager/menu/button_over.png')
        visual:setVisible(true)
      else
        visual:setVisible(false)
      end
    end

    if label then
      label:setColor(selected and '#041626' or '#9CACD1')
      PokemonManager.setNavFont(label, selected)
    end

    if icon then
      icon:setImageSource(PokemonManager.navIconPath .. refs[4] .. (selected and '_hover.png' or '.png'))
    end
  end
end

-- Fundo dourado/branco: fonte sem contorno (a rounded borra texto escuro).
function PokemonManager.setNavFont(label, light)
  label:setFont(light and 'verdana-11px-antialised' or 'verdana-11px-rounded')
end

function PokemonManager.bindMenuHover(buttonId)
  local refs = PokemonManager.navVisualMap[buttonId]
  if not refs then return end
  local button = PokemonManager.window:recursiveGetChildById(buttonId)
  if not button then return end

  button.onHoverChange = function(widget, hovered)
    if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

    local visual = PokemonManager.window:recursiveGetChildById(refs[1])
    local label = PokemonManager.window:recursiveGetChildById(refs[2])
    local icon = PokemonManager.window:recursiveGetChildById(refs[3])
    if not visual then return end

    local selected = (PokemonManager.currentPage == 'summary' and buttonId == 'navSummary')
      or (PokemonManager.currentPage == 'base' and buttonId == 'navBase')
      or (PokemonManager.currentPage == 'ev' and buttonId == 'navBase')
      or (PokemonManager.currentPage == 'vitamins' and buttonId == 'navVitamins')
      or (PokemonManager.currentPage == 'moves' and buttonId == 'navMoves')
      or (PokemonManager.currentPage == 'abilities' and buttonId == 'navAbilities')
      or (PokemonManager.currentPage == 'held' and buttonId == 'navHeld')
      or (PokemonManager.currentPage == 'friend' and buttonId == 'navFriend')
      or (PokemonManager.currentPage == 'incubators' and buttonId == 'navIncubators')
      or (PokemonManager.currentPage == 'evolution' and buttonId == 'navEvolution')

    if selected then
      -- Pagina selecionada: mantem o fundo dourado, nao mexe no hover.
      visual:setImageSource('/modules/game_pokemonmanager/menu/button_over.png')
      visual:setVisible(true)
      if label then label:setColor('#041626'); PokemonManager.setNavFont(label, true) end
      if icon then icon:setImageSource(PokemonManager.navIconPath .. refs[4] .. '_hover.png') end
    elseif hovered then
      visual:setImageSource('/modules/game_pokemonmanager/menu/button_rolar.png')
      visual:setVisible(true)
      if label then label:setColor('#041626'); PokemonManager.setNavFont(label, true) end
      if icon then icon:setImageSource(PokemonManager.navIconPath .. refs[4] .. '_hover.png') end
    else
      visual:setVisible(false)
      if label then label:setColor('#9CACD1'); PokemonManager.setNavFont(label, false) end
      if icon then icon:setImageSource(PokemonManager.navIconPath .. refs[4] .. '.png') end
    end
  end
end

function PokemonManager.bindMenuSelection()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  -- id do botao -> pagina que ele abre.
  local routes = {
    navProfile = 'profile',
    navSummary = 'summary',
    navBase = 'base',
    navVitamins = 'vitamins',
    navMoves = 'moves',
    navAbilities = 'abilities',
    navHeld = 'held',
    navFriend = 'friend',
    navIncubators = 'incubators',
    navEvolution = 'evolution'
  }

  for buttonId, page in pairs(routes) do
    local button = PokemonManager.window:recursiveGetChildById(buttonId)
    if button then
      button.onClick = function()
        PokemonManager.selectMenuButton(buttonId)
        PokemonManager.showPage(page)
        PokemonManager.softRefresh()
      end
    end
    PokemonManager.bindMenuHover(buttonId)
  end

  local navEV = PokemonManager.window:recursiveGetChildById('navEV')
  if navEV then
    navEV:setVisible(false)
    navEV.onClick = function()
      PokemonManager.selectMenuButton('navEV')
      PokemonManager.showPage('ev')
    end
  end

  PokemonManager.selectMenuButton('navSummary')
end

function PokemonManager.show()
  if not g_game.isOnline() then
    modules.game_textmessage.displayFailureMessage('[PokemonManager] Voce precisa estar online!')
    return
  end
  if PokemonManager.window and not PokemonManager.window:isDestroyed() then
    PokemonManager.window:show(); PokemonManager.window:raise(); PokemonManager.window:focus(); PokemonManager.showPage('summary'); PokemonManager.selectMenuButton('navSummary'); PokemonManager.request(); return
  end
  if not PokemonManager.opcodeRegistered then PokemonManager.tryRegisterOpcode() end
  local result
  local lastError
  for _, path in ipairs({'pokemonmanager','/game_pokemonmanager/pokemonmanager',g_resources.getWorkDir()..'modules/game_pokemonmanager/pokemonmanager'}) do
    local ok,res=pcall(function() return g_ui.displayUI(path) end)
    if ok and res then result=res break elseif not ok then lastError=tostring(res) end
  end
  if not result then
    modules.game_textmessage.displayFailureMessage('[PokemonManager] Falha ao carregar interface.')
    g_logger.error('[PokemonManager] Falha ao carregar pokemonmanager.otui: '..tostring(lastError))
    return
  end
  PokemonManager.window=result
  local close=result:recursiveGetChildById('btnClose')
  if close then close.onClick=function() PokemonManager.hide() end end
  local root=modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
  result:setParent(root,true); result:addAnchor(AnchorCenter,'parent',AnchorCenter)
  -- CODEX celular: cabecalho baixo e sem o logo do menu (cabe na altura da tela)
  if type(codexCelular)=='function' and codexCelular() then
    pcall(function()
      local header=result:recursiveGetChildById('header'); if header then header:setHeight(36) end
      local close=result:recursiveGetChildById('btnClose'); if close then close:setMarginTop(3) end
      local logo=result:recursiveGetChildById('managerLogo'); if logo then logo:setHeight(0); logo:setMarginTop(0); logo:hide() end
      local body=result:recursiveGetChildById('body'); if body then body:setMarginTop(4); body:setMarginBottom(4) end
      result:setHeight(math.min(result:getHeight(), root:getHeight() - 4))
    end)
  end
  PokemonManager.bindTeamCards()
  PokemonManager.bindPartyBar()
  PokemonManager.bindDashboardCards()
  PokemonManager.bindBaseCards()
  PokemonManager.bindEVCards()
  PokemonManager.bindEVControls()
  PokemonManager.bindVitaminControls()
  PokemonManager.bindIncubatorControls()
  PokemonManager.bindMenuSelection()
  PokemonManager.showPage('summary')
  PokemonManager.updatePlayerName()
  PokemonManager.request()
end

function PokemonManager.hide()
  if PokemonManager.window and not PokemonManager.window:isDestroyed() then PokemonManager.window:hide() end
end

function PokemonManager.toggle()
  if PokemonManager.window and not PokemonManager.window:isDestroyed() and PokemonManager.window:isVisible() then PokemonManager.hide() else PokemonManager.show() end
end

function PokemonManager.request()
  if not g_game.isOnline() then return end
  if not PokemonManager.opcodeRegistered and not PokemonManager.tryRegisterOpcode() then return end
  local proto=g_game.getProtocolGame(); if not proto then return end
  PokemonManager.pokemon={}; PokemonManager.moves={}; PokemonManager.abilities={}; PokemonManager.abilityDesc={}; PokemonManager.selected=1; PokemonManager.keepSelected=nil; PokemonManager.resetEVPending()
  PokemonManager.resetTeamCards()
  proto:sendExtendedOpcode(PokemonManager.opcode,'REQUEST')
  g_logger.info('[PokemonManager V6.6.0] REQUEST enviado.')
end

-- Atualiza os dados sem fechar o Manager. Chamado nos cliques do jogador
-- (menu lateral, atalhos do resumo): a protecao anti-bot do cliente so
-- permite enviar pacotes a partir de uma acao do jogador, nunca por timer.
-- Mantem o Pokemon selecionado e a pagina atual.
PokemonManager.lastSoftRefresh = 0
function PokemonManager.softRefresh()
  if not g_game.isOnline() then return end
  local now = g_clock.millis()
  if now - (PokemonManager.lastSoftRefresh or 0) < 800 then return end
  PokemonManager.lastSoftRefresh = now
  if not PokemonManager.opcodeRegistered and not PokemonManager.tryRegisterOpcode() then return end
  local proto = g_game.getProtocolGame(); if not proto then return end
  PokemonManager.keepSelected = PokemonManager.selected
  proto:sendExtendedOpcode(PokemonManager.opcode, 'REQUEST')
end


function PokemonManager.updateEconomy()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  local profile = PokemonManager.profile or {}

  local function formatNumber(value)
    value = tonumber(value) or 0
    local text = tostring(math.floor(value))
    while true do
      local changed
      text, changed = text:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
      if changed == 0 then break end
    end
    return text
  end

  local gold = PokemonManager.window:recursiveGetChildById('playerGold')
  local pokeCoins = PokemonManager.window:recursiveGetChildById('playerPokeCoins')
  local donate = PokemonManager.window:recursiveGetChildById('playerDonate')
  local tokens = PokemonManager.window:recursiveGetChildById('playerTokens')

  if gold then gold:setText(formatNumber(profile.gold)) end
  if pokeCoins then pokeCoins:setText(formatNumber(profile.pokecoins)) end
  if donate then donate:setText(formatNumber(profile.donate)) end
  if tokens then tokens:setText(formatNumber(profile.tokens)) end
end

function PokemonManager.updatePlayerId()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local label = PokemonManager.window:recursiveGetChildById('playerId')
  if label then
    label:setText('ID #' .. tostring((PokemonManager.profile or {}).id or 0))
  end
end

function PokemonManager.updatePlayerName()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local label=PokemonManager.window:recursiveGetChildById('playerName')
  local player=g_game.getLocalPlayer()
  if label then label:setText(player and player:getName() or 'Aguardando dados...') end
end

local function pmProfileNumber(value)
  value = tonumber(value) or 0
  local text = tostring(math.floor(value))
  while true do
    local changed
    text, changed = text:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
    if changed == 0 then break end
  end
  return text
end

local function pmProfileDuration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  if hours > 0 then return pmProfileNumber(hours) .. 'h ' .. string.format('%02dm', minutes) end
  return tostring(minutes) .. 'm'
end

-- Outfit do jogador no Perfil. Criado via Lua com pcall: se o fork nao
-- tiver UICreature, a moldura so fica vazia (declarar no .otui quebraria
-- a janela inteira).
function PokemonManager.updateProfileOutfit()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local frame = PokemonManager.window:recursiveGetChildById('profileOutfitFrame')
  local localPlayer = g_game.getLocalPlayer()
  if not frame or not localPlayer then return end
  pcall(function()
    local creature = frame:getChildById('profileOutfit')
    if not creature then
      creature = g_ui.createWidget('UICreature', frame)
      creature:setId('profileOutfit')
      creature:setSize({width = 64, height = 64})
      creature:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
      creature:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      creature:setPhantom(true)
    end
    creature:setOutfit(localPlayer:getOutfit())
  end)
end

function PokemonManager.updateProfileStats()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window
  local profile = PokemonManager.profile or {}
  local function get(id) return win:recursiveGetChildById(id) end
  local function setText(id, text, color)
    local w = get(id)
    if w then
      w:setText(text)
      if color then w:setColor(color) end
    end
  end
  local function setFill(id, ratio, color, fallback)
    local fill = get(id)
    if not fill then return end
    local track = fill:getParent()
    local width = track and track:getWidth() or 0
    if not width or width <= 0 then width = fallback end
    fill:setWidth(math.floor(width * math.max(0, math.min(1, tonumber(ratio) or 0))))
    if color then fill:setBackgroundColor(color) end
  end

  PokemonManager.updateProfileOutfit()

  -- Level / XP. Usa o percentual real do LocalPlayer quando disponivel.
  local level = math.max(1, tonumber(profile.level) or 1)
  local levelPercent = math.max(0, math.min(100, math.floor(tonumber(profile.levelPercent) or 0)))
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer and localPlayer.getLevelPercent then
    local ok, percent = pcall(function() return localPlayer:getLevelPercent() end)
    if ok and percent ~= nil then
      levelPercent = math.max(0, math.min(100, math.floor(tonumber(percent) or 0)))
    end
  end
  setText('profileLevelValue', 'LV ' .. tostring(level))
  setText('profileLevelPercent', tostring(levelPercent) .. '%')
  setFill('profileLevelFill', levelPercent / 100, PokemonManager.lerpColor('#3a6ea5', '#f2c400', levelPercent / 100), 400)
  setText('profileExperience', 'XP ' .. pmProfileNumber(profile.experience))

  -- Identidade.
  local town = tostring(profile.town or '')
  setText('profileTown', 'CIDADE: ' .. (town ~= '' and string.upper(town) or '-'))
  setText('profileRespect', 'RESPEITO: ' .. pmProfileNumber(math.max(0, tonumber(PokemonManager.respect) or 0)))

  local premium = math.max(0, tonumber(profile.premiumDays) or 0)
  local premiumChip = get('profilePremiumChip')
  if premium > 0 then
    setText('profilePremium', 'VIP - ' .. tostring(premium) .. (premium == 1 and ' DIA' or ' DIAS'), '#f2c400')
    if premiumChip then premiumChip:setBorderColor('#f2c400') end
  else
    setText('profilePremium', 'CONTA GRATUITA', '#7f94b1')
    if premiumChip then premiumChip:setBorderColor('#3a5170') end
  end

  local guild = tostring(profile.guild or '')
  local guildRank = tostring(profile.guildRank or '')
  if guild ~= '' then
    setText('profileGuild', 'GUILD: ' .. string.upper(guild) .. (guildRank ~= '' and (' - ' .. string.upper(guildRank)) or ''), '#8fd3ff')
  else
    setText('profileGuild', 'SEM GUILD', '#5f7596')
  end
  local house = tostring(profile.house or '')
  if house ~= '' then
    setText('profileHouse', 'CASA: ' .. string.upper(house), '#72e6a0')
  else
    setText('profileHouse', 'SEM CASA', '#5f7596')
  end

  -- Atividade. A sessao continua contando no cliente desde o ultimo PROFILE.
  local elapsed = math.max(0, os.time() - (tonumber(profile.receivedAt) or os.time()))
  local totalSeconds = math.max(0, tonumber(profile.onlineSeconds) or 0) + elapsed
  local sessionSeconds = math.max(0, tonumber(profile.sessionSeconds) or 0) + elapsed
  setText('profileTimeTotal', pmProfileDuration(totalSeconds))
  setText('profileTimeTotalSub', pmProfileNumber(math.floor(totalSeconds / 86400)) .. ' DIA(S) DE JOGO')
  setText('profileTimeSession', pmProfileDuration(sessionSeconds))
  setText('profileTimeSessionSub', 'DESDE O ULTIMO LOGIN')

  local created = tonumber(profile.accountCreated) or 0
  if created > 0 then
    setText('profileSince', os.date('%d/%m/%Y', created))
    setText('profileSinceSub', 'HA ' .. pmProfileNumber(math.floor(math.max(0, os.time() - created) / 86400)) .. ' DIAS')
  else
    setText('profileSince', '-')
    setText('profileSinceSub', '')
  end

  local deaths = math.max(0, tonumber(profile.deaths) or 0)
  setText('profileDeaths', pmProfileNumber(deaths), deaths > 0 and '#ffffff' or '#72e6a0')
  setText('profileDeathsSub', deaths > 0 and 'REGISTRADAS NO SERVIDOR' or 'NENHUMA MORTE')

  -- Stamina (TFS: maximo 42h = 2520 min; bonus acima de 39h, baixa abaixo de 14h).
  local rawStamina = tonumber(profile.stamina)
  local stamina = math.max(0, math.min(2520, rawStamina or 0))
  local staminaColor, staminaStatus
  if rawStamina == nil then
    staminaColor, staminaStatus = '#5f7596', 'SEM DADOS DO SERVIDOR'
  elseif stamina >= 2340 then
    staminaColor, staminaStatus = '#f2c400', 'BONUS DE EXPERIENCIA'
  elseif stamina >= 840 then
    staminaColor, staminaStatus = '#72e6a0', 'NORMAL'
  else
    staminaColor, staminaStatus = '#ff6b78', 'BAIXA - DESCANSE'
  end
  setText('profileStaminaValue', rawStamina and string.format('%dh %02dm', math.floor(stamina / 60), stamina % 60) or '-')
  setText('profileStaminaPercent', 'MAX 42h')
  setText('profileStaminaStatus', staminaStatus, staminaColor)
  setFill('profileStaminaFill', stamina / 2520, staminaColor, 222)
  local staminaAccent = get('profileStaminaCardAccent')
  if staminaAccent then staminaAccent:setBackgroundColor(staminaColor) end

  -- Fishing.
  local fishing = (profile.skills or {}).fishing or {}
  local fishingLevel = math.max(0, tonumber(fishing.level) or 0)
  local fishingPercent = math.max(0, math.min(100, math.floor(tonumber(fishing.percent) or 0)))
  setText('profileFishingValue', 'NIVEL ' .. tostring(fishingLevel))
  setText('profileFishingPercent', tostring(fishingPercent) .. '%')
  setText('profileFishingStatus', tostring(100 - fishingPercent) .. '% PARA O PROXIMO NIVEL')
  setFill('profileFishingFill', fishingPercent / 100, '#55aaff', 223)

  -- Profissao (sistema em desenvolvimento no servidor).
  local profession = tostring(profile.profession or '')
  local hasProfession = profession ~= '' and string.lower(profession) ~= 'nenhuma'
  local professionLevel = math.max(0, tonumber(profile.professionLevel) or 0)
  local professionPercent = math.max(0, math.min(100, math.floor(tonumber(profile.professionPercent) or 0)))
  local professionAccent = get('profileProfessionCardAccent')
  -- Mesmas cores da janela de Profissoes (game_profissoes).
  local professionColors = {
    engenheiro = '#FFC83D', pescador = '#45A8FF', aventureiro = '#72E6A0', estilista = '#C46BE0'
  }
  local professionColor = professionColors[string.lower(profession)] or '#c77dff'
  if hasProfession then
    setText('playerProfession', string.upper(profession), '#ffffff')
    setText('profileProfessionPercent', tostring(professionPercent) .. '%')
    local secondaryName = tostring(profile.secondaryProfession or '')
    if secondaryName ~= '' then
      -- Secundaria cabe na mesma linha: "NV 12  +  PESCADOR NV 3".
      setText('profileProfessionStatus', 'NV ' .. tostring(professionLevel) .. '  +  ' .. string.upper(secondaryName) .. ' NV ' .. tostring(tonumber(profile.secondaryLevel) or 0),
        professionColors[string.lower(secondaryName)] or professionColor)
    else
      setText('profileProfessionStatus', 'NIVEL ' .. tostring(professionLevel) .. ' / 250', professionColor)
    end
    setFill('profileProfessionFill', professionPercent / 100, professionColor, 223)
    if professionAccent then professionAccent:setBackgroundColor(professionColor) end
    local professionTitle = get('profileProfessionCardTitle')
    if professionTitle then professionTitle:setColor(professionColor) end
  else
    setText('playerProfession', 'SEM PROFISSAO', '#7f94b1')
    setText('profileProfessionPercent', '')
    setText('profileProfessionStatus', 'EM BREVE', '#5f7596')
    setFill('profileProfessionFill', 0, '#c77dff', 223)
    if professionAccent then professionAccent:setBackgroundColor('#3a5170') end
  end
end

function PokemonManager.bindPartyBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.partyCards = {}
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('partyCard' .. i)
    PokemonManager.partyCards[i] = card
    if card then
      card:setVisible(false)
      card:setPhantom(false)
      card.onClick = function() PokemonManager.selectPokemon(i) end
      local icon = card:recursiveGetChildById('icon')
      local name = card:recursiveGetChildById('name')
      local level = card:recursiveGetChildById('level')
      local hpFill = card:recursiveGetChildById('hpFill')
      local hpText = card:recursiveGetChildById('hpText')
      local slot = card:recursiveGetChildById('slot')
      if icon then icon:setPhantom(true) end
      if name then name:setPhantom(true) end
      if level then level:setPhantom(true) end
      if hpFill then hpFill:setPhantom(true) end
      if hpText then hpText:setPhantom(true) end
      if slot then slot:setPhantom(true) end
    end
  end
end

function PokemonManager.resetPartyBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.partyCards < 6 then PokemonManager.bindPartyBar() end
  for i = 1, 6 do
    local card = PokemonManager.partyCards[i]
    if card then
      card:setVisible(false)
      card:setBackgroundColor('#102138')
      card:setBorderColor('#294765')
    end
  end
end

function PokemonManager.updatePartyBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.partyCards < 6 then PokemonManager.bindPartyBar() end
  PokemonManager.resetPartyBar()

  local indexes = {}
  for index, _ in pairs(PokemonManager.pokemon) do table.insert(indexes, index) end
  table.sort(indexes)

  for position, index in ipairs(indexes) do
    if position > 6 then break end
    local p = PokemonManager.pokemon[index]
    local card = PokemonManager.partyCards[position]
    if card and p then
      card:setVisible(true)
      card.onClick = function() PokemonManager.selectPokemon(p.index) end

      local icon = card:recursiveGetChildById('icon')
      local name = card:recursiveGetChildById('name')
      local level = card:recursiveGetChildById('level')
      local hpFill = card:recursiveGetChildById('hpFill')
      local hpText = card:recursiveGetChildById('hpText')
      local slot = card:recursiveGetChildById('slot')

      if icon then
        local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png'
        pcall(function()
          icon:setImageSource(path)
          icon:setImageSize({width = 54, height = 54})
        end)
      end
      if name then
        local displayName = string.upper(tostring(p.name or 'POKEMON'))
        if #displayName > 11 then displayName = string.sub(displayName, 1, 10) .. '…' end
        name:setText(displayName)
      end
      if level then level:setText('Lv.' .. tostring(p.level or 0)) end

      local hp = math.max(0, tonumber(p.hp) or 0)
      local maxhp = math.max(1, tonumber(p.maxhp) or hp)
      local ratio = math.min(1, hp / maxhp)
      if hpFill then
        hpFill:setWidth(math.floor(58 * ratio))
        if ratio <= 0 then
          hpFill:setBackgroundColor('#7d2d38')
        elseif ratio <= 0.25 then
          hpFill:setBackgroundColor('#d94b5d')
        elseif ratio <= 0.5 then
          hpFill:setBackgroundColor('#d9a441')
        else
          hpFill:setBackgroundColor('#43c879')
        end
      end
      if hpText then hpText:setText(tostring(hp) .. '/' .. tostring(maxhp)) end
      if slot then slot:setText('#' .. tostring(position)) end

      if p.index == PokemonManager.selected then
        card:setBackgroundColor('#263b59')
        card:setBorderColor('#ffd24a')
      else
        card:setBackgroundColor('#102138')
        card:setBorderColor('#294765')
      end
      if level then level:setColor(p.index == PokemonManager.selected and '#ffd24a' or '#9bb6dc') end
    end
  end
end

function PokemonManager.bindTeamCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.cards={}
  for i=1,6 do
    local card=PokemonManager.window:recursiveGetChildById('teamCard'..i)
    PokemonManager.cards[i]=card
    if card then
      card:setVisible(false)
      card:setPhantom(false)
      card.onClick=function() PokemonManager.selectPokemon(i) end
      local icon=card:recursiveGetChildById('icon')
      local name=card:recursiveGetChildById('name')
      local info=card:recursiveGetChildById('info')
      local hp=card:recursiveGetChildById('hp')
      local slot=card:recursiveGetChildById('slot')
      if icon then icon:setPhantom(true) end
      if name then name:setPhantom(true) end
      if info then info:setPhantom(true) end
      if hp then hp:setPhantom(true) end
      if slot then slot:setPhantom(true) end
    end
  end
end

function PokemonManager.resetTeamCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.cards < 6 then PokemonManager.bindTeamCards() end
  for i=1,6 do
    local card=PokemonManager.cards[i]
    if card then
      card:setVisible(false)
      card:setBackgroundColor('#17263b')
      card:setBorderColor('#263b59')
    end
  end
end

function PokemonManager.sanitizeIconName(name)
  local icon=tostring(name or ''):lower():gsub('|','_'):gsub(':','_')
  -- forma Mega sem icone proprio: usa o icone do Pokemon base
  if icon:sub(1, 5) == 'mega ' and not g_resources.fileExists('/modules/game_pokemonbar/bar_icon/' .. icon .. '.png') then
    icon = icon:sub(6):gsub(' [xy]$', '')
  end
  return icon
end

function PokemonManager.selectPokemon(index)
  if not PokemonManager.pokemon[index] then return end
  local changed = PokemonManager.selected ~= index
  PokemonManager.selected=index
  if changed then PokemonManager.softRefresh() end
  PokemonManager.resetEVPending()
  PokemonManager.updateSelectedUI()
  PokemonManager.updateDashboard()
  PokemonManager.refreshCardSelection()
  PokemonManager.updatePartyBar()
  if PokemonManager.currentPage == 'base' or PokemonManager.currentPage == 'ev' then
    PokemonManager.updateBaseUI()
  elseif PokemonManager.currentPage == 'vitamins' then
    PokemonManager.updateVitaminsUI()
  elseif PokemonManager.currentPage == 'moves' then
    PokemonManager.updateMovesUI()
  elseif PokemonManager.currentPage == 'abilities' then
    PokemonManager.updateAbilitiesUI()
  elseif PokemonManager.currentPage == 'held' then
    PokemonManager.updateHeldUI()
  elseif PokemonManager.currentPage == 'friend' then
    PokemonManager.updateFriendUI()
  elseif PokemonManager.currentPage == 'evolution' then
    PokemonManager.updateEvolutionUI()
    if changed then PokemonManager.requestEvolution() end
  end
  PokemonManager.refreshEVSelection()
end

function PokemonManager.refreshCardSelection()
  for i=1,6 do
    local card=PokemonManager.cards[i]
    if card and not card:isDestroyed() and PokemonManager.pokemon[i] then
      if i==PokemonManager.selected then
        card:setBackgroundColor('#263b59'); card:setBorderColor('#ffd24a')
      else
        card:setBackgroundColor('#17263b'); card:setBorderColor('#263b59')
      end
    end
  end
end

function PokemonManager.fillTeamCard(index,p)
  local card=PokemonManager.cards[index]
  if not card then return end
  card:setVisible(true)
  local icon=card:recursiveGetChildById('icon')
  local name=card:recursiveGetChildById('name')
  local info=card:recursiveGetChildById('info')
  local hp=card:recursiveGetChildById('hp')
  local slot=card:recursiveGetChildById('slot')
  if icon then
    local path='/modules/game_pokemonbar/bar_icon/'..PokemonManager.sanitizeIconName(p.name)..'.png'
    pcall(function() icon:setImageSource(path); icon:setImageSize({width=58,height=58}) end)
  end
  if name then name:setText(string.upper(p.name)) end
  if info then info:setText('Lv.'..tostring(p.level)..'  Boost +'..tostring(p.boost)) end
  if hp then hp:setText('HP '..tostring(p.hp)..'/'..tostring(p.maxhp > 0 and p.maxhp or p.hp)) end
  if slot then slot:setText('#'..tostring(index)) end
end

function PokemonManager.updateTeamCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if #PokemonManager.cards < 6 then PokemonManager.bindTeamCards() end
  PokemonManager.resetTeamCards()
  local indexes={}
  for index,_ in pairs(PokemonManager.pokemon) do table.insert(indexes,index) end
  table.sort(indexes)
  for position,index in ipairs(indexes) do
    if position<=6 then
      local p=PokemonManager.pokemon[index]
      PokemonManager.fillTeamCard(position,p)
      -- Cards are already fixed in the OTUI. Only map received position to visual slot.
      p.visualSlot=position
    end
  end
  if #indexes>0 then
    if not PokemonManager.pokemon[PokemonManager.selected] then PokemonManager.selected=indexes[1] end
  end
  PokemonManager.refreshCardSelectionByData(indexes)
end

function PokemonManager.refreshCardSelectionByData(indexes)
  for position=1,6 do
    local card=PokemonManager.cards[position]
    if card then
      local p=nil
      for _,index in ipairs(indexes or {}) do
        if PokemonManager.pokemon[index] and PokemonManager.pokemon[index].visualSlot==position then p=PokemonManager.pokemon[index] break end
      end
      if p then
        if p.index==PokemonManager.selected then card:setBackgroundColor('#263b59'); card:setBorderColor('#ffd24a') else card:setBackgroundColor('#17263b'); card:setBorderColor('#263b59') end
        card.onClick=function() PokemonManager.selectPokemon(p.index) end
      else
        card:setVisible(false)
      end
    end
  end
end

function PokemonManager.updateSelectedUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local p=PokemonManager.pokemon[PokemonManager.selected]
  local name=PokemonManager.window:recursiveGetChildById('selectedName')
  local level=PokemonManager.window:recursiveGetChildById('selectedLevel')
  local hp=PokemonManager.window:recursiveGetChildById('selectedHP')
  local nature=PokemonManager.window:recursiveGetChildById('selectedNature')
  local types=PokemonManager.window:recursiveGetChildById('selectedTypes')
  local love=PokemonManager.window:recursiveGetChildById('selectedLove')
  local boost=PokemonManager.window:recursiveGetChildById('selectedBoost')
  local held=PokemonManager.window:recursiveGetChildById('selectedHeld')
  local icon=PokemonManager.window:recursiveGetChildById('selectedIcon')
  if not p then
    if name then name:setText('NENHUM POKEMON SELECIONADO') end
    if level then level:setText('Nivel: -') end
    if hp then hp:setText('HP: - / -') end
    if nature then nature:setText('Nature: -') end
    if types then types:setText('') end
    PokemonManager.updateTypeBadges('selected', 'none', 'none')
    if love then love:setText('Amizade: -') end
    if boost then boost:setText('Boost: -') end
    if held then held:setText('Held: -') end
    return
  end
  if name then name:setText(string.upper(p.name)) end
  if level then level:setText('Nivel: '..tostring(p.level)) end
  if hp then hp:setText('HP: '..tostring(p.hp)..' / '..tostring(p.maxhp > 0 and p.maxhp or p.hp)) end
  if nature then nature:setText('Nature: '..tostring(p.nature)) end
  if types then
    local t1=tostring(p.type1 or 'none'); local t2=tostring(p.type2 or 'none')
    local text='Tipos: '..t1
    if t2~='' and t2~='none' then text=text..' / '..t2 end
    types:setText(text)
    PokemonManager.updateTypeBadges('selected', t1, t2)
    types:setColor(PokemonManager.getTypeColor(t1))
  end
  if love then love:setText('Amizade: '..tostring(p.love)) end
  if boost then boost:setText('Boost: +'..tostring(p.boost)) end
  if held then held:setText('Held: '..tostring(p.held)) end
  if icon then
    local path='/modules/game_pokemonbar/bar_icon/'..PokemonManager.sanitizeIconName(p.name)..'.png'
    pcall(function() icon:setImageSource(path); icon:setImageSize({width=92,height=92}) end)
  end
end


PokemonManager.evPending = PokemonManager.evPending or {0, 0, 0, 0, 0, 0}

function PokemonManager.resetEVPending()
  PokemonManager.evPending = {0, 0, 0, 0, 0, 0}
end

function PokemonManager.setEVPending(row, value)
  local p = PokemonManager.pokemon[PokemonManager.selected]
  if not p or row < 1 or row > 6 then return end

  local currentValues = {
    tonumber(p.evhp) or 0,
    tonumber(p.evatk) or 0,
    tonumber(p.evdef) or 0,
    tonumber(p.evspatk) or 0,
    tonumber(p.evspdef) or 0,
    tonumber(p.evspeed) or 0
  }
  local current = currentValues[row] or 0
  local pending = math.floor(tonumber(value) or 0)
  if pending < -current then pending = -current end
  if pending > 252 - current then pending = 252 - current end

  local pendingAfter = 0
  local totalAfter = 0
  for i = 1, 6 do
    local v = (i == row) and pending or (PokemonManager.evPending[i] or 0)
    pendingAfter = pendingAfter + v
    totalAfter = totalAfter + currentValues[i] + v
  end

  if totalAfter > 512 then
    modules.game_textmessage.displayFailureMessage('[PokemonManager] Limite de 512 EV excedido.')
    return
  end

  local available = tonumber(p.evpoints) or 0
  if available - pendingAfter < 0 then
    modules.game_textmessage.displayFailureMessage('[PokemonManager] Pontos EV insuficientes.')
    return
  end

  PokemonManager.evPending[row] = pending
  local pendingPanel = PokemonManager.window:recursiveGetChildById('evRow' .. row)
  local pendingLabel = pendingPanel and pendingPanel:recursiveGetChildById('basePending' .. row) or nil
  if pendingLabel then pendingLabel:setText((pending >= 0 and '+' or '') .. tostring(pending)) end
  PokemonManager.updateBaseUI()
end

function PokemonManager.changeEVPending(row, delta)
  local current = PokemonManager.evPending[row] or 0
  PokemonManager.setEVPending(row, current + delta)
end

function PokemonManager.bindEVControls()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  for row = 1, 6 do
    local panel = PokemonManager.window:recursiveGetChildById('evRow' .. row)
    if panel then
      local minus = panel:recursiveGetChildById('baseMinus' .. row)
      local plus = panel:recursiveGetChildById('basePlus1' .. row)
      local plus10 = panel:recursiveGetChildById('basePlus10' .. row)
      if minus then minus.onClick = function() PokemonManager.changeEVPending(row, -1) end end
      if plus then plus.onClick = function() PokemonManager.changeEVPending(row, 1) end end
      if plus10 then plus10.onClick = function() PokemonManager.changeEVPending(row, 10) end end
    end
  end

  local clear = PokemonManager.window:recursiveGetChildById('baseClear')
  if clear then
    clear.onClick = function()
      PokemonManager.resetEVPending()
      PokemonManager.updateBaseUI()
    end
  end

  local apply = PokemonManager.window:recursiveGetChildById('baseApply')
  if apply then
    apply.onClick = function()
      local p = PokemonManager.pokemon[PokemonManager.selected]
      if not p then return end

      local current = {
        tonumber(p.evhp) or 0,
        tonumber(p.evatk) or 0,
        tonumber(p.evdef) or 0,
        tonumber(p.evspatk) or 0,
        tonumber(p.evspdef) or 0,
        tonumber(p.evspeed) or 0
      }
      local target = {}
      local total = 0
      local delta = 0
      for i = 1, 6 do
        target[i] = math.max(0, math.min(252, current[i] + (PokemonManager.evPending[i] or 0)))
        total = total + target[i]
        delta = delta + (target[i] - current[i])
      end

      local availablePoints = tonumber(p.evpoints) or 0
      if total > 512 then
        modules.game_textmessage.displayFailureMessage('[PokemonManager] Limite de 512 EV excedido.')
        return
      end
      if delta > availablePoints then
        modules.game_textmessage.displayFailureMessage('[PokemonManager] Pontos EV insuficientes.')
        return
      end

      if not g_game.isOnline() then return end
      local proto = g_game.getProtocolGame()
      if not proto then return end

      proto:sendExtendedOpcode(PokemonManager.opcode, table.concat({
        'APPLY', tostring(PokemonManager.selected),
        tostring(target[1]), tostring(target[2]), tostring(target[3]),
        tostring(target[4]), tostring(target[5]), tostring(target[6])
      }, '|'))
    end
  end
end

function PokemonManager.updateEVUI()
  PokemonManager.updateBaseUI()
end

function PokemonManager.bindVitaminControls()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local map = {
    vitaminRowHp='hp', vitaminRowAttack='attack', vitaminRowDefense='defense', vitaminRowSpAttack='spattack',
    vitaminRowSpDefense='spdefense', vitaminRowSpeed='speed'
  }
  for rowId, status in pairs(map) do
    local row = PokemonManager.window:recursiveGetChildById(rowId)
    local button = row and row:recursiveGetChildById('useButton')
    if button then button.onClick=function() PokemonManager.requestVitaminUse(status, PokemonManager.selected) end end
  end
  local special = PokemonManager.window:recursiveGetChildById('vitaminSpecial')
  local specialMap={vitaminPpMax='ppmax', vitaminPpUp='ppup', vitaminLevel='level'}
  if special then
    for cardId,status in pairs(specialMap) do
      local card=special:recursiveGetChildById(cardId); local button=card and card:recursiveGetChildById('useButton')
      if button then button.onClick=function() PokemonManager.requestVitaminUse(status, PokemonManager.selected) end end
    end
  end
end

-- Ordem das linhas de atributo da pagina de Vitaminas.
PokemonManager.vitaminStatRows = {
  {row = 'vitaminRowHp', label = 'HP', value = 'vitHp', base = 'basehp', item = 'vitItemHp'},
  {row = 'vitaminRowAttack', label = 'ATK', value = 'vitAttack', base = 'baseatk', item = 'vitItemAttack'},
  {row = 'vitaminRowDefense', label = 'DEF', value = 'vitDefense', base = 'basedef', item = 'vitItemDefense'},
  {row = 'vitaminRowSpAttack', label = 'SP.ATK', value = 'vitSpAttack', base = 'basespatk', item = 'vitItemSpAttack'},
  {row = 'vitaminRowSpDefense', label = 'SP.DEF', value = 'vitSpDefense', base = 'basespdef', item = 'vitItemSpDefense'},
  {row = 'vitaminRowSpeed', label = 'SPD', value = 'vitSpeed', base = 'basespd', item = 'vitItemSpeed'}
}
PokemonManager.vitaminPPColor = '#8fd3ff'

local function pmVitaminGain(baseValue, count)
  baseValue = math.max(0, tonumber(baseValue) or 0)
  count = math.max(0, math.min(10, tonumber(count) or 0))
  return math.floor(baseValue * count / 10 * 1.2)
end

function PokemonManager.updateVitaminsUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window

  local p = PokemonManager.pokemon[PokemonManager.selected]
  local function get(id) return win:recursiveGetChildById(id) end
  local function num(key) return p and math.max(0, tonumber(p[key]) or 0) or 0 end

  local title = get('vitaminPokemonName')
  if title then title:setText(p and string.upper(tostring(p.name or 'POKEMON')) or 'NENHUM POKEMON') end

  local vitTotal = math.min(10, num('vitTotal'))
  local remaining = math.max(0, 10 - vitTotal)
  local limitReached = vitTotal >= 10

  -- Resumo: total, restantes e as 10 "pilulas" coloridas por quem consumiu.
  local total = get('vitaminTotalValue')
  if total then
    total:setText(tostring(vitTotal) .. ' / 10')
    total:setColor(limitReached and '#f2c400' or '#ffffff')
  end
  local remainingLabel = get('vitaminRemaining')
  if remainingLabel then
    if not p then
      remainingLabel:setText('')
    elseif limitReached then
      remainingLabel:setText('LIMITE ATINGIDO')
      remainingLabel:setColor('#f2c400')
    else
      remainingLabel:setText('RESTAM ' .. tostring(remaining))
      remainingLabel:setColor('#72e6a0')
    end
  end
  local summaryAccent = get('vitaminSummaryAccent')
  if summaryAccent then summaryAccent:setBackgroundColor(not p and '#3a5170' or (limitReached and '#f2c400' or '#72e6a0')) end

  local pipColors, parts = {}, {}
  for i, def in ipairs(PokemonManager.vitaminStatRows) do
    local count = math.min(10, num(def.value))
    for _ = 1, count do table.insert(pipColors, PokemonManager.summaryStatColors[i]) end
    if count > 0 then table.insert(parts, def.label .. ' ' .. tostring(count)) end
  end
  local ppMaxCount, ppUpCount = num('vitPpMax'), num('vitPpUp')
  for _ = 1, ppMaxCount do table.insert(pipColors, PokemonManager.vitaminPPColor) end
  for _ = 1, ppUpCount do table.insert(pipColors, PokemonManager.vitaminPPColor) end
  if ppMaxCount > 0 then table.insert(parts, 'PP MAX ' .. tostring(ppMaxCount)) end
  if ppUpCount > 0 then table.insert(parts, 'PP UP ' .. tostring(ppUpCount)) end
  -- Se o servidor contar algo que o cliente nao detalha, completa em cinza-azulado.
  while #pipColors < vitTotal do table.insert(pipColors, '#9bb6dc') end

  for k = 1, 10 do
    local pip = get('vitaminPip' .. k)
    if pip then
      local c = k <= vitTotal and pipColors[k] or nil
      pip:setBackgroundColor(c or '#091522')
      pip:setBorderColor(c or '#1c3350')
    end
  end
  local breakdown = get('vitaminBreakdown')
  if breakdown then
    breakdown:setText(#parts > 0 and table.concat(parts, '  -  ') or 'NENHUMA VITAMINA USADA')
  end

  -- Linhas de atributo.
  for i, def in ipairs(PokemonManager.vitaminStatRows) do
    local row = get(def.row)
    if row then
      local color = PokemonManager.summaryStatColors[i]
      local value = math.min(10, num(def.value))
      local baseValue = num(def.base)
      local items = num(def.item)
      local isMax = value >= 10
      local canUse = p ~= nil and items > 0 and not isMax and not limitReached

      local gain = pmVitaminGain(baseValue, value)
      local nextGain = pmVitaminGain(baseValue, value + 1) - gain

      local valueLabel = row:recursiveGetChildById('value')
      if valueLabel then
        valueLabel:setText(tostring(value) .. ' / 10')
        valueLabel:setColor(isMax and '#f2c400' or (value > 0 and '#ffffff' or '#7f94b1'))
      end
      local contribution = row:recursiveGetChildById('contribution')
      if contribution then
        contribution:setText('+' .. tostring(gain))
        contribution:setColor(gain > 0 and '#72e6a0' or '#5f7596')
      end
      local nextLabel = row:recursiveGetChildById('nextGain')
      if nextLabel then
        if not p then
          nextLabel:setText('-')
          nextLabel:setColor('#5f7596')
        elseif isMax then
          nextLabel:setText('MAXIMO')
          nextLabel:setColor('#f2c400')
        elseif limitReached then
          nextLabel:setText('LIMITE')
          nextLabel:setColor('#5f7596')
        else
          nextLabel:setText('+' .. tostring(nextGain))
          nextLabel:setColor(items > 0 and '#f2c400' or '#7f94b1')
        end
      end
      local itemLabel = row:recursiveGetChildById('itemCount')
      if itemLabel then
        itemLabel:setText('x' .. tostring(items) .. ' NA BAG')
        itemLabel:setColor(items > 0 and '#c8d6ec' or '#5f7596')
      end
      local useButton = row:recursiveGetChildById('useButton')
      if useButton then useButton:setEnabled(canUse) end

      local accent = row:recursiveGetChildById('accent')
      if accent then accent:setBackgroundColor(isMax and '#f2c400' or color) end
      local name = row:recursiveGetChildById('name')
      if name then name:setColor(color) end
      row:setBorderColor(isMax and '#6b5a1a' or (canUse and '#294765' or '#1c3350'))

      for k = 1, 10 do
        local pip = row:recursiveGetChildById('pip' .. k)
        if pip then
          if k <= value then
            pip:setBackgroundColor(color)
            pip:setBorderColor(color)
          elseif k == value + 1 and canUse then
            pip:setBackgroundColor('#2a2610')
            pip:setBorderColor('#f2c400')
          else
            pip:setBackgroundColor('#091522')
            pip:setBorderColor('#1c3350')
          end
        end
      end
    end
  end

  -- Itens especiais. PP MAX / PP UP contam no limite de 10; LEVEL nao.
  local special = get('vitaminSpecial')
  if special then
    local defs = {
      {id = 'vitaminPpMax', value = 'vitPpMax', item = 'vitItemPpMax', limited = true},
      {id = 'vitaminPpUp', value = 'vitPpUp', item = 'vitItemPpUp', limited = true},
      {id = 'vitaminLevel', value = 'vitLevel', item = 'vitItemLevel', limited = false}
    }
    for _, def in ipairs(defs) do
      local card = special:recursiveGetChildById(def.id)
      if card then
        local used = num(def.value)
        local items = num(def.item)
        local canUse = p ~= nil and items > 0 and (not def.limited or not limitReached)
        local value = card:recursiveGetChildById('value')
        if value then
          value:setText(tostring(used) .. (used == 1 and ' USADO' or ' USADOS'))
          value:setColor(used > 0 and '#f4c95d' or '#7f94b1')
        end
        local countLabel = card:recursiveGetChildById('itemCount')
        if countLabel then
          countLabel:setText('x' .. tostring(items))
          countLabel:setColor(items > 0 and '#c8d6ec' or '#5f7596')
        end
        local rule = card:recursiveGetChildById('rule')
        if rule then
          if def.limited then
            rule:setText(limitReached and 'LIMITE ATINGIDO' or 'CONTA NO LIMITE')
            rule:setColor(limitReached and '#ff9a7a' or '#5f7596')
          else
            rule:setText('SEM LIMITE')
            rule:setColor('#5f7596')
          end
        end
        local useButton = card:recursiveGetChildById('useButton')
        if useButton then useButton:setEnabled(canUse) end
        local accent = card:recursiveGetChildById('accent')
        local accentColor = def.limited and PokemonManager.vitaminPPColor or '#f2c400'
        if accent then accent:setBackgroundColor(canUse and accentColor or '#3a5170') end
        card:setBorderColor(canUse and '#294765' or '#1c3350')
      end
    end
  end
end


function PokemonManager.moveType(name)
  return PokemonManager.moveTypes[string.lower(tostring(name or ''))] or 'NORMAL'
end

function PokemonManager.updateMovesPartyBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end

  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('movesPartyCard' .. i)
    if card then
      card:setVisible(false)
    end
  end

  local indexes = {}
  for index, _ in pairs(PokemonManager.pokemon) do
    table.insert(indexes, index)
  end
  table.sort(indexes)

  for position, index in ipairs(indexes) do
    if position > 6 then break end

    local p = PokemonManager.pokemon[index]
    local card = PokemonManager.window:recursiveGetChildById('movesPartyCard' .. position)

    if card and p then
      card:setVisible(true)
      card.onClick = function()
        PokemonManager.selectPokemon(p.index)
        PokemonManager.updateMovesPartyBar()
      end

      local icon = card:recursiveGetChildById('icon')
      local level = card:recursiveGetChildById('level')
      local slot = card:recursiveGetChildById('slot')

      if icon then
        local path = '/modules/game_pokemonbar/bar_icon/' ..
          PokemonManager.sanitizeIconName(p.name) .. '.png'
        pcall(function()
          icon:setImageSource(path)
          icon:setImageSize({width = 54, height = 54})
        end)
      end

      if slot then
        slot:setText('#' .. tostring(position))
      end

      if level then
        level:setText('Lv.' .. tostring(p.level or 0))
        level:setColor(index == PokemonManager.selected and '#ffd24a' or '#9bb6dc')
      end

      card:setBorderColor(index == PokemonManager.selected and '#ffd24a' or '#294765')
      card:setBackgroundColor(index == PokemonManager.selected and '#263b59' or '#102138')
    end
  end
end

-- Layout da grade de 2 colunas da pagina de Moves. movesList nao tem
-- mais "layout: verticalBox" no otui (cada PMMoveRow e posicionado na
-- mao aqui, via addAnchor/margin), porque o card precisou ficar
-- compacto (2 linhas) pra caber em meia largura.
local PM_MOVE_ROW_HEIGHT = 48
local PM_MOVE_ROW_SPACING = 6
local PM_MOVE_COLUMN_GAP = 8

-- Estados visuais das linhas de Move.
PokemonManager.moveRowStyle = {
  learned   = {accent = '#72e6a0', border = '#2c5a4a', bg = '#0f2230', name = '#ffffff'},
  ready     = {accent = '#f2c400', border = '#6b5a1a', bg = '#142038', name = '#ffffff'},
  noPoints  = {accent = '#55aaff', border = '#294765', bg = '#102138', name = '#dce8f5'},
  lockedLvl = {accent = '#3a5170', border = '#1c3350', bg = '#0c1828', name = '#9bb6dc'}
}

function PokemonManager.updateMovesUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window

  local list = win:recursiveGetChildById('movesList')
  local pointsLabel = win:recursiveGetChildById('movesPoints')
  local pokemonName = win:recursiveGetChildById('movesPokemonName')
  local subtitleLabel = win:recursiveGetChildById('movesSubtitle')
  if not list then return end

  local function get(id) return win:recursiveGetChildById(id) end
  local function setText(id, text, color)
    local w = get(id)
    if w then
      w:setText(text)
      if color then w:setColor(color) end
    end
  end

  for i = 1, 40 do
    local row = list:recursiveGetChildById('moveRow' .. i)
    if row then row:destroy() end
  end

  local empty = list:recursiveGetChildById('moveEmpty')
  if empty then empty:destroy() end

  local p = PokemonManager.pokemon[PokemonManager.selected]
  local defaultSubtitle = 'Cada level ganho da 1 ponto de skill. Gaste os pontos para aprender Moves.'

  -- Resumo de pontos (tambem usado no estado vazio).
  local function fillSummary(available, total, spent, learnedCount, moveCount, locked, hasPokemon)
    if pointsLabel then
      pointsLabel:setText(tostring(available))
      pointsLabel:setColor(available > 0 and '#ffd24a' or '#7f94b1')
    end
    setText('movesPointsDetail', (available == 1 and 'DISPONIVEL' or 'DISPONIVEIS') .. ' DE ' .. tostring(total))
    setText('movesPointsLegend', 'GASTOS ' .. tostring(spent) .. '  -  LIVRES ' .. tostring(available))
    setText('movesLearnedCount', tostring(learnedCount) .. ' / ' .. tostring(moveCount) .. ' APRENDIDOS',
      (moveCount > 0 and learnedCount >= moveCount) and '#f2c400' or '#72e6a0')

    local accent = get('movesSummaryAccent')
    if accent then accent:setBackgroundColor(available > 0 and '#f2c400' or '#3a5170') end

    local track = get('movesPointsTrack')
    local trackW = track and track:getWidth() or 0
    if not trackW or trackW <= 0 then trackW = 458 end
    local spentFill = get('movesPointsSpent')
    local freeFill = get('movesPointsFree')
    local denom = math.max(1, total, spent + available)
    local spentW = math.floor(trackW * math.min(spent, denom) / denom)
    local freeW = math.min(trackW - spentW, math.floor(trackW * available / denom))
    if spentFill then spentFill:setWidth(math.max(0, spentW)) end
    if freeFill then freeFill:setWidth(math.max(0, freeW)) end

    local chip = get('movesLockChip')
    local chipText = get('movesLockText')
    if not hasPokemon then
      if chip then chip:setBorderColor('#3a5170') end
      if chipText then chipText:setText('-') chipText:setColor('#5f7596') end
    elseif locked then
      if chip then chip:setBorderColor('#ff9a7a') end
      if chipText then chipText:setText('EM CAMPO - GUARDE') chipText:setColor('#ff9a7a') end
    else
      if chip then chip:setBorderColor('#72e6a0') end
      if chipText then chipText:setText('NA POKEBOLA - OK') chipText:setColor('#72e6a0') end
    end
  end

  local function fillColumns(learnedCount, toLearnCount)
    setText('movesColLearnedText', 'APRENDIDOS (' .. tostring(learnedCount) .. ')')
    setText('movesColToLearnText', 'PARA APRENDER (' .. tostring(toLearnCount) .. ')')
  end

  if not p then
    if pokemonName then pokemonName:setText('NENHUM POKEMON') end
    if subtitleLabel then
      subtitleLabel:setText(defaultSubtitle)
      subtitleLabel:setColor('#829abe')
    end
    fillSummary(0, 0, 0, 0, 0, false, false)
    fillColumns(0, 0)
    PokemonManager.updateMovesPartyBar()
    return
  end

  if pokemonName then
    pokemonName:setText(string.upper(tostring(p.name or 'POKEMON')))
  end

  PokemonManager.updateMovesPartyBar()

  -- So pode aprender/esquecer com o Pokemon guardado na pokebola (nao
  -- sendo o summon ativo no momento) -- assim a barra de combate
  -- (opcode 52) sempre reflete o estado atual assim que ele for
  -- invocado de novo, sem precisar sincronizar nada em tempo real.
  local locked = p.isBeingUsed == true

  local listData = PokemonManager.moves[p.index] or {}
  -- codex tm combo: golpes de TM/Sketch podem estar em slots depois dos naturais
  -- (com buraco no meio), entao percorre pelos numeros de slot em ordem
  local codexOrdered = {}
  for idx, mv in pairs(listData) do codexOrdered[#codexOrdered + 1] = { idx = idx, move = mv } end
  table.sort(codexOrdered, function(a, b) return a.idx < b.idx end)
  local points = PokemonManager.movePoints[p.index] or {total = 0, spent = 0}
  local totalPoints = math.max(0, tonumber(points.total) or 0)
  local spentPoints = math.max(0, tonumber(points.spent) or 0)
  local available = math.max(0, totalPoints - spentPoints)

  local learnedCount = 0
  for _, entry in ipairs(codexOrdered) do
    if entry.move.unlocked == true then learnedCount = learnedCount + 1 end
  end

  fillSummary(available, totalPoints, spentPoints, learnedCount, #codexOrdered, locked, true)
  fillColumns(learnedCount, #codexOrdered - learnedCount)

  if subtitleLabel then
    if locked then
      subtitleLabel:setText('Guarde ' .. string.upper(tostring(p.name or 'este Pokemon')) .. ' na pokebola para aprender ou esquecer Moves.')
      subtitleLabel:setColor('#ff9a7a')
    else
      subtitleLabel:setText(defaultSubtitle)
      subtitleLabel:setColor('#829abe')
    end
  end

  if #codexOrdered == 0 then
    local emptyWidget = g_ui.createWidget('PMMoveEmpty', list)
    emptyWidget:setId('moveEmpty')
    emptyWidget:setText('Nenhum Move encontrado para este Pokemon.')
    emptyWidget:addAnchor(AnchorTop, 'parent', AnchorTop)
    emptyWidget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    emptyWidget:addAnchor(AnchorRight, 'parent', AnchorRight)
    return
  end

  -- Coluna esquerda = ja aprendidos, coluna direita = ainda por
  -- aprender (disponivel ou bloqueado por level). Dentro de cada
  -- coluna mantem a ordem original (que normalmente segue o level).
  local totalCount = 0
  local leftCount, rightCount = 0, 0
  local currentLevel = tonumber(p.level) or 0

  for _, codexEntry in ipairs(codexOrdered) do
    local moveIndex, move = codexEntry.idx, codexEntry.move
    totalCount = totalCount + 1
    local isLearned = move.unlocked == true

    local row = g_ui.createWidget('PMMoveRow', list)
    row:setId('moveRow' .. totalCount)

    local colIndex
    row:addAnchor(AnchorTop, 'parent', AnchorTop)
    if isLearned then
      colIndex = leftCount
      leftCount = leftCount + 1
      row:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      row:addAnchor(AnchorRight, 'parent', AnchorHorizontalCenter)
      row:setMarginRight(PM_MOVE_COLUMN_GAP / 2)
    else
      colIndex = rightCount
      rightCount = rightCount + 1
      row:addAnchor(AnchorLeft, 'parent', AnchorHorizontalCenter)
      row:addAnchor(AnchorRight, 'parent', AnchorRight)
      row:setMarginLeft(PM_MOVE_COLUMN_GAP / 2)
    end
    row:setMarginTop(colIndex * (PM_MOVE_ROW_HEIGHT + PM_MOVE_ROW_SPACING))

    local moveIcon = row:recursiveGetChildById('moveIcon')
    local iconBg = row:recursiveGetChildById('iconBg')
    local accent = row:recursiveGetChildById('accent')
    local typeLabel = row:recursiveGetChildById('type')
    local nameLabel = row:recursiveGetChildById('name')
    local levelLabel = row:recursiveGetChildById('level')
    local costLabel = row:recursiveGetChildById('cost')
    local powerLabel = row:recursiveGetChildById('power')
    local statusLabel = row:recursiveGetChildById('status')
    local actionButton = row:recursiveGetChildById('actionButton')
    local levelTrack = row:recursiveGetChildById('levelTrack')
    local levelFill = row:recursiveGetChildById('levelFill')

    local moveName = tostring(move.name or 'MOVE')
    local moveKey = string.lower(moveName)
    local moveLevel = tonumber(move.level) or 1
    local moveCost = tonumber(move.cost) or 1
    local moveType = PokemonManager.moveType(moveName)
    local typeColor = PokemonManager.getTypeColor(moveType)
    local iconFile = PokemonManager.moveIcons[moveKey] or 'normal.png'
    local levelReached = currentLevel >= moveLevel
    local learned = isLearned
    local canAfford = available >= moveCost

    local state
    if learned then
      state = 'learned'
    elseif not levelReached then
      state = 'lockedLvl'
    elseif canAfford then
      state = 'ready'
    else
      state = 'noPoints'
    end
    local style = PokemonManager.moveRowStyle[state]

    if moveIcon then
      -- icone novo da barra de moves (game_pokemonmoves/moveicons.lua)
      local barMod = modules.game_pokemonmoves
      local ok, applied = false, false
      if barMod and barMod.applyMoveIcon then
        ok, applied = pcall(barMod.applyMoveIcon, moveIcon, moveName, 32)
      end
      if not ok or not applied then
        local path = '/modules/game_pokemonmoves/moves_icon/' .. iconFile
        pcall(function()
          moveIcon:setImageSource(path)
          moveIcon:setImageSize({width = 32, height = 32})
        end)
      end
      moveIcon:setOpacity(state == 'lockedLvl' and 0.45 or 1.0)
    end
    if iconBg then iconBg:setBorderColor(state == 'lockedLvl' and '#1c3350' or typeColor) end
    if accent then accent:setBackgroundColor(style.accent) end

    if typeLabel then
      typeLabel:setText(moveType)
      typeLabel:setColor(state == 'lockedLvl' and '#5f7596' or typeColor)
    end

    if nameLabel then
      nameLabel:setText(string.upper(moveName))
      nameLabel:setColor(style.name)
    end

    if levelLabel then
      levelLabel:setText('LV ' .. tostring(moveLevel))
      levelLabel:setColor(levelReached and '#9bb6dc' or '#ff9a7a')
    end

    if powerLabel then
      -- potencia do ataque (vazio em moves de status)
      local power = tonumber(move.power) or 0
      powerLabel:setText(power > 0 and ('POT ' .. tostring(power)) or '')
      powerLabel:setColor(state == 'lockedLvl' and '#5f7596' or '#ff9a3c')
      powerLabel:setTooltip(power > 0 and 'Potencia do ataque' or '')
    end

    if costLabel then
      costLabel:setText(tostring(moveCost) .. ' PT' .. (moveCost > 1 and 'S' or ''))
      costLabel:setColor(learned and '#5f7596' or (canAfford and '#f2c400' or '#7f94b1'))
    end

    -- Estados: bloqueada por level (barra de progresso ate o level),
    -- elegivel sem pontos, elegivel com pontos (pode aprender) ou ja
    -- aprendida (pode esquecer). Botao so clicavel com o Pokemon guardado.
    if levelTrack then levelTrack:setVisible(false) end
    if actionButton then actionButton:setVisible(false) end

    if state == 'lockedLvl' then
      if statusLabel then
        statusLabel:setText('FALTAM ' .. tostring(moveLevel - currentLevel) .. ' LV')
        statusLabel:setColor('#ff9a7a')
      end
      if levelTrack and levelFill then
        levelTrack:setVisible(true)
        local pct = math.max(0, math.min(1, currentLevel / math.max(1, moveLevel)))
        local tw = levelTrack:getWidth()
        if not tw or tw <= 0 then tw = 72 end
        levelFill:setWidth(math.floor(tw * pct))
        levelFill:setBackgroundColor(PokemonManager.lerpColor('#3a6ea5', '#f2c400', pct))
      end
    elseif learned then
      if statusLabel then
        statusLabel:setText(locked and 'GUARDE' or 'APRENDIDO')
        statusLabel:setColor(locked and '#ff9a7a' or '#72e6a0')
      end
      if actionButton then
        actionButton:setVisible(true)
        actionButton:setText('ESQUECER')
        actionButton:setColor('#ff9a9a')
        actionButton:setEnabled(not locked)
        actionButton.onClick = function()
          if not locked then PokemonManager.sendMoveForget(move.name) end
        end
      end
    else
      if statusLabel then
        if locked then
          statusLabel:setText('GUARDE')
          statusLabel:setColor('#ff9a7a')
        elseif canAfford then
          statusLabel:setText('DISPONIVEL')
          statusLabel:setColor('#f2c400')
        else
          statusLabel:setText('SEM PONTOS')
          statusLabel:setColor('#7f94b1')
        end
      end
      if actionButton then
        actionButton:setVisible(true)
        actionButton:setText('APRENDER')
        actionButton:setColor('#8ff09a')
        actionButton:setEnabled(canAfford and not locked)
        actionButton.onClick = function()
          if canAfford and not locked then PokemonManager.sendMoveLearn(move.name) end
        end
      end
    end

    -- codex tm combo: golpe de TM / Sketch (nao se esquece por aqui)
    if move.kind == 'TM' or move.kind == 'SK' then
      if actionButton then actionButton:setVisible(false) end
      if statusLabel then
        statusLabel:setText(move.kind == 'TM' and 'TM' or 'SKETCH')
        statusLabel:setColor('#55aaff')
      end
      if costLabel then costLabel:setText('') end
    end

    -- COMBO: clicar no icone de um move aprendido adiciona ao combo
    local comboBadge = row:recursiveGetChildById('comboBadge')
    local inCombo = PokemonManager.comboPositions(p.index, moveIndex)
    if comboBadge then
      comboBadge:setVisible(learned)
      comboBadge:setText(inCombo ~= '' and inCombo or '+')
      comboBadge:setColor(inCombo ~= '' and '#0a1320' or '#f2c400')
      comboBadge:setBackgroundColor(inCombo ~= '' and '#f2c400' or '#0a1320')
    end
    if learned then
      local function addIt() PokemonManager.comboAdd(moveIndex) end
      if iconBg then
        iconBg:setFocusable(false)
        iconBg:setTooltip('Clique para adicionar ' .. string.upper(moveName) .. ' ao COMBO')
        iconBg.onClick = addIt
      end
      if moveIcon then
        moveIcon:setPhantom(false)
        moveIcon:setTooltip('Clique para adicionar ' .. string.upper(moveName) .. ' ao COMBO')
        moveIcon.onClick = addIt
      end
    end

    row:setBackgroundColor(style.bg)
    row:setBorderColor(style.border)
  end
  PokemonManager.updateComboBar()
end

-- ============================================================
-- COMBO DE MOVES (Auto Moves)
-- O jogador escolhe a ordem dos golpes de cada Pokemon. Fica salvo
-- na pokebola (servidor). Ativa com o botao/atalho COMBO na tela
-- (modulo game_combo), que fala "mcombo".
-- ============================================================
local function pmComboCopy(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

function PokemonManager.comboGetDraft(slot)
  if not PokemonManager.comboDraft[slot] then
    PokemonManager.comboDraft[slot] = pmComboCopy(PokemonManager.combo[slot])
  end
  return PokemonManager.comboDraft[slot]
end

function PokemonManager.comboIsDirty(slot)
  local a = PokemonManager.comboGetDraft(slot)
  local b = PokemonManager.combo[slot] or {}
  if #a ~= #b then return true end
  for i = 1, #a do if a[i] ~= b[i] then return true end end
  return false
end

-- "1" / "1,3" = em quais passos do combo esse move aparece
function PokemonManager.comboPositions(slot, moveIndex)
  local out = {}
  for i, v in ipairs(PokemonManager.comboGetDraft(slot)) do
    if v == moveIndex then out[#out + 1] = tostring(i) end
  end
  return table.concat(out, ',')
end

function PokemonManager.comboAdd(moveIndex)
  local slot = PokemonManager.selected
  local draft = PokemonManager.comboGetDraft(slot)
  if #draft >= PokemonManager.COMBO_MAX then
    modules.game_textmessage.displayFailureMessage('O combo tem no maximo ' .. PokemonManager.COMBO_MAX .. ' golpes.')
    return
  end
  draft[#draft + 1] = moveIndex
  PokemonManager.updateMovesUI()
end

function PokemonManager.comboRemove(pos)
  local draft = PokemonManager.comboGetDraft(PokemonManager.selected)
  if draft[pos] then table.remove(draft, pos) end
  PokemonManager.updateMovesUI()
end

function PokemonManager.comboMove(pos, dir)
  local draft = PokemonManager.comboGetDraft(PokemonManager.selected)
  local other = pos + dir
  if draft[pos] and draft[other] then
    draft[pos], draft[other] = draft[other], draft[pos]
  end
  PokemonManager.updateMovesUI()
end

function PokemonManager.comboClear()
  PokemonManager.comboDraft[PokemonManager.selected] = {}
  PokemonManager.updateMovesUI()
end

function PokemonManager.comboUndo()
  PokemonManager.comboDraft[PokemonManager.selected] = nil
  PokemonManager.updateMovesUI()
end

function PokemonManager.sendComboSave()
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  local draft = PokemonManager.comboGetDraft(PokemonManager.selected)
  local list = {}
  for i, v in ipairs(draft) do list[i] = tostring(v) end
  proto:sendExtendedOpcode(PokemonManager.opcode,
    'COMBO_SET|' .. tostring(PokemonManager.selected) .. '|' .. (#list > 0 and table.concat(list, ',') or '0'))
end

function PokemonManager.updateComboBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window
  local bar = win:recursiveGetChildById('movesComboBar')
  if not bar then return end
  local p = PokemonManager.pokemon[PokemonManager.selected]
  local slot = PokemonManager.selected
  local draft = p and PokemonManager.comboGetDraft(slot) or {}
  local moves = (p and PokemonManager.moves[slot]) or {}
  local dirty = p and PokemonManager.comboIsDirty(slot) or false

  for i = 1, PokemonManager.COMBO_MAX do
    local cell = bar:recursiveGetChildById('comboStep' .. i)
    if cell then
      local idx = draft[i]
      local mv = idx and moves[idx] or nil
      local icon = cell:getChildById('icon')
      local num = cell:getChildById('num')
      local left = cell:getChildById('left')
      local right = cell:getChildById('right')
      local box = cell:getChildById('box') or cell
      if num then num:setText(tostring(i)) end
      if mv then
        local moveName = tostring(mv.name or '')
        box:setBorderColor(PokemonManager.getTypeColor(PokemonManager.moveType(moveName)))
        box:setTooltip(i .. '. ' .. string.upper(moveName) .. '\nClique: tirar do combo')
        if num then num:setColor('#f2c400') end
        if icon then
          icon:setVisible(true)
          local barMod = modules.game_pokemonmoves
          local ok, applied = false, false
          if barMod and barMod.applyMoveIcon then
            ok, applied = pcall(barMod.applyMoveIcon, icon, moveName, 22)
          end
          if not ok or not applied then
            local file = PokemonManager.moveIcons[string.lower(moveName)] or 'normal.png'
            pcall(function()
              icon:setImageSource('/modules/game_pokemonmoves/moves_icon/' .. file)
              icon:setImageSize({width = 22, height = 22})
            end)
          end
        end
        local pos = i
        box.onClick = function() PokemonManager.comboRemove(pos) end
        if left then left:setVisible(i > 1) left.onClick = function() PokemonManager.comboMove(pos, -1) end end
        if right then right:setVisible(draft[i + 1] ~= nil) right.onClick = function() PokemonManager.comboMove(pos, 1) end end
      else
        box:setBorderColor('#1c3350')
        box:setTooltip(idx and 'Move invalido' or 'Vazio - clique no icone de um move APRENDIDO')
        if num then num:setColor('#3a5170') end
        if icon then icon:setVisible(false) end
        if left then left:setVisible(false) end
        if right then right:setVisible(false) end
        local pos = i
        box.onClick = function() if idx then PokemonManager.comboRemove(pos) end end
      end
    end
  end

  local status = bar:recursiveGetChildById('comboStatus')
  if status then
    if not p then
      status:setText('-')
      status:setColor('#6f86a8')
    elseif dirty then
      status:setText('NAO SALVO')
      status:setColor('#ff9a7a')
    elseif #draft == 0 then
      status:setText('SEM COMBO')
      status:setColor('#6f86a8')
    else
      status:setText('SALVO (' .. #draft .. ')')
      status:setColor('#72e6a0')
    end
  end
  -- os cliques sao ligados aqui (o modulo e sandboxed: @onClick no .otui nao enxerga PokemonManager)
  local saveBtn = bar:recursiveGetChildById('comboSave')
  if saveBtn then saveBtn:setEnabled(p ~= nil and dirty); saveBtn.onClick = function() PokemonManager.sendComboSave() end end
  local undoBtn = bar:recursiveGetChildById('comboUndo')
  if undoBtn then undoBtn:setEnabled(p ~= nil and dirty); undoBtn.onClick = function() PokemonManager.comboUndo() end end
  local clearBtn = bar:recursiveGetChildById('comboClear')
  if clearBtn then clearBtn:setEnabled(p ~= nil and #draft > 0); clearBtn.onClick = function() PokemonManager.comboClear() end end
end

-- ============================================================
-- HABILIDADES (Respeito)
-- Estados dos cards: locked = azul-acinzentado, next = dourado
-- (proxima a liberar), unlocked = verde. A barra de cada card
-- vai do azul ao dourado conforme o Respeito se aproxima do req.
-- ============================================================
PokemonManager.abilityGroups = {
  {
    section = 'abilityFieldTitle', label = 'HABILIDADES DE CAMPO', row = 'abilityField',
    items = {
      {id = 'surf', name = 'SURF', req = 30, icon = '/modules/game_pokemonmanager/images/surf.png'},
      {id = 'fly', name = 'FLY', req = 50, icon = '/modules/game_pokemonmanager/images/fly.png'}
    }
  },
  {
    section = 'abilityHeadTitle', label = 'HEADBUTT - ARVORES', row = 'abilityHeadbuttTrees',
    items = {
      {id = 'small', name = 'ARVORES PEQUENAS', req = 5, icon = '/modules/game_pokemonmanager/images/pequenas.png'},
      {id = 'medium', name = 'ARVORES MEDIAS', req = 20, icon = '/modules/game_pokemonmanager/images/medias.png'},
      {id = 'large', name = 'ARVORES GRANDES', req = 45, icon = '/modules/game_pokemonmanager/images/grande.png'}
    }
  },
  {
    section = 'abilityOtherTitle', label = 'OUTRAS HABILIDADES', row = 'abilityOther',
    items = {
      {id = 'cut', name = 'CUT', req = 5, icon = '/modules/game_pokemonmanager/images/cut.png'},
      {id = 'rock', name = 'ROCK SMASH', req = 50, icon = '/modules/game_pokemonmanager/images/rock-smash.png'},
      {id = 'dive', name = 'DIVE', req = 25, icon = '/modules/game_pokemonmanager/images/dive.png'},
      {id = 'waterfall', name = 'WATERFALL', req = 35, icon = '/modules/game_pokemonmanager/images/waterfall.png'}
    }
  }
}

PokemonManager.abilityStateStyle = {
  locked   = {accent = '#3a5170', border = '#1c3350', bg = '#0c1828', name = '#9bb6dc', status = '#7f94b1', iconOpacity = 0.45},
  next     = {accent = '#f2c400', border = '#6b5a1a', bg = '#142038', name = '#ffffff', status = '#f2c400', iconOpacity = 0.85},
  unlocked = {accent = '#72e6a0', border = '#2c5a4a', bg = '#0f2230', name = '#ffffff', status = '#72e6a0', iconOpacity = 1.0}
}

-- Interpola entre duas cores '#rrggbb' (t de 0 a 1). Sempre retorna '#rrggbb'.
function PokemonManager.lerpColor(c1, c2, t)
  t = math.max(0, math.min(1, tonumber(t) or 0))
  local function ch(c, i) return tonumber(c:sub(i, i + 1), 16) or 0 end
  local r = math.floor(ch(c1, 2) + (ch(c2, 2) - ch(c1, 2)) * t + 0.5)
  local g = math.floor(ch(c1, 4) + (ch(c2, 4) - ch(c1, 4)) * t + 0.5)
  local b = math.floor(ch(c1, 6) + (ch(c2, 6) - ch(c1, 6)) * t + 0.5)
  return string.format('#%02x%02x%02x', r, g, b)
end

function PokemonManager.updateAbilitiesUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local win = PokemonManager.window

  local p = PokemonManager.pokemon[PokemonManager.selected]
  PokemonManager.updateAbilitiesPartyBar()

  local respect = math.max(0, tonumber(PokemonManager.respect) or 0)

  local pokemonName = win:recursiveGetChildById('abilitiesPokemonName')
  if pokemonName then pokemonName:setText(p and string.upper(tostring(p.name or 'POKEMON')) or 'NENHUM POKEMON') end

  -- Levantamento geral: total, liberadas, maior req e proxima a liberar.
  local total, unlocked, maxReq = 0, 0, 1
  local nextItem = nil
  local thresholds, seen = {}, {}
  for _, group in ipairs(PokemonManager.abilityGroups) do
    for _, item in ipairs(group.items) do
      total = total + 1
      if item.req > maxReq then maxReq = item.req end
      if respect >= item.req then
        unlocked = unlocked + 1
      elseif not nextItem or item.req < nextItem.req then
        nextItem = item
      end
      if not seen[item.req] then
        seen[item.req] = true
        table.insert(thresholds, item.req)
      end
    end
  end
  table.sort(thresholds)

  -- Card de Respeito.
  local respectLabel = win:recursiveGetChildById('abilitiesRespect')
  if respectLabel then respectLabel:setText(tostring(respect)) end

  local unlockedLabel = win:recursiveGetChildById('abilitiesUnlocked')
  if unlockedLabel then
    unlockedLabel:setText(tostring(unlocked) .. ' / ' .. tostring(total) .. ' LIBERADAS')
    unlockedLabel:setColor(unlocked >= total and '#72e6a0' or '#dce8f5')
  end

  local nextLabel = win:recursiveGetChildById('abilitiesNextUnlock')
  if nextLabel then
    if nextItem then
      nextLabel:setText('PROXIMA: ' .. nextItem.name .. ' - ' .. tostring(nextItem.req) .. ' RESPEITO (FALTAM ' .. tostring(nextItem.req - respect) .. ')')
      nextLabel:setColor('#f2c400')
    else
      nextLabel:setText('TODAS AS HABILIDADES LIBERADAS')
      nextLabel:setColor('#72e6a0')
    end
  end

  local overallPct = math.min(1, respect / maxReq)
  local overallColor = nextItem and PokemonManager.lerpColor('#3a6ea5', '#f2c400', overallPct) or '#72e6a0'
  local accent = win:recursiveGetChildById('abilitiesRespectAccent')
  if accent then accent:setBackgroundColor(overallColor) end

  local track = win:recursiveGetChildById('abilitiesRespectTrack')
  local trackW = 732
  if track then
    local w = track:getWidth()
    if w and w > 0 then trackW = w end
  end
  local fill = win:recursiveGetChildById('abilitiesRespectFill')
  if fill then
    fill:setWidth(math.floor(trackW * overallPct))
    fill:setBackgroundColor(overallColor)
  end
  for i = 1, 7 do
    local tick = win:recursiveGetChildById('abilitiesTick' .. i)
    if tick then
      local req = thresholds[i]
      if req and req < maxReq then
        tick:setVisible(true)
        tick:setMarginLeft(math.max(0, math.floor(trackW * req / maxReq) - 1))
        tick:setBackgroundColor(respect >= req and '#0c1828' or '#f2c400')
        tick:setOpacity(respect >= req and 1.0 or 0.55)
      else
        tick:setVisible(false)
      end
    end
  end

  -- Passiva do Pokemon selecionado.
  local passiveRow = win:recursiveGetChildById('abilityPassive')
  if passiveRow then
    local passive = p and (PokemonManager.abilities[p.index] or PokemonManager.abilities[PokemonManager.selected]) or nil
    local hasPassive = passive ~= nil and passive ~= ''
    local pn = passiveRow:recursiveGetChildById('passiveName')
    local ps = passiveRow:recursiveGetChildById('passiveStatus')
    local pa = passiveRow:recursiveGetChildById('passiveAccent')
    local pd = passiveRow:recursiveGetChildById('passiveDesc')
    if pd then
      local desc = p and (PokemonManager.abilityDesc[p.index] or PokemonManager.abilityDesc[PokemonManager.selected]) or nil
      if not p then
        pd:setText('')
      elseif hasPassive then
        pd:setText(desc and desc ~= '' and desc or 'Habilidade passiva sempre ativa em batalha.')
      else
        pd:setText('Este pokemon nao possui hidden ability.')
      end
    end
    if pn then
      if not p then
        pn:setText('SELECIONE UM POKEMON')
      else
        pn:setText(hasPassive and string.upper(passive) or 'NENHUMA HABILIDADE ESPECIAL')
      end
      pn:setColor(hasPassive and '#ffffff' or '#9bb6dc')
    end
    if ps then
      ps:setText(hasPassive and 'ATIVA' or 'NAO REGISTRADA')
      ps:setColor(hasPassive and '#72e6a0' or '#7f94b1')
    end
    if pa then pa:setBackgroundColor(hasPassive and '#72e6a0' or '#3a5170') end
    passiveRow:setBorderColor(hasPassive and '#2c5a4a' or '#1c3350')
  end

  -- Secoes e cards.
  for _, group in ipairs(PokemonManager.abilityGroups) do
    local groupUnlocked = 0
    local row = win:recursiveGetChildById(group.row)
    for _, item in ipairs(group.items) do
      local ok = respect >= item.req
      if ok then groupUnlocked = groupUnlocked + 1 end
      local card = row and row:recursiveGetChildById(item.id)
      if card then
        local state = ok and 'unlocked' or ((nextItem and item.req == nextItem.req) and 'next' or 'locked')
        local style = PokemonManager.abilityStateStyle[state]
        local pct = math.min(1, respect / math.max(1, item.req))

        card:setBackgroundColor(style.bg)
        card:setBorderColor(style.border)

        local cardAccent = card:recursiveGetChildById('cardAccent')
        if cardAccent then cardAccent:setBackgroundColor(style.accent) end

        local iconBg = card:recursiveGetChildById('cardIconBg')
        if iconBg then iconBg:setBorderColor(state == 'locked' and '#1c3350' or style.border) end

        local icon = card:recursiveGetChildById('cardIcon')
        if icon then
          pcall(function()
            icon:setImageSource(item.icon)
            icon:setImageSize({width = 42, height = 42})
          end)
          icon:setOpacity(style.iconOpacity)
        end

        local nameLabel = card:recursiveGetChildById('cardName')
        if nameLabel then
          nameLabel:setText(item.name)
          nameLabel:setColor(style.name)
        end

        -- Textos curtos: o card mais estreito (184px) tem ~105px de texto.
        local reqLabel = card:recursiveGetChildById('cardReq')
        if reqLabel then
          if ok then
            reqLabel:setText('REQ ' .. tostring(item.req) .. ' RESPEITO')
          else
            reqLabel:setText(tostring(respect) .. '/' .. tostring(item.req) .. ' RESPEITO')
          end
        end

        local st = card:recursiveGetChildById('cardStatus')
        if st then
          if state == 'unlocked' then
            st:setText('LIBERADO')
          elseif state == 'next' then
            st:setText('PROXIMA')
          else
            st:setText('BLOQUEADO')
          end
          st:setColor(style.status)
        end

        local cardTrack = card:recursiveGetChildById('cardTrack')
        local cardFill = card:recursiveGetChildById('cardFill')
        if cardTrack and cardFill then
          local tw = cardTrack:getWidth()
          if not tw or tw <= 0 then tw = card:getWidth() - 78 end
          cardFill:setWidth(math.max(0, math.floor(tw * pct)))
          cardFill:setBackgroundColor(ok and '#72e6a0' or PokemonManager.lerpColor('#3a6ea5', '#f2c400', pct))
        end
      end
    end

    local section = win:recursiveGetChildById(group.section)
    if section then
      local lbl = section:recursiveGetChildById('sectionLabel')
      if lbl then lbl:setText(group.label) end
      local cnt = section:recursiveGetChildById('sectionCount')
      if cnt then
        cnt:setText(tostring(groupUnlocked) .. ' / ' .. tostring(#group.items) .. ' LIBERADAS')
        cnt:setColor(groupUnlocked >= #group.items and '#72e6a0' or '#7f94b1')
      end
    end
  end
end

function PokemonManager.updateAbilitiesPartyBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('abilitiesPartyCard' .. i)
    if card then card:setVisible(false) end
  end

  local indexes = {}
  for index, _ in pairs(PokemonManager.pokemon) do table.insert(indexes, index) end
  table.sort(indexes)

  for position, index in ipairs(indexes) do
    if position > 6 then break end
    local p = PokemonManager.pokemon[index]
    local card = PokemonManager.window:recursiveGetChildById('abilitiesPartyCard' .. position)
    if card and p then
      card:setVisible(true)
      card.onClick = function()
        PokemonManager.selectPokemon(p.index)
        PokemonManager.updateAbilitiesPartyBar()
      end
      local icon = card:recursiveGetChildById('icon')
      local level = card:recursiveGetChildById('level')
      local slot = card:recursiveGetChildById('slot')
      if icon then
        local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png'
        pcall(function()
          icon:setImageSource(path)
          icon:setImageSize({width = 54, height = 54})
        end)
      end
      if slot then slot:setText('#' .. tostring(position)) end
      local isSelected = index == PokemonManager.selected
      if level then
        level:setText('Lv.' .. tostring(p.level or 0))
        level:setColor(isSelected and '#ffd24a' or '#9bb6dc')
      end
      card:setBorderColor(isSelected and '#ffd24a' or '#294765')
      card:setBackgroundColor(isSelected and '#263b59' or '#102138')
    end
  end
end

function PokemonManager.requestHeldItems()
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  PokemonManager.heldItems = {}
  PokemonManager.heldListDone = true -- codex held lista: a proxima lista comeca do zero
  proto:sendExtendedOpcode(PokemonManager.opcode, 'HELD_LIST')
end

-- codex: usar EV Add (26737) no pokemon selecionado (count 0 = todos)
function PokemonManager.sendEvAdd(count)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode,
    'EVADD_USE|' .. tostring(PokemonManager.selected) .. '|' .. tostring(count or 1))
end

function PokemonManager.sendHeldEquip(itemId)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode,
    'HELD_EQUIP|' .. tostring(PokemonManager.selected) .. '|' .. tostring(itemId))
end

function PokemonManager.sendHeldRemove(slotAttr)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode,
    'HELD_REMOVE|' .. tostring(PokemonManager.selected) .. '|' .. tostring(slotAttr or 'held'))
end

function PokemonManager.sendMoveLearn(moveName)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode,
    'MOVE_LEARN|' .. tostring(PokemonManager.selected) .. '|' .. tostring(moveName or ''))
end

function PokemonManager.sendMoveForget(moveName)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode,
    'MOVE_FORGET|' .. tostring(PokemonManager.selected) .. '|' .. tostring(moveName or ''))
end

function PokemonManager.updateHeldPartyBar()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('heldPartyCard' .. i)
    if card then card:setVisible(false) end
  end

  local indexes = {}
  for index, _ in pairs(PokemonManager.pokemon) do table.insert(indexes, index) end
  table.sort(indexes)

  for position, index in ipairs(indexes) do
    if position > 6 then break end
    local p = PokemonManager.pokemon[index]
    local card = PokemonManager.window:recursiveGetChildById('heldPartyCard' .. position)
    if card and p then
      card:setVisible(true)
      card.onClick = function()
        PokemonManager.selectPokemon(p.index)
        PokemonManager.updateHeldUI()
      end
      local icon = card:recursiveGetChildById('icon')
      local level = card:recursiveGetChildById('level')
      local slot = card:recursiveGetChildById('slot')
      local isSelected = index == PokemonManager.selected
      if icon then
        local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png'
        pcall(function()
          icon:setImageSource(path)
          icon:setImageSize({width = 54, height = 54})
        end)
      end
      if slot then slot:setText('#' .. tostring(position)) end
      if level then
        level:setText('Lv.' .. tostring(p.level or 0))
        level:setColor(isSelected and '#ffd24a' or '#9bb6dc')
      end
      card:setBorderColor(isSelected and '#ffd24a' or '#294765')
      card:setBackgroundColor(isSelected and '#263b59' or '#102138')
    end
  end
end

-- Cores por slot: held comum = verde, mega / outros = roxo.
PokemonManager.heldSlotColors = {held = '#72e6a0', equip = '#b98cff', heldY = '#6ec6ff', held3 = '#f2c400'}

function PokemonManager.updateHeldUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.updateHeldPartyBar()
  local win = PokemonManager.window

  local p = PokemonManager.pokemon[PokemonManager.selected]
  local pokemonName = win:recursiveGetChildById('heldPokemonName')
  if pokemonName then
    pokemonName:setText(p and string.upper(tostring(p.name or 'POKEMON')) or 'NENHUM POKEMON')
  end

  -- Held comum e Mega Stone / outros equipaveis ocupam slots
  -- INDEPENDENTES (o Pokemon pode usar os dois ao mesmo tempo), entao
  -- cada um tem sua propria caixa "equipado" e sua propria checagem.
  local held = p and tostring(p.held or '') or ''
  local hasHeld = held ~= '' and held ~= '-' and held ~= '0'
  local equip = p and tostring(p.equip or '') or ''
  local hasEquip = equip ~= '' and equip ~= '-' and equip ~= '0'

  local function updateSlotBox(prefix, hasItem, itemName, clientId, slotAttr)
    local color = PokemonManager.heldSlotColors[slotAttr]
    local box = win:recursiveGetChildById(prefix .. 'EquippedBox')
    local accent = win:recursiveGetChildById(prefix .. 'Accent')
    local current = win:recursiveGetChildById(prefix .. 'Current')
    local status = win:recursiveGetChildById(prefix .. 'Status')
    local remove = win:recursiveGetChildById(prefix .. 'Remove')
    local currentSlot = win:recursiveGetChildById(prefix .. 'CurrentSlot')
    local slotBg = win:recursiveGetChildById(prefix .. 'CurrentSlotBackground')

    if box then box:setBorderColor(hasItem and color or '#1c3350') end
    if accent then accent:setBackgroundColor(hasItem and color or '#3a5170') end
    if slotBg then slotBg:setBorderColor(hasItem and color or '#1c3350') end
    if current then
      current:setText(hasItem and string.upper(itemName) or (p and 'NENHUM ITEM EQUIPADO' or 'NENHUM POKEMON'))
      current:setColor(hasItem and '#ffffff' or '#7f94b1')
    end
    if status then
      if hasItem then
        status:setText('EQUIPADO')
        status:setColor(color)
      else
        status:setText('SLOT LIVRE')
        status:setColor('#7f94b1')
      end
    end
    if currentSlot then
      -- O sprite exige o ID DE CLIENTE, que o servidor manda via
      -- ItemType:getClientId() -- o id do items.xml e so o id de
      -- servidor e nao serve pra desenhar o sprite aqui.
      local cid = hasItem and (tonumber(clientId) or 0) or 0
      currentSlot:setItemId(cid)
      currentSlot:setVisible(cid > 0)
    end
    if remove then
      remove:setEnabled(hasItem)
      remove.onClick = function()
        if hasItem then PokemonManager.sendHeldRemove(slotAttr) end
      end
    end
  end

  updateSlotBox('held', hasHeld, held, p and p.heldClientId, 'held')
  updateSlotBox('equip', hasEquip, equip, p and p.equipClientId, 'equip')

  -- codex: held Y e 3o slot (Attachment Device)
  local heldY = p and tostring(p.heldY or '') or ''
  local hasHeldY = heldY ~= '' and heldY ~= '-' and heldY ~= '0'
  local held3 = p and tostring(p.held3 or '') or ''
  local hasHeld3 = held3 ~= '' and held3 ~= '-' and held3 ~= '0'
  local hasDevice = p and p.hasDevice or false
  updateSlotBox('heldY', hasHeldY, heldY, p and p.heldYClientId, 'heldY')
  updateSlotBox('held3', hasHeld3, held3, p and p.held3ClientId, 'held3')
  do
    local status3 = win:recursiveGetChildById('held3Status')
    local remove3 = win:recursiveGetChildById('held3Remove')
    local current3 = win:recursiveGetChildById('held3Current')
    if p and not hasDevice then
      if current3 then current3:setText('SEM ATTACHMENT DEVICE') end
      if status3 then status3:setText('EQUIPE UM DEVICE PARA LIBERAR'); status3:setColor('#7f94b1') end
    elseif p and hasDevice and not hasHeld3 and remove3 then
      if status3 then status3:setText('DEVICE ATIVO - SLOT LIVRE'); status3:setColor('#f2c400') end
      remove3:setEnabled(true)
      remove3:setText('TIRAR DEVICE')
      remove3.onClick = function() PokemonManager.sendHeldRemove('device') end
    end
    if remove3 and (hasHeld3 or not hasDevice) then remove3:setText('REMOVER') end
  end

  local heldList = win:recursiveGetChildById('heldItemsList')
  local equipList = win:recursiveGetChildById('equipItemsList')
  if not heldList or not equipList then return end
  heldList:destroyChildren()
  equipList:destroyChildren()

  local heldRows, equipRows = 0, 0
  local heldUnits, equipUnits = 0, 0
  local ptype = p and string.lower(tostring(p.baseName or p.name or '')) or ''

  for _, item in ipairs(PokemonManager.heldItems) do
    local isMega = item.kind == 'mega'
    local isDevice = item.kind == 'device'
    local list = isMega and equipList or heldList
    -- Obs: nao usar "isMega and hasEquip or hasHeld" -- quando hasEquip e
    -- false o idioma and/or do Lua cai no hasHeld e bloqueia a Mega Stone
    -- sempre que houver um Held equipado.
    -- codex: Held e Mega Stone tem espacos separados na ball
    local hasItemOfKind
    local slotAttr = isMega and 'equip' or 'held'
    if isMega then
      hasItemOfKind = hasEquip
    elseif isDevice then
      hasItemOfKind = hasDevice
      slotAttr = 'held3'
    else
      -- X no slot X, Y no slot Y; ocupado -> 3o slot se tiver device
      local isY = item.cat == 'Y'
      local mainFull = isY and hasHeldY or (not isY and hasHeld)
      hasItemOfKind = mainFull and not (hasDevice and not hasHeld3)
      slotAttr = isY and 'heldY' or 'held'
      if mainFull and hasDevice and not hasHeld3 then slotAttr = 'held3' end
    end
    local color = PokemonManager.heldSlotColors[slotAttr]

    local compatible = true
    if isMega and item.pokemon and ptype ~= '' then
      compatible = string.lower(tostring(item.pokemon)) == ptype
    elseif isMega and ptype == '' then
      compatible = false
    end

    -- Mega Stone de outra especie: nem mostra na coluna, pra nao
    -- confundir com os itens que o Pokemon selecionado pode de fato
    -- usar. So os Helds normais (que servem pra qualquer Pokemon) e
    -- as Mega Stones compativeis aparecem na lista.
    if not (isMega and not compatible) then
      local canEquip = p ~= nil and compatible and not hasItemOfKind
      local row = g_ui.createWidget('PMHeldRow', list)
      local title = row:recursiveGetChildById('itemName')
      local count = row:recursiveGetChildById('itemCount')
      local typeLabel = row:recursiveGetChildById('itemType')
      local button = row:recursiveGetChildById('equipButton')
      local slot = row:recursiveGetChildById('itemSlot')
      local slotBg = row:recursiveGetChildById('itemSlotBackground')
      local accent = row:recursiveGetChildById('accent')
      local itemCount = tonumber(item.count) or 0

      if title then
        title:setText(string.upper(item.name or 'HELD'))
        title:setColor(canEquip and '#ffffff' or '#9bb6dc')
      end
      if count then count:setText('x' .. tostring(itemCount)) end
      if typeLabel then
        local kind = isMega and 'MEGA STONE' or (isDevice and 'ATTACHMENT DEVICE') or ('HELD ' .. ((item.cat == 'Y') and 'Y' or 'X'))
        if not p then
          typeLabel:setText(kind)
          typeLabel:setColor('#5f7596')
        elseif hasItemOfKind then
          typeLabel:setText(kind .. ' - SLOT OCUPADO')
          typeLabel:setColor('#ff9a7a')
        else
          typeLabel:setText(kind .. ' - DISPONIVEL')
          typeLabel:setColor(color)
        end
      end
      if slot then
        local clientId = tonumber(item.clientId) or 0
        slot:setItemId(clientId)
        slot:setVisible(clientId > 0)
      end
      if slotBg then slotBg:setBorderColor(canEquip and color or '#1c3350') end
      if accent then accent:setBackgroundColor(canEquip and color or '#3a5170') end
      row:setBorderColor(canEquip and '#294765' or '#1c3350')

      if button then
        button:setEnabled(canEquip)
        button:setText('EQUIPAR')
        button.onClick = function()
          if p and compatible and not hasItemOfKind then PokemonManager.sendHeldEquip(tonumber(item.id) or 0, slotAttr) end
        end
      end

      if isMega then
        equipRows = equipRows + 1
        equipUnits = equipUnits + itemCount
      else
        heldRows = heldRows + 1
        heldUnits = heldUnits + itemCount
      end
    end
  end

  local heldTitle = win:recursiveGetChildById('heldListTitle')
  if heldTitle then heldTitle:setText('HELDS NA MOCHILA (' .. tostring(heldRows) .. ' TIPOS - ' .. tostring(heldUnits) .. ' UN.)') end
  local equipTitle = win:recursiveGetChildById('equipListTitle')
  if equipTitle then equipTitle:setText('MEGA / OUTROS COMPATIVEIS (' .. tostring(equipRows) .. ')') end

  if heldRows == 0 then
    local empty = g_ui.createWidget('PMHeldEmpty', heldList)
    empty:setText('NENHUM HELD DISPONIVEL NA MOCHILA')
  end
  if equipRows == 0 then
    local empty = g_ui.createWidget('PMHeldEmpty', equipList)
    empty:setText(p and ('NENHUM ITEM COMPATIVEL COM ' .. string.upper(tostring(p.name or ''))) or 'NENHUM ITEM DISPONIVEL NA MOCHILA')
  end
end

function PokemonManager.updateUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  local count=0
  for _,_ in pairs(PokemonManager.pokemon) do count=count+1 end
  local countLabel=PokemonManager.window:recursiveGetChildById('pokemonCount'); if countLabel then countLabel:setText(tostring(count)..' POKEMON') end
  PokemonManager.updatePlayerName()
  PokemonManager.updateTeamCards()
  PokemonManager.updatePartyBar()
  PokemonManager.updateDashboard()
  PokemonManager.updateSelectedUI()
  if PokemonManager.currentPage == 'base' or PokemonManager.currentPage == 'ev' then
    PokemonManager.updateBaseUI()
  elseif PokemonManager.currentPage == 'vitamins' then
    PokemonManager.updateVitaminsUI()
  elseif PokemonManager.currentPage == 'moves' then
    PokemonManager.updateMovesUI()
  elseif PokemonManager.currentPage == 'abilities' then
    PokemonManager.updateAbilitiesUI()
  elseif PokemonManager.currentPage == 'evolution' then
    PokemonManager.updateEvolutionUI()
  end
end


-- ================================================================
-- EVOLUCAO
-- ================================================================
PokemonManager.evo = nil
PokemonManager.evoCards = {}

-- so chamada por clique (menu, card do Pokemon)
function PokemonManager.requestEvolution()
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame(); if not proto then return end
  if not PokemonManager.pokemon[PokemonManager.selected] then return end
  proto:sendExtendedOpcode(PokemonManager.opcode, 'EVO_REQUEST|' .. tostring(PokemonManager.selected))
end

function PokemonManager.sendEvolve(index, mode)
  local proto = g_game.getProtocolGame(); if not proto then return end
  proto:sendExtendedOpcode(PokemonManager.opcode, 'EVO_DO|' .. tostring(PokemonManager.selected) .. '|' .. index .. '|' .. mode)
end

function PokemonManager.updateEvolutionCards()
  local win = PokemonManager.window
  local team = win and win:recursiveGetChildById('evoTeam')
  if not team then return end
  if #PokemonManager.evoCards == 0 then
    for i = 1, 6 do
      local card = g_ui.createWidget('PMEvoTeamCard', team)
      card:setId('evoTeam' .. i)
      card:setPhantom(false)
      card.onClick = function()
        PokemonManager.selectPokemon(i)
        return true
      end
      PokemonManager.evoCards[i] = card
    end
  end
  for i = 1, 6 do
    local card = PokemonManager.evoCards[i]
    local p = PokemonManager.pokemon[i]
    if card and not card:isDestroyed() then
      card:setVisible(p ~= nil)
      if p then
        local sel = i == PokemonManager.selected
        pcall(function()
          card:getChildById('icon'):setImageSource('/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png')
        end)
        card:getChildById('level'):setText('Lv.' .. tostring(p.level or 0))
        card:getChildById('level'):setColor(sel and '#ffd24a' or '#9bb6dc')
        card:setBackgroundColor(sel and '#263b59' or '#102138')
        card:setBorderColor(sel and '#ffd24a' or '#294765')
      end
    end
  end
end

function PokemonManager.updateEvolutionUI()
  local win = PokemonManager.window
  if not win or win:isDestroyed() then return end
  local function get(id) return win:recursiveGetChildById(id) end
  PokemonManager.updateEvolutionCards()
  local p = PokemonManager.pokemon[PokemonManager.selected]
  local e = PokemonManager.evo
  if e and e.slot ~= PokemonManager.selected then e = nil end
  local list = get('evoList')
  if not list then return end
  list:destroyChildren()
  get('evoPokemonName'):setText(p and (string.upper(p.name or '') .. '  LV ' .. tostring(p.level or 0)) or 'NENHUM POKEMON')
  get('evoTokens'):setText('TOKENS: ' .. tostring(e and e.tokens or 0))
  local hint = get('evoHint')
  hint:setText('')
  if not p then return end
  if not e then
    local w = g_ui.createWidget('PMEvoEmpty', list)
    w:setText('Carregando...')
    return
  end
  if e.busy then hint:setText('Guarde este Pokemon na pokebola para evoluir.') end
  local count = 0
  for index, o in ipairs(e.list) do
    count = count + 1
    local row = g_ui.createWidget('PMEvoRow', list)
    row:setId('evoRow' .. index)
    pcall(function()
      row:getChildById('icon'):setImageSource('/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(o.target) .. '.png')
    end)
    row:getChildById('name'):setText(string.upper(p.name or '') .. '  >  ' .. string.upper(o.target))
    -- caminho 1: level (ou amizade)
    local levelText, levelButton = row:getChildById('levelText'), row:getChildById('levelButton')
    local track, fill = row:recursiveGetChildById('levelTrack'), row:recursiveGetChildById('levelFill')
    local cur, need, label = tonumber(p.level) or 0, o.needLevel, 'LEVEL'
    if need <= 0 and o.needLove > 0 then cur, need, label = tonumber(p.love) or 0, o.needLove, 'AMIZADE' end
    if need > 0 then
      levelText:setText(label .. ' ' .. need .. '  (atual ' .. cur .. ')')
      levelText:setColor(o.canLevel and '#72e6a0' or '#9bb6dc')
      local pct = math.max(0, math.min(1, cur / math.max(1, need)))
      local tw = track:getWidth(); if not tw or tw <= 0 then tw = 120 end
      fill:setWidth(math.floor(tw * pct))
      fill:setBackgroundColor(o.canLevel and '#5fd35f' or '#3a6ea5')
    else
      levelText:setText(o.byItemOnly and 'Evolui so com item' or 'Sem evolucao por level')
      levelText:setColor('#6f86a8')
      track:setVisible(false)
    end
    levelButton:setVisible(need > 0)
    levelButton:setEnabled(o.canLevel and not e.busy)
    levelButton.onClick = function() PokemonManager.sendEvolve(index, 'level') return true end
    -- caminho 2: pedras + tokens
    local stoneItem, stoneText, stoneButton = row:getChildById('stoneItem'), row:getChildById('stoneText'), row:getChildById('stoneButton')
    if o.stoneId > 0 then
      if o.stoneClientId > 0 then stoneItem:setItemId(o.stoneClientId) end
      local okStone = o.stoneHave >= o.stoneNeed
      local okTokens = e.tokens >= o.tokens
      stoneText:setText(o.stoneNeed .. 'x ' .. o.stoneName .. ' (' .. o.stoneHave .. ')' .. ((o.tokens or 0) > 0 and ('  +  ' .. o.tokens .. ' tokens (' .. e.tokens .. ')') or ''))
      stoneText:setColor((okStone and okTokens) and '#dce8f5' or '#ff9a7a')
      stoneButton:setEnabled(okStone and okTokens and not e.busy)
      local armed = false
      stoneButton.onClick = function()
        -- confirma com 2 cliques (gasta pedras e tokens)
        if not armed then
          armed = true
          stoneButton:setText('CONFIRMAR')
          return true
        end
        PokemonManager.sendEvolve(index, 'stone')
        return true
      end
    else
      stoneItem:setVisible(false)
      stoneText:setText('Sem pedra para esta evolucao')
      stoneText:setColor('#6f86a8')
      stoneButton:setVisible(false)
    end
  end
  if count == 0 then
    local w = g_ui.createWidget('PMEvoEmpty', list)
    w:setText('Este Pokemon nao evolui.')
  end
end

function PokemonManager.split(str,separator)
  local result={}; local start=1; local pos=string.find(str,separator,start,true)
  while pos do table.insert(result,string.sub(str,start,pos-1)); start=pos+#separator; pos=string.find(str,separator,start,true) end
  table.insert(result,string.sub(str,start)); return result
end


function PokemonManager.bindFriendCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.friendCards = {}
  for i = 1, 6 do
    local card = PokemonManager.window:recursiveGetChildById('friendTeam' .. i)
    PokemonManager.friendCards[i] = card
    if card then
      card:setPhantom(false)
      card:setFocusable(false)
      local icon = card:recursiveGetChildById('icon')
      local level = card:recursiveGetChildById('level')
      if icon then
        icon:setPhantom(true)
        icon:setFocusable(false)
      end
      if level then
        level:setPhantom(true)
        level:setFocusable(false)
      end
      card.onClick = function()
        PokemonManager.selectPokemon(i)
        PokemonManager.updateFriendCards()
      end
    end
  end
end

-- Cor da faixa de amizade (0-9) ou dourado no maximo.
function PokemonManager.getFriendshipColor(friendship)
  friendship = math.max(0, math.min(1000, tonumber(friendship) or 0))
  if friendship >= 1000 then return PokemonManager.friendshipMaxColor end
  return PokemonManager.friendshipStageColors[math.min(9, math.floor(friendship / 100))] or '#8fd3ff'
end

function PokemonManager.updateFriendCards()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  if not PokemonManager.friendCards or #PokemonManager.friendCards < 6 then
    PokemonManager.bindFriendCards()
  end

  for i = 1, 6 do
    local card = PokemonManager.friendCards[i]
    local p = PokemonManager.pokemon[i]
    if card then
      if p then
        card:setVisible(true)
        local icon = card:recursiveGetChildById('icon')
        local level = card:recursiveGetChildById('level')
        local slot = card:recursiveGetChildById('slot')
        local miniTrack = card:recursiveGetChildById('friendMiniTrack')
        local miniFill = card:recursiveGetChildById('friendMiniFill')
        local friendship = math.max(0, math.min(1000, tonumber(p.friendship) or 0))
        local isSelected = p.index == PokemonManager.selected
        if icon then
          local path = '/modules/game_pokemonbar/bar_icon/' .. PokemonManager.sanitizeIconName(p.name) .. '.png'
          pcall(function()
            icon:setImageSource(path)
            icon:setImageSize({width = 50, height = 50})
          end)
        end
        if slot then slot:setText('#' .. tostring(i)) end
        if level then
          level:setText('Lv.' .. tostring(p.level or 0) .. '  ' .. tostring(friendship))
          level:setColor(isSelected and '#ffd24a' or '#9bb6dc')
        end
        if miniFill then
          local tw = miniTrack and miniTrack:getWidth() or 0
          if not tw or tw <= 0 then tw = 92 end
          miniFill:setWidth(math.floor(tw * friendship / 1000))
          miniFill:setBackgroundColor(PokemonManager.getFriendshipColor(friendship))
        end
        card:setBackgroundColor('#00000000')
        card:setImageSource('/modules/game_pokemonmanager/v2/' .. (isSelected and 'kx_slot_on' or 'kx_slot'))
      else
        card:setVisible(false)
      end
    end
  end
end

function PokemonManager.updateFriendUI()
  if not PokemonManager.window or PokemonManager.window:isDestroyed() then return end
  PokemonManager.updateFriendCards()
  local win = PokemonManager.window
  local function get(id) return win:recursiveGetChildById(id) end
  local function setText(id, text, color)
    local w = get(id)
    if w then
      w:setText(text)
      if color then w:setColor(color) end
    end
  end

  local p = PokemonManager.pokemon[PokemonManager.selected]
  local friendship = p and math.max(0, math.min(1000, tonumber(p.friendship) or 0)) or 0
  local killCount = p and math.max(0, tonumber(p.friendshipKills) or 0) or 0
  -- Regra do sistema: a cada 2 Pokemon derrotados, ganha amizade.
  -- O valor ganho muda conforme a faixa; a quantidade de kills permanece 2.
  local needed = 2
  local isMax = friendship >= 1000
  local stageIndex = math.min(9, math.floor(friendship / 100))
  local activeColor = PokemonManager.getFriendshipColor(friendship)
  local bonusPct = friendship * 0.03

  setText('friendPokemonName', p and string.upper(tostring(p.name or 'POKEMON')) or 'NENHUM POKEMON')

  -- Card principal.
  setText('friendValue', tostring(friendship) .. ' / 1000', p and '#ffffff' or '#7f94b1')
  setText('friendPercent', string.format('%d%%', math.floor(friendship / 10)), activeColor)
  local accent = get('friendCardAccent')
  if accent then accent:setBackgroundColor(p and activeColor or '#3a5170') end
  local badge = get('friendStageBadge')
  if badge then badge:setBorderColor(activeColor) end
  local stageAccent = get('friendStageAccent')
  if stageAccent then stageAccent:setBackgroundColor(activeColor) end
  if isMax then
    setText('friendStage', 'AMIZADE MAXIMA', activeColor)
  else
    setText('friendStage', 'FAIXA ' .. tostring(stageIndex + 1) .. ': ' .. tostring(stageIndex * 100) .. ' - ' .. tostring((stageIndex + 1) * 100), activeColor)
  end

  setText('friendBonus', string.format('+%.2f%%', bonusPct), bonusPct > 0 and '#72e6a0' or '#7f94b1')
  if not p then
    setText('friendBonusNext', '')
  elseif isMax then
    setText('friendBonusNext', 'BONUS MAXIMO ATINGIDO', '#f2c400')
  else
    local nextStart = (stageIndex + 1) * 100
    setText('friendBonusNext', string.format('AO CHEGAR EM %d: +%.2f%%', nextStart, nextStart * 0.03), '#f2c400')
  end

  -- Escada de 10 faixas: completas na cor da faixa, a atual parcial,
  -- as futuras apagadas.
  for i = 1, 10 do
    local tile = get('friendTier' .. i)
    if tile then
      local lo, hi = (i - 1) * 100, i * 100
      local tierColor = PokemonManager.friendshipStageColors[i - 1] or '#8fd3ff'
      local fill = tile:recursiveGetChildById('tierFill')
      local nameL = tile:recursiveGetChildById('tierName')
      local rangeL = tile:recursiveGetChildById('tierRange')
      local bonusL = tile:recursiveGetChildById('tierBonus')
      local ratio = math.max(0, math.min(1, (friendship - lo) / 100))
      local complete = p ~= nil and friendship >= hi
      local current = p ~= nil and not complete and friendship >= lo
      local tw = tile:getWidth()
      if not tw or tw <= 0 then tw = 70 end
      if fill then
        fill:setBackgroundColor(tierColor)
        fill:setWidth(p and math.floor(tw * ratio) or 0)
      end
      local textColor = complete and '#0c1828' or (current and '#ffffff' or '#5f7596')
      if nameL then nameL:setColor(textColor) end
      if rangeL then rangeL:setColor(complete and '#0c1828' or (current and '#dce8f5' or '#5f7596')) end
      if bonusL then bonusL:setColor(complete and '#0c1828' or (current and tierColor or '#5f7596')) end
      tile:setBorderColor((complete or current) and tierColor or '#1c3350')
    end
  end

  -- Kills.
  for k = 1, 2 do
    local pip = get('friendKillPip' .. k)
    if pip then
      local on = p ~= nil and not isMax and k <= killCount
      pip:setBackgroundColor(on and '#8fd3ff' or '#091522')
      pip:setBorderColor(on and '#8fd3ff' or '#1c3350')
    end
  end
  if isMax then
    setText('friendKills', 'KILLS: MAXIMO', '#f2c400')
  else
    setText('friendKills', tostring(math.min(killCount, needed)) .. ' / ' .. tostring(needed) .. ' KILLS', '#d7e1f0')
  end

  -- Proximo nivel.
  if not p then
    setText('friendNext', '-', '#7f94b1')
    setText('friendToStage', '')
  elseif isMax then
    setText('friendNext', 'AMIZADE MAXIMA', '#f2c400')
    setText('friendToStage', 'TODAS AS FAIXAS COMPLETAS', '#72e6a0')
  else
    local remaining = math.max(0, needed - killCount)
    setText('friendNext', 'PROXIMO PONTO: ' .. tostring(remaining) .. ' KILL(S)', '#ffffff')
    local nextStart = (stageIndex + 1) * 100
    local label = nextStart >= 1000 and 'O MAXIMO' or ('A FAIXA ' .. tostring(stageIndex + 2))
    setText('friendToStage', 'FALTAM ' .. tostring(nextStart - friendship) .. ' PARA ' .. label, '#7f94b1')
  end

  -- Destaque da equipe.
  local best, total, count = nil, 0, 0
  for _, member in pairs(PokemonManager.pokemon) do
    local f = math.max(0, math.min(1000, tonumber(member.friendship) or 0))
    total = total + f
    count = count + 1
    if not best or f > (math.max(0, math.min(1000, tonumber(best.friendship) or 0))) then best = member end
  end
  if best then
    local bf = math.max(0, math.min(1000, tonumber(best.friendship) or 0))
    setText('friendBestName', string.upper(tostring(best.name or 'POKEMON')) .. ' - ' .. tostring(bf), PokemonManager.getFriendshipColor(bf))
    setText('friendTeamAvg', 'MEDIA DA EQUIPE: ' .. tostring(math.floor(total / count)), '#7f94b1')
  else
    setText('friendBestName', '-', '#7f94b1')
    setText('friendTeamAvg', 'MEDIA DA EQUIPE: 0', '#7f94b1')
  end
end

function PokemonManager.onExtendedOpcode(protocol,opcode,buffer)
  if opcode~=PokemonManager.opcode then return end
  local parts=PokemonManager.split(buffer or '','|'); local command=parts[1] or ''
  if command=='PROFILE' then
    PokemonManager.profile = {
      id = tonumber(parts[2]) or 0,
      name = parts[3] or '',
      gold = tonumber(parts[4]) or 0,
      pokecoins = tonumber(parts[5]) or 0,
      donate = tonumber(parts[6]) or 0,
      tokens = tonumber(parts[7]) or 0,
      profession = parts[8] or 'Nenhuma',
      level = tonumber(parts[9]) or 1,
      experience = tonumber(parts[10]) or 0,
      levelPercent = tonumber(parts[11]) or 0,
      skills = {
        fishing = {level = tonumber(parts[12]) or 0, percent = tonumber(parts[13]) or 0}
      },
      -- Campos extras (servidor novo). Servidor antigo: ficam nos defaults.
      onlineSeconds = tonumber(parts[14]) or 0,
      sessionSeconds = tonumber(parts[15]) or 0,
      accountCreated = tonumber(parts[16]) or 0,
      town = parts[17] or '',
      stamina = tonumber(parts[18]),
      premiumDays = tonumber(parts[19]) or 0,
      guild = parts[20] or '',
      guildRank = parts[21] or '',
      house = parts[22] or '',
      deaths = tonumber(parts[23]) or 0,
      professionLevel = tonumber(parts[24]) or 0,
      professionPercent = tonumber(parts[25]) or 0,
      secondaryProfession = parts[26] or '',
      secondaryLevel = tonumber(parts[27]) or 0,
      receivedAt = os.time()
    }
    PokemonManager.updatePlayerId()
    PokemonManager.updatePlayerName()
    PokemonManager.updateEconomy()
    PokemonManager.updateProfileStats()
    return
  end

  if command=='INCUBATOR_CRECHE_LIST' then
    PokemonManager.pokeEggClientId = tonumber(parts[2]) or 0
    PokemonManager.crecheEggs = {}
    for i = 3, #parts do
      local f = PokemonManager.split(parts[i], ';')
      if f[1] and f[1] ~= '' then
        PokemonManager.crecheEggs[#PokemonManager.crecheEggs + 1] = {id = f[1], species = f[2] or '?',
          clientId = tonumber(f[3]) or 0, pct = tonumber(f[4]) or 0, gender = f[5] or 'N'}
      end
    end
    PokemonManager.updateIncubEggPicker()
    PokemonManager.updateStepEggUI() -- CODEX: agora sabe o sprite certo do ovo
    return
  end
  if command=='INCUBATOR_EGG_COUNT' then
    PokemonManager.pokeEggCount = tonumber(parts[2]) or 0
    local eggInfo = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubatorEggInfo')
    local chip24h = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip24hCount')
    local chip12h = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip12hCount')
    local chip8h = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip8hCount')
    local chip5min = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip5minCount')
    local eggCount = tonumber(parts[2]) or 0
    PokemonManager.incubatorCounts[39335] = tonumber(parts[3]) or 0
    PokemonManager.incubatorCounts[39336] = tonumber(parts[4]) or 0
    PokemonManager.incubatorCounts[39337] = tonumber(parts[5]) or 0
    PokemonManager.incubatorCounts[39338] = tonumber(parts[6]) or 0
    local clientId24 = tonumber(parts[7]) or 0
    local clientId12 = tonumber(parts[8]) or 0
    local clientId8 = tonumber(parts[9]) or 0
    local clientId5 = tonumber(parts[10]) or 0
    if clientId24 > 0 then PokemonManager.incubatorClientIds[39335] = clientId24 end
    if clientId12 > 0 then PokemonManager.incubatorClientIds[39336] = clientId12 end
    if clientId8 > 0 then PokemonManager.incubatorClientIds[39337] = clientId8 end
    if clientId5 > 0 then PokemonManager.incubatorClientIds[39338] = clientId5 end
    if clientId24 > 0 then
      local icon = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip24hIcon')
      if icon then icon:setItemId(clientId24) end
    end
    if clientId12 > 0 then
      local icon = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip12hIcon')
      if icon then icon:setItemId(clientId12) end
    end
    if clientId8 > 0 then
      local icon = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip8hIcon')
      if icon then icon:setItemId(clientId8) end
    end
    if clientId5 > 0 then
      local icon = PokemonManager.window and PokemonManager.window:recursiveGetChildById('incubChip5minIcon')
      if icon then icon:setItemId(clientId5) end
    end
    -- Os icones das "escolhas" de incubadora (dentro de cada slot) sao criados
    -- antes deste pacote chegar na primeira vez; se ja existirem na tela,
    -- corrige o sprite deles tambem agora que temos o clientId real.
    if PokemonManager.incubatorChoices then
      for slot, choices in pairs(PokemonManager.incubatorChoices) do
        for itemId, widgets in pairs(choices) do
          local spriteId = PokemonManager.incubatorClientIds[itemId]
          local item = widgets and widgets.item
          if spriteId and spriteId > 0 and item and not item:isDestroyed() then
            item:setItemId(spriteId)
            -- So mostra se a linha (row) tambem estiver visivel agora
            -- (ou seja, o slot esta mesmo no estado "escolha").
            local row = widgets.row
            if row and not row:isDestroyed() and row:isVisible() then
              item:setVisible(true)
            end
          end
        end
      end
    end
    if eggInfo then
      eggInfo:setText(tostring(eggCount))
      eggInfo:setColor(eggCount > 0 and '#ffffff' or '#7f94b1')
    end
    if chip24h then
      chip24h:setText('x' .. tostring(PokemonManager.incubatorCounts[39335]))
    end
    if chip12h then
      chip12h:setText('x' .. tostring(PokemonManager.incubatorCounts[39336]))
    end
    if chip8h then
      chip8h:setText('x' .. tostring(PokemonManager.incubatorCounts[39337]))
    end
    if chip5min then
      chip5min:setText('x' .. tostring(PokemonManager.incubatorCounts[39338]))
    end
    for slot = 1, 6 do
      if PokemonManager.incubatorChoices and PokemonManager.incubatorChoices[slot] then
        local data = PokemonManager.incubators[slot]
        local empty = data and data.unlocked and not (data.eggId and data.eggId > 0 and data.startedAt and data.startedAt > 0)
        if empty then
          PokemonManager.updateIncubatorChoiceItems(slot, true)
        end
      end
    end
    PokemonManager.updateIncubatorSummary()
    return
  end

  if command=='INCUBATOR_STATE' then
    local slot = tonumber(parts[2]) or 0
    if slot > 0 and slot <= 6 then
      PokemonManager.incubators[slot] = {
        unlocked = tonumber(parts[3]) == 1,
        cost = tonumber(parts[4]) or 0,
        eggId = tonumber(parts[5]) or 0,
        startedAt = tonumber(parts[6]) or 0,
        incubatorId = tonumber(parts[8]) or 0,
        duration = tonumber(parts[9]) or PokemonManager.incubatorDuration,
        crecheName = (parts[10] and parts[10] ~= '-' and parts[10] ~= '') and parts[10] or nil
      }
      PokemonManager.incubatorServerOffset = (tonumber(parts[7]) or os.time()) - os.time()
      PokemonManager.updateIncubatorSlot(slot)
      PokemonManager.updateIncubatorSummary()
    end
    return
  end

  if command=='INCUBATOR_ERROR' then
    modules.game_textmessage.displayFailureMessage(parts[2] or '[PokemonManager] Falha na incubadora.')
    return
  end

  if command=='INCUBATOR_OK' then
    -- o servidor ja reenvia o estado; nao mandar pacote a partir de pacote
    PokemonManager.updateEconomy()
    PokemonManager.updateIncubators()
    return
  end

  if command=='STEPEGG_STATE' then
    PokemonManager.stepEgg = {
      eggId = tonumber(parts[2]) or 0,
      steps = tonumber(parts[3]) or 0,
      limit = tonumber(parts[4]) or 10000
    }
    PokemonManager.updateStepEggUI()
    return
  end

  if command=='STEPEGG_ERROR' then
    modules.game_textmessage.displayFailureMessage(parts[2] or '[PokemonManager] Falha na incubacao por passos.')
    return
  end

  if command=='STEPEGG_OK' then
    PokemonManager.updateStepEggUI()
    return
  end

  if command=='RESPECT' then
    PokemonManager.respect = tonumber(parts[2]) or 0
    if PokemonManager.currentPage == 'profile' then PokemonManager.updateProfileStats() end
    if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
    if PokemonManager.currentPage == 'abilities' then
      PokemonManager.updateAbilitiesUI()
    end
    return
  end
  if command=='CLEAR' then
    -- lista reenviada pelo servidor (vitamina, held, mega...): mantem o
    -- Pokemon selecionado. So volta pro primeiro quando o Manager abre.
    if not PokemonManager.keepSelected and next(PokemonManager.pokemon) ~= nil then
      PokemonManager.keepSelected = PokemonManager.selected
    end
    PokemonManager.pokemon={}
    if not PokemonManager.keepSelected then PokemonManager.selected=1 end
    PokemonManager.resetEVPending(); PokemonManager.resetTeamCards(); PokemonManager.updateUI(); return
  end
  if command == 'ABILITY' then
    local slot = tonumber(parts[2]) or 0
    local abilityName = parts[3] or ''
    if slot > 0 and abilityName ~= '' then
      PokemonManager.abilities[slot] = abilityName
      PokemonManager.abilityDesc[slot] = parts[4] or ''
      if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
      if PokemonManager.currentPage == 'abilities' and slot == PokemonManager.selected then
        PokemonManager.updateAbilitiesUI()
      end
    end
    return
  end

  if command == 'MOVE' then
    local slot = tonumber(parts[2]) or 0
    local moveIndex = tonumber(parts[3]) or 0
    local moveName = parts[4] or ''
    local moveLevel = tonumber(parts[5]) or 1
    local moveCost = tonumber(parts[6]) or 1
    local moveUnlocked = parts[7] == '1'
    local movePower = tonumber(parts[8]) or 0
    local moveKind = parts[9] or '' -- codex tm combo: 'TM' / 'SK' (Sketch)
    if slot > 0 and moveIndex > 0 and moveName ~= '' then
      PokemonManager.moves[slot] = PokemonManager.moves[slot] or {}
      PokemonManager.moves[slot][moveIndex] = {name = moveName, level = moveLevel, cost = moveCost, unlocked = moveUnlocked, power = movePower, kind = moveKind}
      if PokemonManager.currentPage == 'moves' and slot == PokemonManager.selected then
        PokemonManager.updateMovesUI()
      end
    end
    return
  end

  if command == 'COMBO' then
    local slot = tonumber(parts[2]) or 0
    if slot > 0 then
      local list = {}
      for v in string.gmatch(parts[3] or '', '[^,]+') do
        local n = tonumber(v)
        if n and n > 0 then list[#list + 1] = n end
      end
      PokemonManager.combo[slot] = list
      PokemonManager.comboDraft[slot] = nil
      if PokemonManager.currentPage == 'moves' and slot == PokemonManager.selected then
        PokemonManager.updateMovesUI()
      end
    end
    return
  end

  if command == 'COMBO_SAVED' then
    local count = tonumber(parts[3]) or 0
    if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
      modules.game_textmessage.displayGameMessage(count > 0 and ('Combo salvo (' .. count .. ' golpes). Use o botao COMBO para ativar.') or 'Combo apagado.')
    end
    return
  end

  if command == 'MOVE_POINTS' then
    local slot = tonumber(parts[2]) or 0
    local total = tonumber(parts[3]) or 0
    local spent = tonumber(parts[4]) or 0
    if slot > 0 then
      PokemonManager.movePoints[slot] = {total = total, spent = spent}
      if PokemonManager.currentPage == 'moves' and slot == PokemonManager.selected then
        PokemonManager.updateMovesUI()
      end
      if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
    end
    return
  end

  if command == 'MOVE_LEARNED' or command == 'MOVE_FORGOTTEN' then
    local slot = tonumber(parts[2]) or 0
    local moveName = parts[3] or ''
    local total = tonumber(parts[4]) or 0
    local spent = tonumber(parts[5]) or 0
    if slot > 0 then
      PokemonManager.movePoints[slot] = {total = total, spent = spent}
      local list = PokemonManager.moves[slot]
      if list then
        for _, move in pairs(list) do
          if string.lower(tostring(move.name or '')) == string.lower(moveName) then
            move.unlocked = (command == 'MOVE_LEARNED')
          end
        end
      end
      if PokemonManager.currentPage == 'moves' and slot == PokemonManager.selected then
        PokemonManager.updateMovesUI()
      end
      if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
    end
    return
  end

  if command=='MOVE_ERROR' then
    modules.game_textmessage.displayFailureMessage(parts[2] or '[PokemonManager] Falha na Move.')
    return
  end

  if command=='POKEMON' then
    local p={
      index=tonumber(parts[2]) or 0, name=parts[3] or 'Unknown', level=tonumber(parts[4]) or 0,
      boost=tonumber(parts[5]) or 0, hp=tonumber(parts[6]) or 0, maxhp=tonumber(parts[7]) or 0,
      love=tonumber(parts[8]) or 0, nature=parts[9] or '-', tera=parts[10] or 'none',
      held=parts[11] or '-', type1=parts[12] or 'none', type2=parts[13] or 'none',
      evpoints=tonumber(parts[14]) or 0, evhp=tonumber(parts[15]) or 0, evatk=tonumber(parts[16]) or 0,
      evdef=tonumber(parts[17]) or 0, evspatk=tonumber(parts[18]) or 0, evspdef=tonumber(parts[19]) or 0,
      evspeed=tonumber(parts[20]) or 0,
      ivhp=tonumber(parts[21]) or 0, ivatk=tonumber(parts[22]) or 0, ivdef=tonumber(parts[23]) or 0,
      ivspatk=tonumber(parts[24]) or 0, ivspdef=tonumber(parts[25]) or 0, ivspeed=tonumber(parts[26]) or 0,
      ballid=tonumber(parts[27]) or 0,
      basehp=tonumber(parts[28]) or 0, baseatk=tonumber(parts[29]) or 0, basedef=tonumber(parts[30]) or 0,
      basespatk=tonumber(parts[31]) or 0, basespdef=tonumber(parts[32]) or 0, basespd=tonumber(parts[33]) or 0,
      vitTotal=tonumber(parts[34]) or 0, vitHp=tonumber(parts[35]) or 0, vitAttack=tonumber(parts[36]) or 0,
      vitDefense=tonumber(parts[37]) or 0, vitSpAttack=tonumber(parts[38]) or 0, vitSpDefense=tonumber(parts[39]) or 0,
      vitSpeed=tonumber(parts[40]) or 0, vitPpMax=tonumber(parts[41]) or 0, vitPpUp=tonumber(parts[42]) or 0, vitLevel=tonumber(parts[43]) or 0,
      vitItemHp=tonumber(parts[44]) or 0, vitItemAttack=tonumber(parts[45]) or 0, vitItemDefense=tonumber(parts[46]) or 0,
      vitItemSpAttack=tonumber(parts[47]) or 0, vitItemSpDefense=tonumber(parts[48]) or 0, vitItemSpeed=tonumber(parts[49]) or 0,
      vitItemPpMax=tonumber(parts[50]) or 0, vitItemPpUp=tonumber(parts[51]) or 0, vitItemLevel=tonumber(parts[52]) or 0,
      friendship=math.max(0, math.min(1000, tonumber(parts[53]) or 0)),
      friendshipKills=math.max(0, tonumber(parts[54]) or 0),
      heldClientId=tonumber(parts[55]) or 0,
      equip=parts[56] or '-', equipClientId=tonumber(parts[57]) or 0,
      isBeingUsed=(parts[58] == '1')
    }
    -- forma atual (ex: Mega Charizard X com a Mega Stone equipada)
    local form = parts[59]
    -- bonus fixo do Painel ADM (0 = nenhum)
    p.bonus = {
      tonumber(parts[60]) or 0, tonumber(parts[61]) or 0, tonumber(parts[62]) or 0,
      tonumber(parts[63]) or 0, tonumber(parts[64]) or 0, tonumber(parts[65]) or 0
    }
    -- codex: held Y, 3o slot (Attachment Device)
    p.heldY = parts[66] or '-'
    p.heldYClientId = tonumber(parts[67]) or 0
    p.held3 = parts[68] or '-'
    p.held3ClientId = tonumber(parts[69]) or 0
    p.hasDevice = parts[70] == '1'
    p.evAddCount = tonumber(parts[71]) or 0 -- codex: EV Add (26737) na mochila
    p.baseName = p.name
    if form and form ~= '' and form ~= '-' then
      p.name = form
    end
    PokemonManager.pokemon[p.index]=p
    -- os MOVE deste Pokemon chegam logo depois: comeca a lista do zero
    -- (a forma Mega tem outra lista de moves)
    PokemonManager.moves[p.index] = {}
    if PokemonManager.keepSelected then
      -- atualizacao: so troca a selecao no END, se o Pokemon sumiu
      if p.index == PokemonManager.keepSelected then PokemonManager.selected = p.index end
    elseif not PokemonManager.pokemon[PokemonManager.selected] then
      PokemonManager.selected=p.index
    end
    PokemonManager.updateUI()
    return
  end
  if command=='EV_APPLIED' then
    PokemonManager.resetEVPending()
    PokemonManager.updateUI()
    return
  end
  if command=='EV_ERROR' then
    modules.game_textmessage.displayFailureMessage(parts[2] or '[PokemonManager] Falha ao aplicar EV.')
    return
  end
  if command=='EVO_START' then
    local slot = tonumber(parts[2]) or 0
    PokemonManager.evo = {slot = slot, name = parts[3] or '', tokens = tonumber(parts[4]) or 0,
      busy = parts[5] == '1', list = {}}
    if tonumber(parts[6]) == 0 and PokemonManager.currentPage == 'evolution' then PokemonManager.updateEvolutionUI() end
    return
  end
  if command=='EVO' then
    local e = PokemonManager.evo
    if not e or e.slot ~= (tonumber(parts[2]) or 0) then return end
    local i = tonumber(parts[3]) or 0
    e.list[i] = {target = parts[4] or '?', needLevel = tonumber(parts[5]) or 0, needLove = tonumber(parts[6]) or 0,
      stoneId = tonumber(parts[7]) or 0, stoneClientId = tonumber(parts[8]) or 0, stoneName = parts[9] or '-',
      stoneNeed = tonumber(parts[10]) or 0, stoneHave = tonumber(parts[11]) or 0, tokens = tonumber(parts[12]) or 0,
      canLevel = parts[13] == '1', canStone = parts[14] == '1', byItemOnly = parts[15] == '1'}
    if PokemonManager.currentPage == 'evolution' then PokemonManager.updateEvolutionUI() end
    return
  end
  if command=='EVO_DONE' then
    PokemonManager.evoArmed = nil
    return
  end
  if command=='EVO_ERROR' then
    PokemonManager.evoArmed = nil
    modules.game_textmessage.displayFailureMessage(parts[2] or 'Nao foi possivel evoluir.')
    if PokemonManager.currentPage == 'evolution' then PokemonManager.updateEvolutionUI() end
    return
  end
  if command=='VITAMIN_APPLIED' then
    PokemonManager.updateUI()
    return
  end
  if command=='VITAMIN_ERROR' then
    modules.game_textmessage.displayFailureMessage(parts[2] or '[PokemonManager] Falha ao usar vitamina.')
    return
  end
  if command=='HELD_ITEM' then
    local itemId=tonumber(parts[2]) or 0
    local itemName=parts[3] or ''
    local count=tonumber(parts[4]) or 0
    local kind=parts[5] or 'held'
    local compatiblePokemon=parts[6] or ''
    local clientId=tonumber(parts[7]) or 0
    local cat=parts[8] or ''
    -- codex held lista: o servidor reenvia a lista inteira depois de equipar/remover;
    -- se a anterior ja terminou (HELD_END), comeca uma nova em vez de somar (duplicava)
    if PokemonManager.heldListDone ~= false then
      PokemonManager.heldItems = {}
      PokemonManager.heldListDone = false
    end
    for i = #PokemonManager.heldItems, 1, -1 do
      if PokemonManager.heldItems[i].id == itemId then table.remove(PokemonManager.heldItems, i) end
    end
    if itemId > 0 and itemName ~= '' and count > 0 then
      table.insert(PokemonManager.heldItems, {
        id=itemId, name=itemName, count=count, kind=kind, pokemon=compatiblePokemon, clientId=clientId, cat=cat
      })
      if PokemonManager.currentPage == 'held' then PokemonManager.updateHeldUI() end
    end
    return
  end

  if command=='HELD_END' then
    -- lista vazia (ex.: equipou o ultimo held da mochila): limpa
    if PokemonManager.heldListDone ~= false then PokemonManager.heldItems = {} end
    PokemonManager.heldListDone = true
    if PokemonManager.currentPage == 'held' then PokemonManager.updateHeldUI() end
    return
  end

  if command=='HELD_EQUIPPED' then
    local slot=tonumber(parts[2]) or 0
    local slotAttr=PM_HELD_SLOTS[parts[3] or ''] and parts[3] or 'held'
    if slotAttr == 'device' then
      if slot > 0 and PokemonManager.pokemon[slot] then PokemonManager.pokemon[slot].hasDevice = true end
      if PokemonManager.currentPage == 'held' then PokemonManager.updateHeldUI() end
      return
    end
    local itemName=parts[4] or '-'
    local clientId=tonumber(parts[5]) or 0
    if slot > 0 and PokemonManager.pokemon[slot] then
      PokemonManager.pokemon[slot][slotAttr]=itemName
      PokemonManager.pokemon[slot][slotAttr .. 'ClientId']=clientId
      if PokemonManager.currentPage == 'held' then PokemonManager.updateHeldUI() end
      PokemonManager.updateSelectedUI()
      if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
    end
    return
  end

  if command=='HELD_REMOVED' then
    local slot=tonumber(parts[2]) or 0
    local slotAttr=PM_HELD_SLOTS[parts[3] or ''] and parts[3] or 'held'
    if slotAttr == 'device' then
      if slot > 0 and PokemonManager.pokemon[slot] then PokemonManager.pokemon[slot].hasDevice = false end
      if PokemonManager.currentPage == 'held' then PokemonManager.updateHeldUI() end
      return
    end
    if slot > 0 and PokemonManager.pokemon[slot] then
      PokemonManager.pokemon[slot][slotAttr]='-'
      PokemonManager.pokemon[slot][slotAttr .. 'ClientId']=0
      if PokemonManager.currentPage == 'held' then PokemonManager.updateHeldUI() end
      PokemonManager.updateSelectedUI()
      if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
    end
    return
  end

  if command=='HELD_ERROR' then
    modules.game_textmessage.displayFailureMessage(parts[2] or '[PokemonManager] Falha no Held.')
    return
  end

  if command=='FRIENDSHIP' then
    local slot=tonumber(parts[2]) or 0
    local value=tonumber(parts[3]) or 0
    local killCount=tonumber(parts[4]) or 0
    if slot > 0 and PokemonManager.pokemon[slot] then
      PokemonManager.pokemon[slot].friendship=value
      PokemonManager.pokemon[slot].friendshipKills=killCount
      if PokemonManager.currentPage == 'friend' and slot == PokemonManager.selected then
        PokemonManager.updateFriendUI()
      end
      if slot == PokemonManager.selected then
        PokemonManager.updateSelectedUI()
      end
      if PokemonManager.currentPage == 'summary' then PokemonManager.updateDashboard() end
    end
    return
  end

  if command=='END' then
    if PokemonManager.keepSelected then
      if not PokemonManager.pokemon[PokemonManager.selected] then
        local first = nil
        for i = 1, 6 do if PokemonManager.pokemon[i] then first = i break end end
        PokemonManager.selected = first or 1
      end
      PokemonManager.keepSelected = nil
    end
    PokemonManager.updateUI(); g_logger.info('[PokemonManager V6.6.0] Lista de Pokemon recebida.') return end
  if command=='PING' then g_logger.info('[PokemonManager V6.6.0] PING recebido.') end
end

-- ============================================================
-- codex tera badge3: o tipo Tera aparece como 3o selo de tipo
-- no Manager (ao lado dos tipos originais do pokemon)
-- ============================================================
do
  local function codexBadge3(prefix)
    local win = PokemonManager.window
    if not win or win:isDestroyed() then return nil end
    local b1 = win:recursiveGetChildById(prefix .. 'TypeBadge1')
    local b2 = win:recursiveGetChildById(prefix .. 'TypeBadge2')
    if not b1 or not b2 or b1:getParent() ~= b2:getParent() then return nil end
    local b3 = win:recursiveGetChildById(prefix .. 'TypeBadge3')
    if not b3 then
      b3 = g_ui.createWidget('UIWidget', b2:getParent())
      b3:setId(prefix .. 'TypeBadge3')
      b3:setSize(b2:getSize())
      b3:setPhantom(true)
      b3:setFocusable(false)
    end
    b3:breakAnchors()
    local left = b2:isVisible() and b2 or b1
    b3:addAnchor(AnchorLeft, left:getId(), AnchorRight)
    b3:addAnchor(AnchorVerticalCenter, b1:getId(), AnchorVerticalCenter)
    b3:setMarginLeft(6)
    return b3
  end

  local codexOriginalBadges = PokemonManager.updateTypeBadges
  PokemonManager.updateTypeBadges = function(prefix, type1, type2)
    codexOriginalBadges(prefix, type1, type2)
    local ok, b3 = pcall(codexBadge3, prefix)
    if not ok or not b3 then return end
    local p = PokemonManager.pokemon and PokemonManager.pokemon[PokemonManager.selected]
    local tera = tostring((p and pmTeraName and pmTeraName(p.tera)) or ''):lower()
    local t1, t2 = tostring(type1 or ''):lower(), tostring(type2 or ''):lower()
    if tera == '' or tera == 'none' or tera == t1 or tera == t2 then
      b3:setVisible(false)
      return
    end
    PokemonManager.setTypeBadge(prefix .. 'TypeBadge3', tera)
    b3:setTooltip('Tipo Tera: o pokemon ganhou esse tipo (fraquezas, resistencias e golpes)')
  end
end

-- ============================================================
-- CODEX MANAGER V2: abas no topo (PC) / coluna de abas (celular)
--   O menu lateral antigo fica escondido; cada aba abre as paginas de
--   sempre (mesma logica). Abas com 2 paginas ganham sub-abas no topo.
-- ============================================================
-- fonte do visual v2 (TTF): nomes ChakraPetch-Bold_<tamanho> / ChakraPetch-SemiBold_<tamanho>
for _, f in ipairs({{'ChakraPetch-Bold', {12, 13, 14, 20, 22}}, {'ChakraPetch-SemiBold', {12}}}) do
  for _, tam in ipairs(f[2]) do
    local ok, res = pcall(function()
      return g_fonts.importFontWithSize('/modules/game_pokemonmanager/fonts/' .. f[1] .. '.ttf', tam)
    end)
    if not ok or res == false then g_logger.warning('[Manager v2] fonte ' .. f[1] .. ' ' .. tam .. ' nao carregou: ' .. tostring(res)) end
  end
end

PM_V2 = '/modules/game_pokemonmanager/v2/'
PokemonManager.ABAS = {
  {id = 'perfil', arte = 88,  nome = 'PERFIL',   icone = 'perfil',     paginas = {{'profile', 'navProfile', 'Perfil'}}},
  {id = 'resumo', arte = 97,  nome = 'RESUMO',   icone = 'resumo',     paginas = {{'summary', 'navSummary', 'Resumo'}}},
  {id = 'status', arte = 91,  nome = 'STATUS',   icone = 'ev',         paginas = {{'base', 'navBase', 'Atributos'}, {'vitamins', 'navVitamins', 'Vitaminas'}}, extras = {ev = true}},
  {id = 'combate', arte = 102, nome = 'COMBATE',  icone = 'moves',      paginas = {{'moves', 'navMoves', 'Moves'}, {'abilities', 'navAbilities', 'Habilidades'}}},
  {id = 'itens', arte = 81,   nome = 'ITENS',    icone = 'held',       paginas = {{'held', 'navHeld', 'Itens Equip'}}},
  {id = 'vinculo', arte = 98, nome = 'VINCULO',  icone = 'amizade',    paginas = {{'friend', 'navFriend', 'Amizade'}}},
  {id = 'evolucao', arte = 110, nome = 'EVOLUCAO', icone = 'evolucao',  paginas = {{'evolution', 'navEvolution', 'Evolucao'}}},
  {id = 'outros', arte = 95,  nome = 'OUTROS',   icone = 'incubadora', paginas = {{'incubators', 'navIncubators', 'Incubadoras'}}},
}

local function pmAbaDaPagina(page)
  for _, aba in ipairs(PokemonManager.ABAS) do
    if aba.extras and aba.extras[page] then return aba end
    for _, pg in ipairs(aba.paginas) do
      if pg[1] == page then return aba end
    end
  end
end

local function pmAbrirPagina(pg)
  PokemonManager.selectMenuButton(pg[2])
  PokemonManager.showPage(pg[1])
  if PokemonManager.softRefresh then PokemonManager.softRefresh() end
end

function PokemonManager.marcarAba(page)
  local win = PokemonManager.window
  if not win or win:isDestroyed() or not win.codexAbas then return end
  local atual = pmAbaDaPagina(page)
  for _, aba in ipairs(PokemonManager.ABAS) do
    local b = win.codexAbas[aba.id]
    if b then
      local on = aba == atual
      b:setOn(on)
      b:setImageSource(PM_V2 .. 'kt_' .. aba.id .. (on and '_on' or ''))
    end
  end
  local sub = win:recursiveGetChildById('codexSubAbas')
  if not sub then return end
  sub:destroyChildren()
  if atual then
    atual.ultima = page
    if #atual.paginas > 1 then
      for _, pg in ipairs(atual.paginas) do
        local s = g_ui.createWidget('PMSubTab', sub)
        s:setText(pg[3])
        s:setOn((pg[1] == page or (atual.extras and atual.extras[page] and pg[1] == 'base')) and true or false)
        s.onClick = function() scheduleEvent(function() pmAbrirPagina(pg) end, 1) end
      end
    end
  end
end

function PokemonManager.montarAbas()
  local win = PokemonManager.window
  if not win or win:isDestroyed() or win.codexAbas then return end
  local barra = win:recursiveGetChildById('codexAbasBarra')
  if not barra then
    g_logger.error('[Manager v2] layout antigo (sem codexAbasBarra)')
    return
  end
  g_logger.info('[Manager v2] montando as abas')
  win.codexAbas = {}
  local celular = type(codexCelular) == 'function' and codexCelular()
  if celular then
    local logo = win:recursiveGetChildById('codexHeaderLogo')
    if logo then logo:hide() end
  end
  local icone = win:recursiveGetChildById('dashboardIcon')
  if icone then icone.codexLookSize = 170 end
  for _, aba in ipairs(PokemonManager.ABAS) do
    local b = g_ui.createWidget('PMTab', barra)
    b:setText('')
    b:setWidth(aba.arte)
    b:setHeight(32)
    b:setImageSource(PM_V2 .. 'kt_' .. aba.id)
    local icon = b:getChildById('icon')
    if icon then icon:hide() end
    b.onClick = function()
      local alvo = aba.paginas[1]
      for _, pg in ipairs(aba.paginas) do
        if pg[1] == aba.ultima then alvo = pg end
      end
      -- fora do clique (nao destruir/recriar nada durante o proprio clique)
      scheduleEvent(function() pmAbrirPagina(alvo) end, 1)
    end
    win.codexAbas[aba.id] = b
  end
end

-- o arquivo roda 2 vezes (scripts: do .otmod + dofile do onLoad) e a 2a vez
-- recria show/showPage: por isso liga de novo sempre que a funcao nao for a nossa.
if PokemonManager.show ~= PokemonManager.codexShowAbas then
  local showOriginal = PokemonManager.show
  PokemonManager.codexShowAbas = function(...)
    local r = showOriginal(...)
    local ok, err = pcall(PokemonManager.montarAbas)
    if not ok then g_logger.error('[Manager v2] erro ao montar as abas: ' .. tostring(err)) end
    ok, err = pcall(PokemonManager.marcarAba, PokemonManager.currentPage or 'summary')
    if not ok then g_logger.error('[Manager v2] erro ao marcar a aba: ' .. tostring(err)) end
    return r
  end
  PokemonManager.show = PokemonManager.codexShowAbas
  g_logger.info('[Manager v2] abas ligadas')
end
if PokemonManager.showPage ~= PokemonManager.codexPageAbas then
  local pageOriginal = PokemonManager.showPage
  PokemonManager.codexPageAbas = function(page, ...)
    local r = pageOriginal(page, ...)
    pcall(PokemonManager.marcarAba, page)
    return r
  end
  PokemonManager.showPage = PokemonManager.codexPageAbas
end
