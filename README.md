# Gemini Edit — extensão para Aseprite

Pega o sprite atual (ou a cel/seleção), exporta para PNG, chama um CLI local
de geração de imagem com o seu prompt, e aplica o resultado de volta no sprite
— em uma nova camada ou substituindo a cel atual. Tudo dentro de uma
`app.transaction`, então `Ctrl+Z` desfaz de uma vez.

## Instalação

1. Zipe a pasta (o `package.json` tem que ficar na **raiz** do zip):
   ```
   cd gemini-edit && zip -r ../gemini-edit.aseprite-extension .
   ```
2. No Aseprite: `Edit > Preferences > Extensions > Add Extension` → escolha o
   `.aseprite-extension`.
3. Reinicie o Aseprite. O comando aparece em `Edit > Gemini Edit...`.

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
# nanobanana (pip install nanobanana)
nanobanana "{prompt}" -e "{input}" -o "{output}"

# nano-banana-cli (npm)
nano-banana "{prompt}" --file "{input}" --output "{output}"

# seu próprio script Python com a SDK do google-genai
python3 ~/bin/edit.py --in "{input}" --out "{output}" --prompt "{prompt}"
```

O `gemini` CLI oficial + extensão nanobanana **não** serve bem aqui: ele grava
em `./nanobanana-output/` com nome derivado do prompt, então você não sabe o
caminho de saída. Se quiser insistir nele, use um wrapper que move o arquivo
mais recente para `{output}`.

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
  anti-aliasing, flat colors, transparent background"*.

## Debug

- Log da última execução: `<temp>/aseprite-gemini/gemini.log`
- PNGs de entrada/saída ficam na mesma pasta (`in-*.png`, `out-*.png`) — o
  Aseprite não expõe `os.remove`, então eles não são apagados automaticamente.
- Console de erros do Lua: `View > Developer Console`.

## Limitações conhecidas

- `os.execute` é **bloqueante**: a janela do Aseprite congela enquanto o CLI roda.
  Não tem thread nem async na API de scripting — a alternativa seria disparar o
  comando em background e usar um `Timer` fazendo poll no `{output}`.
- A reamostragem é feita em Lua puro, pixel a pixel. Uma imagem 1024×1024 leva
  alguns segundos.
- Requer Aseprite 1.3+.
