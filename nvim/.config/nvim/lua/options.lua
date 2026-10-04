local policy = require("buffer_policy")
local shared = require("state")

-- FLASH completion uses native LSP/buffer words, not the pynvim Python host.
-- Avoid the Python ftplugin's synchronous host probe. An explicit host opts in.
if vim.g.loaded_python3_provider == nil and vim.g.python3_host_prog == nil then
	vim.g.loaded_python3_provider = 0
end

-- Neovim 0.12+ 전용. 사용자 플러그인 경로를 제외하고 설치본의 기본 런타임만 사용합니다.
vim.opt.packpath = { vim.env.VIMRUNTIME }
-- Keep the installation's parser directory as well as its runtime scripts.
vim.opt.runtimepath = vim.tbl_filter(function(path)
	return path == shared.config_root or path == vim.env.VIMRUNTIME or path:match("/lib[^/]*/nvim$") ~= nil
end, vim.opt.runtimepath:get())

-- Choose compatibility paths once at startup, not on every editor event.
-- The legacy API references below are used only when the new API is absent.
shared.highlight_yank = vim.hl.hl_op or vim.hl.on_yank
if vim.fn.has("nvim-0.13") == 1 then
	-- Keep 0.12's FocusGained/:checktime autoread without per-buffer file watchers.
	vim.g.loaded_autoread = 1
end
shared.set_window_width = nil
if vim.api.nvim_win_resize then
	shared.set_window_width = function(win, width)
		vim.api.nvim_win_resize(win, width, -1, {})
	end
else
	-- Neovim 0.12 does not provide nvim_win_resize().
	shared.set_window_width = vim.api.nvim_win_set_width
end

-- =========================================
-- ============== CORE OPTIONS =============
-- =========================================
shared.nopack_data = vim.fn.stdpath("data") .. "/nopack"
-- Keep existing sessions and undo files when adopting the nopack name.
local legacy_data = vim.fn.stdpath("data") .. "/offline"
if vim.fn.isdirectory(legacy_data) == 1 and vim.fn.isdirectory(shared.nopack_data) == 0 then
	if vim.fn.rename(legacy_data, shared.nopack_data) ~= 0 then
		shared.nopack_data = legacy_data
	end
end
-- Share persistent undo across Pack and Nopack, independently of NVIM_APPNAME.
local undo_dir = (vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")) .. "/nvim/undo"
vim.fn.mkdir(undo_dir, "p")
-- Herdr panes may outlive the SSH session that started their server.
shared.use_osc52 = vim.env.SSH_CONNECTION ~= nil or vim.env.SSH_TTY ~= nil or vim.env.HERDR_ENV == "1"

-- Use PATH first, then existing Mason installations; never install tools here.
function shared.resolve_tool(name)
	local path = vim.fn.exepath(name)
	if path ~= "" then
		return path
	end
	local installed = vim.fn.stdpath("data") .. "/mason/bin/" .. name
	return vim.fn.executable(installed) == 1 and installed or ""
end

local default_options = {
	autoread = true, -- reload clean buffers on focus changes or :checktime, including on NFS
	backup = false, -- do not retain a backup after writing
	clipboard = shared.use_osc52 and "" or "unnamedplus", -- SSH/herdr use the yank hook; other desktops use their provider
	lazyredraw = false, -- keep normal redraws; do not defer display updates
	cmdheight = 1, -- more space in the neovim command line for displaying messages
	completeopt = { "menu", "menuone", "noselect", "popup", "fuzzy" },
	autocompletedelay = 150,
	complete = { ".", "w", "b", "t" },
	pumborder = "rounded",
	winborder = "rounded",
	conceallevel = 0, -- so that `` is visible in markdown files
	fileencoding = "utf-8", -- the encoding written to a file
	foldmethod = "manual", -- folds are controlled manually
	foldexpr = "", -- no plugin-provided fold expression
	guifont = "RobotoMono Nerd Font Mono,monospace:h17", -- prefer solid-dot Braille glyphs for dashboard art
	hidden = true, -- required to keep multiple buffers and open multiple buffers
	hlsearch = true, -- highlight all matches on previous search pattern
	ignorecase = true, -- ignore case in search patterns
	mouse = "a", -- allow the mouse to be used in neovim
	pumheight = 10, -- pop up menu height
	showmode = true, -- show the active input mode
	showtabline = 2, -- always show tabs
	smartcase = true, -- smart case
	smartindent = false, -- let filetype indent rules handle '#' lines normally
	splitbelow = true, -- force all horizontal splits to go below current window
	splitright = true, -- force all vertical splits to go to the right current window
	swapfile = false, -- do not create swap files
	termguicolors = true, -- set term gui colors (most terminals support this)
	title = true, -- set the title of window to the value of the titlestring
	undodir = undo_dir, -- shared persistent undo
	undofile = true, -- enable persistent undo
	updatetime = 250, -- idle time before CursorHold
	writebackup = false, -- do not create a temporary backup while writing
	expandtab = true, -- convert tabs to spaces
	shiftwidth = 4, -- the number of spaces inserted for each indentation
	tabstop = 4, -- display tabs at four-column stops
	cursorline = true,
	cursorlineopt = "line,number", -- highlight the current row and its line number
	cursorcolumn = true, -- highlight the current column to form a crosshair
	-- ===== USER SETTINGS: LINE NUMBERS / 줄 번호 설정 =====
	-- 아래 두 값만 수정하세요. true = 켜기, false = 끄기. 재시작 후 적용됩니다.
	-- number: 줄 번호 표시. relativenumber: 현재 커서에서 떨어진 줄 수 표시.
	-- 둘 다 true이면 현재 줄은 실제 번호, 나머지 줄은 상대 번호로 표시됩니다.
	number = true, -- set numbered lines
	relativenumber = true, -- set relative numbered lines
	numberwidth = 2, -- set number column width to 2 {default 4}
	signcolumn = "yes", -- always show the sign column, otherwise it would shift the text each time
	wrap = true, -- wrap long lines at the window edge
	spell = false,
	spelllang = "en",
	background = "dark",
	scrolloff = 5, -- keep context above and below the cursor
	sidescrolloff = 8,
	ttyfast = true,
	sessionoptions = "buffers,curdir,tabpages,winsize",
}

-- Apply the shared editor options before configuring window-local behavior.
vim.opt.shortmess:append("c")

for k, v in pairs(default_options) do
	vim.opt[k] = v
end

-- Returning from an internal terminal does not necessarily trigger FocusGained.
local file_check_pending = false
function shared.check_external_files()
	if file_check_pending then
		return
	end
	file_check_pending = true
	vim.schedule(function()
		file_check_pending = false
		if vim.fn.getcmdwintype() == "" and not vim.api.nvim_get_mode().mode:match("^[ct]") then
			vim.cmd("checktime")
		end
	end)
end
local file_changes = vim.api.nvim_create_augroup("nopack-file-changes", { clear = true })
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" }, {
	group = file_changes,
	callback = shared.check_external_files,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
	group = file_changes,
	callback = function(args)
		if policy.is_source(args.buf) and not vim.bo[args.buf].modified then
			vim.notify("Reloaded external file changes: " .. vim.fn.fnamemodify(args.file, ":~:."))
		end
	end,
})

-- Editing and command-line options are independent of the display modules.
vim.cmd("filetype plugin indent on")
vim.cmd("syntax enable")
vim.opt.whichwrap:append("<,>,[,],h,l")
vim.opt.iskeyword:append("-")
-- Keep :find / Tab completion from recursively walking an entire server.
vim.opt.path = { ".", "" }
vim.opt.wildmenu = true
vim.opt.wildmode = "longest:full,full"
vim.opt.wildignore:append({ "*/.git/*", "*/node_modules/*", "*/__pycache__/*" })

-- Runtime UI changes use vim.wo[win][0] / vim.opt_local, never window defaults.
-- Ordinary editor navigation preserves :set/:setlocal and filetype settings.
-- Only utility windows own temporary numbering/statuscolumn changes.
local numbering_options = { "number", "relativenumber", "statuscolumn" }
local source_numbering = {}
local numbering_group = vim.api.nvim_create_augroup("nopack-line-numbers", { clear = true })
local relative_numbers = default_options.relativenumber
local relative_numbers_override
function shared.toggle_relative_numbers()
	local enabled = not relative_numbers
	relative_numbers, relative_numbers_override = enabled, enabled
	vim.go.relativenumber = enabled
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if policy.is_editor(win) then
			vim.wo[win][0].relativenumber = enabled
		end
	end
end
vim.api.nvim_create_autocmd("BufWinLeave", {
	group = numbering_group,
	callback = function(args)
		-- A source may briefly occupy a utility window during a nested transition.
		-- Never remember the utility's temporary settings as that source's choice.
		if not policy.is_source(args.buf) or vim.w.nopack_numbering_utility then
			return
		end
		local saved = {}
		for _, name in ipairs(numbering_options) do
			saved[name] = vim.wo[name]
		end
		local win = vim.api.nvim_get_current_win()
		source_numbering[win] = source_numbering[win] or {}
		source_numbering[win][args.buf] = saved
	end,
})
vim.api.nvim_create_autocmd({ "WinClosed", "BufWipeout" }, {
	group = numbering_group,
	callback = function(args)
		if args.event == "WinClosed" then
			source_numbering[tonumber(args.match)] = nil
		else
			for _, buffers in pairs(source_numbering) do
				buffers[args.buf] = nil
			end
		end
	end,
})
local function update_window_numbering(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	local source = policy.is_source(buf)
	if source then
		if vim.w[win].nopack_numbering_utility then
			local saved = (source_numbering[win] or {})[buf] or {}
			for _, name in ipairs(numbering_options) do
				local value = saved[name]
				if value == nil then
					value = vim.go[name]
				end
				vim.wo[win][0][name] = value
			end
			vim.w[win].nopack_numbering_utility = nil
		end
		if relative_numbers_override ~= nil then
			vim.wo[win][0].relativenumber = relative_numbers_override
		end
	else
		vim.w[win].nopack_numbering_utility = true
	end
	if vim.bo[buf].filetype == "netrw" or vim.bo[buf].filetype == "flash-explorer" then
		vim.wo[win][0].number = vim.bo[buf].filetype == "netrw"
		vim.wo[win][0].relativenumber = false
		local statuscolumn = vim.bo[buf].filetype == "flash-explorer" and "%s " or ""
		if vim.wo[win].statuscolumn ~= statuscolumn then
			vim.wo[win][0].statuscolumn = statuscolumn
		end
	end
end
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "BufWinEnter", "FileType", "VimEnter", "SessionLoadPost" }, {
	group = numbering_group,
	callback = function(args)
		if args.event == "FileType" then
			-- Apply after filetype plugins, only to windows displaying this buffer.
			vim.schedule(function()
				for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
					update_window_numbering(win)
				end
			end)
		elseif args.event == "VimEnter" or args.event == "SessionLoadPost" then
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				update_window_numbering(win)
			end
		else
			update_window_numbering(vim.api.nvim_get_current_win())
		end
	end,
})

-- =========================================
-- ================ LEADER =================
-- =========================================
vim.g.mapleader = vim.g.mapleader or " " -- default only; preserve a leader set before loading FLASH
