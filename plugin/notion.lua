if vim.g.loaded_notion_nvim then
  return
end
vim.g.loaded_notion_nvim = 1

vim.api.nvim_create_user_command('Notion', function(args)
  local subcommand = args.fargs[1]
  if subcommand == 'create' then
    -- Join all arguments after 'create' as the title
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