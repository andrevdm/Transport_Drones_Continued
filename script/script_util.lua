local util = require("util")

local deregister_gui_internal
deregister_gui_internal = function(gui_element, data)
  data[gui_element.index] = nil
  for k, child in pairs (gui_element.children) do
    deregister_gui_internal(child, data)
  end
end

util.deregister_gui = function(gui_element, data)
  local player_data = data[gui_element.player_index]
  if not player_data then return end
  deregister_gui_internal(gui_element, player_data)
end

util.register_gui = function(data, gui_element, param)
  local player_data = data[gui_element.player_index]
  if not player_data then
    data[gui_element.player_index] = {}
    player_data = data[gui_element.player_index]
  end
  player_data[gui_element.index] = param
end


util.distance = function(p1, p2)
  return (((p1.x - p2.x) ^ 2) + ((p1.y - p2.y) ^ 2)) ^ 0.5
end

util.copy = util.table.deepcopy

util.angle = function(position_1, position_2)
  local d_x = (position_2[1] or position_2.x) - (position_1[1] or position_1.x)
  local d_y = (position_2[2] or position_2.y) - (position_1[2] or position_1.y)
  return math.atan2(d_y, d_x)
end


--- Split string at a separator character, respecting parenthesis depth.
local function split_at(str, sep)
  local parts = {}
  local depth = 0
  local start = 1
  for i = 1, #str do
    local c = str:sub(i, i)
    if c == "(" then depth = depth + 1
    elseif c == ")" then depth = depth - 1
    elseif c == sep and depth == 0 then
      parts[#parts + 1] = str:sub(start, i - 1)
      start = i + 1
    end
  end
  parts[#parts + 1] = str:sub(start)
  return parts
end

--- Convert infix bitwise operators (|, &, ~, $) to bit32 function calls.
-- Precedence (low to high): OR (|), XOR ($), AND (&), NOT (~)
local function process_bitwise(expr)
  -- OR (lowest precedence)
  local parts = split_at(expr, "|")
  if #parts > 1 then
    for i, p in ipairs(parts) do parts[i] = process_bitwise(p) end
    return "bor(" .. table.concat(parts, ",") .. ")"
  end
  -- XOR
  parts = split_at(expr, "$")
  if #parts > 1 then
    for i, p in ipairs(parts) do parts[i] = process_bitwise(p) end
    return "bxor(" .. table.concat(parts, ",") .. ")"
  end
  -- AND
  parts = split_at(expr, "&")
  if #parts > 1 then
    for i, p in ipairs(parts) do parts[i] = process_bitwise(p) end
    return "band(" .. table.concat(parts, ",") .. ")"
  end
  -- NOT (prefix, consumes everything at this precedence level)
  if expr:sub(1, 1) == "~" then
    return "bnot(" .. process_bitwise(expr:sub(2)) .. ")"
  end
  -- Process parenthesized sub-expressions
  return (expr:gsub("%b()", function(m)
    return "(" .. process_bitwise(m:sub(2, -2)) .. ")"
  end))
end

--- Parse math expressions from text input fields.
-- Supports: plain numbers, suffixes (2k, 1.5m), arithmetic (+, -, *, /),
-- bitwise operators (AND/&, OR/|, NOT/~, XOR), parentheses, and combinations.
-- Returns a number or nil if the input is invalid.
util.parse_math_input = function(text)
  if not text or text == "" then return nil end
  local plain = tonumber(text)
  if plain then return plain end
  -- Normalize: lowercase, strip spaces
  local expr = text:lower():gsub("%s+", "")
  -- Expand suffixes: 2k -> 2000, 1.5m -> 1500000
  expr = expr:gsub("([%d%.]+)m", function(n) return tostring((tonumber(n) or 0) * 1000000) end)
  expr = expr:gsub("([%d%.]+)k", function(n) return tostring((tonumber(n) or 0) * 1000) end)
  -- Normalize C-style operators to single-char symbols (before word replacement)
  expr = expr:gsub("||", "|"):gsub("&&", "&"):gsub("!=", "~"):gsub("!", "~")
  -- Replace word operators with symbols (xor before or to avoid substring match)
  expr = expr:gsub("xor", "\1"):gsub("and", "&"):gsub("not", "~"):gsub("or", "|"):gsub("\1", "$")
  -- Process bitwise operators into function calls if present
  if expr:match("[|&~%$]") then
    expr = process_bitwise(expr)
  end
  -- Validate: only digits, dots, arithmetic, parens, commas, and bit32 function names
  if expr:match("[^%d%.%+%-%*/%(%)%%,abandortx]") then return nil end
  local env = {band = bit32.band, bor = bit32.bor, bnot = bit32.bnot, bxor = bit32.bxor}
  local fn = load("return " .. expr, nil, "t", env)
  if not fn then return nil end
  local ok, result = pcall(fn)
  if ok and type(result) == "number" and result == result then return result end
  return nil
end

return util
