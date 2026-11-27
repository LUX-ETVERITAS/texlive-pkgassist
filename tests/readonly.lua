-- Exercise tlmgr's readonly diagnostic without changing runner ACLs. The
-- Windows success case runs the actual launcher with the ordinary Open verb.
local script, scenario, doc = arg[1], arg[2], arg[3]
local popen, first_pass = io.popen, true
local function failed(message)
  return {
    lines = function() return message:gmatch("[^\n]+") end,
    close = function() return nil, "exit", 1 end,
  }
end
function io.popen(command, mode)
  if first_pass and command:match("^pdflatex ") then
    first_pass = false
    return failed("! LaTeX Error: File `booktabs.sty' not found.")
  elseif command:match("['\"]install['\"] ['\"]booktabs['\"]") then
    print("TEST read-only system tree")
    return failed("You don't have permission to change the installation in any way,")
  elseif command:find("-Verb RunAs", 1, true) then
    assert(command:find("tlmgr.bat'", 1, true))
    assert(command:find("-ArgumentList 'install booktabs'", 1, true))
    assert(not command:find(doc, 1, true))
    print("TEST Windows elevation requested")
    if scenario == "cancel" then return failed("User canceled the operation") end
    command = command:gsub("%-Verb RunAs", "-Verb Open", 1)
  end
  return popen(command, mode)
end
arg = {"--tree", "system", doc}
dofile(script)
