describe("config", function()
  local config

  before_each(function()
    -- Reset module cache
    package.loaded['notion.config'] = nil
    config = require('notion.config')
  end)

  describe("defaults", function()
    it("should have correct default values", function()
      assert.is_not_nil(config)
      assert.is_not_nil(config.defaults)
      assert.is_nil(config.defaults.notion_token_cmd)
      assert.is_nil(config.defaults.database_id)
      assert.equals(10, config.defaults.page_size)
      assert.equals(300, config.defaults.cache_ttl)
      assert.equals(false, config.defaults.debug)
      assert.equals(1000, config.defaults.sync_debounce_ms)
    end)
  end)

  describe("setup", function()
    it("should merge options with defaults", function()
      local opts = {
        page_size = 20,
        debug = true,
        database_id = "test_db_id"
      }

      config.setup(opts)

      assert.equals(20, config.get('page_size'))
      assert.equals(true, config.get('debug'))
      assert.equals("test_db_id", config.get('database_id'))
      assert.equals(300, config.get('cache_ttl')) -- default preserved
    end)

    it("should handle empty options", function()
      config.setup()

      assert.equals(10, config.get('page_size'))
      assert.equals(false, config.get('debug'))
    end)

    it("should handle nil options", function()
      config.setup(nil)

      assert.equals(10, config.get('page_size'))
      assert.equals(false, config.get('debug'))
    end)
  end)

  describe("get", function()
    it("should return configured values", function()
      config.setup({
        page_size = 25,
        debug = true
      })

      assert.equals(25, config.get('page_size'))
      assert.equals(true, config.get('debug'))
    end)

    it("should return nil for unknown keys", function()
      config.setup()

      assert.is_nil(config.get('unknown_key'))
    end)
  end)

  describe("execute_command", function()
    it("should handle successful string commands", function()
      vim.fn.system = function(cmd)
        return "token_value\n"
      end
      vim.v.shell_error = 0

      config.setup({
        notion_token_cmd = "echo token_value"
      })

      assert.equals("token_value", config.get('notion_token'))
    end)

    it("should handle successful table commands", function()
      vim.fn.system = function(cmd)
        return "token_value\n"
      end
      vim.v.shell_error = 0

      config.setup({
        notion_token_cmd = {"echo", "token_value"}
      })

      assert.equals("token_value", config.get('notion_token'))
    end)

    it("should handle command failures", function()
      vim.fn.system = function(cmd)
        return ""
      end
      vim.v.shell_error = 1

      config.setup({
        notion_token_cmd = "false"
      })

      assert.is_nil(config.get('notion_token'))
    end)
  end)
end)