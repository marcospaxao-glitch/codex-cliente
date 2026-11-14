-- ============================================================
-- CODEX - AURA POR TIPO
-- O servidor manda o "skull" 11..28 (um tipo de pokemon) ou 30 (arco-iris).
-- No cliente antigo isso era desenhado no C++ (creature.cpp).
-- No Redemption: um shader de contorno brilhante na cor do tipo
-- + o efeito 823 preso na criatura, tingido na mesma cor.
-- ============================================================
local EFEITO_AURA = 823      -- efeito que gira em volta (igual ao cliente antigo)
local ID_BASE = 9100         -- ids dos "attached effects" (9111..9128)

-- cores iguais as do creature.cpp antigo (0..255)
local CORES = {
  [11] = {199, 184, 189}, -- normal
  [12] = {255, 0, 0},     -- fire
  [13] = {153, 64, 37},   -- fighting
  [14] = {0, 0, 255},     -- water
  [15] = {205, 235, 255}, -- flying
  [16] = {62, 204, 36},   -- grass
  [17] = {120, 0, 222},   -- poison
  [18] = {255, 251, 0},   -- electric
  [19] = {169, 112, 44},  -- ground
  [20] = {196, 71, 207},  -- psychic
  [21] = {72, 24, 11},    -- rock
  [22] = {175, 230, 255}, -- ice
  [23] = {135, 171, 81},  -- bug
  [24] = {72, 30, 171},   -- dragon
  [25] = {107, 80, 157},  -- ghost
  [26] = {63, 63, 63},    -- dark
  [27] = {147, 147, 147}, -- steel
  [28] = {254, 183, 220}, -- fairy
}
local ARCO_IRIS = 30

local function vec3(c)
  return string.format('vec3(%.3f, %.3f, %.3f)', c[1] / 255, c[2] / 255, c[3] / 255)
end

-- contorno grosso que pulsa entre 40% e 60% (como o original)
local function codigoContorno(corGlsl)
  return [[
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
vec3 corAura() { return ]] .. corGlsl .. [[; }
void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  if (col.a > 0.5) { gl_FragColor = col; return; }
  float o1 = 1.0 / 64.0;
  float o2 = 2.0 / 64.0;
  float a = 0.0;
  a += texture2D(u_Tex0, v_TexCoord + vec2( o1, 0.0)).a;
  a += texture2D(u_Tex0, v_TexCoord + vec2(-o1, 0.0)).a;
  a += texture2D(u_Tex0, v_TexCoord + vec2(0.0,  o1)).a;
  a += texture2D(u_Tex0, v_TexCoord + vec2(0.0, -o1)).a;
  a += texture2D(u_Tex0, v_TexCoord + vec2( o2, 0.0)).a * 0.6;
  a += texture2D(u_Tex0, v_TexCoord + vec2(-o2, 0.0)).a * 0.6;
  a += texture2D(u_Tex0, v_TexCoord + vec2(0.0,  o2)).a * 0.6;
  a += texture2D(u_Tex0, v_TexCoord + vec2(0.0, -o2)).a * 0.6;
  if (a <= 0.0) { gl_FragColor = col; return; }
  float pulso = 0.4 + 0.2 * (sin(u_Time * 2.5) + 1.0) / 2.0;
  float forca = clamp(a / 3.0, 0.0, 1.0) * pulso;
  gl_FragColor = vec4(corAura() * forca, forca);
}
]]
end

-- multiplica a cor do efeito pela cor do tipo
local function codigoTinta(corGlsl)
  return [[
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
void main()
{
  vec4 col = texture2D(u_Tex0, v_TexCoord);
  vec3 c = ]] .. corGlsl .. [[;
  gl_FragColor = vec4(col.rgb * c * 1.5, col.a);
}
]]
end

local ARCO_IRIS_GLSL = 'vec3(0.5 + 0.5 * sin(u_Time * 3.0), 0.5 + 0.5 * sin(u_Time * 3.0 + 2.094), 0.5 + 0.5 * sin(u_Time * 3.0 + 4.188))'

local pronto = false
-- O Redemption cria os shaders depois (na fila da tela) e guarda so o ponteiro
-- do texto do nome e do codigo: por isso eles ficam guardados aqui para sempre.
local GUARDA = {}

local function criarShader(nome, codigo, framebuffer)
  GUARDA[#GUARDA + 1] = nome
  GUARDA[#GUARDA + 1] = codigo
  g_shaders.createFragmentShaderFromCode(nome, codigo, framebuffer)
  g_shaders.setupOutfitShader(nome)
end

local function registrar()
  if pronto then return end
  pronto = true
  for skull, cor in pairs(CORES) do
    criarShader('Codex Aura ' .. skull, codigoContorno(vec3(cor)), true)
    criarShader('Codex Tinta ' .. skull, codigoTinta(vec3(cor)), false)
    local nomeEf = 'Codex Efeito ' .. skull
    GUARDA[#GUARDA + 1] = nomeEf
    local ef = g_attachedEffects.registerByThing(ID_BASE + skull, nomeEf, EFEITO_AURA, ThingCategoryEffect)
    if ef then ef:setLoop(-1) end
  end
  criarShader('Codex Aura ' .. ARCO_IRIS, codigoContorno(ARCO_IRIS_GLSL), true)
end

local function limpar(creature)
  if creature.codexAura then
    pcall(function() creature:detachEffectById(ID_BASE + creature.codexAura) end)
    pcall(function() creature:setShader('') end)
    creature.codexAura = nil
  end
end

local function aplicar(creature, skull)
  if not creature then return end
  skull = skull or creature:getSkull()
  if creature.codexAura == skull then return end
  limpar(creature)
  if not (CORES[skull] or skull == ARCO_IRIS) then return end
  creature.codexAura = skull
  creature:setShader('Codex Aura ' .. skull)
  if CORES[skull] then
    local ef = g_attachedEffects.getById(ID_BASE + skull)
    if ef then
      local copia = ef:clone()
      copia:setShader('Codex Tinta ' .. skull)
      creature:attachEffect(copia)
    end
  end
end

local function onSkullChange(creature, skull) aplicar(creature, skull) end
local function onAppear(creature) aplicar(creature) end

local function varrer()
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  -- no inicio do jogo a posicao ainda e invalida (65535,65535,255)
  if not pos or pos.z > 15 or pos.x >= 65535 then return end
  for _, c in ipairs(g_map.getSpectators(pos, true)) do aplicar(c) end
end

local function varrerDepois()
  scheduleEvent(varrer, 1000)
end

function init()
  registrar() -- cria os shaders ja na entrada (ficam prontos antes de logar)
  connect(Creature, { onSkullChange = onSkullChange, onAppear = onAppear })
  connect(g_game, { onGameStart = varrerDepois })
  if g_game.isOnline() then varrer() end
end

function terminate()
  disconnect(Creature, { onSkullChange = onSkullChange, onAppear = onAppear })
  disconnect(g_game, { onGameStart = varrerDepois })
end
