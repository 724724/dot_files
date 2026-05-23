-- Replay nwg-displays output (hyprlang format) through the Lua API.
-- Reads monitors.conf, then monitors.override.conf (used by scripts/lid.sh)
-- so later specs win per output.

local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

local function split(s, sep)
    local parts = {}
    for piece in (s .. sep):gmatch("(.-)" .. sep) do
        table.insert(parts, trim(piece))
    end
    return parts
end

local function maybe_number(s)
    return tonumber(s) or s
end

local function parse_monitor(value)
    local parts = split(value, ",")
    if not parts[1] then return nil end

    local spec = { output = parts[1] }
    if parts[2] == "disable" or parts[2] == "disabled" then
        spec.disabled = true
        return spec
    end

    if parts[2] then spec.mode     = parts[2] end
    if parts[3] then spec.position = parts[3] end
    if parts[4] then spec.scale    = maybe_number(parts[4]) end

    local i = 5
    while parts[i] and parts[i + 1] do
        spec[parts[i]] = maybe_number(parts[i + 1])
        i = i + 2
    end
    return spec
end

local function parse_workspace_rule(value)
    local parts = split(value, ",")
    if not parts[1] then return nil end

    local rule = { workspace = parts[1] }
    for i = 2, #parts do
        local k, v = parts[i]:match("^([^:]+):(.*)$")
        if k then
            k, v = trim(k), trim(v)
            if     v == "true"  then rule[k] = true
            elseif v == "false" then rule[k] = false
            else                     rule[k] = maybe_number(v) end
        end
    end
    return rule
end

local monitor_specs = {}
local monitor_order = {}
local workspace_rules = {}

local function add_monitor(spec)
    if not monitor_specs[spec.output] then
        table.insert(monitor_order, spec.output)
    end
    monitor_specs[spec.output] = spec
end

local function load(path)
    local f = io.open(path, "r")
    if not f then return end
    for raw in f:lines() do
        local line = trim(raw)
        if line ~= "" and not line:match("^#") then
            local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")
            if key == "monitor" then
                local spec = parse_monitor(value)
                if spec then add_monitor(spec) end
            elseif key == "workspace" then
                local rule = parse_workspace_rule(value)
                if rule then table.insert(workspace_rules, rule) end
            end
        end
    end
    f:close()
end

local home = os.getenv("HOME") or ""
load(home .. "/.config/hypr/monitors.conf")
load(home .. "/.config/hypr/workspaces.conf")
load(home .. "/.config/hypr/monitors.override.conf")

for _, name in ipairs(monitor_order) do
    hl.monitor(monitor_specs[name])
end
for _, rule in ipairs(workspace_rules) do
    hl.workspace_rule(rule)
end
