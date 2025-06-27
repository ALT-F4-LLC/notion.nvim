describe("init", function()
  local init_module
  local mock_config
  local mock_api

  before_each(function()
    -- Reset module cache
    package.loaded['notion.init'] = nil
    package.loaded['notion.config'] = nil
    package.loaded['notion.api'] = nil

    -- Mock dependencies
    mock_config = {
      setup = spy.new(function() end)
    }

    mock_api = {
      create_page = spy.new(function() end),
      edit_page = spy.new(function() end),
      list_and_edit_pages = spy.new(function() end),
      sync_page = spy.new(function() end),
      open_current_page_in_browser = spy.new(function() end),
      delete_page = spy.new(function() end)
    }

    package.preload['notion.config'] = function() return mock_config end
    package.preload['notion.api'] = function() return mock_api end

    init_module = require('notion.init')
  end)

  describe("setup", function()
    it("should call config.setup with provided options", function()
      local opts = { page_size = 20, debug = true }

      init_module.setup(opts)

      assert.spy(mock_config.setup).was_called_with(opts)
    end)

    it("should call config.setup with empty table when no options provided", function()
      init_module.setup()

      assert.spy(mock_config.setup).was_called_with({})
    end)

    it("should create NotionCreate command", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      assert.is_not_nil(commands_created.NotionCreate)
      assert.equals('function', type(commands_created.NotionCreate.callback))
    end)

    it("should create NotionEdit command", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      assert.is_not_nil(commands_created.NotionEdit)
      assert.equals('function', type(commands_created.NotionEdit.callback))
    end)

    it("should create NotionSync command", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      assert.is_not_nil(commands_created.NotionSync)
      assert.equals('function', type(commands_created.NotionSync.callback))
    end)

    it("should create NotionBrowser command", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      assert.is_not_nil(commands_created.NotionBrowser)
      assert.equals('function', type(commands_created.NotionBrowser.callback))
    end)

    it("should create NotionDelete command", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      assert.is_not_nil(commands_created.NotionDelete)
      assert.equals('function', type(commands_created.NotionDelete.callback))
    end)
  end)

  describe("command callbacks", function()
    it("should call create_page with full argument string for NotionCreate", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      commands_created.NotionCreate.callback({ args = "Test Page Title" })
      assert.spy(mock_api.create_page).was_called_with("Test Page Title")
    end)

    it("should call edit_page with args for NotionEdit when args provided", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      commands_created.NotionEdit.callback({ args = "page-id" })
      assert.spy(mock_api.edit_page).was_called_with("page-id")
    end)

    it("should call list_and_edit_pages for NotionEdit when no args", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      commands_created.NotionEdit.callback({ args = "" })
      assert.spy(mock_api.list_and_edit_pages).was_called()
    end)

    it("should call sync_page for NotionSync", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      commands_created.NotionSync.callback({})
      assert.spy(mock_api.sync_page).was_called()
    end)

    it("should call open_current_page_in_browser for NotionBrowser", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      commands_created.NotionBrowser.callback({})
      assert.spy(mock_api.open_current_page_in_browser).was_called()
    end)

    it("should call delete_page for NotionDelete", function()
      local commands_created = {}
      vim.api.nvim_create_user_command = function(name, callback, opts)
        commands_created[name] = { callback = callback, opts = opts }
      end

      init_module.setup()

      commands_created.NotionDelete.callback({})
      assert.spy(mock_api.delete_page).was_called()
    end)
  end)
end)