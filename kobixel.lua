----------------------------------------------------------------------
-- Kobixel - Aseprite extension
--
-- Exports the sprite (or the current cel/selection) to PNG, sends it to a
-- local image-generation CLI (Gemini / nano-banana / whatever you want)
-- along with a prompt, and brings the result back into the sprite.
--
-- Requires Aseprite v1.3+ (uses Image:pixels(), app.fs, app.transaction).
----------------------------------------------------------------------

local DEFAULTS = {
  prompt      = "",
  command     = 'kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}"',
  source      = "sprite",     -- "sprite" (flattened frame) | "cel"
  target      = "new_layer",  -- "new_layer" | "replace"
  upscale     = 8,            -- upscale factor for what is SENT
  resample    = "average",    -- "average" | "point"
  snapPalette = true,
  alphaCut    = 128,
  fidelity    = 70,           -- 0-100: proximity factor to the original drawing
}

local cfg = {}   -- in-memory config (mirrors plugin.preferences)

----------------------------------------------------------------------
-- system/file utilities
----------------------------------------------------------------------

local function isWindows()
  return app.fs.pathSeparator == "\\"
end

local function workDir()
  local base = app.fs.tempPath or app.fs.userConfigPath or app.fs.currentPath or "."
  local dir = app.fs.joinPath(base, "aseprite-kobixel")
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

-- escapes the prompt to go inside double quotes in the shell
local function escapeForShell(s)
  if isWindows() then
    -- cmd.exe: no reliable quote escaping; swap for single quotes
    -- and strip dangerous shell metacharacters.
    s = s:gsub('"', "'")
    s = s:gsub("[%%&|<>^]", " ")
    return s
  else
    return (s:gsub("([\\\"$`])", "\\%1"))
  end
end

-- substitutes {input} {output} {prompt} in the template
local function fillTemplate(tpl, map)
  return (tpl:gsub("{(%w+)}", function(key)
    return map[key] or ("{" .. key .. "}")
  end))
end

-- translates the fidelity slider (0-100) into a text instruction for the
-- image model: there's no "strength"-style parameter in Gemini's API/UI
-- to control this, so the only way is to ask for it in writing.
-- 100 = stay as close as possible to the original drawing (only apply
-- the requested change); 0 = use the drawing only as loose color/style
-- inspiration and prioritize what was asked in the prompt.
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

-- writes a wrapper script and FIRES IT IN THE BACKGROUND: Aseprite runs
-- everything on a single thread, so a plain os.execute would freeze the
-- whole UI for the 20-90s+ the external command takes. PowerShell's
-- Start-Process returns control immediately; the wrapper also writes the
-- exit code to a separate "done" file, so we can tell the process finished
-- without waiting out the full timeout on error.
--
-- The wrapper's filename is unique per run (via "stamp"): since this runs
-- in the background, nothing stops the user from clicking "Generate" again
-- before the first generation finishes (60-90s+) — and Windows reads the
-- .bat line by line by file position, so if two runs reused the same
-- filename, the second would overwrite the .bat while the first is still
-- being interpreted, corrupting the run (skips lines, silently never gets
-- around to running the external command).
local function runCommandAsync(cmd, logPath, donePath, stamp)
  local dir = workDir()
  local runner = app.fs.joinPath(dir, "kobixel-run-" .. stamp .. (isWindows() and ".bat" or ".sh"))

  local f = io.open(runner, "w")
  if not f then
    return false, "Could not write the wrapper script to " .. runner
  end
  if isWindows() then
    f:write("@echo off\r\n")
    -- without this the console stays on the system code page (e.g. cp1252)
    -- and any accented character in the CLI's output becomes an invalid
    -- byte, truncating the text shown in app.alert.
    f:write("chcp 65001 >nul\r\n")
    -- "call" is mandatory here: if the External command resolves to a .bat
    -- or .cmd (e.g. an npm-installed global bin's shim), invoking it bare
    -- transfers control into that script and NEVER returns to this wrapper
    -- — the lines below (the not-found hint, writing donePath) would
    -- silently never run, and the plugin would poll until MAX_WAIT_SECONDS
    -- on every single run. "call" is a no-op for a plain .exe, so it's safe
    -- unconditionally.
    f:write('call ' .. cmd .. ' > "' .. logPath .. '" 2>&1\r\n')
    -- cmd.exe's own ERRORLEVEL 9009 ("command not found") only appears on a
    -- BARE invocation — "call" itself collapses it down to a generic 1,
    -- indistinguishable from the CLI's own failure exit codes. So this
    -- can't precisely detect "not installed" on Windows; instead it appends
    -- a hint on ANY failure, worded as a suggestion rather than a
    -- diagnosis, so it stays honest when the real cause is something else
    -- (e.g. Chrome's debug port not open).
    f:write('if errorlevel 1 echo [kobixel] The command failed. If kobixel-gemini-web is not installed yet, run: npm install -g . inside tools/kobixel-gemini-web >> "' .. logPath .. '"\r\n')
    f:write('echo %ERRORLEVEL% > "' .. donePath .. '"\r\n')
  else
    f:write("#!/bin/sh\n")
    f:write(cmd .. ' > "' .. logPath .. '" 2>&1\n')
    f:write("kobixel_exit=$?\n")
    -- Same any-failure hint as the Windows branch above, kept symmetric
    -- rather than using POSIX's more precise exit code 127 ("command not
    -- found") — see the comment on the Windows branch for why 9009 isn't
    -- reliable there, which is the reason this stays uniform across OSes.
    f:write('if [ "$kobixel_exit" -ne 0 ]; then echo "[kobixel] The command failed. If kobixel-gemini-web is not installed yet, run: npm install -g . inside tools/kobixel-gemini-web" >> "' .. logPath .. '"; fi\n')
    f:write('echo "$kobixel_exit" > "' .. donePath .. '"\n')
  end
  f:close()

  local ok
  if isWindows() then
    -- do NOT use "start /B" here: it reuses the caller process's console,
    -- and the ephemeral cmd.exe that os.execute creates (Aseprite is a GUI
    -- app with no console of its own) dies almost immediately — which can
    -- take the child process down with it before it really runs. It's
    -- intermittent: sometimes it works, sometimes the CLI never gets to
    -- run. PowerShell's Start-Process creates a real process detached
    -- from that console.
    ok = os.execute(
      'powershell -NoProfile -WindowStyle Hidden -Command ' ..
      '"Start-Process -FilePath \'' .. runner .. '\' -WindowStyle Hidden"')
  else
    ok = os.execute('sh "' .. runner .. '" &')
  end
  return ok, nil
end

-- last non-empty line of a string (to show only the most recent step
-- from the log in the progress dialog).
local function lastLine(s)
  if not s or s == "" then return nil end
  local last = nil
  for line in s:gmatch("[^\r\n]+") do
    last = line
  end
  return last
end

----------------------------------------------------------------------
-- color conversion
----------------------------------------------------------------------

local pc = app.pixelColor

local function paletteOf(sprite)
  return sprite.palettes[1]
end

-- any color mode -> RGBA image
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

-- RGBA -> sprite's color mode (optionally snapping to the palette)
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
-- resampling
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
        -- box average, with premultiplied alpha
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
-- image I/O (with fallbacks for API variations)
----------------------------------------------------------------------

local function savePNG(img, path)
  local ok = pcall(function() img:saveAs(path) end)
  if ok then return true end

  -- fallback: create a temporary sprite and save a copy
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

  -- fallback: open as a sprite, flatten into an Image, close
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
-- main pipeline
----------------------------------------------------------------------

local MAX_WAIT_SECONDS = 180
local POLL_INTERVAL = 0.5
local runCounter = 0   -- ensures a unique stamp even if fired within the same second
local activeRun = false -- simple lock: only one generation at a time in this session

-- brings the generated PNG back into the sprite: resamples, converts to
-- the sprite's color mode, and inserts it inside a transaction (Ctrl+Z
-- undoes everything at once).
--
-- frameNumber/targetLayer are captured from WHEN THE USER CLICKED
-- "Generate", not read from app.frame/app.layer here: the generation runs
-- in the background for 30-90s+, and if the user switches tabs/frames in
-- the meantime, app.frame/app.layer would then point somewhere else — the
-- result would land in the wrong place with no error to warn about it.
local function finalizeResult(data, sprite, rect, outPath, frameNumber, targetLayer)
  local result = loadPNG(outPath)
  if not result then
    return app.alert("Could not read the generated PNG:\n" .. outPath)
  end

  local shrunk = resampleTo(result, rect.width, rect.height, data.resample)
  local final = toSpriteColorMode(shrunk, sprite, data.snapPalette, data.alphaCut)

  app.transaction("Kobixel", function()
    if data.target == "new_layer" then
      local layer = sprite:newLayer()
      layer.name = "Kobixel: " .. data.prompt:sub(1, 24)
      sprite:newCel(layer, frameNumber, final, Point(rect.x, rect.y))
    else
      if not targetLayer or not targetLayer.isImage then
        return app.alert("The current layer doesn't accept pixels. Use 'New layer'.")
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
    return app.alert("No sprite open.")
  end
  if data.prompt == "" then
    return app.alert("Write a prompt.")
  end
  if activeRun then
    return app.alert("A Kobixel generation is already running. Wait for it to finish before requesting another.")
  end

  -- Capture frame/layer NOW: the generation runs in the background for
  -- 30-90s+, and if the user switches tabs/frames in the meantime,
  -- app.frame/app.layer would point somewhere else by the time it
  -- finishes. See the comment in finalizeResult.
  local frameNumber = app.frame
  local targetLayer = app.layer

  -- 1. work area: the selection, if any; otherwise the whole sprite/cel
  local rect
  local baseImage
  if data.source == "cel" then
    local cel = app.cel
    if not cel then
      return app.alert("The current layer has no cel on this frame.")
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

  -- 2. prepare the input PNG (RGBA + nearest-neighbor upscale)
  local rgba = toRGBA(baseImage, sprite)
  local sent = upscaleNearest(rgba, data.upscale)

  local dir = workDir()
  runCounter = runCounter + 1
  local stamp = tostring(os.time()) .. "-" .. tostring(runCounter)
  local inPath   = app.fs.joinPath(dir, "in-" .. stamp .. ".png")
  local outPath  = app.fs.joinPath(dir, "out-" .. stamp .. ".png")
  local logPath  = app.fs.joinPath(dir, "kobixel-" .. stamp .. ".log")
  local donePath = app.fs.joinPath(dir, "done-" .. stamp .. ".txt")

  if not savePNG(sent, inPath) then
    return app.alert("Failed to save the input PNG to:\n" .. inPath)
  end

  -- 3. build and fire the command in the background (doesn't block the UI)
  -- Final order sent to Gemini: user prompt -> proximity-factor instruction
  -- -> fixed pixel-art text (the latter is appended by backends, e.g.
  -- edit.mjs, right after {prompt}).
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
    return app.alert("Could not start the external command.\n\nCommand:\n" .. cmd)
  end

  -- 4. progress dialog: a Timer periodically checks whether the output
  -- file (or the "done" sentinel) has appeared yet, updating the text
  -- with the log's last line — without blocking Aseprite's UI.
  local progress = Dialog{ title = "Kobixel" }
  local elapsed = 0
  local timer

  local function stopAndClose()
    activeRun = false
    if timer then timer:stop() end
    progress:close()
  end

  local function onFailure()
    stopAndClose()
    local log = readFile(logPath, 1200) or "(no log)"
    app.alert{
      title = "Kobixel",
      text = {
        "The CLI did not generate the expected output file:",
        outPath,
        "",
        "Command:",
        cmd,
        "",
        "Command output:",
        log,
      }
    }
  end

  local function onSuccess()
    stopAndClose()
    -- pcall: if the sprite was closed or became invalid during the wait
    -- (30-90s+ in the background), this turns into an alert instead of a
    -- silent error only visible in the Developer Console.
    local finalizeOk, finalizeErr = pcall(finalizeResult, data, sprite, rect, outPath, frameNumber, targetLayer)
    if not finalizeOk then
      app.alert("Error inserting the result into the sprite:\n" .. tostring(finalizeErr) ..
        "\n\nThe generated PNG is still at:\n" .. outPath)
    end
  end

  activeRun = true

  progress:label{ id = "status", text = "Starting..." }
  progress:separator{}
  progress:button{ id = "cancel", text = "Cancel", onclick = stopAndClose }

  timer = Timer{
    interval = POLL_INTERVAL,
    ontick = function()
      elapsed = elapsed + POLL_INTERVAL

      if app.fs.isFile(outPath) then
        return onSuccess()
      end
      if app.fs.isFile(donePath) then
        -- the process finished (successfully or not) without writing
        -- outPath: no point waiting out the full timeout.
        return onFailure()
      end
      if elapsed >= MAX_WAIT_SECONDS then
        return onFailure()
      end

      local dots = string.rep(".", math.floor(elapsed / POLL_INTERVAL) % 4)
      local last = lastLine(readFile(logPath, 400)) or "waiting for the CLI..."
      progress:modify{ id = "status", text =
        string.format("Generating%s (%ds)\n%s", dots, math.floor(elapsed), last) }
    end
  }
  timer:start()

  progress:show{ wait = false }
end

----------------------------------------------------------------------
-- dialog / config
----------------------------------------------------------------------

local function showDialog(plugin)
  -- load preferences
  local saved = (plugin and plugin.preferences and plugin.preferences.cfg) or cfg
  for k, v in pairs(DEFAULTS) do
    if saved[k] == nil then saved[k] = v end
  end

  local dlg = Dialog("Kobixel")

  dlg:entry{ id = "prompt", label = "Prompt:", text = saved.prompt, focus = true }

  dlg:slider{ id = "fidelity", label = "Proximity factor:",
              min = 0, max = 100, value = saved.fidelity }
  dlg:label{ label = "", text = "100 = same as the drawing, only applies the request · 0 = uses the drawing only as loose inspiration" }

  dlg:combobox{
    id = "source", label = "Send:",
    option = saved.source == "cel" and "Current layer" or "Flattened sprite",
    options = { "Flattened sprite", "Current layer" } }

  dlg:slider{ id = "upscale", label = "Upscale before sending:",
              min = 1, max = 32, value = saved.upscale }

  dlg:separator{ text = "Back to the sprite" }

  dlg:combobox{
    id = "target", label = "Apply to:",
    option = saved.target == "replace" and "Replace current cel" or "New layer",
    options = { "New layer", "Replace current cel" } }

  dlg:combobox{
    id = "resample", label = "Downscale with:",
    option = saved.resample == "point" and "Point (sharp)" or "Average (smooth)",
    options = { "Average (smooth)", "Point (sharp)" } }

  dlg:check{ id = "snapPalette", text = "Lock colors to the sprite's palette",
             selected = saved.snapPalette }

  dlg:slider{ id = "alphaCut", label = "Alpha cutoff:",
              min = 1, max = 255, value = saved.alphaCut }

  dlg:separator{ text = "External command" }
  dlg:label{ label = "", text = "Placeholders: {input} {output} {prompt} {width} {height}" }
  dlg:entry{ id = "command", label = "", text = saved.command }

  dlg:button{ id = "ok", text = "Generate", focus = false }
  dlg:button{ id = "cancel", text = "Cancel" }

  dlg:show()

  local d = dlg.data
  if not d.ok then return end

  local data = {
    prompt      = d.prompt,
    fidelity    = d.fidelity,
    command     = d.command,
    source      = (d.source == "Current layer") and "cel" or "sprite",
    target      = (d.target == "Replace current cel") and "replace" or "new_layer",
    resample    = (d.resample == "Point (sharp)") and "point" or "average",
    upscale     = d.upscale,
    snapPalette = d.snapPalette,
    alphaCut    = d.alphaCut,
  }

  -- persist
  if plugin and plugin.preferences then
    plugin.preferences.cfg = data
  end
  cfg = data

  run(data)
end

----------------------------------------------------------------------
-- extension entry point
----------------------------------------------------------------------

function init(plugin)
  -- The "group" must be the exact id of an existing group in Aseprite's
  -- own gui.xml. An invalid id = the command gets registered (works for a
  -- keyboard shortcut) but is invisible in every menu. "file_scripts" =
  -- File > Scripts.
  plugin:newCommand{
    id = "Kobixel",
    title = "Kobixel...",
    group = "file_scripts",
    onclick = function() showDialog(plugin) end,
    onenabled = function() return app.sprite ~= nil end,
  }
end

function exit(plugin) end

-- To test as a standalone script (File > Scripts), uncomment:
-- showDialog(nil)
