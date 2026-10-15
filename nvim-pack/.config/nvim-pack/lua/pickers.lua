local M = {}
local initialized = false
local names = { ERROR = "Error", WARN = "Warn", INFO = "Info", HINT = "Hint" }
local function diagnostic_colors()
	for _, name in pairs(names) do
		local hl = vim.api.nvim_get_hl(0, { name = "Diagnostic" .. name, link = false })
		hl.bold = true
		hl.cterm = vim.tbl_extend("force", hl.cterm or {}, { bold = true })
		if name == "Error" then
			hl.fg, hl.ctermfg = "#ff0000", 9
		end
		if name == "Warn" then
			hl.fg, hl.ctermfg = "#ffd700", 220
		end
		vim.api.nvim_set_hl(0, "PackPicker" .. name, hl)
	end
end
diagnostic_colors()
vim.api.nvim_create_autocmd("ColorScheme", { callback = diagnostic_colors })

function M.setup()
	if initialized then
		return
	end
	local telescope = require("telescope")
	local actions = require("telescope.actions")
	telescope.setup({
		defaults = {
			prompt_prefix = "> ",
			selection_caret = "> ",
			multi_icon = "+ ",
			disable_devicons = true,
			sorting_strategy = "ascending",
			selection_strategy = "reset",
			layout_config = { prompt_position = "top", width = 0.9, height = 0.9 },
			preview = { treesitter = false, filesize_limit = 2, highlight_limit = 0.5 },
			vimgrep_arguments = {
				"rg",
				"--color=never",
				"--no-heading",
				"--with-filename",
				"--line-number",
				"--column",
				"--smart-case",
				"--hidden",
				"--glob",
				"!.git",
			},
			mappings = { i = { ["<Esc>"] = actions.close } },
		},
		pickers = {
			live_grep = { debounce = 100 }, -- Coalesce rapid input before launching another rg process.
			find_files = {
				hidden = true,
				find_command = vim.fn.executable("rg") == 1 and { "rg", "--files", "--hidden", "--glob", "!.git" }
					or nil,
			},
			diagnostics = { sort_by = "severity" },
		},
		extensions = { undo = { use_delta = false } },
	})
	local ok, err = pcall(telescope.load_extension, "fzf")
	if not ok then
		vim.notify(
			"fzf-native unavailable; using Telescope's Lua sorter. Run :PackBuildFzf.\n" .. tostring(err),
			vim.log.levels.WARN
		)
	end
	telescope.load_extension("ui-select")
	initialized = true
end
vim.api.nvim_create_user_command("PackBuildFzf", function()
	if require("native_build").fzf() and initialized then
		require("telescope").load_extension("fzf")
	end
end, { desc = "Build Telescope's native fuzzy sorter" })

function M.open(name, opts)
	M.setup()
	return require("telescope.builtin")[name](opts or {})
end

function M.locations(items, title)
	M.setup()
	local conf = require("telescope.config").values
	require("telescope.pickers")
		.new({}, {
			prompt_title = title or "LSP locations",
			finder = require("telescope.finders").new_table({
				results = items,
				entry_maker = require("telescope.make_entry").gen_from_quickfix({}),
			}),
			previewer = conf.qflist_previewer({}),
			sorter = conf.generic_sorter({}),
		})
		:find()
end

function M.diagnostics(buf)
	M.setup()
	local maker = require("telescope.make_entry").gen_from_diagnostics({})
	local display = require("telescope.pickers.entry_display").create({
		separator = " ",
		items = { { width = 1 }, { remaining = true } },
	})
	local sorter = require("telescope.config").values.generic_sorter({})
	local score = sorter.scoring_function
	sorter.scoring_function = function(self, prompt, line, entry)
		local result = score(self, prompt, line, entry)
		if result < 0 then
			return result
		end
		return vim.diagnostic.severity[entry.type] * 2 + result / (1 + result)
	end
	M.open("diagnostics", {
		bufnr = buf,
		sort_by = "severity",
		sorter = sorter,
		entry_maker = function(item)
			local entry = maker(item)
			entry.display = function(e)
				local name = names[e.type]
				return display({
					{ name:sub(1, 1), "PackPicker" .. name },
					string.format("%s:%d:%d %s", vim.fn.fnamemodify(e.filename, ":~:."), e.lnum, e.col, e.text),
				})
			end
			return entry
		end,
	})
end

function M.buffers(buffers)
	M.setup()
	local conf = require("telescope.config").values
	require("telescope.pickers")
		.new({}, {
			prompt_title = "Buffers",
			finder = require("telescope.finders").new_table({
				results = buffers,
				entry_maker = function(buf)
					local file = vim.api.nvim_buf_get_name(buf)
					local label = file == "" and "[No Name]" or vim.fn.fnamemodify(file, ":~:.")
					return { value = buf, bufnr = buf, filename = file, ordinal = label, display = label }
				end,
			}),
			previewer = conf.grep_previewer({}),
			sorter = conf.generic_sorter({}),
		})
		:find()
end

local function keymaps()
	M.setup()
	local maker = require("telescope.make_entry").gen_from_keymaps({ width_lhs = 24 })
	M.open("keymaps", {
		entry_maker = function(item)
			local entry = maker(item)
			local leader = vim.keycode("<leader>")
			local lhs = item.lhsraw or vim.keycode(item.lhs)
			entry.lhs = lhs:sub(1, #leader) == leader and ("<leader>" .. vim.fn.keytrans(lhs:sub(#leader + 1)))
				or vim.fn.keytrans(lhs)
			entry.ordinal = entry.mode .. " " .. entry.lhs .. " " .. entry.desc
			return entry
		end,
	})
end

local function colorschemes()
	M.setup()
	local original, background = vim.g.colors_name or "default", vim.o.background
	local confirmed, pending = false, nil
	local function apply(name)
		local queued = pending ~= nil
		pending = name
		if queued then
			return
		end
		vim.schedule(function()
			local target = pending
			pending = nil
			vim.o.background = background
			vim.cmd.colorscheme(target)
		end)
	end
	local source = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(source, 0, math.min(500, vim.api.nvim_buf_line_count(source)), false)
	local conf = require("telescope.config").values
	require("telescope.pickers")
		.new({}, {
			prompt_title = "Colorschemes",
			finder = require("telescope.finders").new_table({ results = vim.fn.getcompletion("", "color") }),
			sorter = conf.generic_sorter({}),
			previewer = require("telescope.previewers").new_buffer_previewer({
				define_preview = function(self, entry)
					apply(entry.value)
					if not self.state.loaded then
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
						self.state.loaded = true
					end
				end,
			}),
			attach_mappings = function(prompt)
				vim.api.nvim_create_autocmd("BufWipeout", {
					buffer = prompt,
					once = true,
					callback = function()
						if not confirmed then
							apply(original)
						end
					end,
				})
				require("telescope.actions").select_default:replace(function()
					local entry = require("telescope.actions.state").get_selected_entry()
					if entry then
						confirmed = true
					end
					require("telescope.actions").close(prompt)
					if entry then
						apply(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

for key, picker in pairs({
	sg = { "git_commits", "Search Git commits" },
	sc = { "commands", "Search commands" },
	st = { "live_grep", "Search text" },
	sr = { "oldfiles", "Search recent files" },
	t = { "grep_string", "Search word under cursor" },
	["<CR>"] = { "git_files", "Search Git files" },
	f = { "find_files", "Find files" },
	sh = { "help_tags", "Search help" },
	["s/"] = { "live_grep", "Search open files", { grep_open_files = true } },
}) do
	vim.keymap.set("n", "<leader>" .. key, function()
		M.open(picker[1], picker[3])
	end, { desc = picker[2] })
end
vim.keymap.set("x", "<leader>t", function()
	local text = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() }), "\n")
	if text == "" then
		return
	end
	vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
	M.open("grep_string", {
		search = text,
		additional_args = text:find("\n", 1, true) and { "--multiline" } or nil,
	})
end, { desc = "Find selection, then refine matches" })
vim.keymap.set("n", "<leader>sd", function()
	M.diagnostics()
end, { desc = "Search diagnostics" })
vim.keymap.set("n", "<leader>sk", keymaps, { desc = "Search keymaps" })
vim.keymap.set("n", "<leader>sp", colorschemes, { desc = "Preview colorschemes" })
vim.keymap.set("n", "<leader>sn", function()
	M.open("find_files", { cwd = vim.fn.stdpath("config") })
end, { desc = "Search Neovim files" })
vim.keymap.set(
	"n",
	"<leader>u",
	require("buffer_policy").guard(function()
		M.setup()
		require("undo_picker").open()
	end),
	{ desc = "Search undo history" }
)
return M
