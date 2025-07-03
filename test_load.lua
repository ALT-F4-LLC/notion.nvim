--[[
Test loader for notion.nvim local development

This script unloads any existing notion.nvim plugin and loads the local version
from the current directory for testing purposes.

Usage (within Neovim):
  :luafile test_load.lua
  or
  :lua dofile('test_load.lua')
  or
  :lua require('test_load').reload()

Features:
- Unloads existing notion.nvim plugin completely
- Loads the local version from current directory
- Enables debug mode for detailed timing info
- Verifies all commands and modules are working
- Provides helpful usage information
--]]

local M = {}

-- Function to clear/unload existing plugin
local function unload_plugin()
    -- Clear global plugin loaded flag
    vim.g.loaded_notion_nvim = nil

    -- Clear all notion-related modules from package.loaded
    local modules_to_clear = {
        'notion',
        'notion.api',
        'notion.config',
        'notion.init'
    }

    for _, module in ipairs(modules_to_clear) do
        package.loaded[module] = nil
    end

    -- Clear user commands if they exist
    local commands_to_clear = {
        'Notion',
        'NotionCreate',
        'NotionEdit',
        'NotionSync',
        'NotionBrowser',
        'NotionDelete'
    }

    for _, cmd in ipairs(commands_to_clear) do
        pcall(vim.api.nvim_del_user_command, cmd)
    end

    print("✓ Unloaded existing notion.nvim plugin")
end

-- Function to load local plugin
local function load_local_plugin()
    local current_dir = vim.fn.getcwd()
    local lua_path = current_dir .. '/lua'
    local plugin_path = current_dir .. '/plugin'

    -- Force clear all notion modules first
    for module_name, _ in pairs(package.loaded) do
        if module_name:match('^notion') then
            package.loaded[module_name] = nil
        end
    end

    -- Directly load local files using dofile instead of require
    local function load_local_module(module_path, module_name)
        local file_path = lua_path .. '/' .. module_path
        if vim.fn.filereadable(file_path) == 1 then
            local chunk, err = loadfile(file_path)
            if chunk then
                local module = chunk()
                package.loaded[module_name] = module
                return module
            else
                error("Failed to load " .. file_path .. ": " .. tostring(err))
            end
        else
            error("File not found: " .. file_path)
        end
    end

    -- Load modules in dependency order
    print("Loading local modules directly...")

    -- Load config first
    local config = load_local_module('notion/config.lua', 'notion.config')
    print("✓ Loaded notion.config from local file")

    -- Load api
    local api = load_local_module('notion/api.lua', 'notion.api')
    print("✓ Loaded notion.api from local file")

    -- Load init/main
    local init = load_local_module('notion/init.lua', 'notion.init')
    local notion = load_local_module('notion.lua', 'notion')
    print("✓ Loaded notion modules from local files")

    -- Setup with default configuration for testing
    notion.setup({
        debug = true,       -- Enable debug mode for testing
        sync_debounce_ms = 500, -- Faster sync for testing
    })

    -- Load the plugin file that defines the main :Notion command
    local plugin_file = plugin_path .. '/notion.lua'
    if vim.fn.filereadable(plugin_file) == 1 then
        local plugin_ok, plugin_err = pcall(dofile, plugin_file)
        if not plugin_ok then
            print("✗ Failed to load plugin file: " .. tostring(plugin_err))
            return false
        end
        print("✓ Loaded plugin commands from: " .. plugin_path)
    else
        print("✗ Plugin file not found: " .. plugin_file)
        return false
    end

    -- Verify we're using the local API
    local api_module = package.loaded['notion.api']
    if api_module and api_module.edit_page then
        local debug_info = debug.getinfo(api_module.edit_page, 'S')
        if debug_info and debug_info.source then
            print("✓ Verified notion.api loaded from: " .. debug_info.source)
        end
    end

    print("✓ Local notion.nvim plugin successfully loaded!")
    return true
end

-- Function to verify plugin is loaded
local function verify_plugin()
    -- Check if commands exist
    local commands = {
        'Notion',
        'NotionCreate',
        'NotionEdit',
        'NotionSync',
        'NotionBrowser',
        'NotionDelete'
    }

    local missing_commands = {}
    for _, cmd in ipairs(commands) do
        local ok, cmd_list = pcall(vim.api.nvim_get_commands, { builtin = false })
        local exists = ok and cmd_list and cmd_list[cmd] ~= nil
        if not exists then
            table.insert(missing_commands, cmd)
        end
    end

    if #missing_commands > 0 then
        print("✗ Missing commands: " .. table.concat(missing_commands, ', '))
        return false
    end

    -- Check if modules are loaded
    local modules = { 'notion', 'notion.api', 'notion.config' }
    for _, module in ipairs(modules) do
        if not package.loaded[module] then
            print("✗ Module not loaded: " .. module)
            return false
        end
    end

    print("✓ All commands and modules verified")
    return true
end

-- Main function
function M.reload()
    print("=== Reloading notion.nvim for local testing ===")

    unload_plugin()

    if load_local_plugin() then
        if verify_plugin() then
            print("✓ Local notion.nvim successfully loaded and verified!")
            print("")
            print("Available commands:")
            print("  :Notion create <title>  - Create new page")
            print("  :Notion edit [id]       - Edit existing page")
            print("  :Notion delete          - Delete page")
            print("  :NotionBrowser          - Open in browser")
            print("  :NotionSync             - Manual sync")
            print("")
            print("Debug mode is enabled - you'll see detailed timing info.")
        else
            print("✗ Plugin verification failed")
        end
    else
        print("✗ Failed to load local plugin")
    end
end

-- Auto-run when file is loaded
M.reload()

return M
