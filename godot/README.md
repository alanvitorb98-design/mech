# BornToMech em Godot 4

Porte do protótipo 0.4 (o `index.html` da raiz) para a Godot 4. A cena inteira é montada em código, com as mesmas medidas e a mesma lógica da versão de navegador.

## Como abrir

1. Instale a Godot 4 (versão 4.2 ou mais nova, edição padrão, sem .NET): https://godotengine.org/download
2. Abra a Godot, clique em **Importar** e escolha o arquivo `godot/project.godot` deste repositório.
3. Espere a primeira importação dos modelos e texturas terminar.
4. Aperte **F5** pra jogar.

## O que tem em cada arquivo

- `scripts/main.gd`: monta o mundo, o mech, a cabine e as chaves, e roda a simulação (sistemas, pernas, soco, canhão, inimigos, ondas).
- `scripts/state.gd`: o estado de uma partida.
- `scripts/panel.gd`: desenha os painéis de instrumentos (mostradores, alavancas, radar, painel de partida).
- `scripts/audio.gd`: gera em código o som contínuo das máquinas e os efeitos.
- `assets/modelos`: colosso, rastejante e antebraço gerados no Higgsfield. Sem esses arquivos o jogo cai nos modelos de caixas.
- `assets/texturas`: chapa rebitada e placas de aviso.

## Controles

Os mesmos da versão web: W/S pernas, A/D girar a base, mouse mira, clique esquerdo segura e solta o soco, clique direito bloqueia, Q guarda, Espaço canhão, 1/2/3 energia, Shift + mouse olha pela cabine, F aciona a chave na mira, M som, Esc pausa.

## Estado

Este porte foi escrito e conferido só por análise de sintaxe, sem rodar a Godot. É esperado aparecer algum erro na primeira execução: copie a mensagem do painel **Depurador** da Godot pra corrigirmos.
