-- Snacks owns pickers, dashboard, terminal and utility UI; Oil owns the explorer.
local Snacks = require("snacks")
local policy = require("buffer_policy")
local function dim_filter(buf)
	return policy.allows(buf) and vim.g.snacks_dim ~= false and vim.b[buf].snacks_dim ~= false
end
-- Keep the dashboard's three roles distinct across themes and profiles.
local function dashboard_highlights()
	for name, target in pairs({ Header = "Title", Desc = "String", Key = "Number" }) do
		vim.api.nvim_set_hl(0, "SnacksDashboard" .. name, { link = target })
	end
end
dashboard_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("PackDashboardColors", { clear = true }),
	callback = dashboard_highlights,
})
Snacks.setup({
	bigfile = require("bigfile"),
	quickfile = { enabled = true },
	explorer = { enabled = false },
	input = { enabled = true, icon = "" },
	statuscolumn = {
		enabled = true,
		left = { "sign", "git", "fold" },
		right = {},
	},
	scope = {
		-- Register guarded mappings below; resolve scopes only when requested.
		enabled = false,
		treesitter = { enabled = false },
		filter = policy.allows,
	},
	dim = {
		animate = { enabled = false },
		filter = dim_filter,
		scope = { treesitter = { enabled = false }, filter = dim_filter },
	},
	profiler = {
		on_stop = { highlights = false },
		icons = {
			time = "ms ",
			pct = "% ",
			count = "x ",
			require = "require ",
			modname = "module ",
			plugin = "plugin ",
			autocmd = "event ",
			file = "file ",
			fn = "fn ",
			status = "Profile ",
		},
	},
	notifier = {
		enabled = true,
		icons = { error = "E", warn = "W", info = "I", debug = "D", trace = "T" },
		-- Also suppress icons explicitly supplied by other plugins.
		filter = function(notification)
			notification.icon = ""
			return true
		end,
	},
	indent = {
		enabled = true,
		filter = function(buf)
			return policy.allows(buf) and vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false
		end,
		indent = { char = "┊" },
		scope = {
			enabled = false,
			-- Snacks attaches a scope listener even when its highlight is disabled.
			filter = function()
				return false
			end,
		},
		animate = { enabled = false },
	},
	scroll = {
		enabled = false,
		filter = function(buf)
			return policy.allows(buf) and vim.g.snacks_scroll ~= false and vim.b[buf].snacks_scroll ~= false
		end,
	},
	terminal = {
		win = { position = "bottom", height = 0.3, keys = { term_normal = false } },
	},
	lazygit = {
		configure = false, -- Use lazygit's own config and colors instead of the Neovim theme.
		win = {
			position = "float",
			height = 0.9,
			width = 0.9,
			backdrop = false,
			wo = { winhighlight = "Normal:Normal,NormalNC:Normal" },
		},
	},
	toggle = { which_key = false, notify = false },
	picker = {
		enabled = true,
		prompt = "> ",
		previewers = { diff = { style = "syntax" } },
		icons = {
			files = { enabled = false, dir = "", dir_open = "", file = "" },
			keymaps = { nowait = "" },
			undo = { saved = "S" },
			ui = { live = "LIVE", selected = "[x] ", unselected = "[ ] " },
			git = {
				commit = "",
				staged = "+",
				added = "+",
				deleted = "-",
				ignored = "!",
				modified = "M",
				renamed = "R",
				unmerged = "U",
				untracked = "?",
			},
			diagnostics = { Error = "E", Warn = "W", Hint = "H", Info = "I" },
			lsp = { unavailable = "X", enabled = "on", disabled = "off", attached = "attached" },
		},
		config = function(opts)
			-- Includes every kind supplied by Snacks, without a Nerd Font dependency.
			for kind in pairs(opts.icons.kinds) do
				opts.icons.kinds[kind] = kind .. " "
			end
		end,
		sources = {
			undo = {
				config = function()
					-- Snacks writes undo previews here, including on a fresh installation.
					vim.fn.mkdir(vim.fn.stdpath("cache"), "p")
				end,
				format = function(item, picker)
					local result = Snacks.picker.format.undo(item, picker)
					-- The current-entry marker is hard-coded in the upstream formatter.
					result[1][1] = item.current and "> " or "  "
					return result
				end,
			},
		},
	},
	dashboard = {
		enabled = true,
		preset = {
			header = table.concat({
				"",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡀⠀⠀⠀⠀⠀⡀⢀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠼⠤⠤⠤⠤⠤⣧⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡸⢸⠀⠀⠀⠀⠀⠀⡟⠀⣾⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⢸⠘⢏⠉⠉⠉⡽⡇⠀⢹⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⠀⢸⢠⠘⡆⠀⡸⠁⡇⡀⢸⡆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡰⠃⠀⡖⡞⣚⣆⣹⣼⣁⣀⢳⠓⠚⢹⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡴⠁⠀⠀⡇⣧⠀⢀⡜⢳⡀⠀⢸⠀⠀⠀⢣⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠜⠁⠀⠀⠀⡇⡟⢲⡞⠒⠒⢳⣺⢸⠀⠀⠀⠈⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⠋⠀⠀⠀⠀⠀⡇⡷⠃⡇⠀⠀⠀⢹⣸⠀⠀⠀⠀⠘⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⣠⢿⢓⣒⣓⣀⣀⣀⡞⠛⡖⠒⠢⠀⠀⡟⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⣠⠞⠁⠀⠀⠀⠀⠀⣠⠞⢹⢸⢸⠀⠀⠀⠀⠀⡇⠀⠘⢦⢰⠀⠀⡇⠘⣆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⢀⡤⠊⠁⠀⠀⠀⠀⠀⣠⠞⠁⠀⢸⢸⠘⠒⠲⠒⠒⠒⡇⠀⠀⠀⠳⡄⠀⡇⠀⠈⢆⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⢀⣠⠴⠊⠁⠀⠀⠀⠀⠀⢀⡤⡎⠁⠀⠀⠀⢸⢸⠀⠀⢀⠀⠀⠀⡇⠀⠀⠀⢀⠈⢦⡗⠀⠀⠈⢣⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡗⠒⡁⠀⠀⠀⠀⠀⠀⠀",
				"⠈⠁⠀⠀⠀⠀⠀⠀⢀⡠⠖⠁⠀⡇⠀⠀⠀⠀⠚⣾⠒⣒⠚⣢⠀⢰⠓⠒⠒⠒⠺⠀⠀⣟⢆⠀⠀⠀⡟⣄⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣑⡞⣹⡄⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⢀⣀⡤⠚⠁⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⢰⠀⠀⠀⠀⢸⢰⠀⠀⠀⠀⡇⠀⡇⠀⠙⠢⣄⡇⠈⠣⡀⠀⠀⠀⠀⣀⡴⣋⢼⡏⠠⢻⠘⢄⠀⠀⠀⠀⠀",
				"⢀⠤⠔⠊⠉⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⠘⠒⠒⢲⠒⢺⢸⠀⠀⠀⠀⡇⠀⡇⠀⠀⠀⠀⡏⠑⠒⢺⠓⠲⠶⡟⠓⠉⡇⢸⣇⣠⢸⠀⠀⡗⠦⣀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⣿⠀⠀⠀⢸⠀⢸⢸⠀⠀⠀⠀⡅⠀⣇⣀⣀⣀⠀⡇⠀⠠⢼⠤⠤⣤⣧⣤⣤⣧⣼⣧⣼⢸⠤⠤⠇⣀⣈⣉⡁",
				"⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⡇⠀⠀⠀⢀⣀⣿⠀⠤⠤⠼⠔⢺⢸⠀⠀⠀⠀⣏⣀⠧⡤⡤⣖⢒⣷⣚⡻⠭⠯⠭⠗⠒⠓⠒⠛⢻⣏⣹⢸⠉⠉⠁⠀⠐⠒⠂",
				"⠀⠀⠀⠀⠀⠀⡇⠀⠀⣀⡀⠤⠤⡗⠒⠈⠉⠁⠀⢸⠀⠀⠀⣀⣠⣼⢸⠀⠀⠀⠀⣇⠦⠽⠚⠒⠉⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⡟⢻⢸⣀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⢀⣀⠤⠔⡗⠉⠁⠀⠀⠀⠀⡇⠀⠀⠀⢀⡠⣼⠖⡘⢍⠰⡡⢺⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⠀⢀⠁⠀⠸⠇⠸⠼⠀⠈⠆⠢⠄⠀⠀",
				"⠐⠉⠁⠀⠀⠀⡇⠀⠀⠀⠀⠀⢀⣧⠤⠖⠋⢽⣠⢃⠞⣈⡶⠜⠒⢹⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⠔⡠⠌⢁⡐⠒⢒⡠⠀⢓⡈⠄⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⡇⠀⢀⡠⠔⠚⡍⠰⠎⣠⠒⣢⡥⢾⠋⠁⠀⠀⠀⢸⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠈⠉⢦⡀⠀⣀⠧⠚⠉⠒⠒⠒⠃⢀⣴⠗⠋⠁⡇⢸⠀⠐⠂⠢⠤⢼⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⢣⠈⠉⠉⠉⠉⠻⣉⡶⠖⠋⠀⠀⠀⠀⡇⢸⠀⠸⡉⠏⢐⣾⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
				"⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⣖⠒⠒⠠⡀⠀⠀⡇⢸⠀⠀⡱⠈⠁⣼⢸⠀⠀⠀⠀⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
			}, "\n"),
			keys = {
				{
					key = "f",
					desc = "Find file",
					action = function()
						Snacks.picker.files()
					end,
				},
				{
					key = "r",
					desc = "Recent files",
					action = function()
						Snacks.picker.recent()
					end,
				},
				{
					key = "l", desc = "Restore last session", action = ':lua require("persistence").load({ last = true })',
				},
				{
					key = "p",
					desc = "Select session",
					action = function()
						require("persistence").select()
					end,
				},
				{ key = "n", desc = "New file", action = ":ene | startinsert" },
				{
					key = "c",
					desc = "Config",
					action = function()
						vim.cmd.edit(vim.fn.stdpath("config") .. "/init.lua")
					end,
				},
				{
					key = "u",
					desc = "Update plugins",
					action = function()
						vim.pack.update()
					end,
				},
				{ key = "q", desc = "Quit", action = ":qa" },
			},
		},
		formats = {
			icon = function()
				return { "", width = 0 }
			end,
		},
		sections = {
			{ section = "header" },
			{ section = "keys", gap = 1, padding = 1 },
			{ text = { "https://sunwook-hwang.github.io", hl = "header" }, align = "center" },
		},
	},
})
-- Keep the original single sign column instead of Snacks' two sign slots.
vim.b.snacks_statuscolumn_right = false
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = vim.api.nvim_create_augroup("PackStatusColumn", { clear = true }),
	callback = function(ev)
		vim.b[ev.buf].snacks_statuscolumn_right = false
	end,
})
vim.keymap.set("n", "<leader>A", function()
	Snacks.dashboard()
end, { desc = "Open dashboard" })
for _, mapping in ipairs({
	{ "[i", "jump", "Jump to top edge of scope" },
	{ "]i", "jump", "Jump to bottom edge of scope" },
	{ "ii", "textobject", "Inner scope" },
	{ "ai", "textobject", "Full scope" },
}) do
	local jump = mapping[2] == "jump"
	vim.keymap.set(
		jump and { "n", "x", "o" } or { "x", "o" },
		mapping[1],
		policy.guard(function()
			Snacks.scope[mapping[2]]({
				cursor = false,
				min_size = jump and 1 or 2,
				edge = mapping[1] ~= "ii",
				bottom = mapping[1] == "]i",
			})
		end),
		{ silent = true, desc = mapping[3] }
	)
end
Snacks.toggle.indent():map("<leader>Ti")
Snacks.toggle.scroll():map("<leader>TS")
Snacks.toggle.dim():map("<leader>Tm")
Snacks.toggle.profiler():map("<leader>Dp")
Snacks.toggle.profiler_highlights():map("<leader>Dh")
vim.keymap.set("n", "<leader>DP", function()
	Snacks.profiler.pick()
end, { desc = "Show profiler results" })
