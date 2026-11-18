-- ============================================================
-- JORNADA DO TREINADOR - textos (sem acentos, como o resto do cliente)
-- A ORDEM tem que ser a mesma de J.PASSOS no servidor
-- (data/lib/core/codexjornada.lua). Tipo e meta ficam la.
--   titulo : nome da missao (lista e quadro)
--   fala   : o Professor explicando (aparece ao comecar a missao)
--   dica   : como fazer no PC
--   cel    : como fazer no celular (se nao tiver, usa a dica)
--   feito  : o Professor quando a missao termina
-- ============================================================
JORNADA_PROFESSOR = 'Professor Carvalho'
JORNADA_PROFESSOR_CURTO = 'Prof. Carvalho' -- nome embaixo da foto

JORNADA_INICIO = [[Ola, treinador! Eu sou o Professor Carvalho.

Vou te ensinar tudo o que voce precisa para comecar a sua jornada: soltar e cuidar do seu Pokemon, batalhar, capturar, comprar e crescer.

Sao 18 missoes curtas. Cada uma da experiencia, gold e itens. Vamos nessa?]]

JORNADA_FIM = [[Parabens! Voce completou a Jornada do Treinador.

Agora voce conhece o basico do Codex. Ainda tem muito mais: ginasios, clas, dungeons de lendarios, Tera, Mega Evolucao, pesca, creche...

Quando tiver duvida, abra o Guia (botao Guia). Boa sorte, treinador!]]

JORNADA_CAPITULOS = {'Primeiros passos', 'Cuidando do time', 'Capturar', 'Pokemon Manager', 'Economia', 'Crescendo'}

JORNADA_MISSOES = {
  -- ===== Capitulo 1: Primeiros passos =====
  {cap = 1, titulo = 'Conheca o Professor',
   fala = [[Aqui no Codex voce anda com ate 6 Pokemon na sua equipe. O resto fica guardado no PC.

Esta janela e a sua Jornada. A missao atual tambem aparece num quadro na tela: toque nele para abrir a Jornada de novo.

Quando terminar uma missao, volte aqui e pegue o premio. Leu? Entao clique em Entendi!]],
   dica = 'Clique em Entendi! aqui embaixo.',
   feito = 'Otimo! Pegue o seu primeiro premio. O gold vai direto para o seu PokeBank.'},

  {cap = 1, titulo = 'Aprenda um golpe no Manager',
   fala = [[Os golpes do seu Pokemon sao liberados no Pokemon Manager, o centro de tudo do seu Pokemon: golpes, atributos, itens, evolucao, amizade e ovos.

Cada level do Pokemon da 1 ponto de skill. Gaste os pontos na aba Moves para aprender um golpe.

Ainda nao tem Pokemon? Escolha o seu inicial na sala onde voce comecou.]],
   dica = 'Com o Pokemon guardado na pokebola, abra o Manager (botao no topo ou Ctrl+D), aba Moves, escolha um golpe e aprenda.',
   cel = 'Com o Pokemon guardado na pokebola: MENU, grupo Pokemon, Manager. Aba Moves, escolha um golpe e aprenda.',
   feito = 'Golpe aprendido! Ele ja aparece na barra de golpes. Agora vamos soltar o seu Pokemon.'},

  {cap = 1, titulo = 'Solte o seu Pokemon',
   fala = [[Agora o seu parceiro tem que sair da pokebola para batalhar.

Solte ele!]],
   dica = 'Clique na foto do Pokemon na barra de Pokemon (ou clique duplo na pokebola na janela Equipe, Ctrl+Shift+P).',
   cel = 'Toque na foto do Pokemon na barra de Pokemon, no alto da tela.',
   feito = 'Ai esta ele! Clicar de novo na foto guarda o Pokemon na pokebola.'},

  {cap = 1, titulo = 'Use 3 golpes',
   fala = [[Hora de usar os golpes que o seu Pokemon aprendeu! Cada golpe tem tempo de recarga e alguns pedem level.

Ataque um Pokemon selvagem e use os golpes do seu Pokemon.]],
   dica = 'Com o Pokemon solto, clique num golpe na barra de golpes. Golpe novo? Aprenda no Manager, aba Moves.',
   cel = 'Toque num golpe na barra de golpes, logo acima do chat.',
   feito = 'Muito bem! Combinar golpes e a chave das batalhas.'},

  {cap = 1, titulo = 'Derrote 5 Pokemon selvagens',
   fala = [[Agora e para valer! Ataque Pokemon selvagens perto da cidade. O seu Pokemon ataca o mesmo alvo que voce.

Derrotar Pokemon da experiencia para voce e para o seu Pokemon.]],
   dica = 'Clique no Pokemon selvagem (ou use a lista Batalha, Ctrl+B) para atacar.',
   cel = 'Toque em ATACAR: ele escolhe o selvagem mais perto. O botao de setas troca de alvo.',
   feito = 'Voce e bom nisso! Pegue o premio: tem pocoes para a proxima missao.'},

  -- ===== Capitulo 2: Cuidando do time =====
  {cap = 2, titulo = 'Use uma pocao no Pokemon',
   fala = [[Batalhar cansa! As pocoes curam o seu Pokemon no meio da luta: Small, Great, Ultra, Hyper e Full Restore.

Use uma pocao no seu Pokemon solto.]],
   dica = 'Na mochila (Ctrl+I): botao direito na pocao, Usar com, e clique no seu Pokemon.',
   cel = 'Abra a BOLSA, segure o dedo na pocao, escolha Usar com e toque no seu Pokemon.',
   feito = 'Isso! Lembre: o Revive volta um Pokemon desmaiado (na barra aparece um botao verde).'},

  {cap = 2, titulo = 'Mova o Pokemon (Order)',
   fala = [[O Order manda o seu Pokemon andar para onde voce quiser.

Alguns Pokemon usam o Order para habilidades: voar, surfar, cortar arvore, quebrar pedra...]],
   dica = 'Clique com o botao do meio do mouse no chao (ou no botao Mover/Order e depois no chao).',
   cel = 'Toque no botao ORDER (ao lado do joystick) e depois no chao.',
   feito = 'Perfeito! Com o Order voce tambem monta no Pokemon que voa ou surfa.'},

  {cap = 2, titulo = 'Cure-se com a Enfermeira',
   fala = [[No Centro Pokemon a Enfermeira cura voce e todos os seus Pokemon de graca.

Va ate ela e diga hi.]],
   dica = 'Va ao Centro Pokemon, fique perto da Nurse e digite hi no chat.',
   cel = 'Va ao Centro Pokemon, fique perto da Nurse, toque em HI.',
   feito = 'Pronto, time novinho! Volte la sempre que precisar.'},

  -- ===== Capitulo 3: Capturar =====
  {cap = 3, titulo = 'Abra a Pokedex',
   fala = [[A Pokedex mostra tudo de cada Pokemon: tipos, golpes, evolucoes e onde encontrar.

Usar a Pokedex num Pokemon que voce nunca viu da experiencia!]],
   dica = 'Clique em Pokedex no topo (Ctrl+F), ou use o botao Pokedex num Pokemon.',
   cel = 'Abra o MENU, grupo Pokemon, e toque em Pokedex.',
   feito = 'Descobrir Pokemon novos tambem da experiencia. Continue usando!'},

  {cap = 3, titulo = 'Capture um Pokemon',
   fala = [[Hora de aumentar a sua equipe!

Derrote um Pokemon selvagem e use uma pokebola vazia no corpo dele. Bolas melhores tem mais chance. Cada bola que falha conta para uma captura garantida.]],
   dica = 'Derrote o selvagem; na mochila, botao direito na pokebola vazia, Usar com, e clique no corpo.',
   cel = 'Derrote o selvagem; na BOLSA segure a pokebola vazia, Usar com, e toque no corpo.',
   feito = 'Capturado! Ele foi para a sua equipe (ou para o PC, se a equipe estiver cheia).'},

  {cap = 3, titulo = 'Derrote 20 Pokemon',
   fala = [[Treinar e o caminho para ficar forte. O seu Pokemon tambem sobe de level e pode evoluir.

Derrote 20 Pokemon selvagens. Dica: ligue o Autoloot para pegar o loot sozinho.]],
   dica = 'Autoloot: Ctrl+Shift+A (ou !autoloot). O loot vai para a Bolsa de Loot.',
   cel = 'Autoloot: MENU, grupo Pokemon, Autoloot. O loot vai para a Bolsa de Loot (botao LOOT).',
   feito = 'Que treino! Venda o loot nos NPCs para ganhar gold.'},

  -- ===== Capitulo 4: Pokemon Manager =====
  {cap = 4, titulo = 'Distribua os atributos (EV)',
   fala = [[Derrotando Pokemon, o seu ganha pontos de EV. Voce escolhe onde colocar: HP, Ataque, Defesa, Atq. Especial, Def. Especial ou Velocidade.

Cada atributo vai ate 252 e o total ate 512.]],
   dica = 'No Manager, aba Atributos: use +1 / +10 num atributo e clique em APLICAR EV.',
   cel = 'No Manager, aba Atributos: toque em +1 / +10 num atributo e depois em APLICAR EV.',
   feito = 'Agora o seu Pokemon e do seu jeito! Pegue o premio: tem um Pokemon Egg para a proxima missao.'},

  {cap = 4, titulo = 'Choque um ovo',
   fala = [[Ovos chocam Pokemon novos! Tem dois jeitos:

- Incubadora: coloque o ovo numa incubadora e espere o tempo dela.
- Por passos: ande carregando o ovo (10.000 passos), sem precisar de incubadora.]],
   dica = 'No Manager, aba Incubadoras: COLOCAR OVO numa incubadora, ou comece a incubacao por passos.',
   cel = 'No Manager, aba Incubadoras: COLOCAR OVO numa incubadora, ou comece a incubacao por passos.',
   feito = 'O ovo esta chocando! Quando ficar pronto, pegue o Pokemon na mesma aba.'},

  -- ===== Capitulo 5: Economia =====
  {cap = 5, titulo = 'Compre algo no Mark',
   fala = [[O Mark vende os itens basicos: bolas, pocoes, revives e mais. Tudo e pago pelo PokeBank.

Va ate o Mark e compre qualquer coisa.]],
   dica = 'Fique perto do Mark, diga hi e depois trade. Escolha o item e compre.',
   cel = 'Fique perto do Mark, toque em HI e depois em TRADE. Escolha o item e compre.',
   feito = 'Compra feita! Os NPCs tambem compram o seu loot direto da Bolsa de Loot.'},

  {cap = 5, titulo = 'Pegue a Recompensa diaria',
   fala = [[Todo dia tem um presente para voce! Sao 28 dias seguidos de recompensas.

Pegue a recompensa de hoje.]],
   dica = 'Botao Recompensas no topo, Recompensa (ou Ctrl+Shift+D).',
   cel = 'MENU, grupo Recompensas, Recompensa.',
   feito = 'Volte todo dia para nao perder a sequencia!'},

  {cap = 5, titulo = 'Abra o seu PC',
   fala = [[No PC fica tudo o que nao esta com voce: Pokemon (30 caixas) e itens, separados por abas.

Va ate um computador (PC) no Centro Pokemon e abra.]],
   dica = 'Clique com o botao direito no computador do Centro Pokemon.',
   cel = 'Segure o dedo no computador do Centro Pokemon (ou use o botao USAR).',
   feito = 'Voce pode travar Pokemon no PC com o cadeado: ai eles nao sao vendidos por engano.'},

  -- ===== Capitulo 6: Crescendo =====
  {cap = 6, titulo = 'Complete uma Missao diaria',
   fala = [[Todo dia voce recebe 3 missoes (facil, media e dificil) com gold, experiencia e pontos para a loja de missoes.

Complete uma e pegue o premio dela.]],
   dica = 'Botao Recompensas no topo, Missoes Diarias (ou Ctrl+Shift+Q).',
   cel = 'MENU, grupo Recompensas, Missoes Diarias.',
   feito = 'Essa e uma otima rotina diaria!'},

  {cap = 6, titulo = 'Chegue ao level 15',
   fala = [[Ultima missao! Continue treinando, capturando e fazendo missoes ate o level 15.

Quando chegar, volte aqui para o grande premio.]],
   dica = 'Derrote Pokemon, faca as Missoes diarias e use a Pokedex em Pokemon novos.',
   feito = 'Level 15! Voce ja e um treinador de verdade.'},
}
