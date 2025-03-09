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
---@return string[]
local function make_comment(text, tab)
  local tab = tab or '---'
  local text = decode_text(text or '')

  local lines = text == '' and { text } or utils.get_lines(text)
  local result = {}

  for index, line in ipairs(lines) do
    result[index] = tab .. "    " .. line
    index = index + 1
  end

  result[1] = tab .. lines[1]

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

---Define defold unique userdata class
---@param name string
---@return string
local function make_defold_type_definition(name)
  local content = ""
  content = content .. string.format('record %s is defold_type, userdata', name)
  content = content .. string.format('\n\twhere self.type == "%s"', name)
  return content
end

---Make an module with internal stuff
---@return string[]
local function make_internal()
  local content = {
    'global interface defold_type',
    '\ttype: string',
    'end',
    '',
    make_defold_type_definition('hashed'),
    'end',
    '',
    make_defold_type_definition('constant'),
    'end',
    '',
    '---hashes a string',
    '---s string to hash',
    '---return a hashed string',
    'global function hash(_: string): hashed end',
    '',
    '---get hex representation of a hash value as a string',
    '---h hash value to get hex string for',
    '---return hex representation of the hash',
    'global function hash_to_hex(_: hashed): string end',
    '',
    '---pretty printing',
    '---v value to print',
    'global function pprint(...: any)',
    '\tprint(...)',
    'end',
  }
  return content
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

---Make annotable func lines
---@param element element
---@return content_line
local function make_func(element)
  local generic = config.generics[element.name]
  local generic_occuriences = 0
  assert(not generic)

  local content = { '' }
  local params = {}
  local returns = {}

  internal.content_append(content, make_comment(element.brief))
  --internal.content_append(content, make_comment(element.description))

  for _, parameter in ipairs(element.parameters) do
    local unpacked = internal.param_from_doc(parameter)
    local param_text = string.format("%s %s", unpacked.name, parameter.doc)
    local param_code = internal.param_to_string(unpacked)

    internal.content_append(content, make_comment(param_text))
    table.insert(params, param_code)
  end

  for _, returnvalue in ipairs(element.returnvalues) do
    local unpacked = internal.param_from_doc(returnvalue)
    local return_text = string.format("return %s", returnvalue.doc)
    local return_code = internal.param_to_string(unpacked, true)

    internal.content_append(content, make_comment(return_text))
    table.insert(returns, return_code)
  end

  local params_combined = table.concat(params, ', ')
  local returns_combined = table.concat(returns, ', ')
  local func
  if returns_combined ~= "" then
    func = string.format("%s: function(%s): %s", element.name, params_combined, returns_combined)
  else
    func = string.format("%s: function(%s)", element.name, params_combined)
  end
  internal.content_append(content, func)

  return content
end

---Make an annotable alias
---@param element element
---@return content_line
local function make_alias(element)
  local content
  if element.alias == "userdata" then
    content = make_defold_type_definition(element.name) .. 'end'
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
      local params = internal.param_from_string(type)
      if comment ~= "" then
        content_fields[index] = make_comment(comment, "--")
        index = index + 1
      end
      content_fields[index] = string.format('%s: %s', field_name, params.types)
      index = index + 1
    end)
  end

  local content_operators = {}
  index = 1

  if operators then
    internal.foreach_stable(operators, function(operator_name, operator)
      local params = internal.param_from_string(operator.param)
      local returns = internal.param_from_string(operator.result)
      content_operators[index] = string.format("%s: function(%s): %s", operator_name, params.types, returns.types)
      index = index + 1
    end)
  end

  local content = {
    '',
    string.format('record %s is defold_type, userdata', name),
    string.format('\twhere self.type == "%s"', name),
    '',
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
    FUNCTION = make_func,
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
    go = true,
  }
  if not allowed[module.info.namespace] then
    module.elements = {}
    return
  end

  -- filter out unnessesary
  local skip = {
    builtins = true,
  }
  if skip[module.info.namespace] then
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

  -- remove blacklisted functions
  remove_elements(module, function (v)
    return utils.is_blacklisted(config.ignored_funcs, v.name)
  end)

  if module.info.namespace == "meta" then
    -- delete some strange stuff
    local toremove = {
      array = true,
      bool = true,
      float = true,
      render_target = true,
      resource_handle = true,
      hash = true,
      constant = true,
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
    globalize(make_internal()),
    globalize(generate_api(root_group)),
  }
  local strings = internal.content_stringify(content)

  -- write file
  local api_path = config.api_folder .. config.folder_separator .. 'defold.d.tl'
  utils.save_file_lines(strings, api_path)

  print('-- Teal Annotations Generated Successfully!\n')
end

return generator
