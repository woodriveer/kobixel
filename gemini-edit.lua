----------------------------------------------------------------------
-- Gemini Edit - Aseprite extension
--
-- Exporta o sprite (ou a cel/seleção atual) para PNG, manda para um CLI
-- local de geração de imagem (Gemini / nano-banana / o que você quiser)
-- junto com um prompt, e traz o resultado de volta para dentro do sprite.
--
-- Requer Aseprite v1.3+ (usa Image:pixels(), app.fs, app.transaction).
----------------------------------------------------------------------

local DEFAULTS = {
  prompt      = "",
  command     = 'node "D:\\Developer\\repixel-ai\\tools\\gemini-web-edit\\edit.mjs" --in "{input}" --out "{output}" --prompt "{prompt}"',
  source      = "sprite",     -- "sprite" (frame achatado) | "cel"
  target      = "new_layer",  -- "new_layer" | "replace"
  upscale     = 8,            -- fator de ampliação do que é ENVIADO
  resample    = "average",    -- "average" | "point"
  snapPalette = true,
  alphaCut    = 128,
  fidelity    = 70,           -- 0-100: fator de proximidade com o desenho original
}

local cfg = {}   -- config em memória (espelha plugin.preferences)

----------------------------------------------------------------------
-- utilitários de sistema / arquivos
----------------------------------------------------------------------

local function isWindows()
  return app.fs.pathSeparator == "\\"
end

local function workDir()
  local base = app.fs.tempPath or app.fs.userConfigPath or app.fs.currentPath or "."
  local dir = app.fs.joinPath(base, "aseprite-gemini")
  if not app.fs.isDirectory(dir) then
    app.fs.makeAllDirectories(dir)
  end
  return dir
end

local function readFile(path, maxBytes)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("a") or ""
  f:close()
  if maxBytes and #s > maxBytes then
    s = "...\n" .. s:sub(#s - maxBytes)
  end
  return s
end

-- escapa o prompt para ir dentro de aspas duplas no shell
local function escapeForShell(s)
  if isWindows() then
    -- cmd.exe: sem escape confiável para aspas; troca por aspas simples
    -- e remove metacaracteres perigosos.
    s = s:gsub('"', "'")
    s = s:gsub("[%%&|<>^]", " ")
    return s
  else
    return (s:gsub("([\\\"$`])", "\\%1"))
  end
end

-- substitui {input} {output} {prompt} no template
local function fillTemplate(tpl, map)
  return (tpl:gsub("{(%w+)}", function(key)
    return map[key] or ("{" .. key .. "}")
  end))
end

-- traduz o slider de fidelidade (0-100) numa instrução em texto pro
-- modelo de imagem: não existe um parâmetro tipo "strength" na API/UI do
-- Gemini pra controlar isso, então o único jeito é pedir por escrito.
-- 100 = ficar o mais parecido possível com o desenho original (só aplica
-- a mudança pedida); 0 = usar o desenho só como inspiração solta de
-- cor/estilo e priorizar o que foi pedido no prompt.
local function fidelityInstruction(fidelity)
  if fidelity >= 90 then
    return "Preserve the input image closely: keep the same pose, proportions, " ..
      "composition, and silhouette. Only apply the requested change - do not " ..
      "redesign or reinterpret the subject."
  elseif fidelity >= 60 then
    return "Stay reasonably close to the input image's composition and subject, " ..
      "but adjust details freely as needed to match the request."
  elseif fidelity >= 30 then
    return "Use the input image as a loose visual reference (general shape and " ..
      "color palette only) - feel free to reinterpret it significantly to match " ..
      "the request."
  else
    return "Use the input image only as a rough color/style inspiration. " ..
      "Prioritize the text request over the input image's composition: create " ..
      "something new that matches the request, not a small variation of the " ..
      "input."
  end
end

-- grava um script wrapper e DISPARA EM SEGUNDO PLANO: aseprite roda tudo
-- numa thread só, então um os.execute comum trava a UI inteira pelos
-- 20-90s+ que o comando externo leva. Start-Process do PowerShell devolve
-- o controle na hora; o wrapper também grava o código de saída num arquivo
-- "done" à parte, pra dar pra saber que o processo terminou sem precisar
-- esperar o timeout inteiro em caso de erro.
--
-- O nome do wrapper é único por execução (com "stamp"): como isso roda em
-- segundo plano, nada impede o usuário de clicar em "Gerar" de novo antes
-- da primeira geração terminar (60-90s+) — e o Windows lê o .bat linha a
-- linha por posição no arquivo, então se duas execuções reaproveitassem o
-- mesmo nome de arquivo, a segunda sobrescreveria o .bat enquanto a
-- primeira ainda está sendo interpretada, corrompendo a execução (pula
-- linhas, silenciosamente nunca chega a rodar o comando externo).
local function runCommandAsync(cmd, logPath, donePath, stamp)
  local dir = workDir()
  local runner = app.fs.joinPath(dir, "gemini-run-" .. stamp .. (isWindows() and ".bat" or ".sh"))

  local f = io.open(runner, "w")
  if not f then
    return false, "Não consegui escrever o script wrapper em " .. runner
  end
  if isWindows() then
    f:write("@echo off\r\n")
    -- sem isso o console fica na code page do sistema (ex. cp1252) e
    -- qualquer acento na saida do CLI vira byte invalido, truncando o
    -- texto exibido no app.alert.
    f:write("chcp 65001 >nul\r\n")
    f:write(cmd .. ' > "' .. logPath .. '" 2>&1\r\n')
    f:write('echo %ERRORLEVEL% > "' .. donePath .. '"\r\n')
  else
    f:write("#!/bin/sh\n")
    f:write(cmd .. ' > "' .. logPath .. '" 2>&1\n')
    f:write('echo $? > "' .. donePath .. '"\n')
  end
  f:close()

  local ok
  if isWindows() then
    -- NÃO usar "start /B" aqui: ele reaproveita o console do processo que
    -- chamou, e o cmd.exe efêmero que o os.execute cria (o Aseprite é uma
    -- GUI sem console próprio) morre quase na hora — o que pode derrubar
    -- junto o processo filho antes dele rodar de verdade. É intermitente:
    -- às vezes funciona, às vezes o CLI nunca chega a executar. Start-Process
    -- do PowerShell cria um processo de verdade desacoplado desse console.
    ok = os.execute(
      'powershell -NoProfile -WindowStyle Hidden -Command ' ..
      '"Start-Process -FilePath \'' .. runner .. '\' -WindowStyle Hidden"')
  else
    ok = os.execute('sh "' .. runner .. '" &')
  end
  return ok, nil
end

-- última linha não-vazia de um texto (pra mostrar só o passo mais recente
-- do log no diálogo de progresso).
local function lastLine(s)
  if not s or s == "" then return nil end
  local last = nil
  for line in s:gmatch("[^\r\n]+") do
    last = line
  end
  return last
end

----------------------------------------------------------------------
-- conversão de cores
----------------------------------------------------------------------

local pc = app.pixelColor

local function paletteOf(sprite)
  return sprite.palettes[1]
end

-- qualquer modo de cor -> imagem RGBA
local function toRGBA(src, sprite)
  if src.colorMode == ColorMode.RGB then
    return src
  end
  local out = Image(ImageSpec{
    width = src.width, height = src.height,
    colorMode = ColorMode.RGB, transparentColor = 0 })
  local pal = paletteOf(sprite)
  local transIdx = src.spec.transparentColor
  for it in src:pixels() do
    local v = it()
    local r, g, b, a = 0, 0, 0, 0
    if src.colorMode == ColorMode.GRAY then
      local lum = pc.grayaV(v)
      r, g, b, a = lum, lum, lum, pc.grayaA(v)
    else -- INDEXED
      if v == transIdx then
        r, g, b, a = 0, 0, 0, 0
      else
        local c = pal:getColor(v)
        r, g, b, a = c.red, c.green, c.blue, c.alpha
      end
    end
    out:putPixel(it.x, it.y, pc.rgba(r, g, b, a))
  end
  return out
end

local function nearestPaletteIndex(pal, r, g, b)
  local best, bestDist = 0, math.maxinteger
  for i = 0, #pal - 1 do
    local c = pal:getColor(i)
    if c.alpha > 0 then
      local dr, dg, db = c.red - r, c.green - g, c.blue - b
      local d = dr * dr + dg * dg + db * db
      if d < bestDist then
        bestDist, best = d, i
      end
    end
  end
  return best
end

-- RGBA -> modo de cor do sprite (opcionalmente travando na paleta)
local function toSpriteColorMode(src, sprite, snap, alphaCut)
  local cm = sprite.colorMode
  if cm == ColorMode.RGB and not snap then
    return src
  end

  local pal = paletteOf(sprite)
  local transIdx = sprite.transparentColor or 0
  local out = Image(ImageSpec{
    width = src.width, height = src.height,
    colorMode = cm, transparentColor = transIdx })

  for it in src:pixels() do
    local v = it()
    local r, g, b, a = pc.rgbaR(v), pc.rgbaG(v), pc.rgbaB(v), pc.rgbaA(v)
    local outv
    if a < alphaCut then
      if cm == ColorMode.INDEXED then outv = transIdx
      elseif cm == ColorMode.GRAY then outv = pc.graya(0, 0)
      else outv = pc.rgba(0, 0, 0, 0) end
    elseif cm == ColorMode.INDEXED then
      outv = nearestPaletteIndex(pal, r, g, b)
    elseif cm == ColorMode.GRAY then
      outv = pc.graya(math.floor(0.299 * r + 0.587 * g + 0.114 * b), 255)
    else -- RGB + snap
      local c = pal:getColor(nearestPaletteIndex(pal, r, g, b))
      outv = pc.rgba(c.red, c.green, c.blue, 255)
    end
    out:putPixel(it.x, it.y, outv)
  end
  return out
end

----------------------------------------------------------------------
-- reamostragem
----------------------------------------------------------------------

local function upscaleNearest(img, factor)
  if factor <= 1 then return img end
  local out = Image(ImageSpec{
    width = img.width * factor, height = img.height * factor,
    colorMode = ColorMode.RGB, transparentColor = 0 })
  for y = 0, out.height - 1 do
    local sy = math.floor(y / factor)
    for x = 0, out.width - 1 do
      out:putPixel(x, y, img:getPixel(math.floor(x / factor), sy))
    end
  end
  return out
end

local function resampleTo(src, w, h, mode)
  if src.width == w and src.height == h then return src end

  local out = Image(ImageSpec{
    width = w, height = h, colorMode = ColorMode.RGB, transparentColor = 0 })
  local sx = src.width / w
  local sy = src.height / h

  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if mode == "point" or sx < 1 or sy < 1 then
        local px = math.min(src.width - 1, math.floor((x + 0.5) * sx))
        local py = math.min(src.height - 1, math.floor((y + 0.5) * sy))
        out:putPixel(x, y, src:getPixel(px, py))
      else
        -- média em caixa, com alfa pré-multiplicado
        local x0 = math.floor(x * sx)
        local x1 = math.min(src.width - 1, math.max(x0, math.ceil((x + 1) * sx) - 1))
        local y0 = math.floor(y * sy)
        local y1 = math.min(src.height - 1, math.max(y0, math.ceil((y + 1) * sy) - 1))
        local sr, sg, sb, sa, n = 0, 0, 0, 0, 0
        for py = y0, y1 do
          for px = x0, x1 do
            local v = src:getPixel(px, py)
            local a = pc.rgbaA(v)
            sr = sr + pc.rgbaR(v) * a
            sg = sg + pc.rgbaG(v) * a
            sb = sb + pc.rgbaB(v) * a
            sa = sa + a
            n = n + 1
          end
        end
        if sa == 0 then
          out:putPixel(x, y, pc.rgba(0, 0, 0, 0))
        else
          out:putPixel(x, y, pc.rgba(
            math.floor(sr / sa), math.floor(sg / sa), math.floor(sb / sa),
            math.floor(sa / n)))
        end
      end
    end
  end
  return out
end

----------------------------------------------------------------------
-- I/O de imagem (com fallbacks para variações da API)
----------------------------------------------------------------------

local function savePNG(img, path)
  local ok = pcall(function() img:saveAs(path) end)
  if ok then return true end

  -- fallback: cria um sprite temporário e salva uma cópia
  local prev = app.sprite
  local tmp = Sprite(img.width, img.height, ColorMode.RGB)
  tmp.cels[1].image = img
  local ok2 = pcall(function() tmp:saveCopyAs(path) end)
  tmp:close()
  app.sprite = prev
  return ok2
end

local function loadPNG(path)
  local img
  local ok = pcall(function() img = Image{ fromFile = path } end)
  if ok and img then return img end

  -- fallback: abre como sprite, achata em uma Image, fecha
  local prev = app.sprite
  local tmp
  local ok2 = pcall(function() tmp = Sprite{ fromFile = path } end)
  if not ok2 or not tmp then
    app.sprite = prev
    return nil
  end
  local flat = Image(ImageSpec{
    width = tmp.width, height = tmp.height,
    colorMode = ColorMode.RGB, transparentColor = 0 })
  flat:drawSprite(tmp, 1)
  tmp:close()
  app.sprite = prev
  return flat
end

----------------------------------------------------------------------
-- pipeline principal
----------------------------------------------------------------------

local MAX_WAIT_SECONDS = 180
local POLL_INTERVAL = 0.5
local runCounter = 0   -- garante stamp único mesmo se disparado no mesmo segundo
local activeRun = false -- trava simples: só uma geração por vez nesta sessão

-- traz o PNG gerado de volta pro sprite: reamostra, converte pro modo de
-- cor do sprite, e insere numa transaction (Ctrl+Z desfaz de uma vez).
--
-- frameNumber/targetLayer vêm capturados de QUANDO O USUÁRIO CLICOU EM
-- "Gerar", não lidos de app.frame/app.layer aqui: a geração roda em segundo
-- plano por 30-90s+, e se o usuário trocar de aba/frame nesse meio tempo,
-- app.frame/app.layer nesse momento já apontam pra outra coisa — o
-- resultado entraria no lugar errado, sem erro nenhum pra avisar.
local function finalizeResult(data, sprite, rect, outPath, frameNumber, targetLayer)
  local result = loadPNG(outPath)
  if not result then
    return app.alert("Não consegui ler o PNG gerado:\n" .. outPath)
  end

  local shrunk = resampleTo(result, rect.width, rect.height, data.resample)
  local final = toSpriteColorMode(shrunk, sprite, data.snapPalette, data.alphaCut)

  app.transaction("Gemini Edit", function()
    if data.target == "new_layer" then
      local layer = sprite:newLayer()
      layer.name = "Gemini: " .. data.prompt:sub(1, 24)
      sprite:newCel(layer, frameNumber, final, Point(rect.x, rect.y))
    else
      if not targetLayer or not targetLayer.isImage then
        return app.alert("A camada atual não aceita pixels. Use 'Nova camada'.")
      end
      local cel = targetLayer:cel(frameNumber)
      if cel then
        cel.image = final
        cel.position = Point(rect.x, rect.y)
      else
        sprite:newCel(targetLayer, frameNumber, final, Point(rect.x, rect.y))
      end
    end
  end)

  app.refresh()
end

local function run(data)
  local sprite = app.sprite
  if not sprite then
    return app.alert("Nenhum sprite aberto.")
  end
  if data.prompt == "" then
    return app.alert("Escreva um prompt.")
  end
  if activeRun then
    return app.alert("Já tem uma geração do Gemini Edit rodando. Espere terminar antes de pedir outra.")
  end

  -- Captura frame/camada AGORA: a geração roda em segundo plano por
  -- 30-90s+, e se o usuário trocar de aba/frame nesse meio tempo,
  -- app.frame/app.layer no momento em que terminar já apontam pra outra
  -- coisa. Ver o comentário em finalizeResult.
  local frameNumber = app.frame
  local targetLayer = app.layer

  -- 1. área de trabalho: seleção, se houver; senão o sprite/cel inteiro
  local rect
  local baseImage
  if data.source == "cel" then
    local cel = app.cel
    if not cel then
      return app.alert("A camada atual não tem cel neste frame.")
    end
    baseImage = cel.image
    rect = Rectangle(cel.position.x, cel.position.y, cel.image.width, cel.image.height)
  else
    baseImage = Image(sprite.spec)
    baseImage:drawSprite(sprite, frameNumber)
    rect = sprite.bounds
  end

  local sel = sprite.selection
  if sel and not sel.isEmpty then
    local r = sel.bounds:intersect(rect)
    if r.width > 0 and r.height > 0 then
      local cropped = Image(ImageSpec{
        width = r.width, height = r.height,
        colorMode = baseImage.colorMode,
        transparentColor = baseImage.spec.transparentColor })
      cropped:drawImage(baseImage, Point(rect.x - r.x, rect.y - r.y))
      baseImage = cropped
      rect = r
    end
  end

  -- 2. prepara o PNG de entrada (RGBA + ampliação nearest)
  local rgba = toRGBA(baseImage, sprite)
  local sent = upscaleNearest(rgba, data.upscale)

  local dir = workDir()
  runCounter = runCounter + 1
  local stamp = tostring(os.time()) .. "-" .. tostring(runCounter)
  local inPath   = app.fs.joinPath(dir, "in-" .. stamp .. ".png")
  local outPath  = app.fs.joinPath(dir, "out-" .. stamp .. ".png")
  local logPath  = app.fs.joinPath(dir, "gemini-" .. stamp .. ".log")
  local donePath = app.fs.joinPath(dir, "done-" .. stamp .. ".txt")

  if not savePNG(sent, inPath) then
    return app.alert("Falha ao salvar o PNG de entrada em:\n" .. inPath)
  end

  -- 3. monta e dispara o comando em segundo plano (não bloqueia a UI)
  -- Ordem final enviada ao Gemini: prompt do usuário -> instrução de
  -- fator de proximidade -> texto fixo de pixel art (esse último é
  -- colado pelos backends, ex. edit.mjs, logo depois do {prompt}).
  local effectivePrompt = data.prompt .. fidelityInstruction(data.fidelity)
  local cmd = fillTemplate(data.command, {
    input  = inPath,
    output = outPath,
    prompt = escapeForShell(effectivePrompt),
    width  = tostring(sent.width),
    height = tostring(sent.height),
  })

  local ok, err = runCommandAsync(cmd, logPath, donePath, stamp)
  if err then return app.alert(err) end
  if not ok then
    return app.alert("Não consegui iniciar o comando externo.\n\nComando:\n" .. cmd)
  end

  -- 4. diálogo de progresso: um Timer confere periodicamente se o arquivo
  -- de saída (ou o sentinel de "terminou") já apareceu, e vai atualizando
  -- o texto com a última linha do log — sem travar a UI do Aseprite.
  local progress = Dialog{ title = "Gemini Edit" }
  local elapsed = 0
  local timer

  local function stopAndClose()
    activeRun = false
    if timer then timer:stop() end
    progress:close()
  end

  local function onFailure()
    stopAndClose()
    local log = readFile(logPath, 1200) or "(sem log)"
    app.alert{
      title = "Gemini Edit",
      text = {
        "O CLI não gerou o arquivo de saída esperado:",
        outPath,
        "",
        "Comando:",
        cmd,
        "",
        "Saída do comando:",
        log,
      }
    }
  end

  local function onSuccess()
    stopAndClose()
    -- pcall: se o sprite foi fechado ou virou inválido durante a espera
    -- (30-90s+ em segundo plano), isso vira um alerta em vez de um erro
    -- silencioso só no Developer Console.
    local finalizeOk, finalizeErr = pcall(finalizeResult, data, sprite, rect, outPath, frameNumber, targetLayer)
    if not finalizeOk then
      app.alert("Erro ao inserir o resultado no sprite:\n" .. tostring(finalizeErr) ..
        "\n\nO PNG gerado continua em:\n" .. outPath)
    end
  end

  activeRun = true

  progress:label{ id = "status", text = "Iniciando..." }
  progress:separator{}
  progress:button{ id = "cancel", text = "Cancelar", onclick = stopAndClose }

  timer = Timer{
    interval = POLL_INTERVAL,
    ontick = function()
      elapsed = elapsed + POLL_INTERVAL

      if app.fs.isFile(outPath) then
        return onSuccess()
      end
      if app.fs.isFile(donePath) then
        -- o processo terminou (bem ou mal) sem gravar outPath: não faz
        -- sentido continuar esperando o timeout inteiro.
        return onFailure()
      end
      if elapsed >= MAX_WAIT_SECONDS then
        return onFailure()
      end

      local dots = string.rep(".", math.floor(elapsed / POLL_INTERVAL) % 4)
      local last = lastLine(readFile(logPath, 400)) or "aguardando o CLI..."
      progress:modify{ id = "status", text =
        string.format("Gerando%s (%ds)\n%s", dots, math.floor(elapsed), last) }
    end
  }
  timer:start()

  progress:show{ wait = false }
end

----------------------------------------------------------------------
-- interface
----------------------------------------------------------------------

local function showDialog(plugin)
  -- carrega preferências
  local saved = (plugin and plugin.preferences and plugin.preferences.cfg) or cfg
  for k, v in pairs(DEFAULTS) do
    if saved[k] == nil then saved[k] = v end
  end

  local dlg = Dialog("Gemini Edit")

  dlg:entry{ id = "prompt", label = "Prompt:", text = saved.prompt, focus = true }

  dlg:slider{ id = "fidelity", label = "Fator de proximidade:",
              min = 0, max = 100, value = saved.fidelity }
  dlg:label{ label = "", text = "100 = igual ao desenho, só aplica o pedido · 0 = usa o desenho só como inspiração solta" }

  dlg:combobox{
    id = "source", label = "Enviar:",
    option = saved.source == "cel" and "Camada atual" or "Sprite achatado",
    options = { "Sprite achatado", "Camada atual" } }

  dlg:slider{ id = "upscale", label = "Ampliar antes de enviar:",
              min = 1, max = 32, value = saved.upscale }

  dlg:separator{ text = "Volta para o sprite" }

  dlg:combobox{
    id = "target", label = "Aplicar em:",
    option = saved.target == "replace" and "Substituir cel atual" or "Nova camada",
    options = { "Nova camada", "Substituir cel atual" } }

  dlg:combobox{
    id = "resample", label = "Reduzir com:",
    option = saved.resample == "point" and "Ponto (nítido)" or "Média (suave)",
    options = { "Média (suave)", "Ponto (nítido)" } }

  dlg:check{ id = "snapPalette", text = "Travar cores na paleta do sprite",
             selected = saved.snapPalette }

  dlg:slider{ id = "alphaCut", label = "Corte de alfa:",
              min = 1, max = 255, value = saved.alphaCut }

  dlg:separator{ text = "Comando externo" }
  dlg:label{ label = "", text = "Placeholders: {input} {output} {prompt} {width} {height}" }
  dlg:entry{ id = "command", label = "", text = saved.command }

  dlg:button{ id = "ok", text = "Gerar", focus = false }
  dlg:button{ id = "cancel", text = "Cancelar" }

  dlg:show()

  local d = dlg.data
  if not d.ok then return end

  local data = {
    prompt      = d.prompt,
    fidelity    = d.fidelity,
    command     = d.command,
    source      = (d.source == "Camada atual") and "cel" or "sprite",
    target      = (d.target == "Substituir cel atual") and "replace" or "new_layer",
    resample    = (d.resample == "Ponto (nítido)") and "point" or "average",
    upscale     = d.upscale,
    snapPalette = d.snapPalette,
    alphaCut    = d.alphaCut,
  }

  -- persiste
  if plugin and plugin.preferences then
    plugin.preferences.cfg = data
  end
  cfg = data

  run(data)
end

----------------------------------------------------------------------
-- entrada como extensão
----------------------------------------------------------------------

function init(plugin)
  -- O "group" precisa ser o id exato de um grupo existente no gui.xml do
  -- Aseprite. Id inválido = comando registrado (serve para atalho de teclado)
  -- mas invisível em todos os menus. "file_scripts" = File > Scripts.
  plugin:newCommand{
    id = "GeminiEdit",
    title = "Gemini Edit...",
    group = "file_scripts",
    onclick = function() showDialog(plugin) end,
    onenabled = function() return app.sprite ~= nil end,
  }
end

function exit(plugin) end

-- Para testar como script solto (File > Scripts), descomente:
-- showDialog(nil)
