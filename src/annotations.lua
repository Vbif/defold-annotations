--[[
  annotations.lua
  github.com/astrochili/defold-annotations

  Copyright (c) 2023 Roman Silin
  MIT license. See LICENSE for details.
--]]

---@meta

---@class module
---@field info info
---@field elements element[]

---@class info
---@field namespace string
---@field brief string
---@field description? string

---@class element
---@field type string
---@field name string
---@field description string
---@field parameters? parameter[]
---@field returnvalues? returnvalue[]
---@field alias? string
---@field fields? table
---@field operators? table

---@class parameter
---@field name string
---@field doc string

---@class element_group
---@field name string
---@field elements element[]
---@field groups table<string, element_group>

---@alias content_line string|string[]
---@alias content content_line[]
---@alias returnvalue parameter
