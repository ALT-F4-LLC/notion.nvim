-- luacheck: globals reset_vim_mocks
require('tests.spec_helper')

describe("Telescope integration", function()
  local api, config
  local mock_curl

  before_each(function()
    reset_vim_mocks()

    -- Reset module cache AND preload (to clear mocks from other tests)
    package.loaded['notion.api'] = nil
    package.loaded['notion.config'] = nil
    package.loaded['plenary.curl'] = nil
    package.preload['notion.api'] = nil
    package.preload['notion.config'] = nil

    -- Mock curl
    mock_curl = {
      get = function() return { status = 200, body = '{"success": true}' } end,
      post = function() return { status = 200, body = '{"success": true}' } end,
      patch = function() return { status = 200, body = '{"success": true}' } end,
      delete = function() return { status = 200, body = '{"success": true}' } end
    }
    package.preload['plenary.curl'] = function() return mock_curl end

    config = require('notion.config')
    api = require('notion.api')

    -- Debug: print config module contents
    -- print("\n=== Config module keys ===")
    -- for k, v in pairs(config) do
    --   print(k, type(v))
    -- end
  end)

  describe("config.telescope_available()", function()
    it("returns false when telescope is not available", function()
      vim.telescope.available = false
      -- Debug output
      if not config.telescope_available then
        print("\nDEBUG: config.telescope_available is nil!")
        print("Config type:", type(config))
        print("Config keys:")
        for k in pairs(config) do
          print("  -", k)
        end
      end
      assert.is_false(config.telescope_available())
    end)

    it("returns true when telescope is available", function()
      vim.telescope.available = true
      assert.is_true(config.telescope_available())
    end)
  end)

  describe("config.should_use_telescope()", function()
    it("auto-detects when use_telescope is nil (telescope available)", function()
      vim.telescope.available = true
      config.setup({ use_telescope = nil })
      assert.is_true(config.should_use_telescope())
    end)

    it("auto-detects when use_telescope is nil (telescope unavailable)", function()
      vim.telescope.available = false
      config.setup({ use_telescope = nil })
      assert.is_false(config.should_use_telescope())
    end)

    it("forces telescope when use_telescope is true", function()
      vim.telescope.available = false  -- Even if not available
      config.setup({ use_telescope = true })
      assert.is_true(config.should_use_telescope())
    end)

    it("disables telescope when use_telescope is false", function()
      vim.telescope.available = true  -- Even if available
      config.setup({ use_telescope = false })
      assert.is_false(config.should_use_telescope())
    end)
  end)

  describe("api.get_all_pages()", function()
    before_each(function()
      vim.env.NOTION_TOKEN = "test-token"
      config.setup({ database_id = "test-db-id" })

      -- Mock curl.post to return pages
      mock_curl.post = function()
        return {
          status = 200,
          body = vim.json.encode({
            results = {
              {
                id = "page1",
                properties = {
                  Name = {
                    title = { { text = { content = "Page 1" } } }
                  }
                },
                url = "https://notion.so/page1",
                created_time = "2024-01-01T10:00:00.000Z",
                last_edited_time = "2024-01-02T11:00:00.000Z"
              },
              {
                id = "page2",
                properties = {
                  Name = {
                    title = { { text = { content = "Page 2" } } }
                  }
                },
                url = "https://notion.so/page2",
                created_time = "2024-01-03T10:00:00.000Z",
                last_edited_time = "2024-01-04T11:00:00.000Z"
              }
            },
            has_more = false
          })
        }
      end
    end)

    it("fetches all pages without pagination", function()
      local pages = api.get_all_pages("test-db-id")

      assert.are.equal(2, #pages)
      assert.are.equal("Page 1", pages[1].title)
      assert.are.equal("page1", pages[1].id)
      assert.are.equal("Page 2", pages[2].title)
    end)

    it("handles pagination with multiple requests", function()
      local request_count = 0
      mock_curl.post = function()
        request_count = request_count + 1

        if request_count == 1 then
          -- First page
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "page1",
                  properties = { Name = { title = { { text = { content = "Page 1" } } } } },
                  url = "https://notion.so/page1",
                  created_time = "2024-01-01T10:00:00.000Z",
                  last_edited_time = "2024-01-02T11:00:00.000Z"
                }
              },
              has_more = true,
              next_cursor = "cursor1"
            })
          }
        else
          -- Second page
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "page2",
                  properties = { Name = { title = { { text = { content = "Page 2" } } } } },
                  url = "https://notion.so/page2",
                  created_time = "2024-01-03T10:00:00.000Z",
                  last_edited_time = "2024-01-04T11:00:00.000Z"
                }
              },
              has_more = false
            })
          }
        end
      end

      local pages = api.get_all_pages("test-db-id")

      assert.are.equal(2, #pages)
      assert.are.equal("Page 1", pages[1].title)
      assert.are.equal("Page 2", pages[2].title)
      assert.are.equal(2, request_count)
    end)

    it("handles empty results", function()
      mock_curl.post = function()
        return {
          status = 200,
          body = vim.json.encode({
            results = {},
            has_more = false
          })
        }
      end

      local pages = api.get_all_pages("test-db-id")
      assert.are.equal(0, #pages)
    end)

    it("retries once on API failure", function()
      local attempt = 0
      mock_curl.post = function()
        attempt = attempt + 1
        if attempt == 1 then
          return { status = 500, body = '{"error": "server error"}' }  -- First attempt fails
        end
        -- Second attempt succeeds
        return {
          status = 200,
          body = vim.json.encode({
            results = {
              {
                id = "page1",
                properties = { Name = { title = { { text = { content = "Page 1" } } } } },
                url = "https://notion.so/page1",
                created_time = "2024-01-01T10:00:00.000Z",
                last_edited_time = "2024-01-02T11:00:00.000Z"
              }
            },
            has_more = false
          })
        }
      end

      local pages = api.get_all_pages("test-db-id")
      assert.are.equal(1, #pages)
      assert.are.equal(2, attempt)  -- Verify retry happened
    end)

    it("handles pages with untitled names", function()
      mock_curl.post = function()
        return {
          status = 200,
          body = vim.json.encode({
            results = {
              {
                id = "page1",
                properties = {
                  Name = { title = {} }  -- Empty title
                },
                url = "https://notion.so/page1",
                created_time = "2024-01-01T10:00:00.000Z",
                last_edited_time = "2024-01-02T11:00:00.000Z"
              }
            },
            has_more = false
          })
        }
      end

      local pages = api.get_all_pages("test-db-id")
      assert.are.equal(1, #pages)
      assert.are.equal("Untitled", pages[1].title)
    end)

    it("respects safety limit for pagination", function()
      local request_count = 0
      mock_curl.post = function()
        request_count = request_count + 1
        -- Simulate infinite pagination
        return {
          status = 200,
          body = vim.json.encode({
            results = { {
              id = "page" .. request_count,
              properties = { Name = { title = { { text = { content = "Page " .. request_count } } } } },
              url = "",
              created_time = "",
              last_edited_time = ""
            } },
            has_more = true,
            next_cursor = "cursor" .. request_count
          })
        }
      end

      local pages = api.get_all_pages("test-db-id")

      -- Should stop at max_requests (100)
      assert.are.equal(100, request_count)
      assert.are.equal(100, #pages)
    end)
  end)

  describe("api.list_and_edit_pages() with telescope", function()
    before_each(function()
      vim.env.NOTION_TOKEN = "test-token"
      config.setup({ database_id = "test-db-id" })

      -- Mock curl.post to return 2 pages
      mock_curl.post = function()
        return {
          status = 200,
          body = vim.json.encode({
            results = {
              {
                id = "page1",
                properties = { Name = { title = { { text = { content = "Page 1" } } } } },
                url = "https://notion.so/page1",
                created_time = "2024-01-01",
                last_edited_time = "2024-01-02"
              },
              {
                id = "page2",
                properties = { Name = { title = { { text = { content = "Page 2" } } } } },
                url = "https://notion.so/page2",
                created_time = "2024-01-03",
                last_edited_time = "2024-01-04"
              }
            },
            has_more = false
          })
        }
      end

      -- Mock curl.get for edit_page (which fetches page details)
      mock_curl.get = function()
        return {
          status = 200,
          body = vim.json.encode({})
        }
      end
    end)

    it("uses vim.ui.select when telescope is disabled", function()
      vim.telescope.available = false
      config.setup({ database_id = "test-db-id", use_telescope = false })

      local select_called = false
      vim.ui.select = function(items, opts, on_choice)
        select_called = true
        assert.are.equal(2, #items)
        assert.are.equal("Page 1", items[1].title)
      end

      api.list_and_edit_pages()
      assert.is_true(select_called)
    end)

    it("falls back to vim.ui.select when telescope is unavailable", function()
      vim.telescope.available = false
      config.setup({ database_id = "test-db-id", use_telescope = nil })

      local select_called = false
      vim.ui.select = function(items, opts, on_choice)
        select_called = true
      end

      api.list_and_edit_pages()
      assert.is_true(select_called)
    end)

    it("shows warning when telescope forced but unavailable", function()
      vim.telescope.available = false
      config.setup({ database_id = "test-db-id", use_telescope = true })

      local warnings = {}
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN then
          table.insert(warnings, msg)
        end
      end

      api.list_and_edit_pages()
      assert.is_true(#warnings > 0)
      assert.is_not_nil(warnings[1]:match("Telescope not available"))
    end)

    it("shows page count notification", function()
      local notifications = {}
      vim.notify = function(msg, level)
        if level == vim.log.levels.INFO then
          table.insert(notifications, msg)
        end
      end

      api.list_and_edit_pages()
      assert.is_true(#notifications > 0)
      assert.is_not_nil(notifications[1]:match("Found 2 pages"))
    end)

    it("handles empty database", function()
      mock_curl.post = function()
        return {
          status = 200,
          body = vim.json.encode({
            results = {},
            has_more = false
          })
        }
      end

      local warnings = {}
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN then
          table.insert(warnings, msg)
        end
      end

      api.list_and_edit_pages()
      assert.is_true(#warnings > 0)
      assert.is_not_nil(warnings[1]:match("No pages found"))
    end)

    it("handles missing database_id", function()
      config.setup({})  -- No database_id

      local errors = {}
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          table.insert(errors, msg)
        end
      end

      api.list_and_edit_pages()
      assert.is_true(#errors > 0)
      assert.is_not_nil(errors[1]:match("Database ID not configured"))
    end)

    it("sorts pages alphabetically by title (case-insensitive)", function()
      -- Mock unsorted pages from API
      mock_curl.post = function()
        return {
          status = 200,
          body = vim.json.encode({
            results = {
              {
                id = "page3",
                properties = { Name = { title = { { text = { content = "Zebra Project" } } } } },
                url = "https://notion.so/page3",
                created_time = "2024-01-03",
                last_edited_time = "2024-01-03"
              },
              {
                id = "page1",
                properties = { Name = { title = { { text = { content = "Apple Notes" } } } } },
                url = "https://notion.so/page1",
                created_time = "2024-01-01",
                last_edited_time = "2024-01-01"
              },
              {
                id = "page4",
                properties = { Name = { title = { { text = { content = "banana ideas" } } } } },
                url = "https://notion.so/page4",
                created_time = "2024-01-04",
                last_edited_time = "2024-01-04"
              },
              {
                id = "page2",
                properties = { Name = { title = { { text = { content = "Untitled" } } } } },
                url = "https://notion.so/page2",
                created_time = "2024-01-02",
                last_edited_time = "2024-01-02"
              }
            },
            has_more = false
          })
        }
      end

      local selected_pages = {}
      vim.ui.select = function(items, opts, on_choice)
        selected_pages = items
      end

      api.list_and_edit_pages()

      -- Verify pages are sorted alphabetically (case-insensitive)
      assert.are.equal(4, #selected_pages)
      assert.are.equal("Apple Notes", selected_pages[1].title)
      assert.are.equal("banana ideas", selected_pages[2].title)
      assert.are.equal("Untitled", selected_pages[3].title)
      assert.are.equal("Zebra Project", selected_pages[4].title)
    end)
  end)
end)
