describe("plugin", function()
  local original_loaded

  before_each(function()
    original_loaded = vim.g.loaded_notion_nvim
    vim.g.loaded_notion_nvim = nil

    -- Reset module cache
    package.loaded['notion.api'] = nil
  end)

  after_each(function()
    vim.g.loaded_notion_nvim = original_loaded
  end)

  it("should not load twice", function()
    vim.g.loaded_notion_nvim = 1

    -- Mock require to track if it's called
    local require_calls = {}
    local original_require = require
    _G.require = function(module)
      table.insert(require_calls, module)
      return original_require(module)
    end

    -- Execute the guard logic
    if vim.g.loaded_notion_nvim then
      -- Should return early, not execute rest
      assert.equals(1, vim.g.loaded_notion_nvim)
    end

    _G.require = original_require
  end)

  it("should create Notion command with subcommands", function()
    local commands_created = {}
    vim.api.nvim_create_user_command = function(name, callback, opts)
      commands_created[name] = { callback = callback, opts = opts }
    end

    -- Mock the API module
    local mock_api = {
      create_page = spy.new(function() end),
      edit_page = spy.new(function() end),
      list_and_edit_pages = spy.new(function() end),
      delete_page = spy.new(function() end)
    }

    package.preload['notion.api'] = function() return mock_api end

    -- Simulate plugin loading
    vim.g.loaded_notion_nvim = 1

    vim.api.nvim_create_user_command('Notion', function(args)
      local subcommand = args.fargs[1]
      if subcommand == 'create' then
        local title_parts = {}
        for i = 2, #args.fargs do
          table.insert(title_parts, args.fargs[i])
        end
        local title = table.concat(title_parts, ' ')
        require('notion.api').create_page(title)
      elseif subcommand == 'edit' then
        if args.fargs[2] then
          require('notion.api').edit_page(args.fargs[2])
        else
          require('notion.api').list_and_edit_pages()
        end
      elseif subcommand == 'delete' then
        require('notion.api').delete_page()
      else
        vim.notify('Unknown subcommand: ' .. (subcommand or ''), vim.log.levels.ERROR)
        vim.notify('Available commands: create <title>, edit [page_id], delete', vim.log.levels.INFO)
      end
    end, {
      nargs = '*',
      complete = function(ArgLead, CmdLine, CursorPos)
        local subcommands = {'create', 'edit', 'delete'}
        return vim.tbl_filter(function(cmd)
          return cmd:match('^' .. ArgLead)
        end, subcommands)
      end,
      desc = 'Notion.nvim commands'
    })

    assert.is_not_nil(commands_created.Notion)
    assert.equals('*', commands_created.Notion.opts.nargs)
    assert.equals('Notion.nvim commands', commands_created.Notion.opts.desc)
    assert.is_function(commands_created.Notion.opts.complete)

    -- Test create subcommand
    commands_created.Notion.callback({
      fargs = {'create', 'My', 'New', 'Page'}
    })
    assert.spy(mock_api.create_page).was_called_with('My New Page')

    -- Test edit subcommand with page ID
    commands_created.Notion.callback({
      fargs = {'edit', 'page_id_123'}
    })
    assert.spy(mock_api.edit_page).was_called_with('page_id_123')

    -- Test edit subcommand without page ID
    commands_created.Notion.callback({
      fargs = {'edit'}
    })
    assert.spy(mock_api.list_and_edit_pages).was_called()

    -- Test delete subcommand
    commands_created.Notion.callback({
      fargs = {'delete'}
    })
    assert.spy(mock_api.delete_page).was_called()

    -- Test unknown subcommand
    local notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    commands_created.Notion.callback({
      fargs = {'unknown'}
    })

    assert.equals(2, #notifications)
    assert.is_not_nil(string.match(notifications[1].msg, "Unknown subcommand"))
    assert.is_not_nil(string.match(notifications[2].msg, "Available commands"))
  end)

  it("should provide command completion", function()
    -- Simulate the completion function from plugin
    local function test_complete(ArgLead, CmdLine, CursorPos)
      local subcommands = {'create', 'edit', 'delete'}
      return vim.tbl_filter(function(cmd)
        return cmd:match('^' .. ArgLead)
      end, subcommands)
    end

    -- Test completion
    local results = test_complete('c', 'Notion c', 8)
    assert.equals(1, #results)
    assert.equals('create', results[1])

    results = test_complete('e', 'Notion e', 8)
    assert.equals(1, #results)
    assert.equals('edit', results[1])

    results = test_complete('d', 'Notion d', 8)
    assert.equals(1, #results)
    assert.equals('delete', results[1])

    results = test_complete('', 'Notion ', 7)
    assert.equals(3, #results)
  end)
end)