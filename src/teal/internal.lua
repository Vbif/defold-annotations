--[[
  teal/internal.lua
  github.com/astrochili/defold-annotations

  Copyright (c) 2023 Roman Silin
  MIT license. See LICENSE for details.
--]]

---@class generator_teal_internal
local internal = {}

--
-- Local

---Make simple string array from content (helper)
---@param result string[]
---@param index number
---@param content content
---@param prefix string?
---@return number
local function content_stringify_internal(result, index, content, prefix)
  local next_prefix = prefix and prefix .. '\t' or ''

  for _, line in ipairs(content) do
    if type(line) == 'string' then
      index = index + 1
      result[index] = prefix .. line
    else
      index = content_stringify_internal(result, index, line, next_prefix)
    end
  end

  return index
end

--
-- Public

---Append second table to the first one
---@param content content
---@param line content_line
function internal.content_append(content, line)
  local size = #content
  if type(line) == 'string' then
    content[size + 1] = line
  else
    for index, value in ipairs(line) do
      content[size + index] = value
    end
  end
end

---Make simple string array from content
---@param content content
---@return string[]
function internal.content_stringify(content)
  local result = {}
  content_stringify_internal(result, 0, content)
  return result
end

return internal