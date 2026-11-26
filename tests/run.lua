-- Tiny test runner. Run from the repository root: `npm test`.
ROOT = ROOT or "."
package.path = ROOT .. "/tests/?.lua;" .. package.path

local realPrint = print
local results = { passed = 0, failed = {} }

local T = {}

function T.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        results.passed = results.passed + 1
        realPrint("  ok    " .. name)
    else
        table.insert(results.failed, { name = name, err = err })
        realPrint("  FAIL  " .. name .. "\n        " .. tostring(err))
    end
end

local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
end

function T.truthy(v, msg)
    if not v then error(msg or "expected a truthy value", 2) end
end

function T.falsy(v, msg)
    if v then error((msg or "expected a falsy value") .. " (got " .. show(v) .. ")", 2) end
end

local SUITES = { "test_core", "test_options", "test_minimap", "test_shield", "test_secrets" }

for _, suite in ipairs(SUITES) do
    realPrint(suite)
    local chunk = assert(loadfile(ROOT .. "/tests/" .. suite .. ".lua"))
    chunk(T)
end
_G.print = realPrint

realPrint(string.format("\n%d passed, %d failed", results.passed, #results.failed))
if #results.failed > 0 then
    error("test failures", 0)
end
