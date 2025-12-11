# notion.nvim

A Neovim plugin for seamless integration with Notion's API, allowing you to edit Notion pages directly within Neovim using markdown syntax.

```
     ███╗   ██╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗    ███╗   ██╗██╗   ██╗██╗███╗   ███╗
     ████╗  ██║██╔═══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║    ████╗  ██║██║   ██║██║████╗ ████║
     ██╔██╗ ██║██║   ██║   ██║   ██║██║   ██║██╔██╗ ██║    ██╔██╗ ██║██║   ██║██║██╔████╔██║
     ██║╚██╗██║██║   ██║   ██║   ██║██║   ██║██║╚██╗██║    ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
     ██║ ╚████║╚██████╔╝   ██║   ██║╚██████╔╝██║ ╚████║ ██╗██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
     ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝
```

## Features

- **Native Notion editing** - Edit Notion pages directly in Neovim buffers
- **Robust sync system** - Diff-based synchronization with intelligent pagination and retry logic
- **Markdown support** - Full markdown syntax with rich text formatting (bold, italic, code, links)
- **Smart debouncing** - Prevents API abuse with configurable sync delays
- **Enhanced Telescope integration** - Article preview with caching and fuzzy search (requires telescope.nvim)
- **Image support** - Embed and edit images with captions using markdown syntax
- **Block preservation** - Maintains Notion block structure and ordering
- **Rate limiting handling** - Automatic retry logic for API rate limits
- **Cross-platform** - Works on macOS, Linux, and Windows
- **Debug mode** - Detailed timing information for performance analysis

## Requirements

- Neovim 0.8+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, recommended for better page browsing)
- Notion API integration token
- Notion database ID

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'ALT-F4-LLC/notion.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',  -- Optional but recommended
  },
  config = function()
    require('notion').setup({
      -- Secure token retrieval (recommended)
      notion_token_cmd = {"doppler", "secrets", "get", "--plain", "NOTION_TOKEN"},
      -- Or rely on NOTION_TOKEN environment variable (no config needed)
      database_id = 'your_database_id_here',   -- or set NOTION_DATABASE_ID env var
      debug = false,                          -- Enable debug timing info
      sync_debounce_ms = 1000,               -- Minimum time between syncs
      use_telescope = nil,                   -- nil = auto-detect, true = force, false = disable
    })
  end
}
```

## Setup

1. Create a Notion integration at https://www.notion.so/my-integrations
2. Copy the integration token
3. Create or find a database in Notion and copy its ID from the URL
4. Share the database with your integration

### Finding Your Database ID

The database ID is in the URL when viewing your database:
```
https://www.notion.so/workspace/DATABASE_ID?v=...
```

## Configuration

```lua
require('notion').setup({
  notion_token_cmd = nil,     -- Command to retrieve token (e.g. {"doppler", "secrets", "get", "--plain", "NOTION_TOKEN"})
  database_id = nil,          -- Database ID (or use NOTION_DATABASE_ID env var)
  page_size = 10,             -- Number of pages per API request (pagination fetches all)
  debug = false,              -- Show detailed timing information
  sync_debounce_ms = 1000,    -- Minimum milliseconds between syncs (prevents API abuse)
  use_telescope = nil,        -- nil = auto-detect, true = force telescope, false = use vim.ui.select
})
```

### Telescope Integration

If [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) is installed, the plugin uses it for enhanced page browsing instead of `vim.ui.select`. This provides:

- **Full article preview** - See complete article content in markdown format as you browse
- **Smart caching** - Previewed articles load instantly when you return to them
- **Debounced loading** - 300ms delay prevents freezing when scrolling quickly through articles
- **Fuzzy search** - Fast filtering across all page titles
- **Pagination support** - Automatically fetches and displays all pages from your database
- **Alphabetical sorting** - Pages displayed in A-Z order by title

**Preview behavior:**
- Articles load after 300ms pause (prevents API spam while scrolling)
- Cached articles display instantly with no delay
- Only one article loads at a time to prevent UI freezing
- Shows "Loading..." indicator while fetching large articles

The integration auto-detects Telescope availability. You can override this behavior:
- `use_telescope = nil` - Auto-detect (default, recommended)
- `use_telescope = true` - Force Telescope (warns if unavailable, falls back to vim.ui.select)
- `use_telescope = false` - Always use vim.ui.select

### Token Security

**Security First**: Tokens cannot be hardcoded in configuration. Choose one of these secure methods:

**Option 1: Environment Variable (Simple)**
```bash
export NOTION_TOKEN="your_token_here"
```

**Option 2: Secret Management Command (Recommended)**
```lua
require('notion').setup({
  -- Using Doppler
  notion_token_cmd = {"doppler", "secrets", "get", "--plain", "NOTION_TOKEN"},

  -- Using 1Password CLI
  notion_token_cmd = {"op", "read", "op://vault/notion/token"},

  -- Using AWS Secrets Manager
  notion_token_cmd = {"aws", "secretsmanager", "get-secret-value", "--secret-id", "notion-token", "--query", "SecretString", "--output", "text"},

  -- Using any custom command
  notion_token_cmd = {"your-secret-tool", "get", "notion-token"},

  database_id = 'your_database_id_here',
})
```

## Usage

### Core Workflow

1. **Create pages**: `:Notion create <title>` - Create and immediately edit new pages
2. **Browse and edit**: `:Notion edit` - Browse pages with live preview and fuzzy search (requires Telescope) or simple selection menu
3. **Save changes**: `:w` - Automatically syncs changes back to Notion
4. **Delete pages**: `:Notion delete` - Browse and archive pages
5. **Open in browser**: `:NotionBrowser` - Open current page in browser

### Commands

#### Primary Commands (`:Notion`)
- `:Notion create <title>` - Create page and open for editing (title required)
- `:Notion edit [page_id]` - Browse and select page for editing in Neovim
- `:Notion delete` - Browse and delete (archive) pages

#### Additional Commands
- `:NotionBrowser` - Open current buffer's page in browser
- `:NotionSync` - Manually sync current buffer (backup for `:w`)

#### Alternative Syntax (Individual Commands)
- `:NotionCreate <title>` - Create page (title required)
- `:NotionEdit [page_id]` - Edit pages
- `:NotionDelete` - Delete pages

### Editing Experience

When you edit a Notion page:

1. **Automatic buffer setup** - Page opens as a markdown buffer with auto-sync
2. **Rich formatting support**:
   - `**bold**` and `*italic*` text
   - `` `inline code` `` formatting
   - `# ## ###` headers
   - `- [ ]` and `- [x]` todo items
   - `- ` bulleted lists
   - `1. ` numbered lists
   - ````code blocks````
   - `![caption](url)` images

3. **Robust sync** - Only modified blocks are updated with automatic retry on failures
4. **Instant feedback** - Success/error notifications after each save

### Performance

The plugin uses a sophisticated sync system that:
- **Intelligent pagination** - Handles large documents by fetching all blocks efficiently
- **Compares existing vs new content** to identify changes with precise diff algorithm
- **Only updates modified blocks** with automatic retry on API failures
- **Preserves block order** using Notion's positioning API
- **Scales efficiently** with document size through smart pagination
- **Rate limiting resilience** - Automatic backoff and retry for API limits

Typical sync times:
- Small edits (1-2 blocks): 200-800ms
- Large documents: Performance scales with changed content, not total size
- Pagination and retries add minimal overhead while ensuring reliability

## Environment Variables

Set these instead of hardcoding in config:

- `NOTION_TOKEN` - Your Notion integration token
- `NOTION_DATABASE_ID` - The ID of your Notion database

## Troubleshooting

### Enable Debug Mode

```lua
require('notion').setup({
  debug = true,  -- Shows detailed timing for each operation
})
```

Debug output shows:
- API request timing
- Diff calculation performance
- Block operation details
- Total sync time

### Common Issues

1. **"Notion token not configured"**
   - Set `NOTION_TOKEN` environment variable or configure `notion_token_cmd`

2. **"Database ID not configured"**
   - Set `database_id` in config or `NOTION_DATABASE_ID` environment variable

3. **"Too soon! Wait Xms before next sync"**
   - Debouncing prevents API abuse - wait or adjust `sync_debounce_ms`

4. **Slow sync performance**
   - Enable debug mode to see timing breakdown
   - Performance depends on Notion API response time (typically 200-600ms per request)
   - Large pages may require multiple API calls due to pagination (normal behavior)

5. **Temporary sync failures**
   - Plugin automatically retries failed requests once
   - Rate limiting is handled with intelligent backoff
   - Enable debug mode to see retry attempts and timing

## API Reference

The plugin exposes a Lua API:

```lua
local notion = require('notion.api')

-- Create a new page and open for editing
notion.create_page('My Page Title')

-- Edit a page by ID in Neovim buffer
notion.edit_page('page-id-here')

-- Browse and select pages for editing
notion.list_and_edit_pages()

-- Delete (archive) pages with selection UI
notion.delete_page()

-- Sync current buffer to Notion
notion.sync_page()

-- Open current buffer's page in browser
notion.open_current_page_in_browser()

-- Legacy browser-based functions
notion.open_page('search query')
notion.list_pages()
notion.open_page_by_url('https://notion.so/...')

-- Clear preview cache (useful after making changes outside Neovim)
require('notion.telescope').clear_preview_cache()
```

## Technical Details

### Sync Algorithm

1. **Fetch existing blocks** from Notion page with intelligent pagination
2. **Convert buffer content** to Notion block format
3. **Calculate precise diff** between existing and new blocks
4. **Delete changed blocks** that no longer match
5. **Insert new blocks** at correct positions using `after` parameter
6. **Preserve unchanged blocks** for optimal performance
7. **Retry on failures** with automatic backoff for rate limiting

### Block Type Support

- `heading_1`, `heading_2`, `heading_3` - Markdown headers
- `paragraph` - Regular text with rich formatting
- `bulleted_list_item` - Bulleted lists
- `numbered_list_item` - Numbered lists
- `to_do` - Checkbox items
- `code` - Code blocks with language detection
- `image` - Images with captions (both external URLs and Notion-hosted files)

### Rate Limiting & Reliability

Built-in protection against API limits and failures:
- **Debouncing** - Minimum time between syncs (default: 1000ms)
- **Per-page sync state tracking** - Prevents concurrent syncs
- **Graceful handling** of rapid save attempts
- **Automatic retry logic** - Intelligent backoff for API rate limits
- **Pagination handling** - Efficiently fetches all blocks from large pages
- **Failure recovery** - Retry mechanisms for temporary API issues

## License

APACHE 2.0
