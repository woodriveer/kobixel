*[Read in English](README.en-US.md)*

# Repixel AI — extensão para Aseprite

Pega o sprite atual (ou a cel/seleção), exporta para PNG, chama um CLI local
de geração de imagem com o seu prompt, e aplica o resultado de volta no sprite
— em uma nova camada ou substituindo a cel atual. Tudo dentro de uma
`app.transaction`, então `Ctrl+Z` desfaz de uma vez.

Só existe **uma** extensão de verdade neste projeto: o
`repixel-ai-X.Y.Z.aseprite-extension`, instalado dentro do Aseprite. Nada
aqui depende de instalar nada no Chrome.

## Estado atual

A extensão do Aseprite exporta o PNG, roda **um comando externo qualquer**
configurado no campo "Comando externo" do diálogo, e traz o resultado de
volta. `tools/repixel-gemini-web/` (abaixo) é o comando padrão hoje e é o único
caminho que usa a cota de imagem da assinatura Gemini Pro sem chave de API.
Outras opções investigadas e por que não são a recomendação:

| Opção | Resultado |
|---|---|
| `tools/repixel-gemini-web/` (Playwright + Chrome já logado) | **Recomendado.** Sem chave de API, usa a assinatura Gemini Pro. ~20-40s por edição. Ver setup abaixo. |
| `tools/gemini_edit.py` (API do Gemini direto) — **removido do repositório** | Exigia API key no [AI Studio](https://aistudio.google.com/apikey) com **faturamento ativado** — sem tier gratuito pra modelos de imagem, e não usava a assinatura Gemini Pro. Removido por isso; o código continua no histórico do git se precisar. |
| `tools/gemini-edit.ps1` (`gemini` CLI + extensão nanobanana) — **removido do repositório** | Não funcionava: o login gratuito do `gemini` CLI foi descontinuado pela Google (`IneligibleTierError`), e a extensão nanobanana também exigia uma API key paga própria. Removido por isso; o código continua no histórico do git se precisar. |
| Automação via agente Claude (`claude --chrome -p`) | Funciona, mas ~5min e ~US$1 de uso da assinatura Claude por edição — testado e descartado por custo/latência em favor do Playwright direto. |
| `nanobanana` / `nano-banana-cli` (CLIs de terceiros) | Só o exemplo original do campo — precisa instalar e configurar, não é solução pronta. |

**Nota**: `tools/gemini_edit.py` e `tools/gemini-edit.ps1` foram removidos deste repositório (ambos exigiam API key paga, e o segundo já estava quebrado). Se o seu campo "Comando externo" ainda aponta para um dos dois, troque pelo comando do `edit.mjs` — ver "O CLI" abaixo.

**Limitação conhecida de todos os caminhos**: o Nano Banana não expõe canal
alfa real por nenhuma via testada (download, clipboard, nem extraindo via
canvas). Pedir "fundo transparente" no prompt só resulta em fundo
branco/quadriculado opaco. Remova o fundo manualmente no Aseprite (varinha
mágica) quando precisar de transparência.

## Instalação

1. Gere o `.aseprite-extension` com o script de release:
   ```powershell
   .\release.ps1
   ```
   Isso sobe o `version` no `package.json` (patch por padrão), apaga
   builds antigos, e gera `repixel-ai-X.Y.Z.aseprite-extension` na raiz do
   repo. Ver "Gerando uma nova release" abaixo pra mais opções.
2. No Aseprite: `Edit > Preferences > Extensions` → **remova a versão
   antiga** primeiro (evita cache) → `Add Extension` → escolha o
   `.aseprite-extension` novo.
3. Reinicie o Aseprite. O comando aparece em `Edit > Repixel AI...`.

Na primeira execução o Aseprite vai pedir permissão para o script escrever
arquivos e executar comandos. Marque a opção de dar confiança total ao script,
senão o diálogo aparece a cada chamada.

## Gerando uma nova release

Depois de editar `repixel-ai.lua`, rode:

```powershell
.\release.ps1                # sobe o patch: 0.1.0 -> 0.1.1 (padrão)
.\release.ps1 -Bump minor    # 0.1.0 -> 0.2.0
.\release.ps1 -Bump major    # 0.1.0 -> 1.0.0
```

Isso faz tudo: sobe o número de versão no `package.json`, apaga qualquer
`.aseprite-extension` antigo na raiz, e gera o novo zip.

**Por que sempre subir a versão**: o Aseprite identifica a extensão pelo
campo `name` do `package.json`, não pelo nome do arquivo — ele só mostra
como atualização se o `version` for maior que o instalado. Reinstalar sem
subir a versão parece não fazer nada, mesmo com o `.lua` alterado de
verdade (é exatamente esse bug que o script evita).

Se preferir fazer manualmente em vez de usar o script:
```powershell
# edite "version" em package.json à mão primeiro
Compress-Archive -Path package.json, repixel-ai.lua -DestinationPath repixel-ai-X.Y.Z.zip -Force
Rename-Item repixel-ai-X.Y.Z.zip repixel-ai-X.Y.Z.aseprite-extension
```

## O CLI

O plugin não fala com a API do Google direto — ele executa um comando do
shell. O template é editável no diálogo e aceita estes placeholders:

| Placeholder | Vira |
|---|---|
| `{input}`  | caminho do PNG exportado do sprite |
| `{output}` | caminho onde o CLI **deve** gravar o resultado |
| `{prompt}` | seu prompt, já escapado |
| `{width}` / `{height}` | dimensões do PNG enviado |

Exemplo que funciona (script pronto deste repo — ver setup abaixo):

```sh
node "C:\caminho\para\tools\repixel-gemini-web\edit.mjs" --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}"
```

`--width`/`--height` são opcionais: o `edit.mjs` os usa para dizer ao Gemini o tamanho real do PNG enviado (em vez de um valor fixo) e continua funcionando normalmente se você omitir os dois.

Antes de colar o comando no campo do plugin, **teste o script direto no
terminal** com um PNG qualquer — assim os erros aparecem no terminal em vez
de num diálogo truncado do Aseprite.

### `tools/repixel-gemini-web/` (recomendado)

Controla um Chrome que **você mesmo abre e loga**, via a porta de debug do
Chrome (`--remote-debugging-port`) — não usa API key nenhuma, usa a cota de
imagem da sua assinatura Gemini Pro/Ultra pelo site.

Por quê não é mais simples que isso: o Google bloqueia login de conta Google
feito por um navegador que a própria automação abriu ("Esse navegador ou app
pode não ser seguro"), mesmo usando o Chrome de verdade — é uma defesa deles
contra automação de login, não um bug. A saída é nunca deixar a automação
logar: você loga manualmente num Chrome aberto por você, e o script só
**conecta** nessa instância já autenticada.

**Setup (uma vez):**

```sh
cd tools/repixel-gemini-web
npm install
```

**Antes de cada sessão de uso** (ou deixe essa janela sempre aberta), abra o
Chrome você mesmo com a porta de debug:

```powershell
"C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="%USERPROFILE%\.repixel-ai\chrome-profile" --remote-debugging-port=9222 https://gemini.google.com/app
```

Na primeira vez, faça login normalmente nessa janela. A sessão fica salva
nesse perfil dedicado (separado do seu Chrome do dia a dia), então da
próxima vez já abre logado — mas **a janela precisa continuar aberta**
enquanto for usar o plugin; o script conecta nela, não abre a sua própria.

Se o script não conseguir conectar (`Could not connect to Chrome's debug
port`), é porque essa janela não está aberta ou foi fechada — abra de novo.

### PATH

`os.execute` herda o ambiente do processo do Aseprite. Se você abriu o Aseprite
pelo launcher gráfico ou pela Steam, o `PATH` provavelmente não tem `~/.local/bin`
nem o node do nvm. **Use caminho absoluto do binário** no template se der
"command not found".

## Fator de proximidade

O slider "Fator de proximidade" (0-100) controla o quanto o resultado deve
se parecer com o sprite original, versus priorizar o que foi pedido no
prompt. Não existe um parâmetro tipo "strength"/"denoise" na API ou na UI do
Gemini pra isso — o slider vira uma instrução em texto (em inglês, junto do
prompt) que muda dependendo da faixa:

| Faixa | Instrução |
|---|---|
| 90-100 | Preservar pose, proporções, composição e silhueta; só aplicar a mudança pedida. |
| 60-89 | Ficar razoavelmente perto da composição original, mas ajustar detalhes livremente. |
| 30-59 | Usar o desenho só como referência solta (forma/paleta geral); pode reinterpretar bastante. |
| 0-29 | Usar o desenho só como inspiração de cor/estilo; priorizar o prompt sobre a composição original. |

Isso é só orientação por texto pro modelo — ele pode não seguir à risca,
principalmente perto dos extremos.

## Dicas de uso

- **Ampliar antes de enviar**: modelos de imagem trabalham em ~1024px. Mandar um
  PNG 32×32 cru dá resultado ruim. O padrão (8×) manda 256×256 com nearest
  neighbor, preservando a grade de pixels.
- **Travar cores na paleta**: essencial para sprites indexados e para manter a
  paleta original em sprites RGB.
- **Reduzir com Média** costuma ganhar de Ponto quando o modelo devolve arte com
  anti-aliasing; **Ponto** ganha quando ele devolve pixel art limpa.
- Peça explicitamente no prompt: *"pixel art, {width}x{height} grid, no
  anti-aliasing, flat colors"*. Não peça fundo transparente — o Nano Banana
  não devolve alfa real (ver "Estado atual" acima); ele volta com fundo
  branco/sólido opaco, que dá pra remover depois com a varinha mágica.

## Progresso e execução

O comando externo roda em segundo plano (via `Start-Process` do PowerShell no
Windows — nomes de arquivo únicos por execução, ver "Debug" abaixo), não
trava a UI do Aseprite. Enquanto roda, um diálogo mostra a última linha do log e o
tempo decorrido (com um botão "Cancelar" pra parar de esperar, sem matar o
processo em si). `tools/repixel-gemini-web/edit.mjs` imprime marcadores de
etapa (`[3/6] Uploading input image...` etc.) que aparecem nesse diálogo —
se usar outro comando externo, ele só vai mostrar o que o próprio comando
imprimir no log.

Timeout total de espera: 3 minutos (`MAX_WAIT_SECONDS` no `.lua`). Se o
comando externo terminar sem gerar `{output}` — ou passar do timeout — o
diálogo de progresso fecha e mostra o log completo num alerta.

## Debug

- Log de cada execução: `<temp>/aseprite-repixel-ai/repixel-<stamp>.log` (um
  arquivo por execução — nome fixo daria pra uma segunda geração corromper o
  `.bat` da primeira enquanto ela ainda roda em segundo plano).
- PNGs de entrada/saída ficam na mesma pasta (`in-*.png`, `out-*.png`) — o
  Aseprite não expõe `os.remove`, então eles não são apagados automaticamente.
- Console de erros do Lua: `View > Developer Console`.
- Só dá pra rodar uma geração por vez (o plugin bloqueia uma segunda
  enquanto a primeira não termina).

## Limitações conhecidas

- A reamostragem é feita em Lua puro, pixel a pixel. Uma imagem 1024×1024 leva
  alguns segundos (isso ainda roda de forma síncrona, depois que o comando
  externo já terminou).
- Requer Aseprite 1.3+.
