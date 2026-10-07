-- =========================================
-- ============ DISABLE DEFAULTS ===========
-- =========================================
-- Older terminals may display OSC 9;4 progress commands as literal text.
vim.api.nvim_create_augroup("nvim.progress", { clear = true })

vim.g.loaded_gzip = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1

vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_getscript = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_2html_plugin = 1

vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_nvim_dir_plugin = 1 -- Oil handles directory buffers, including on Neovim 0.13.

-- =========================================
-- ============== CORE OPTIONS =============
-- =========================================
HOME_PATH = vim.loop.os_homedir()
-- Share persistent undo across Pack and Nopack, independently of NVIM_APPNAME.
local undo_dir = (vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")) .. "/nvim/undo"
vim.fn.mkdir(undo_dir, "p")

local default_options = {
	backup = false, -- creates a backup file
	clipboard = "unnamedplus", -- allows neovim to access the system clipboard
	lazyredraw = false,
	cmdheight = 1, -- more space in the neovim command line for displaying messages
	-- colorcolumn = "90", -- fixes indentline for now
	completeopt = { "menu", "menuone", "noselect", "popup", "fuzzy" },
	autocompletedelay = 150,
	complete = { ".", "w", "b", "t" },
	pumborder = "rounded",
	conceallevel = 0, -- so that `` is visible in markdown files
	fileencoding = "utf-8", -- the encoding written to a file
	foldmethod = "manual",
	foldexpr = "",
	guifont = "RobotoMono Nerd Font Mono,monospace:h17", -- prefer solid-dot Braille glyphs for dashboard art
	hidden = true, -- required to keep multiple buffers and open multiple buffers
	hlsearch = true, -- highlight all matches on previous search pattern
	ignorecase = true, -- ignore case in search patterns
	mouse = "a", -- allow the mouse to be used in neovim
	pumheight = 10, -- pop up menu height
	showmode = true, -- we don't need to see things like -- INSERT -- anymore
	showtabline = 2, -- always show tabs
	smartcase = true, -- smart case
	smartindent = true, -- make indenting smarter again
	splitbelow = true, -- force all horizontal splits to go below current window
	splitright = true, -- force all vertical splits to go to the right of current window
	swapfile = false, -- creates a swapfile
	termguicolors = true, -- set term gui colors (most terminals support this)
	title = true, -- set the title of window to the value of the titlestring
	-- -- opt.titlestring = "%<%F%=%l/%L - nvim" -- what the title of the window will be set to
	undodir = undo_dir, -- shared persistent undo
	undofile = true, -- enable persistent undo
	updatetime = 250, -- CursorHold/write delay; completion uses autocompletedelay
	writebackup = false, -- if a file is being edited by another program (or was written to file while editing with another program), it is not allowed to be edited
	expandtab = true, -- convert tabs to spaces
	shiftwidth = 4, -- the number of spaces inserted for each indentation
	tabstop = 4, -- insert 2 spaces for a tab
	cursorline = true, -- highlight the current line
	cursorcolumn = false, -- avoid syntax redraw across rows during cursor movement
	-- ===== USER SETTINGS: LINE NUMBERS =====
	-- Edit the two values below: true enables, false disables. Restart to apply changes.
	-- number: show line numbers. relativenumber: show line distance from the cursor.
	-- With both enabled, the current line shows its absolute number; other lines show relative numbers.
	number = true, -- set numbered lines
	relativenumber = true, -- set relative numbered lines
	numberwidth = 2, -- set number column width to 2 {default 4}
	signcolumn = "yes", -- always show the sign column, otherwise it would shift the text each time
	wrap = true, -- display lines as one long line
	spell = false,
	spelllang = "en",
	background = "dark",
	scrolloff = 5, -- is one of my fav
	sidescrolloff = 8,
	ttyfast = true,
	sessionoptions = "buffers,curdir,tabpages,winsize",
} ---  VIM ONLY COMMANDS  ---cmd "filetype plugin on"cmd('let &titleold="' .. TERMINAL .. '"')cmd "set inccommand=split"cmd "set iskeyword+=-"

---  SETTINGS  ---
vim.opt.shortmess:append("c")
vim.opt.fillchars:append({ foldopen = "-", foldclose = ">" })

for k, v in pairs(default_options) do
	vim.opt[k] = v
end

-- Filetype indentation and navigation are editing options, independent of the theme.
vim.cmd("filetype indent on")
vim.opt.whichwrap:append("<,>,[,],h,l")
vim.opt.iskeyword:append("-")

-- =========================================
-- ================ LEADER =================
-- =========================================
vim.g.mapleader = vim.g.mapleader or " " -- Default only; preserve a leader set before loading.
