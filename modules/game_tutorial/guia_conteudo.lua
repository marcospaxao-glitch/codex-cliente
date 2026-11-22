-- GERADO: conteudo do Guia Codex (edite os textos aqui mesmo, sem acentos)
-- items = ids do CLIENTE (sprite) | pokes = nomes | imagem opcional: imgs/paginas/<id>.png
GUIA_CODEX = {
  {name = "Comecando", pages = {
    {id = "bemvindo", title = "Bem-vindo ao Codex",
     items = {}, itemNames = {},
     pokes = {"pikachu", "charmander", "squirtle", "bulbasaur"},
     text = [==[Este guia explica todos os sistemas do servidor.

COMO USAR O GUIA
- Escolha um assunto na lista da esquerda.
- Digite na busca (ex.: "tera", "pesca", "castelo") para achar rapido.
- Use os botoes Anterior / Proximo ou as setas do teclado.
- Abra o guia a qualquer hora pelo botao Guia no topo ou por Ctrl+Shift+H.

DICA
Quase toda janela do jogo tem um atalho de teclado. A pagina "Atalhos do teclado" junta todos.]==]},
    {id = "primeiro", title = "Seu primeiro Pokemon",
     items = {23829, 25225, 25228}, itemNames = {"Empty Pokeball", "Small Potion", "Revive"},
     pokes = {"bulbasaur", "charmander", "squirtle"},
     text = [==[No primeiro login voce escolhe o seu Pokemon inicial.

O QUE VOCE RECEBE
- O Pokemon escolhido no nivel 5.
- 100 Poke Balls para capturar.
- 100 Small Potions para curar.
- 10 Revives para reviver Pokemon desmaiado.

PRIMEIROS PASSOS
1. Solte o Pokemon (clique duplo na ball, na janela Equipe ou na barra).
2. Ataque um Pokemon selvagem: o seu ataca o mesmo alvo.
3. Use os golpes (m1, m2...) pelos atalhos que voce configurar.
4. Quando o selvagem cair, use uma Poke Ball no corpo para capturar.]==]},
    {id = "interface", title = "Barra do topo e janelas",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[A barra do topo junta todos os botoes do jogo.

ESQUERDA (mais usados)
Mochila, Equipe, Bolsa de Loot, Pesca, Manager, Evoluir, Pokedex, Mover e Celular.

CATEGORIAS (com busca dentro)
- Combate: Ranked 1v1, Batalha, Cla e Castelos.
- Atalhos: Hotbar, Hotkeys, Barra Pokemon, Mapa, Autoloot.
- Social: Insignias, VIP.
- Recompensas: Recompensa diaria, Gacha, Missoes diarias, Quests.

DIREITA
Guia, Informacoes, Loja.

ATALHOS DA BARRA
- Ctrl+Shift+M abre a ultima categoria usada.
- Ctrl+Shift+T mostra/esconde a barra.

As janelas podem ser arrastadas pela borda e a maioria lembra onde voce deixou.]==]},
    {id = "atalhos", title = "Atalhos do teclado",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[JANELAS
Ctrl+I  Mochila
Ctrl+Shift+P  Equipe Pokemon
Ctrl+D  Pokemon Manager
Ctrl+F  Pokedex
Ctrl+E  Evoluir Pokemon
Ctrl+K  Hotkeys (atalhos de golpes e itens)
Ctrl+B  Batalha
Ctrl+M  Minimapa  |  Ctrl+Tab  mapa grande
Ctrl+P  Lista VIP
Ctrl+S  Habilidades do personagem
Ctrl+J  Profissoes
Ctrl+Shift+A  Autoloot
Ctrl+Shift+F  Varas de pesca
Ctrl+Shift+Q  Missoes diarias
Ctrl+Shift+D  Recompensa diaria
Ctrl+Shift+G  Gacha
Ctrl+Shift+C  Cla e Castelos
Ctrl+Shift+H  Este guia

JOGO
Botao do meio do mouse  Mover (order) o Pokemon
PageUp / PageDown  Subir / descer voando (!up / !down)
Ctrl+W  Limpar textos da tela
Ctrl+=  /  Ctrl+-  Zoom do mapa
Ctrl+R  Reportar bug
Ctrl+Q  Sair  |  Ctrl+L  Voltar para a lista de personagens]==]},
    {id = "comandos", title = "Comandos no chat",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Digite no chat (Default):

!comandos  lista os comandos
!up / !down  voar ou mergulhar para cima/baixo
!bug  destrava o personagem preso (dive, duelo, Saffari...)
!online  jogadores online
!autoloot  liga/desliga o autoloot
!ovos  abre a Creche com os seus ovos de qualquer lugar
!ranked  abre a janela da Ranked 1v1
!loja  recebe as compras feitas no site
!tv on / !tv off  permite ou bloqueia que te assistam pela TV
!sairdungeon  desiste da dungeon atual
!buyhouse / !leavehouse  comprar / deixar casa
!tutorial  mostra as dicas basicas de novo]==]},
    {id = "cura", title = "Curar, morrer e bencao",
     items = {25225, 25226, 25224, 25230, 25229}, itemNames = {"Small Potion", "Great Potion", "Ultra Potion", "Hyper Potion", "Full Restore"},
     pokes = {"chansey"},
     text = [==[CURAR
- Nurse (Centro Pokemon): diga hi e heal. Cura voce e todos os seus Pokemon de graca.
- Pocoes: Small, Great, Ultra, Hyper e Full Restore. Use a pocao no Pokemon (Usar com).

MORRER
Ao morrer voce perde parte da experiencia.

BENCAO
O Priest pode te benzer (diga hi e benzer). Com a bencao voce perde bem menos experiencia ao morrer.]==]},
  }},
  {name = "Pokemon", pages = {
    {id = "equipe", title = "Equipe (6 Pokemon)",
     items = {23829}, itemNames = {"Empty Pokeball"},
     pokes = {},
     text = [==[Voce anda com ate 6 Pokemon. O resto fica guardado no PC.

JANELA EQUIPE (Ctrl+Shift+P)
- Cada Pokemon tem um lugar fixo (1 a 6).
- Clique para selecionar, clique duplo para soltar/guardar.
- Use itens (revive, pocao, Tera Crystal, held...) direto no card do Pokemon.
- Pegar uma ball do chao coloca na mochila, se tiver vaga na equipe, ele preenche o a vaga vazia.

Com o Pokemon fora a ball nao pode ir para o chao (guarde antes).]==]},
    {id = "barra", title = "Barra de Pokemon",
     items = {25228}, itemNames = {"Revive"},
     pokes = {"pidgeot", "gengar"},
     text = [==[A barra mostra a equipe com foto, vida e level.

- Clique na foto para soltar/trocar o Pokemon.
- Botao direito na barra: barra vertical/horizontal, modo (completo, foto e vida, so foto) e travar posicao.

REVIVE NA BARRA
Quando um Pokemon desmaia aparece o botao verde de revive na foto.
- Clique: usa o revive escolhido.
- Botao direito: escolhe Revive (volta com metade da vida) ou Max Revive (volta com a vida cheia).
A escolha fica salva.]==]},
    {id = "golpes", title = "Golpes e Hotkeys",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Cada Pokemon tem ate 12 golpes: m1 ate m12.

COMO USAR
Abra as Hotkeys (Ctrl+K), escolha uma tecla (ex.: F1) e escreva o comando:
  #s m1   (golpe 1)
  #s m2   (golpe 2) ... ate #s m12
Marque "Enviar automaticamente".

As teclas comecam vazias: monte do seu jeito.

HOTBAR
A Hotbar mostra os mesmos atalhos em botoes na tela, com itens e golpes. Arraste itens para ela.

Cada golpe tem tempo de recarga e alguns pedem level minimo.]==]},
    {id = "mover", title = "Mover o Pokemon (Order)",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[O Order manda o Pokemon andar para onde voce clicar.

- Botao do meio do mouse no lugar desejado, ou o botao Mover no topo.
- Alguns Pokemon usam o Order para habilidades: voar (Fly), surfar (Ride/Surf), cortar arvore (Cut), quebrar pedra (Rock Smash) e outras.
- Voando: PageUp / PageDown sobe ou desce de andar.]==]},
    {id = "captura", title = "Capturar Pokemon",
     items = {23829, 23827, 23855, 23852}, itemNames = {"Empty Pokeball", "Empty Greatball", "Empty Ultraball", "Empty Saffariball"},
     pokes = {"magikarp", "scyther"},
     text = [==[1. Derrote o Pokemon selvagem.
2. Use uma Pokebola vazia no corpo dele (Usar com).
3. Se der certo, a ball vai para a equipe (ou para o PC se estiver cheia).

BOLAS
Poke Ball, Great Ball, Ultra Ball, Master Ball e bolas especiais (Net, Dusk, Heavy, Fast, Love, Premier, Park...). Bolas melhores tem mais chance.

GARANTIA DE CAPTURA
Cada bola que falha conta para aquele Pokemon. Ao chegar no limite, a proxima captura e garantida:
comum 300, incomum 400, raro 500, shiny/mega 600, lendario 800.
O jogo mostra o contador quando voce erra.

Capturar pela primeira vez da experiencia extra.]==]},
    {id = "autoball", title = "Auto Ball",
     items = {37363}, itemNames = {"Autoball"},
     pokes = {},
     text = [==[Joga a bola sozinho nos Pokemon que voce derrota.

PRECISA DO ITEM Auto Ball na mochila.
- Use o item para mostrar/esconder o quadro e a lista.
- Escolha a bola e quais Pokemon (lista) devem ser capturados.
- Ligue no quadro.

A captura usa as mesmas regras e chances da captura normal.
Sem o item o sistema desliga e o quadro some.]==]},
    {id = "evoluir", title = "Evolucao",
     items = {}, itemNames = {},
     pokes = {"charmander", "charmeleon", "charizard"},
     text = [==[- Clique em Evoluir no topo (ou Ctrl+E) e depois no seu Pokemon.
- Pokemon que evoluem por level evoluem quando chegam no level pedido.
- Outros pedem pedra de evolucao ou item especial: use o item no Pokemon.

A Pokedex mostra como cada Pokemon evolui.]==]},
    {id = "pokedex", title = "Pokedex",
     items = {}, itemNames = {},
     pokes = {"eevee", "umbreon"},
     text = [==[Abra pelo topo ou Ctrl+F.

Mostra status, tipos, habilidades, golpes, evolucoes e onde encontrar cada Pokemon (todas as formas, inclusive Shiny e Mega).

Descobrir um Pokemon novo da experiencia ao personagem.]==]},
    {id = "manager", title = "Pokemon Manager",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[O Manager (Ctrl+D) mostra tudo do Pokemon.

ABA STATUS
Vida, ataque, defesa, ataque e defesa especial, velocidade, IVs, nature, tipos, Tera, boost e amizade.

ABA MOVES
- Golpes do Pokemon, com level de cada um.
- Pontos: a cada level o Pokemon ganha pontos para liberar golpes.
- Golpes de TM e Sketch aparecem marcados (TM / SK).
- Botao Golpes Tera: escolhe golpes do tipo Tera.
- Monta a sequencia do Auto Combo.

ADDON
Botao direito no seu Pokemon solto > Addon: troca a aparencia (addons) que ele tem liberada.]==]},
    {id = "genes", title = "Sexo, IVs e estrelas",
     items = {}, itemNames = {},
     pokes = {"ditto", "snorlax"},
     text = [==[Todo Pokemon selvagem nasce com:
- SEXO (macho ou femea; alguns nao tem).
- IVs: o "DNA" de cada status, de 0 a 31. Quanto maior, mais forte.
- ESTRELAS: resumo da qualidade dos IVs.
- As vezes ja nasce com BOOST.

O selo em cima do Pokemon mostra sexo, tipo, estrelas e boost.
Ao capturar, tudo e mantido.

Para conseguir filhotes melhores use a Creche (pagina Creche e ovos).]==]},
    {id = "nature", title = "Natures",
     items = {29804, 29803}, itemNames = {"Nature", "Nature Reset"},
     pokes = {},
     text = [==[A nature aumenta um status e diminui outro (ex.: Adamant = mais ataque, menos ataque especial).
Hardy, Docile, Bashful, Quirky e Serious sao neutras.

TROCAR A NATURE
- Nature (item): sorteia outra nature, sempre diferente da atual. Se o Pokemon nao tiver, ganha uma.
- Use com o Pokemon guardado na ball.

O Manager mostra a nature e o efeito.]==]},
    {id = "tera", title = "Tera Type (3o tipo)",
     items = {37366}, itemNames = {"Tera Crystal"},
     pokes = {"pidgeot"},
     text = [==[O Tera Type e um terceiro tipo do Pokemon.

O QUE ELE FAZ
- O Pokemon passa a contar esse tipo em fraquezas, resistencias e bonus de golpe do mesmo tipo.
- +10% em um status ligado ao tipo Tera (so com o Pokemon solto).
- Libera golpes desse tipo: Golpes Tera e TMs do tipo.

TERA CRYSTAL
Troca ou acrescenta o Tera Type (sorteia um tipo que o Pokemon ainda nao tem).
Use com o Pokemon guardado. Trocar o Tera apaga os Golpes Tera escolhidos.]==]},
    {id = "teramoves", title = "Golpes Tera",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[No Manager, aba Moves, botao Golpes Tera.

- Lista os golpes do MESMO tipo do Tera do Pokemon.
- Escolha e coloque nos slots livres (ate m12).
- O custo e o mesmo do TM.
- Os golpes Tera aparecem no Manager e podem ir para o Auto Combo.]==]},
    {id = "tm", title = "TM (ensinar golpes)",
     items = {}, itemNames = {},
     pokes = {"smeargle"},
     text = [==[TMs ensinam golpes novos ao Pokemon.

- Solte o Pokemon, clique com o botao direito nele > TM System.
- Escolha o golpe e o slot (m1..m12).
- Paga com CDs.
- Cada TM tem a lista de Pokemon que aprendem.
- Pokemon com Tera Type tambem aprendem os TMs do tipo Tera.
- Pokemon que ainda evoluem nao aprendem TM.
- Smeargle aprende golpes com o Sketch.

Os golpes de TM aparecem no Manager e no Auto Combo.]==]},
    {id = "amizade", title = "Amizade",
     items = {}, itemNames = {},
     pokes = {"eevee"},
     text = [==[A amizade (0 a 1000) sobe conforme o Pokemon derrota inimigos.
Sobe mais rapido nas faixas do meio e devagar perto do maximo.

O Manager mostra a amizade de cada Pokemon da equipe.
A Gacha de amizade entrega Pokemon com amizade alta.]==]},
    {id = "boost", title = "Boost",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[O boost deixa o Pokemon mais forte: cada ponto de boost = +1% no status total.

MAQUINA DE BOOST
1. Coloque as stones na maquina.
2. Aperte o botao: a janela mostra o boost atual, ate onde as stones alcancam e quanto o status sobe.
3. Escolha o boost novo e confirme.

Cada nivel novo custa mais stones que o anterior.
Pokemon selvagem as vezes ja nasce com boost.]==]},
    {id = "held", title = "Held Items",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Held Items dao bonus ao Pokemon que segura (dano, defesa, experiencia, velocidade...). Vao do tier 1 ao tier 7.

VENDEDOR DE HELDS
- trade: comprar e vender helds.
- helds: explica como funcionam.
- fundir: 3 helds IGUAIS do mesmo tier viram 1 do tier seguinte (100%). Custo em gp, pago do banco.

TIRAR O HELD
Pelo Held Remover (solte o Pokemon e diga remover) ou pelo app do notebook.]==]},
    {id = "mega", title = "Mega Evolucao",
     items = {}, itemNames = {},
     pokes = {"mega charizard x", "charizard"},
     text = [==[Pokemon com Mega Evolucao precisam da Mega Stone certa (ex.: Charizardite X).

- Equipe a Mega Stone no Pokemon.
- Mega Pokemon sao bem mais fortes.
- Mega Stones vem de premios, eventos, dungeons e da Gacha Mega.

MEGA COLLECTOR
Compra Mega Stones que voce nao quer: diga mega e o nome da pedra.]==]},
    {id = "shiny", title = "Shiny",
     items = {}, itemNames = {},
     pokes = {"shiny charizard"},
     text = [==[Shiny e a versao rara, com cor diferente e status melhores.

Como conseguir:
- Encontrar selvagem (raro).
- Forja do PC: pequena chance de virar Shiny.
- Gacha Shiny.

Shiny tem garantia de captura propria (600 bolas).]==]},
    {id = "creche", title = "Creche e ovos",
     items = {}, itemNames = {},
     pokes = {"ditto"},
     text = [==[NPC CRECHE: diga creche.
- Deixe um casal (macho + femea da mesma especie) ou qualquer Pokemon + Ditto.
- O casal produz um ovo.
- O filhote herda o melhor dos pais. Pais perfeitos = ovo perfeito.

CHOCAR
O ovo e um item: ele choca andando (passos), em qualquer lugar.
Look no ovo mostra o Pokemon, sexo, IV e passos que faltam.
Ovo pronto: use para chocar.

!ovos abre a Creche de qualquer lugar.]==]},
    {id = "abilities", title = "Habilidades e estagios",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[ESTAGIOS
Ataque, Defesa e Evasao sobem ou descem de -6 ate +6 com golpes como Swords Dance, Iron Defense, Charm...
Somem quando o tempo acaba ou o Pokemon volta para a ball.

HABILIDADES
Alguns Pokemon tem habilidades escondidas (hidden abilities). Shiny e Mega herdam a habilidade da especie.
A Pokedex mostra a habilidade de cada um.]==]},
  }},
  {name = "Combate", pages = {
    {id = "autocombo", title = "Auto Combo",
     items = {37364}, itemNames = {"Autocombo"},
     pokes = {},
     text = [==[Solta os golpes sozinho, na ordem que voce montou.

PRECISA DO ITEM Auto Combo na mochila.
1. No Manager (aba Moves), monte a sequencia de golpes de cada Pokemon. Fica salva na ball.
2. Use o item para mostrar o botao do combo.
3. Aperte o botao: liga. Aperte de novo: desliga.

- Golpe em recarga, longe ou sem level: pula para o proximo.
- Sem alvo, dormindo ou em area protegida: espera.
- Golpes de area so sao usados com um alvo perto (ate 2 sqm).
- Trocar de Pokemon nao desliga: usa o combo do novo.]==]},
    {id = "autotarget", title = "Auto Target",
     items = {37365}, itemNames = {"Autotarget"},
     pokes = {},
     text = [==[Com o Pokemon solto e sem alvo, mira sozinho no Pokemon selvagem mais perto.

PRECISA DO ITEM Auto Target na mochila.
Use o item para mostrar/esconder o quadro e ligue por ele.]==]},
    {id = "afk", title = "Anti-AFK",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Quem ficar 20 minutos sem ANDAR e desconectado.
2 minutos antes aparece um aviso.

Vale com ou sem Auto Combo / Auto Ball / Auto Target ligados: para continuar, ande um pouco.]==]},
    {id = "espec", title = "Especializacoes",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[MESTRE DAS ESPECIALIZACOES: diga especializacao.

- Escolha 1 de 10 especializacoes. Cada uma cobre alguns tipos.
- Ranks 1 a 6: golpes desses tipos batem mais forte e os seus Pokemon desses tipos levam menos dano.
- Subir de rank: entregue loot comprimido dos tipos + gp do banco.
- Trocar de especializacao: paga e volta para o rank 1.]==]},
    {id = "ranked", title = "Ranked 1v1",
     items = {}, itemNames = {},
     pokes = {"lucario", "gardevoir"},
     text = [==[Abra pelo topo (Combate) ou !ranked.

- Entre na fila: so enfrenta jogadores do mesmo rank (ou 1 acima/abaixo).
- Partida 3 contra 3, com o level real dos Pokemon.
- Sem pocao e sem revive.
- Vitoria da pontos, derrota tira.
- Temporada de 3 meses. No fim, recompensa pelo rank final e extra para o top 3.]==]},
    {id = "clas", title = "Clas e Castelos",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Abra por Ctrl+Shift+C ou pelo topo (Combate).

CLA
Crie, convide, expulse e mude cargos na hora, sem relogar.

GUERRA DE CASTELOS
- Quando a guerra comeca, um contador aparece no canto da tela.
- Dentro do castelo so leva dano quem e de outro cla (nao aliado).
- Quem quebrar o Emperium domina o castelo. Quem estiver com ele no fim da guerra fica com o castelo.

DONO DO CASTELO
- Bonus de experiencia e loot para os membros.
- Guardioes contratados (o cla escolhe onde ficam). Eles nao atacam os membros.
- Bau do castelo: membros guardam, lider e vice retiram. O bau diario cai dentro dele.
- Perdeu o castelo: tudo do bau vai para o PC do lider.]==]},
    {id = "ginasios", title = "Ginasios, Liga e Insignias",
     items = {36263}, itemNames = {"Badge Bag"},
     pokes = {"onix", "starmie"},
     text = [==[LIDERES DE GINASIO
Brock, Misty, Lt. Surge, Erika, Koga, Sabrina, Blaine, Giovanni e os lideres de Johto. Vencer da a insignia.

INSIGNIAS
Ficam na Caixa de Insignias (botao Insignias). Algumas areas e NPCs pedem insignias.

LIGA
O League Register libera a Liga para quem venceu todos os ginasios. Depois vem a Elite (Lorelei, Bruno, Agatha, Lance).]==]},
    {id = "respeito", title = "Respeito e duelos",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Treinadores pelo mapa aceitam duelos (ex.: Trainer Lucas, Larissa, Pietro).
O RespectMaster tem desafios que dao pontos de Respeito.

Em duelo contra NPC algumas acoes ficam bloqueadas (ex.: trocar de area). Travou? Use !bug.]==]},
    {id = "dungeon", title = "Dungeons de lendarios",
     items = {31670}, itemNames = {"Terminal De Dungeons"},
     pokes = {"mewtwo", "lugia"},
     text = [==[TERMINAL DE DUNGEONS: use o terminal para ver as dungeons.

- Cada dungeon tem um lendario.
- Voce entra sozinho e paga em tokens.
- Derrote o lendario e abra o bau de premio. O bau te devolve ao terminal.
- Desistir: !sairdungeon (fora de combate).]==]},
  }},
  {name = "Itens e dinheiro", pages = {
    {id = "pokebank", title = "PokeBank e moedas",
     items = {3043, 37278, 37279, 36499}, itemNames = {"Crystal Coin", "Pokecoins", "Tokens", "Diamond Donate"},
     pokes = {},
     text = [==[O PokeBank guarda as suas moedas e paga as compras dos NPCs.

MOEDAS
- Gold: dinheiro normal (gold, platinum, crystal coin).
- PokeCoins: moeda especial (item PokeCoins).
- Tokens: moeda de eventos, dungeons e Token Collector.
- Donate: moeda da loja (item Diamond Donate).

Todas podem ser depositadas, sacadas e transferidas para outros jogadores (por ID).
O extrato mostra tudo o que entrou e saiu.]==]},
    {id = "mochila", title = "Mochila, Bolsa de Loot e Autoloot",
     items = {36680}, itemNames = {"Fire Type Backpack"},
     pokes = {},
     text = [==[MOCHILA (Ctrl+I) guarda os seus itens.

BOLSA DE LOOT
- 40 espacos so para o loot. Nao pesa.
- O autoloot coloca tudo nela.
- Voce pode colocar backpacks VAZIAS dentro: cada uma soma os espacos dela.
- Os NPCs compram direto da bolsa.

AUTOLOOT (Ctrl+Shift+A)
- Coletar tudo ou so os itens da sua lista.
- Bolsa cheia: o que nao couber fica no corpo.
- Com a Fire Backpack as moedas vao direto para o banco.]==]},
    {id = "lojas", title = "Lojas e NPCs de compra",
     items = {}, itemNames = {},
     pokes = {"kangaskhan"},
     text = [==[Diga hi e trade:
- Mark: itens basicos (bolas, pocoes, revives...). Tem aba VIP mais barata.
- Token Collector: loja paga com tokens.
- Pokemon Collector: compra os Pokemon da sua equipe (mostra sexo, estrelas, IV, nature e Tera). Pokemon com cadeado nao aparecem.
- Eletronicos: celulares e aparelhos.
- Vendedor de Helds: helds e fusao.
- Mega Collector: compra Mega Stones.
- Architect: moveis.

As compras e vendas usam o PokeBank.]==]},
    {id = "pc", title = "PC (armazenamento)",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[No PC fica tudo o que nao esta com voce.

POKEMON
30 caixas com 20 lugares. Guarde e retire Pokemon pela janela do PC.

ITENS
Abas automaticas por tipo de item.

BUSCA GERAL
Digite um nome: mostra os Pokemon de todas as caixas e os itens de todas as abas.

CADEADO
Trave um Pokemon: ele nao pode ser vendido, liberado ou usado na Forja.]==]},
    {id = "forja", title = "Forja Pokemon",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Na aba Forja do PC voce melhora os IVs de um Pokemon aos poucos.

- ORIGEM: o Pokemon que fica. Ele mantem tudo (ball, nivel, nature, IVs, EVs, Tera, golpes, held).
- MATERIAIS: 1 a 3 Pokemon da mesma especie. Eles somem na forja.
- Cada material da +1 a +3 pontos no IV que a NATURE da origem favorece (ex.: Adamant = Ataque).
- Nature neutra, ou esse IV ja em 31: os pontos vao para o menor IV.
- A forja pode falhar: a origem nao muda e os materiais sao perdidos.
- A chance cai um pouco a cada forja do mesmo Pokemon.
- Pequena chance de virar Shiny.

O custo e a chance aparecem na janela antes de confirmar.]==]},
    {id = "market", title = "Market",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Anuncie itens e Pokemon que estao no PC.

- O item sai do PC e fica anunciado.
- Comprado: vai para o PC do comprador e o dinheiro cai no seu PokeBank (mesmo offline).
- Expirou ou cancelou: volta para o seu PC.

O Market esta no PC e no app do celular.]==]},
    {id = "correio", title = "Correio",
     items = {3503, 3507}, itemNames = {"Parcel", "Label"},
     pokes = {},
     text = [==[Mande itens e Pokemon para outro jogador, online ou offline.

1. Pegue um parcel vazio e um label.
2. Escreva no label o ID do jogador (ex.: 25) ou o nome.
3. Coloque o label e os itens/Pokemon dentro do parcel.
4. Jogue o parcel na caixa de correio.

Chega direto no PC do destinatario.]==]},
    {id = "troca", title = "Troca entre jogadores",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Botao direito no jogador > Trocar com ...; ele precisa aceitar.

- Cada um oferece itens da mochila e Pokemon da equipe.
- Os dois apertam Pronto e depois Confirmar.
- Qualquer mudanca desfaz o Pronto dos dois.
- Ate 3 sqm de distancia, no mesmo andar.]==]},
    {id = "loja", title = "Loja e compras do site",
     items = {36499}, itemNames = {"Diamond Donate"},
     pokes = {},
     text = [==[LOJA (botao Loja no topo)
Itens, roupas e servicos pagos com Donate (saldo do PokeBank ou o item Diamond Donate).

COMPRAS DO SITE
O que voce compra no site chega ao entrar no jogo ou com !loja.
Mochila cheia: vai para o deposito.]==]},
    {id = "buffs", title = "Buffs com tempo",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Alguns itens dao um efeito por um tempo: mais experiencia, mais loot, mais chance de captura...

- O efeito aparece no canto esquerdo do mapa com o tempo correndo.
- Usar outro item do mesmo efeito soma o tempo.
- Deslogar nao para o relogio.]==]},
  }},
  {name = "Atividades", pages = {
    {id = "pesca", title = "Pesca",
     items = {}, itemNames = {},
     pokes = {"magikarp", "gyarados"},
     text = [==[VARAS (Ctrl+Shift+F)
- A vara em uso fica num lugar proprio, com as iscas dela.
- Para trocar, arraste outra vara para a janela Varas.
- Old, Great, Super e Ultra Rod: varas melhores pescam Pokemon melhores.

PESCAR
Use a vara na agua. Pescar e um bom jeito de subir de level.

NPCs
- Pescador Jonas: mostra os Pokemon de cada vara.
- Fishing Master e quests de pesca melhoram a sua vara.

!lenda liga/desliga lendarios na pesca.]==]},
    {id = "saffari", title = "Saffari Zone",
     items = {23852}, itemNames = {"Empty Saffariball"},
     pokes = {"tauros", "kangaskhan"},
     text = [==[Entrada pelo NPC Luis, em Saffron. Paga pelo PokeBank.

REGRAS
- Nao entra com celular, notebook nem revive.
- La dentro so funciona a Saffari Ball.
- Acabaram as Saffari Balls: voce volta para a entrada.]==]},
    {id = "pokepark", title = "PokePARK",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[NPC PokePARK: diga hi e registrar.
A entrada custa 1 PokePARK ticket (loja ou dungeons).
La dentro voce encontra Pokemon especiais.]==]},
    {id = "missoes", title = "Missoes diarias",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Ctrl+Shift+Q, botao no topo ou NPC Supervisora Clara.

- Todo dia: 3 missoes (facil, media, dificil).
- Tipos: derrotar, capturar, pescar e entregar itens.
- 1 troca gratis por dia.
- Completar as 3 libera um bonus.
- Recompensas: gold, experiencia, itens e pontos de missao.
- Pontos de missao compram itens na aba Loja.]==]},
    {id = "daily", title = "Recompensa diaria",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Ctrl+Shift+D ou botao Recompensa.

- Resgate 1 recompensa por dia (28 dias).
- Conta premium recebe tambem a linha premium do dia.
- Virou premium no meio do ciclo? Resgate as premium dos dias que ja passaram.
- No fim do ultimo dia comeca um ciclo novo.]==]},
    {id = "gacha", title = "Gacha",
     items = {37299, 37300, 37301, 37302, 37303}, itemNames = {"Gacha Normal", "Gacha Shiny", "Gacha Ivs", "Gacha Mega", "Gacha Amizade"},
     pokes = {},
     text = [==[Use um item de Gacha: a roleta gira e sorteia um Pokemon.

- Gacha normal: Pokemon comum.
- Gacha shiny: versao Shiny.
- Gacha IVs: IVs altos (chance de perfeito).
- Gacha mega: Pokemon com Mega + Mega Stone.
- Gacha amizade: amizade alta.

O Pokemon vai para a equipe ou para o PC. Ctrl+Shift+G abre a janela.]==]},
    {id = "profissoes", title = "Profissoes",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[Ctrl+J abre as profissoes. Fale com o NPC Profissao para comecar.

- Engenheiro: pokebolas e aparelhos.
- Pescador: varas e iscas.
- Aventureiro: kits de exploracao e reliquias.
- Estilista: roupas, acessorios e bolsas.

Suba de nivel produzindo receitas. O Cartao de Profissao libera uma profissao secundaria.]==]},
    {id = "vocacoes", title = "Vocacoes",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[JOB MANAGER
Hunter, Catcher, Healer, Blocker ou Explorer.
- Pede level 100.
- O curso custa 1000 tokens.
Fale com ele para saber a vantagem de cada uma.]==]},
    {id = "celular", title = "Celular",
     items = {37305}, itemNames = {"Celular Vermelho"},
     pokes = {},
     text = [==[Use o celular para abrir os apps:

- Aluguel: alugar uma casa livre (paga com o gold do PokeBank).
- WhatsApp: contatos por ID, conversas e grupos. Chega mesmo offline.
- Loc: mandar a sua localizacao (marca no minimapa).
- Market: comprar e anunciar (vai e sai do PC).

A cor do celular so muda o tema.]==]},
    {id = "tv", title = "TV",
     items = {29614}, itemNames = {"Tv"},
     pokes = {},
     text = [==[Use a TV para assistir outro jogador online.
- Voce fica invisivel e parado, a camera segue o jogador.
- Pare pelo botao Parar.
- !tv off: ninguem pode te assistir.  !tv on: libera.]==]},
    {id = "casas", title = "Casas",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[- !buyhouse em frente a porta da casa livre compra.
- !leavehouse deixa a casa.
- O app Aluguel do celular aluga casas livres.
- Architect vende moveis.]==]},
  }},
  {name = "Ajuda", pages = {
    {id = "problemas", title = "Problemas comuns",
     items = {}, itemNames = {},
     pokes = {},
     text = [==[PERSONAGEM TRAVADO
!bug destrava (dive, duelo, Saffari...).

JANELA SUMIU
Abra de novo pelo botao do topo ou pelo atalho. Arraste pela borda para posicionar.

POKEMON NAO SOLTA
Veja se ele esta desmaiado (use revive) ou se esta em area que nao permite.

REPORTAR
Ctrl+R abre o reporte de bug. Mande print e explique o que aconteceu.]==]},
  }},
}
