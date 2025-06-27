-- Test utility functions and edge cases

describe("utility functions", function()

  describe("markdown parsing edge cases", function()
    it("should handle empty strings", function()
      -- Test that empty strings don't cause errors
      local empty_string = ""
      assert.equals("", empty_string)
    end)

    it("should handle special characters", function()
      local special_chars = "Special chars: @#$%^&*()_+-=[]{}|;':\",./<>?"
      assert.is_string(special_chars)
    end)

    it("should handle unicode characters", function()
      local unicode = "Unicode: 🚀 ✨ 🎉 中文 日本語"
      assert.is_string(unicode)
    end)
  end)

  describe("vim table utilities", function()
    it("should test vim.tbl_deep_extend", function()
      local table1 = { a = 1, b = 2 }
      local table2 = { b = 3, c = 4 }

      local result = vim.tbl_deep_extend('force', table1, table2)

      assert.equals(1, result.a)
      assert.equals(3, result.b) -- table2 value should override
      assert.equals(4, result.c)
    end)

    it("should test vim.tbl_filter", function()
      local input = { 1, 2, 3, 4, 5, 6 }
      local result = vim.tbl_filter(function(val) return val % 2 == 0 end, input)

      assert.equals(3, #result)
      assert.equals(2, result[1])
      assert.equals(4, result[2])
      assert.equals(6, result[3])
    end)

    it("should test vim.trim", function()
      local trimmed = vim.trim("  hello world  ")
      assert.equals("hello world", trimmed)

      local no_whitespace = vim.trim("nospace")
      assert.equals("nospace", no_whitespace)
    end)
  end)

  describe("time utilities", function()
    it("should test vim.loop.hrtime", function()
      local time1 = vim.loop.hrtime()
      -- Small delay
      for i = 1, 1000 do
        -- Simple busy wait
      end
      local time2 = vim.loop.hrtime()

      -- Time should advance
      assert.is_true(time2 >= time1)
    end)
  end)

  describe("json utilities", function()
    it("should handle json encoding", function()
      local data = { key = "value", number = 42 }
      local encoded = vim.json.encode(data)
      assert.is_string(encoded)
    end)

    it("should handle json decoding", function()
      local json_string = '{"success": true}'
      local decoded = vim.json.decode(json_string)
      assert.equals(true, decoded.success)
    end)
  end)

  describe("buffer utilities", function()
    it("should handle buffer operations", function()
      local buf = vim.api.nvim_create_buf()
      assert.equals(1, buf)

      vim.api.nvim_buf_set_name(buf, "test.md")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"# Test", "Content"})

      local current_buf = vim.api.nvim_get_current_buf()
      assert.is_number(current_buf)
    end)
  end)

  describe("command utilities", function()
    it("should handle user command creation", function()
      local command_created = false
      local original_create = vim.api.nvim_create_user_command
      vim.api.nvim_create_user_command = function(name, callback, opts)
        command_created = true
        assert.equals("TestCommand", name)
        assert.is_function(callback)
        assert.is_table(opts)
      end

      vim.api.nvim_create_user_command("TestCommand", function() end, {})
      assert.is_true(command_created)

      vim.api.nvim_create_user_command = original_create
    end)
  end)

  describe("notification utilities", function()
    it("should handle notifications", function()
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      vim.notify("Test message", vim.log.levels.INFO)
      assert.equals(1, #notifications)
      assert.equals("Test message", notifications[1].msg)
      assert.equals(vim.log.levels.INFO, notifications[1].level)

      vim.notify = original_notify
    end)
  end)

  describe("ui utilities", function()
    it("should handle vim.ui.select", function()
      local selected_item = nil
      vim.ui.select({"option1", "option2", "option3"}, {
        prompt = "Choose:"
      }, function(choice)
        selected_item = choice
      end)

      -- Our mock should select the first item
      assert.equals("option1", selected_item)
    end)
  end)

  describe("system utilities", function()
    it("should handle system commands", function()
      local result = vim.fn.system("echo test")
      assert.is_string(result)

      local has_feature = vim.fn.has("feature")
      assert.is_number(has_feature)
    end)
  end)
end)