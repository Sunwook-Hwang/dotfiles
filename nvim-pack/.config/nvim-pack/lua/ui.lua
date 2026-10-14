local policy = require("buffer_policy")
require("dashboard")
require("mini.notify").setup({
	lsp_progress = { enable = false },
	window = { winblend = 0 },
	content = {
		format = function(notification)
			return notification.msg
		end,
	},
})
require("mini.bufremove").setup({ silent = true })

local input = vim.ui.input
vim.ui.input = function(opts, callback)
	opts = opts or {}
	-- Preserve native completion/highlight support when requested by an input caller.
	if opts.completion or opts.highlight then
		return input(opts, callback)
	end
	local dialog = require("nui.input")({
		position = "50%",
		size = { width = math.min(60, vim.o.columns - 4) },
		border = { style = "rounded", text = { top = opts.prompt or "Input", top_align = "left" } },
	}, {
		default_value = opts.default or "",
		on_submit = callback,
		on_close = function()
			callback(nil)
		end,
	})
	dialog:mount()
	vim.keymap.set({ "i", "n" }, "<Esc>", function()
		dialog:unmount()
	end, { buffer = dialog.bufnr })
end
-- Load Telescope only when a selection is requested.
vim.ui.select = function(items, opts, callback)
	require("pickers").setup()
	return vim.ui.select(items, opts, callback)
end

local ibl = require("ibl")
ibl.setup({
	indent = { char = "┊", tab_char = "┊" },
	scope = { enabled = false },
	viewport_buffer = { min = 10 }, -- Limit off-screen work while retaining a scroll margin.
})
require("ibl.hooks").register(require("ibl.hooks").type.ACTIVE, policy.allows)
local indent_enabled = true
vim.keymap.set("n", "<leader>Ti", function()
	indent_enabled = not indent_enabled
	ibl.update({ enabled = indent_enabled })
end, { desc = "Toggle indent guides" })

-- Scope operations need no automatic drawing or CursorMoved listener.
for _, key in ipairs({ "[i", "]i", "ii", "ai" }) do
	local jump = key == "[i" or key == "]i"
	vim.keymap.set(
		jump and { "n", "x", "o" } or { "x", "o" },
		key,
		policy.guard(function()
			local scope = require("mini.indentscope")
			if jump then
				scope.operator(key == "[i" and "top" or "bottom", vim.fn.mode() == "n")
			else
				scope.textobject(key == "ai")
			end
		end),
		{ silent = true, desc = jump and "Jump to scope edge" or "Select indent scope" }
	)
end

local scroll_enabled = false
vim.keymap.set("n", "<leader>TS", function()
	scroll_enabled = not scroll_enabled
	local animate = require("mini.animate")
	if not _G.MiniAnimate then
		animate.setup({
			cursor = { enable = false },
			resize = { enable = false },
			open = { enable = false },
			close = { enable = false },
			scroll = { enable = scroll_enabled },
		})
	else
		animate.config.scroll.enable = scroll_enabled
	end
end, { desc = "Toggle smooth scroll" })

local dim_enabled = false
local dim_configured = false
local function apply_dim()
	if not dim_enabled then
		return
	end
	local allowed = policy.allows(0) and policy.is_editor(0)
	-- Twilight renders other windows too. Suspend it while a protected file is visible.
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if policy.is_source(buf) and not policy.allows(buf) then
			allowed = false
			break
		end
	end
	local twilight = require("twilight")
	if allowed then
		twilight.enable()
	else
		twilight.disable()
	end
end
vim.keymap.set("n", "<leader>Tm", function()
	dim_enabled = not dim_enabled
	local twilight = require("twilight")
	if not dim_configured then
		twilight.setup({ treesitter = false })
		dim_configured = true
	end
	if dim_enabled then
		apply_dim()
	else
		twilight.disable()
	end
end, { desc = "Toggle dimming" })
local function apply_policy(buf)
	vim.b[buf].minianimate_disable = not policy.allows(buf)
	apply_dim()
end
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
	callback = function(ev)
		apply_policy(ev.buf)
	end,
})
vim.api.nvim_create_autocmd("User", {
	pattern = "PackBufferRestricted",
	callback = function(ev)
		apply_policy(ev.data.buf)
		ibl.refresh(ev.data.buf)
	end,
})

local profiling = false
local profile_path = vim.fn.stdpath("state") .. "/lua-profile.log"
local function profile_results()
	if vim.fn.filereadable(profile_path) == 0 then
		vim.notify("No profile results yet")
		return
	end
	vim.cmd.sview(vim.fn.fnameescape(profile_path))
end
vim.keymap.set("n", "<leader>Dp", function()
	local profile = require("plenary.profile")
	if profiling then
		profile.stop()
		profiling = false
		profile_results()
	else
		vim.fn.mkdir(vim.fn.stdpath("state"), "p")
		profile.start(profile_path)
		profiling = true
		vim.notify("Lua profiling started")
	end
end, { desc = "Start/stop Lua profiling" })
vim.keymap.set("n", "<leader>DP", profile_results, { desc = "Show profiler results" })
