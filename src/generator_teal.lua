--[[
  generator.lua
  github.com/astrochili/defold-annotations

  Copyright (c) 2023 Roman Silin
  MIT license. See LICENSE for details.
--]]

local html_entities = require 'libs.html_entities'
local config = require 'src.config'
local utils = require 'src.utils'
local terminal = require 'src.terminal'

local generator = {}

--
-- Local

---Decode text to get rid of html tags and entities
---@param text string
---@return string
local function decode_text(text)
  local result = text:gsub('%b<>', '')
  local decoded_result = html_entities.decode(result)

  if type(decoded_result) == 'string' then
    result = decoded_result
  end

  return result
end

---Change . to _ in class names
---@param name string
---@return string
local function corect_name(name)
  local res, _ = string.gsub(name, '%.', '_')
  return res
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
  type = corect_name(type)
  for index, value in ipairs(list) do
    if value == "array" then
      type = string.format("{%s}", type)
    end
  end
  return type
end

---Convert Lua annotation type to Teal
---@param type string
---@return string
local function convert_type(type)
  type = string.gsub(type, "%s+", "")
  local types = {}
  for value in string.gmatch(type, "([^|]+)") do
    local conv = convert_type_single(value)
    table.insert(types, conv)
  end
  return table.concat(types, "|")
end

---Split string with type and comment to separate strings
---@param text string
---@return string type
---@return string comment
local function split_type_comment(text)
  local index = string.find(text, " ")
  if index then
    return string.sub(text, 1, index), string.sub(text, index)
  else
    return text, ""
  end
end

---Make an annotable comment
---@param text string
---@param tab? string Indent string, default is '---'
---@return string
local function make_comment(text, tab)
  local tab = tab or '---'
  local text = decode_text(text or '')

  local lines = text == '' and { text } or utils.get_lines(text)
  local result = ''

  for index, line in ipairs(lines) do
    result = result .. tab .. line

    if index < #lines then
      result = result .. '\n'
    end
  end

  return result
end

---Make an annotable global header
---@param defold_version string
---@return string
local function make_global_header(defold_version)
  local result = ''

  result = result .. '--[[\n'
  result = result .. '  Generated with ' .. config.generator_url .. '\n'
  result = result .. '  Defold ' .. defold_version .. '\n'
  result = result .. '--]]\n\n'

  return result
end

---Make an annotable module header
---@param title string
---@param description string
---@return string
local function make_module_header(title, description)
  local result = ''

  result = result .. '--[[\n'
  result = result .. '  ' .. decode_text(title) .. '\n'

  if description and description ~= title then
    result = result .. '\n'
    result = result .. make_comment(description, '  ') .. '\n'
  end

  result = result .. '--]]'

  return result
end

---Wrap the class body to an annotable namespace
---@param name string
---@param body string
---@return string
local function make_namespace(name, body)
  local result = ''

  result = result .. '---@class defold_api.' .. name .. '\n'
  result = result .. name .. ' = {}\n\n'
  result = result .. body .. '\n\n'
  result = result .. 'return ' .. name

  return result
end

---Make an annotatable constant
---@param element element
---@return string
local function make_const(element)
  local result = ''

  result = result .. make_comment(element.description) .. '\n'
  result = result .. element.name .. ' = nil'

  return result
end

---Make an annotatable param name
---@param parameter table
---@param is_return boolean
---@param element element
---@return string name
---@return boolean is_optional
local function make_param_name(parameter, is_return, element)
  local name = parameter.name
  local is_optional = false

  if name:sub(1, 1) == '[' and name:sub(-1) == ']' then
    is_optional = true
    name = name:sub(2, #name - 1)
  end

  name = config.global_name_replacements[name] or name

  local local_replacements = config.local_name_replacements[element.name] or {}
  name = local_replacements[(is_return and 'return_' or 'param_') .. name] or name

  if name:sub(-3) == '...' then
    name = '...'
  end

  name = name:gsub('-', '_')

  return name, is_optional
end

---Make annotatable param types
---@param name string
---@param types table
---@param is_optional boolean
---@param is_return boolean
---@param element element
---@return string concated_string
local function make_param_types(name, types, is_optional, is_return, element)
  local local_replacements = config.local_type_replacements[element.name] or {}

  for index = 1, #types do
    local type = types[index]
    local is_known = false

    local replacement = config.global_type_replacements[type] or type
    replacement = local_replacements[(is_return and 'return_' or 'param_') .. type .. '_' .. name] or replacement

    if replacement then
      type = replacement
      is_known = true
    end

    for _, known_type in ipairs(config.known_types) do
      is_known = is_known or type == known_type
    end

    local known_classes = utils.sorted_keys(config.known_classes)
    for _, known_class in ipairs(known_classes) do
      is_known = is_known or type == known_class
    end

    local known_aliases = utils.sorted_keys(config.known_aliases)
    for _, known_alias in ipairs(known_aliases) do
      is_known = is_known or type == known_alias
    end

    is_known = is_known or type:sub(1, 9) == 'function('

    if not is_known then
      types[index] = config.unknown_type
    else
      type = type:gsub('function%(%)', 'function')

      if type:sub(1, 9) == 'function(' then
        type = 'fun' .. type:sub(9)
      end

      types[index] = type
    end
  end

  if is_optional then
    local is_already_optional = false

    for _, type in ipairs(types) do
      is_already_optional = is_already_optional or type == 'nil'
    end

    if not is_already_optional then
      table.insert(types, 'nil')
    end
  end

  local result = table.concat(types, '|')
  result = #result > 0 and result or config.unknown_type

  return result
end

---Make an annotable param description
---@param description string
---@return string
local function make_param_description(description)
  local result = decode_text(description)
  result = result:gsub('\n', '\n---')
  return result
end

---Make annotable param line
---@param parameter table
---@param element element
---@return string
local function make_param(parameter, element)
  local name, is_optional = make_param_name(parameter, false, element)
  local joined_types = make_param_types(name, parameter.types, is_optional, false, element)
  local description = make_param_description(parameter.doc)

  return '---@param ' .. name .. ' ' .. joined_types .. ' ' .. description
end

---Make an annotable return line
---@param returnvalue table
---@param element element
---@return string
local function make_return(returnvalue, element)
  local name, is_optional = make_param_name(returnvalue, true, element)
  local types = make_param_types(name, returnvalue.types, is_optional, true, element)
  local description = make_param_description(returnvalue.doc)

  return '---@return ' .. types .. ' ' .. name .. ' ' .. description
end

---Make annotable func lines
---@param element element
---@return string?
local function make_func(element)
  if utils.is_blacklisted(config.ignored_funcs, element.name) then
    return
  end

  local comment = make_comment(element.description) .. '\n'

  local generic = config.generics[element.name]
  local generic_occuriences = 0

  local params = ''
  for _, parameter in ipairs(element.parameters) do
    local param = make_param(parameter, element)
    local count = 0

    if generic then
      param, count = param:gsub(' ' .. generic .. ' ', ' T ')
      generic_occuriences = generic_occuriences + count
    end

    params = params .. param .. '\n'
  end

  local returns = ''
  for _, returnvalue in ipairs(element.returnvalues) do
    local return_ = make_return(returnvalue, element)
    local count = 0

    if generic then
      return_, count = return_:gsub(' ' .. generic .. ' ', ' T ')
      generic_occuriences = generic_occuriences + count
    end

    returns = returns .. return_ .. '\n'
  end

  if generic_occuriences >= 2 then
    generic = ('---@generic T: ' .. generic .. '\n')
  else
    generic = ''
  end

  local func_params = {}

  for _, parameter in ipairs(element.parameters) do
    local name = make_param_name(parameter, false, element)
    table.insert(func_params, name)
  end

  local func = 'function ' .. element.name .. '(' .. table.concat(func_params, ', ') .. ') end'
  local result = comment .. generic .. params .. returns .. func

  return result
end

---Make an annotable alias
---@param element element
---@return string
local function make_alias(element)
  if element.alias == "userdata" then
    return string.format("global record %s is userdata end", element.name)
  end
  return string.format("global type %s = %s", element.name, element.alias)
end

---Make an annnotable class declaration
---@param element element
---@return string
local function make_class(element)
  local name = corect_name(element.name)
  local fields = element.fields
  assert(fields)

  if fields.is_global == true then
    return ''
  end

  local result = ''
  result = result .. string.format('global record %s \n', name)

  -- if fields.is_global == true then
  --   fields.is_global = nil
  --   result = result .. name .. ' = {}'
  -- end

  local field_names = utils.sorted_keys(fields)
  for _, field_name in ipairs(field_names) do
    local type = fields[field_name]
    local comment = ""
    type, comment = split_type_comment(type)
    type = convert_type(type)
    if comment ~= "" then
      result = result .. make_comment(comment, "\t--") .. '\n'
    end
    result = result .. string.format('\t%s: %s\n', field_name, type)
  end

  result = result .. 'end'

  -- local operators = element.operators

  -- if operators then
  --   local operator_names = utils.sorted_keys(operators)

  --   result = result .. '\n'

  --   for index, operator_name in ipairs(operator_names) do
  --     local operator = operators[operator_name]

  --     if operator.param then
  --       result = result .. '---@operator ' .. operator_name .. '(' .. operator.param .. '): ' .. operator.result
  --     else
  --       result = result .. '---@operator ' .. operator_name .. ': ' .. operator.result
  --     end

  --     if index < #operator_names then
  --       result = result .. '\n'
  --     end
  --   end
  -- end

  return result
end

---Generate API module
---@param module module
---@return string
local function generate_api(module)
  local content = make_module_header(module.info.brief, module.info.description)
  content = content .. '\n\n'

  local makers = {
    FUNCTION = make_func,
    VARIABLE = make_const,
    BASIC_CLASS = make_class,
    BASIC_ALIAS = make_alias
  }

  local elements = {}
  -- local namespace_is_required = false

  for _, element in ipairs(module.elements) do
    if makers[element.type] ~= nil then
      table.insert(elements, element)
    end

    -- if not namespace_is_required then
    --   local element_has_namespace = element.name:sub(1, #module.info.namespace) == module.info.namespace
    --   namespace_is_required = element_has_namespace
    -- end
  end

  if #elements == 0 then
    print('[-] The module "' .. module.info.namespace .. '" is skipped because there are no known elements')
    return ""
  end

  table.sort(elements, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    else
      return a.type < b.type
    end
  end)

  local body = ''

  for index, element in ipairs(elements) do
    local maker = makers[element.type]
    local text = maker(element)

    if text then
      body = body .. text

      -- if index < #elements then
      --   local newline = element.type == 'BASIC_ALIAS' and '\n' or '\n\n'
      --   body = body .. newline
      -- end
      body = body .. '\n\n'
    end
  end

  -- if namespace_is_required then
  --   content = content .. make_namespace(module.info.namespace, body)
  -- else
  --   content = content .. body
  -- end
  content = content .. body

  return content
end

---Removes elements with match callback
---@param module module
---@param match function(element):boolean
local function remove_elements(module, match)
  local new_elements = {}
  for i, v in ipairs(module.elements) do
    if not match(v) then
      table.insert(new_elements, v)
    end
  end
  module.elements = new_elements
end

---Change something in module for teal. Trying to put everything ugly here
---@param module module
local function patch(module)

  local allowed = {
    meta = true,
  }

  if not allowed[module.info.namespace] then
    module.elements = {}
    return
  end

  -- skip all editor stuff for now
  remove_elements(module, function (v)
    return string.sub(v.name, 1, 6) == 'editor'
  end)

  if module.info.namespace == "meta" then
    -- delete some strange stuff
    local toremove = {
      array = true,
      bool = true,
      float = true,
      render_target = true,
      quaternion = true,
      resource_handle = true,
    }
    remove_elements(module, function (v)
      return toremove[v.name]
    end)
  end
end

--
-- Public

---Generate API modules in one d.tl file
---@param modules module[]
---@param defold_version string like '1.0.0'
function generator.generate_api(modules, defold_version)
  print('-- Teal Annotations Generation')

  local api_path = config.api_folder .. config.folder_separator .. 'defold.d.tl'
  local header = make_global_header(defold_version)
  utils.append_file(header, api_path)

  for _, module in ipairs(modules) do
    patch(module)
    local content = generate_api(module)
    utils.append_file(content, api_path)
  end

  print('-- Teal Annotations Generated Successfully!\n')
end

return generator
