--[[
  teal/internal.lua
  github.com/astrochili/defold-annotations

  Copyright (c) 2023 Roman Silin
  MIT license. See LICENSE for details.
--]]

local utils = require 'src.utils'
local config = require 'src.config'

---@class generator_teal_internal
local internal = {}

--
-- Local

---Split string to string array of types
---@param type string
---@return string[]
local function split_type(type)
  local list = {}
  for value in string.gmatch(type, "([^|]+)") do
    table.insert(list, value)
  end
  return list
end

---Convert Lua annotation type to Teal
---@param type string
---@return string
local function convert_type_single(type)
  local list = {}
  while true do
    local last_two = string.sub(type, -2)
    if last_two == "[]" then
      table.insert(list, "array")
      type = string.sub(type, 1, -3)
    else
      break
    end
  end
  for index, value in ipairs(list) do
    if value == "array" then
      type = string.format("{%s}", type)
    end
  end
  return type
end

---Change some strange types
---@param types table<string, boolean>
local function correct_types_wrong(types)
  local dojob = function (changes)
    for before, after in pairs(changes) do
      if types[before] then
        types[before] = nil
        local new_types = split_type(after)
        for _, value in ipairs(new_types) do
          types[value] = true
        end
      end
    end
  end

  dojob(config.global_type_replacements)

  local changes = {
    ["function(self, url, property)"] = "function(self, url, hash)",
    ["bool"] = "boolean",
  }
  dojob(changes)
end

---Fuse every userdata for now
---@param types table<string, boolean>
local function correct_types_userdata(types)
  local userdata_types = {
    "vector3", "vector4", "quaternion", "hash", "url", "constant"
  }
  local userdata_count = 0
  for _, value in ipairs(userdata_types) do
    if types[value] then
      userdata_count = userdata_count + 1
    end
  end

  if userdata_count > 1 then
    for _, value in ipairs(userdata_types) do
      types[value] = nil
    end
    types["any"] = true
  end
end

---Apply variaty of rules to transform lua to teal types\
---@param types string[]
---@return string
local function correct_types(types)
  local map = {}
  for _, value in ipairs(types) do
    map[value] = true
  end

  correct_types_wrong(map)
  correct_types_userdata(map)

  types = {}
  for key, _ in pairs(map) do
    local corrected_teal = convert_type_single(key)
    table.insert(types, corrected_teal)
  end
  table.sort(types)

  return table.concat(types, "|")
end

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

---Iterate over table in stable order
---@param t table
---@param callback function(string, table)
function internal.foreach_stable(t, callback)
  local keys = utils.sorted_keys(t)
  for _, key in ipairs(keys) do
    callback(key, t[key])
  end
end

---Make param structure from document representation
---@param parameter parameter
---@return teal_param
function internal.param_from_doc(parameter)
  local name = parameter.name
  local is_optional = false
  local types = ""

  if name:sub(1, 1) == '[' and name:sub(-1) == ']' then
    is_optional = true
    name = name:sub(2, #name - 1)
  end

  types = correct_types(parameter.types)

  return {
    name = name,
    is_optional = is_optional,
    types = types
  }
end

---Make param structure from string representation
---@param text string
---@return teal_param
function internal.param_from_string(text)
  text = text or ""
  text = string.gsub(text, "%s+", "")

  local types = split_type(text)
  local type_string = correct_types(types)

  return {
    name = "",
    is_optional = false,
    types = type_string
  }
end

---Convert param to string representation
---@param param teal_param
---@param skip_name? boolean
---@return string
function internal.param_to_string(param, skip_name)
  if skip_name then
    return param.types
  end

  if param.is_optional then
    return string.format("%s?: %s", param.name, param.types)
  end

  return string.format("%s: %s", param.name, param.types)
end

return internal
