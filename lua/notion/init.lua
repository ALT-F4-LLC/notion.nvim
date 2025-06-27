local M = {}

local notion = require('notion.api')
local config = require('notion.config')

function M.setup(opts)
  config.setup(opts or {})

  vim.api.nvim_create_user_command('NotionCreate', function(args)
    -- args.args contains the full argument string, perfect for multi-word titles
    notion.create_page(args.args)
  end, {
    nargs = '+',
    desc = 'Create a new Notion page (title required)'
  })

  vim.api.nvim_create_user_command('NotionEdit', function(args)
    if args.args and args.args ~= '' then
      notion.edit_page(args.args)
    else
      notion.list_and_edit_pages()
    end
  end, {
    nargs = '?',
    desc = 'Edit a Notion page in Neovim'
  })

  vim.api.nvim_create_user_command('NotionSync', function()
    notion.sync_page()
  end, {
    desc = 'Sync current buffer changes back to Notion'
  })

  vim.api.nvim_create_user_command('NotionBrowser', function()
    notion.open_current_page_in_browser()
  end, {
    desc = 'Open current Notion page in browser'
  })

  vim.api.nvim_create_user_command('NotionDelete', function()
    notion.delete_page()
  end, {
    desc = 'Delete (archive) a Notion page'
  })
end

return M
