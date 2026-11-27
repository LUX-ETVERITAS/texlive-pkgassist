#!/usr/bin/env texlua
-- Copyright (c) 2026 Ruilin Mao
-- SPDX-License-Identifier: MIT
local version = "0.1.0"
-- Run with the texlua from the same TeX Live installation as the engine.
local windows = package.config:sub(1, 1) == "\\"
local help = [[
Usage: texlua texlive-pkgassist.lua [options] document.tex

  --engine NAME         Select pdflatex (default), xelatex, lualatex or latex
  --tree system|user|auto
                        Choose the installation tree (default: auto)
  --usermode            Alias for --tree user
  --preflight           Batch-check explicit packages in the main preamble
  --latexmk             Use latexmk for bibliography and repeat runs
  --font FAMILY=PACKAGE Install PACKAGE if fontspec reports FAMILY missing
  --require-tool CMD=PACKAGE
                        Install PACKAGE if CMD is missing from PATH
  --version             Print the version
  --help                Show this help
]]

local function fail(message, status)
  io.stderr:write("texlive-pkgassist: ", message, "\n")
  os.exit(status or 1)
end

local engine, tree, document = "pdflatex", nil, nil
local preflight, latexmk = false, false
local fonts, tools = {}, {}
local engines = {pdflatex = true, xelatex = true, lualatex = true, latex = true}
local i = 1
while i <= #arg do
  local option = arg[i]
  if option == "--help" or option == "-h" then
    print(help)
    os.exit(0)
  elseif option == "--version" then
    print("texlive-pkgassist " .. version)
    os.exit(0)
  elseif option == "--engine" then
    i = i + 1
    engine = arg[i]
    if not engines[engine] then fail(help, 2) end
  elseif option == "--preflight" then
    preflight = true
  elseif option == "--latexmk" then
    latexmk = true
  elseif option == "--font" or option == "--require-tool" then
    i = i + 1
    local key, pkg = (arg[i] or ""):match("^([^=]+)=([%w][%w.+_-]*)$")
    if not key then fail(help, 2) end
    if option == "--font" then
      fonts[key] = pkg
    else
      if not key:match("^[%w][%w._+-]*$") then fail(help, 2) end
      tools[key] = pkg
    end
  elseif option == "--tree" or option:match("^%-%-tree=") or option == "--usermode" then
    local choice = option:match("^%-%-tree=(.*)$") or "user"
    if option == "--tree" then
      i = i + 1
      choice = arg[i]
    end
    if choice ~= "system" and choice ~= "user" and choice ~= "auto" then fail(help, 2) end
    if tree and tree ~= choice then fail("Conflicting installation tree options", 2) end
    tree = choice
  elseif option:sub(1, 1) == "-" or document then
    fail(help, 2)
  else
    document = option
  end
  i = i + 1
end
if not document then fail(help, 2) end
tree = tree or "auto"
if windows then document = document:gsub("\\", "/") end
if not document:match("^/") and not (windows and document:match("^%a:/")) then
  document = "./" .. document
end
local input, open_error = io.open(document, "rb")
if not input then fail(open_error, 2) end
input:close()

local function quote(value)
  if value:find("[%z\r\n]") then fail("Command arguments cannot contain newlines or NUL characters", 2) end
  if windows then
    -- cmd expands percent variables even inside double quotes.
    if value:find('[%%!"]') then fail('Windows command arguments cannot contain %, ! or double quotes', 2) end
    return '"' .. value .. '"'
  end
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Program names are fixed. Quote each argument separately for the local shell.
local function run(program, arguments, on_line)
  local parts = {program}
  for _, value in ipairs(arguments) do
    parts[#parts + 1] = quote(value)
  end
  local pipe, err = io.popen(table.concat(parts, " ") .. " 2>&1", "r")
  if not pipe then fail(err or ("Could not start " .. program)) end
  for line in pipe:lines() do
    line = line:gsub("\r$", "")
    print(line)
    if on_line then on_line(line) end
  end
  local ok, reason, code = pipe:close()
  if ok then return 0 end
  if reason == "signal" then return 128 + code end
  return code or 1
end

local extensions = {}
for ext in ("sty cls def cfg clo fd ldf tex enc map tfm vf bbx cbx lbx bst"):gmatch("%S+") do
  extensions[ext] = true
end

kpse.set_program_name("texlua", engine)

local function sorted_keys(set)
  local keys = {}
  for key in pairs(set) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

-- Limit parsing to actual diagnostics, including file:line prefixes. TeX can
-- wrap the terminal output at max_print_line, even in the middle of a name.
local function diagnostics()
  local result, context = {}, nil
  local function inspect(message)
    local name = message:match("[Ff]ile%s+[`'\"]([%w_][%w._+-]*)['\"]%s+not%s+found")
      or message:match("I can't find file%s+[`'\"]([%w_][%w._+-]*)['\"]")
    if name and extensions[name:match("%.([%w]+)$")] then result.file = name end
    local font = message:match('[Ff]ont%s+"([^"]+)"%s+cannot be found')
    if font then result.font = font end
  end
  function result.read(line)
    if line:match("biblatex.*%(re%)run Biber") then result.biber = true end
    local start = line:match("^!%s*(.*)") or line:match("^.-:%d+:%s*(.*)")
    if start then
      context = start
    elseif context and #context < 1200 and line ~= "" and not line:match("^l%.%d+") then
      local rest = line:gsub("^%(fontspec%)%s*", " ")
      inspect(context .. " " .. rest)
      context = context .. rest
    else
      context = nil
    end
    if context then inspect(context) end
  end
  return result
end

local manager = windows and (os.selfdir:gsub("/", "\\") .. "\\tlmgr.bat") or "tlmgr"
local manager_command = windows and ("@" .. quote(manager)) or manager
local usertree_ready = false
local function tlmgr(args, on_line)
  if tree == "user" then
    if not usertree_ready then
      local db = kpse.var_value("TEXMFHOME") .. "/tlpkg/texlive.tlpdb"
      if not lfs.attributes(db) then
        local status = run(manager_command, {"init-usertree"})
        if status ~= 0 and not lfs.attributes(db) then fail("Could not initialize the user TeX tree", status) end
      end
      usertree_ready = true
    end
    table.insert(args, 1, "--usermode")
  end
  return run(manager_command, args, on_line)
end

local function windows_system_install(names)
  -- Use the tlmgr shipped beside this interpreter. Keep the elevated process
  -- in TeX Live's bin directory, away from the document and its build rules.
  local bin = os.selfdir:gsub("/", "\\")
  if not lfs.attributes(manager) then fail("Could not find the TeX Live manager at " .. manager) end
  -- Pass the path as data. Only validated package names enter the command.
  local command = "try { $p = Start-Process -ErrorAction Stop -Verb RunAs -Wait -PassThru"
    .. " -FilePath ([IO.Path]::Combine($env:AUTOINSTALL_TEXLIVE_BIN, 'tlmgr.bat'))"
    .. " -WorkingDirectory $env:AUTOINSTALL_TEXLIVE_BIN"
    .. " -ArgumentList 'install " .. table.concat(names, " ") .. "';"
    .. " if ($null -eq $p.ExitCode) { exit 1 }; exit $p.ExitCode"
    .. " } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"
  local powershell = os.getenv("SystemRoot") .. "\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
  print("texlive-pkgassist: Requesting Windows authorization to install " .. table.concat(names, " "))
  local previous_bin = os.getenv("AUTOINSTALL_TEXLIVE_BIN")
  assert(os.setenv("AUTOINSTALL_TEXLIVE_BIN", bin))
  -- The @ prefix keeps cmd /c from stripping a leading executable-path quote.
  local status = run("@" .. quote(powershell), {"-NoProfile", "-NonInteractive", "-Command", command})
  os.setenv("AUTOINSTALL_TEXLIVE_BIN", previous_bin)
  if status ~= 0 then fail("System tree installation did not complete. See the Windows or tlmgr error above.", status) end
end

local installed = {}
local function install(packages, needs_binary)
  local names = sorted_keys(packages)
  if #names == 0 then return end
  for _, pkg in ipairs(names) do
    if installed[pkg] then fail("The dependency is still missing after installing " .. pkg .. ". Check the engine search path.") end
  end
  print("texlive-pkgassist: tlmgr install " .. table.concat(names, " "))
  local args = {"install", table.unpack(names)}
  local readonly = false
  local status = tlmgr(args, function(line)
    if line:find("don't have permission to change the installation", 1, true) then readonly = true end
  end)
  if status ~= 0 and readonly and tree == "system" and windows then
    windows_system_install(names)
    status = 0
  elseif status ~= 0 and readonly and tree == "system" then
    fail("The system tree is read-only. Ask an administrator to run tlmgr install " .. table.concat(names, " "), status)
  elseif status ~= 0 and readonly and tree == "auto" and not needs_binary then
    print("texlive-pkgassist: The system tree is read-only. Retrying in the user tree.")
    tree = "user"
    status = tlmgr({"install", table.unpack(names)})
  end
  if status ~= 0 then
    fail("Installation failed. See the tlmgr output above. Relocatable packages can use --tree user. Binary tools require a writable TeX Live installation.", status)
  end
  for _, pkg in ipairs(names) do installed[pkg] = true end
end

local function resolve(files, required)
  local patterns, matches = {}, {}
  for _, name in ipairs(sorted_keys(files)) do
    patterns[#patterns + 1] = name:gsub("([.+-])", "\\%1")
    matches[name] = {}
  end
  if #patterns == 0 then return {} end
  local current
  local status = tlmgr({"search", "--global", "--file", "/(" .. table.concat(patterns, "|") .. ")$"}, function(line)
    if line:match("^%S") then
      current = line:match("^([%w][%w._+-]*):%s*$")
    elseif current then
      local path = line:match("^%s+(.-)%s*$")
      local name = path and path:match("/([^/]+)$")
      if matches[name] and (path:match("^texmf%-dist/") or path:match("^RELOC/"))
          and not path:match("^[^/]+/doc/") and not path:match("^[^/]+/source/") then
        matches[name][current] = true
      end
    end
  end)
  if status ~= 0 then fail("Package lookup failed. See the tlmgr output above.", status) end
  local packages = {}
  for _, name in ipairs(sorted_keys(files)) do
    local candidates = sorted_keys(matches[name])
    if #candidates == 1 then
      packages[candidates[1]] = true
    elseif required then
      if #candidates == 0 then fail("No runtime package in the repository provides " .. name) end
      fail(name .. " has multiple providers: " .. table.concat(candidates, ", "))
    end
  end
  return packages
end

-- Opt-in lexical preflight. TeX's conditional branches and macros are resolved
-- by the real engine on the normal diagnostic path.
local function preamble_files()
  local lines = {}
  for line in io.lines(document) do
    line = line:gsub("%%.*", "")
    local stop = line:find("\\begin%s*{%s*document%s*}")
    lines[#lines + 1] = stop and line:sub(1, stop - 1) or line
    if stop then break end
  end
  local source, files = table.concat(lines, "\n"), {}
  local commands = {usepackage = "sty", RequirePackage = "sty", documentclass = "cls"}
  for pos, command, after in source:gmatch("()\\(%a+)()") do
    if commands[command] and source:sub(pos - 1, pos - 1) ~= "\\" then
      local tail = source:sub(after):match("^%s*(.*)")
      tail = tail:gsub("^%b[]%s*", "", 1)
      local names = tail:match("^{([%w%s_,.+-]+)}")
      for token in (names or ""):gmatch("[^,]+") do
        local name = token:match("^%s*([%w_][%w.+_-]*)%s*$")
        if name then
          local file = name .. "." .. commands[command]
          if not kpse.find_file(file, "tex") then files[file] = true end
        end
      end
    end
  end
  return files
end

local function tool_exists(name)
  if windows then return run("where.exe", {"/Q", name}) == 0 end
  return run("command", {"-v", name}) == 0
end

local function ensure_tool(name, pkg)
  if tool_exists(name) then return end
  if tree == "user" then fail("Missing tool on PATH: " .. name .. ". Install this tool in the build environment.") end
  install({[pkg] = true}, true)
  if not tool_exists(name) then fail("Installed " .. pkg .. ", but PATH still does not contain " .. name) end
end

for _, name in ipairs(sorted_keys(tools)) do ensure_tool(name, tools[name]) end
if preflight then install(resolve(preamble_files(), false)) end
local modes = {pdflatex = "-pdf", lualatex = "-lualatex", xelatex = "-xelatex", latex = "-dvi"}
local explicit_latexmk = latexmk
local retry = false
while true do
  local diag, status = diagnostics()
  if latexmk then
    ensure_tool("latexmk", "latexmk")
    local args = {modes[engine], "-interaction=nonstopmode", "-halt-on-error", "-file-line-error"}
    if not explicit_latexmk then table.insert(args, 1, "-norc") end
    if retry then args[#args + 1] = "-g" end
    args[#args + 1] = document
    status = run("latexmk", args, diag.read)
  else
    status = run(engine, {"-interaction=nonstopmode", "-halt-on-error", "-file-line-error", document}, diag.read)
  end
  if status ~= 0 and diag.file then
    install(resolve({[diag.file] = true}, true))
  elseif status ~= 0 and diag.font then
    local pkg = fonts[diag.font]
    if not pkg then fail("Missing font: " .. diag.font .. ". Install the font on the system or use --font FAMILY=PACKAGE.") end
    install({[pkg] = true})
  elseif diag.biber and ((status == 0 and not latexmk) or (latexmk and not tool_exists("biber"))) then
    ensure_tool("biber", "biber")
    latexmk = true
  elseif status == 0 then
    os.exit(0)
  else
    fail("Build failed. See the output above.", status)
  end
  retry = true
end
