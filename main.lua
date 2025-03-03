--[[
  main.lua
  github.com/astrochili/defold-annotations

  Copyright (c) 2023 Roman Silin
  MIT license. See LICENSE for details.
--]]

local fetcher = require 'src.fetcher'
local parser = require 'src.parser'
local meta = require 'src.meta'
local generator_lua = require 'src.generator_lua'
local generator_teal = require 'src.teal.generator'
local terminal = require 'src.terminal'
local config = require 'src.config'

-- Fetch the Defold version
local defold_version = arg[1] or fetcher.fetch_version()

-- Fetch docs from the Github release
local json_paths = fetcher.fetch_docs(defold_version)

-- Create and append the known types and aliases module
local modules = {}
table.insert(modules, meta.make_module())

-- Parse .json files to namespace modules
parser.parse_json(json_paths, modules)

-- Clean output folder
terminal.delete_folder(config.api_folder)
terminal.create_folder(config.api_folder)

-- Generate the API folder with .lua files
generator_lua.generate_api(modules, defold_version)

-- Generate the API folder with .d.tl files
generator_teal.generate_api(modules, defold_version)
