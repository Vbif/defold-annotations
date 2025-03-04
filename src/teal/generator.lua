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
local internal = require 'src.teal.internal'

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
---@return string[]
local function make_global_header(defold_version)
  local result = {}

  result[1] = string.format('--[[')
  result[2] = string.format('  Generated with %s', config.generator_url)
  result[3] = string.format('  Defold %s', defold_version)
  result[4] = string.format('--]]')
  result[5] = ''

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
---@return content_line
local function make_alias(element)
  local content
  if element.alias == "userdata" then
    content = string.format("global record %s is userdata end", element.name)
  else
    content = string.format("global type %s = %s", element.name, element.alias)
  end
  return content
end

---Make an annnotable class declaration
---@param element element
---@return content_line
local function make_class(element)
  local name = element.name
  local fields = element.fields
  local operators = element.operators
  assert(fields)

  local content_fields = {}
  local index = 1

  if fields then
    internal.foreach_stable(fields, function(field_name, type)
      local comment = ""
      type, comment = split_type_comment(type)
      type = convert_type(type)
      if comment ~= "" then
        content_fields[index] = make_comment(comment, "--")
        index = index + 1
      end
      content_fields[index] = string.format('%s: %s', field_name, type)
      index = index + 1
    end)
  end

  local content_operators = {}
  index = 1

  if operators then
    internal.foreach_stable(operators, function(operator_name, operator)
      local params = {}
      if operator.param then
        table.insert(params, operator.param)
      end
      local func_params = table.concat(params, ", ")
      content_operators[index] = string.format("%s: function(%s): %s", operator_name, func_params, operator.result)
      index = index + 1
    end)
  end

  local content = {
    '',
    string.format('record %s is userdata', name),
    content_fields,
    content_operators,
    'end',
  }
  return content
end

---Generate API module
---@param group element_group
---@return content
local function generate_api(group)

  local makers = {
    -- FUNCTION = make_func,
    -- VARIABLE = make_const,
    BASIC_CLASS = make_class,
    BASIC_ALIAS = make_alias
  }

  local type_order = {
    FUNCTION = 4,
    VARIABLE = 3,
    BASIC_CLASS = 1,
    BASIC_ALIAS = 2,
    PROPERTY = 0,
    MESSAGE = 0,
  }
  local elements = group.elements
  table.sort(elements, function(a, b)
    if a.type == b.type then
      return a.name < b.name
    else
      return type_order[a.type] < type_order[b.type]
    end
  end)

  local content = {}

  for _, element in ipairs(elements) do
    local maker = makers[element.type]
    if maker then
      local sub_content = maker(element)
      internal.content_append(content, sub_content)
    end
  end

  internal.foreach_stable(group.groups, function(subgroup_name, subgroup)
    local sub_content = {
      '',
      string.format('record %s', subgroup.name),
      generate_api(subgroup),
      'end',
    }
    internal.content_append(content, sub_content)
  end)

  return content
end

---Put element in proper group
---@param group element_group
---@param element element
local function sift_element(group, element)
  --Dissect name of element
  local name_group
  local name_element = element.name
  local index = string.find(name_element, "%.")
  if index then
    name_group = string.sub(name_element, 1, index - 1)
    name_element = string.sub(name_element, index + 1)
  end

  --put recursivly in proper subgroup or inside this
  if name_group then
    local sub = group.groups[name_group]
    if not sub then
      sub = {
        name = name_group,
        elements = {},
        groups = {}
      }
      group.groups[name_group] = sub
    end

    element.name = name_element
    sift_element(sub, element)
  else
    table.insert(group.elements, element)
  end
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
local function patch_module(module)

  -- filter for developing purpose
  local allowed = {
    meta = true,
    --go = true,
  }
  if not allowed[module.info.namespace] then
    module.elements = {}
    return
  end

  -- skip all editor stuff for now
  remove_elements(module, function (v)
    return string.sub(v.name, 1, 6) == 'editor'
  end)

  -- remove empty defenitions
  remove_elements(module, function (v)
    return v.fields and v.fields.is_global == true
  end)

  if module.info.namespace == "meta" then
    -- delete some strange stuff
    local toremove = {
      array = true,
      bool = true,
      float = true,
      render_target = true,
      resource_handle = true,
    }
    remove_elements(module, function (v)
      return toremove[v.name]
    end)
  end

end

---Make all types global in definition
---@param content content
---@return content
local function globalize(content)
  for index, line in ipairs(content) do
    if type(line) == "string" then
      local sub_record = string.sub(line, 1, 6)
      local sub_type = string.sub(line, 1, 4)
      if sub_record == "record" or sub_type == "type" then
        content[index] = "global " .. line
      end
    end
  end
  return content
end

--
-- Public

---Generate API modules in one d.tl file
---@param modules module[]
---@param defold_version string like '1.0.0'
function generator.generate_api(modules, defold_version)
  print('-- Teal Annotations Generation')

  -- rearrange everything to groups
  local root_group = {
    name = "",
    elements = {},
    groups = {}
  }
  for _, module in ipairs(modules) do
    patch_module(module)
    for _, element in ipairs(module.elements) do
      sift_element(root_group, element)
    end
  end

  -- generate recursivly, add global, flattern
  local content = {
    make_global_header(defold_version),
    globalize(generate_api(root_group)),
  }
  local strings = internal.content_stringify(content)

  -- write file
  local api_path = config.api_folder .. config.folder_separator .. 'defold.d.tl'
  utils.save_file_lines(strings, api_path)

  print('-- Teal Annotations Generated Successfully!\n')
end

return generator
