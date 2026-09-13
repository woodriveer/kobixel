# Gemini Edit — extensão para Aseprite

Pega o sprite atual (ou a cel/seleção), exporta para PNG, chama um CLI local
de geração de imagem com o seu prompt, e aplica o resultado de volta no sprite
— em uma nova camada ou substituindo a cel atual. Tudo dentro de uma
`app.transaction`, então `Ctrl+Z` desfaz de uma vez.

Só existe **uma** extensão de verdade neste projeto: o
`gemini-edit-X.Y.Z.aseprite-extension`, instalado dentro do Aseprite. Nada
aqui depende de instalar nada no Chrome.

## Estado atual

A extensão do Aseprite exporta o PNG, roda **um comando externo qualquer**
configurado no campo "Comando externo" do diálogo, e traz o resultado de
volta. `tools/gemini-web-edit/` (abaixo) é o comando padrão hoje e é o único
caminho que usa a cota de imagem da assinatura Gemini Pro sem chave de API.
Outras opções investigadas e por que não são a recomendação:

| Opção | Resultado |
|---|---|
| `tools/gemini-web-edit/` (Playwright + Chrome já logado) | **Recomendado.** Sem chave de API, usa a assinatura Gemini Pro. ~20-40s por edição. Ver setup abaixo. |
| `tools/gemini_edit.py` (API do Gemini direto) | Funciona e é rápido, mas exige API key no [AI Studio](https://aistudio.google.com/apikey) com **faturamento ativado** — não tem tier gratuito pra modelos de imagem, e não usa a assinatura Gemini Pro. |
| `tools/gemini-edit.ps1` (`gemini` CLI + extensão nanobanana) | **Não funciona**: o login gratuito do `gemini` CLI foi descontinuado pela Google (`IneligibleTierError`, pede pra migrar pro Antigravity). Mesmo funcionando, a extensão nanobanana pede uma API key paga própria. |
| Automação via agente Claude (`claude --chrome -p`) | Funciona, mas ~5min e ~US$1 de uso da assinatura Claude por edição — testado e descartado por custo/latência em favor do Playwright direto. |
| `nanobanana` / `nano-banana-cli` (CLIs de terceiros) | Só o exemplo original do campo — precisa instalar e configurar, não é solução pronta. |

**Limitação conhecida de todos os caminhos**: o Nano Banana não expõe canal
alfa real por nenhuma via testada (download, clipboard, nem extraindo via
canvas). Pedir "fundo transparente" no prompt só resulta em fundo
branco/quadriculado opaco. Remova o fundo manualmente no Aseprite (varinha
mágica) quando precisar de transparência.

## Instalação

1. Zipe `package.json` e `gemini-edit.lua` juntos, sem subpasta (o
   `package.json` tem que ficar na **raiz** do zip):
   ```powershell
   Compress-Archive -Path package.json, gemini-edit.lua -DestinationPath gemini-edit-X.Y.Z.zip -Force
   Rename-Item gemini-edit-X.Y.Z.zip gemini-edit-X.Y.Z.aseprite-extension
   ```
   (`X.Y.Z` = o valor de `version` no `package.json`.)
2. No Aseprite: `Edit > Preferences > Extensions > Add Extension` → escolha o
   `.aseprite-extension`.
3. Reinicie o Aseprite. O comando aparece em `Edit > Gemini Edit...`.

**Atualizando uma versão já instalada**: o Aseprite identifica a extensão
pelo campo `name` do `package.json`, não pelo nome do arquivo — ele só mostra
como atualização se o `version` for maior que o instalado. Sempre suba o
`version` antes de gerar um novo zip, senão reinstalar parece não fazer nada
mesmo com o `.lua` alterado.

Na primeira execução o Aseprite vai pedir permissão para o script escrever
arquivos e executar comandos. Marque a opção de dar confiança total ao script,
senão o diálogo aparece a cada chamada.

## O CLI

O plugin não fala com a API do Google direto — ele executa um comando do
shell. O template é editável no diálogo e aceita estes placeholders:

| Placeholder | Vira |
|---|---|
| `{input}`  | caminho do PNG exportado do sprite |
| `{output}` | caminho onde o CLI **deve** gravar o resultado |
| `{prompt}` | seu prompt, já escapado |
| `{width}` / `{height}` | dimensões do PNG enviado |

Exemplos que funcionam:

```sh
# script pronto deste repo, via navegador (recomendado — ver setup abaixo)
node "C:\caminho\para\tools\gemini-web-edit\edit.mjs" --in "{input}" --out "{output}" --prompt "{prompt}"

# script pronto deste repo, via API direta (precisa de chave paga — ver abaixo)
python "C:\caminho\para\tools\gemini_edit.py" --in "{input}" --out "{output}" --prompt "{prompt}"
```

Antes de colar o comando no campo do plugin, **teste o script direto no
terminal** com um PNG qualquer — assim os erros aparecem no terminal em vez
de num diálogo truncado do Aseprite.

### `tools/gemini-web-edit/` (recomendado)

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
cd tools/gemini-web-edit
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

### `tools/gemini_edit.py` (alternativa via API paga)

Fala direto com a API do Gemini, sem navegador no meio — mais rápido, mas
cobra por imagem.

```sh
pip install google-genai
setx GEMINI_API_KEY "sua-chave-aqui"   # pegue em https://aistudio.google.com/apikey, com faturamento ativado
```

Modelo padrão: `gemini-2.5-flash-image` (será desligado em 2 de outubro de
2026 — troque para `gemini-3.1-flash-image` via `--model` ou
`GEMINI_IMAGE_MODEL` quando isso acontecer).

### `tools/gemini-edit.ps1` (não recomendado — deixado para referência)

Usa o `gemini` CLI + extensão nanobanana. Não funciona hoje porque a Google
descontinuou o login gratuito do `gemini` CLI para contas individuais.

### PATH

`os.execute` herda o ambiente do processo do Aseprite. Se você abriu o Aseprite
pelo launcher gráfico ou pela Steam, o `PATH` provavelmente não tem `~/.local/bin`
nem o node do nvm. **Use caminho absoluto do binário** no template se der
"command not found".

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

O comando externo roda em segundo plano (`start /B` no Windows), não trava a
UI do Aseprite. Enquanto roda, um diálogo mostra a última linha do log e o
tempo decorrido (com um botão "Cancelar" pra parar de esperar, sem matar o
processo em si). `tools/gemini-web-edit/edit.mjs` imprime marcadores de
etapa (`[3/6] Uploading input image...` etc.) que aparecem nesse diálogo —
se usar outro comando externo, ele só vai mostrar o que o próprio comando
imprimir no log.

Timeout total de espera: 3 minutos (`MAX_WAIT_SECONDS` no `.lua`). Se o
comando externo terminar sem gerar `{output}` — ou passar do timeout — o
diálogo de progresso fecha e mostra o log completo num alerta.

## Debug

- Log de cada execução: `<temp>/aseprite-gemini/gemini-<stamp>.log` (um
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
