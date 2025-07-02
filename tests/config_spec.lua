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

    it("should sanitize command in error messages for string commands", function()
      vim.fn.system = function(cmd)
        return ""
      end
      vim.v.shell_error = 1

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      config.setup({
        notion_token_cmd = "doppler secrets get NOTION_TOKEN --plain"
      })

      assert.equals(2, #notifications) -- One for failed command, one for token not configured
      -- Find the command failure notification
      local command_error_msg = nil
      for _, notif in ipairs(notifications) do
        if string.match(notif.msg, "Failed to retrieve token") then
          command_error_msg = notif.msg
          break
        end
      end

      assert.is_not_nil(command_error_msg)
      -- Verify the command is sanitized (only shows command name)
      assert.is_not_nil(string.match(command_error_msg, "doppler %[REDACTED%]"))
      assert.is_nil(string.match(command_error_msg, "NOTION_TOKEN"))
      assert.is_nil(string.match(command_error_msg, "--plain"))
    end)

    it("should sanitize command in error messages for table commands", function()
      vim.fn.system = function(cmd)
        return ""
      end
      vim.v.shell_error = 1

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      config.setup({
        notion_token_cmd = {"doppler", "secrets", "get", "--plain", "NOTION_TOKEN"}
      })

      assert.equals(2, #notifications) -- One for failed command, one for token not configured

      -- Check that NOTION_TOKEN is not present in command failure notifications
      local found_token_in_command_error = false
      for _, notif in ipairs(notifications) do
        if string.match(notif.msg, "Failed to retrieve token") and string.match(notif.msg, "NOTION_TOKEN") then
          found_token_in_command_error = true
          break
        end
      end

      assert.is_false(found_token_in_command_error, "Token value should not appear in command error messages")

      -- Check that at least one notification mentions command failure
      local found_command_error = false
      for _, notif in ipairs(notifications) do
        if string.match(notif.msg, "Failed to retrieve token") then
          found_command_error = true
          break
        end
      end

      assert.is_true(found_command_error, "Should have command failure notification")
    end)
  end)
end)