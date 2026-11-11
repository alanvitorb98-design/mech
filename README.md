# BornToMech

Protótipo de um jogo de gerenciamento e horde shooter em primeira pessoa, dentro do cockpit de um mech de uns 40 m. Cada movimento tem peso: as pernas demoram pra embalar, o torso gira como torre de tanque e todo soco depende de pressão hidráulica. O jogador precisa ler o inimigo e começar a agir antes.

Versão atual: protótipo 0.4.

## Como rodar

Não tem instalação nem build. O jogo está em `index.html` e usa Three.js 0.160 carregado por CDN, então precisa de internet. Os modelos 3D ficam em `assets/modelos` e só carregam quando a pasta é servida por um servidor (abrir o arquivo direto no navegador cai nas formas simples antigas).

Sirva a pasta com qualquer servidor estático e abra no navegador:

```sh
python3 -m http.server 8000
# abra http://localhost:8000
```

Precisa de teclado e mouse. Fones são recomendados, porque o som faz parte do painel.

## Versão Godot

A pasta [`godot/`](godot/) tem o mesmo protótipo portado pra Godot 4. Abra `godot/project.godot` na Godot 4.2 ou mais nova e aperte F5. Detalhes em [`godot/README.md`](godot/README.md).

## Controles

| Tecla | Ação |
| --- | --- |
| W / S | Acelerador das pernas (frente e ré) |
| A / D | Girar a base |
| Mouse | Mira com a cabeça. O torso vem atrás com inércia |
| Segurar clique esquerdo | Pressurizar o braço. Soltar dispara o soco |
| Clique direito | Bloquear com o braço esquerdo |
| Q | Levantar ou baixar a guarda |
| Espaço | Canhão de ombro (esquenta o reator) |
| Segurar 1 / 2 / 3 | Puxar energia pra pernas, braços ou arma |
| Shift + mouse | Olhar pela cabine sem girar o torso |
| F | Acionar a chave ou botão na mira |
| M | Liga e desliga o som |
| Esc | Pausa |

## O que já existe

- Cockpit com vidro até os pés e painéis analógicos físicos (consoles laterais e painel do teto).
- Sistemas: turbina a gás, pressão hidráulica, reator com calor e desligamento, distribuição de energia elétrica, dano por seção.
- Andar comandado pelo passo, com pernas e braços em cinemática inversa.
- Posturas dos braços: descanso, guarda, carga e bloqueio.
- Inimigos: Colosso com ataques avisados (investida e pancada) e rastejantes que agarram nas pernas.
- Som contínuo gerado no navegador com Web Audio.
- 5 ondas.

## Partida a frio

O mech começa desligado. O painel de partida fica no console da esquerda (segure Shift pra olhar pra ele, mire na chave e aperte F). A lâmpada âmbar pisca na próxima chave:

1. Bateria
2. Bomba de combustível
3. Partida da turbina (o motor de arranque gira por uns segundos até acender)
4. Bomba hidráulica
5. Reator (abra a tampa vermelha e ligue)
6. Travas das pernas

As ondas só começam depois disso. As chaves continuam valendo durante a luta: desligar o reator esfria mais rápido, cortar o combustível apaga a turbina, e se o reator superaquecer ele desliga sozinho e precisa ser religado na mão. Há também a chave da luz da cabine. Na tela inicial dá pra marcar "Pular a partida a frio".

## Modelos e arte conceitual

A arte conceitual e os modelos 3D foram gerados no Higgsfield, com tema e visual próprios:

- `assets/conceito/`: mech M-40, cockpit, Colosso, rastejante e braço.
- `assets/texturas/`: chapa pintada com rebites (paredes, teto e consoles) e placas de aviso da cabine.
- `assets/modelos/`: malhas GLB convertidas da arte. O Colosso é cortado em tronco, braços e pernas na hora de carregar, pra continuar animando os avisos de ataque. O antebraço com o punho substitui as caixas dos braços no cockpit. O mech completo aparece girando na tela inicial.

## Direção

- Sensação de robô humanoide gigante contra monstros gigantes, com tema e visual próprios.
- Visual rústico e plausível, sem ser futurista nem steampunk.
- Todos os indicadores são objetos dentro da cabine, nada desenhado por cima da tela.
