local policy = require("buffer_policy")
local oil = require("oil")
local project = require("project")

oil.setup({
	columns = {}, -- File names only; no icon provider required.
	win_options = { number = false, relativenumber = false, statuscolumn = "" },
	view_options = { show_hidden = true }, -- Git-ignored files are visible too.
	watch_for_changes = false,
	keymaps = {
		-- Preserve the profile's window navigation, save and terminal keys.
		["<C-h>"] = false,
		["<C-l>"] = false,
		["<C-s>"] = false,
		["<C-t>"] = {
			callback = function()
				return require("terminal")()
			end,
			desc = "Toggle bottom terminal",
			mode = { "n", "i" },
		},
		["gv"] = { "actions.select", opts = { vertical = true } },
		["gh"] = { "actions.select", opts = { horizontal = true } },
		["gt"] = { "actions.select", opts = { tab = true } },
		["gR"] = "actions.refresh",
	},
})

-- -------------------------------------
-- File explorer: use the same package / standard-library / project boundaries as nopack.
-- -------------------------------------
do
	vim.api.nvim_create_autocmd("BufEnter", {
		group = vim.api.nvim_create_augroup("pack-project-root", { clear = true }),
		callback = function(args)
			local file = vim.api.nvim_buf_get_name(args.buf)
			if not policy.is_editor(0) or file == "" then
				return
			end
			local dir = vim.fs.dirname(file)
			local cached = project.for_dir(dir)
			if not cached.recognized then
				return
			end
			local root = cached.root
			if vim.fn.getcwd() ~= root then
				vim.cmd.lcd(vim.fn.fnameescape(root))
			end
		end,
	})
	vim.api.nvim_create_user_command("PackRefresh", function()
		vim.api.nvim_exec_autocmds("User", { pattern = "PackRefresh", modeline = false })
		vim.api.nvim_exec_autocmds("BufEnter", { group = "pack-project-root", buffer = 0, modeline = false })
		vim.cmd("redrawstatus")
	end, { desc = "Refresh project root and formatter availability" })
	vim.keymap.set("n", "<leader>e", function()
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "oil" then
				vim.api.nvim_set_current_win(win)
				oil.close()
				return
			end
		end
		local dir
		local wins = { vim.api.nvim_get_current_win() }
		vim.list_extend(wins, vim.api.nvim_tabpage_list_wins(0))
		for _, win in ipairs(wins) do
			local buf = vim.api.nvim_win_get_buf(win)
			local name = vim.api.nvim_buf_get_name(buf)
			if policy.is_editor(win) and name ~= "" then
				dir = vim.fs.dirname(name)
				vim.api.nvim_set_current_win(win)
				break
			end
		end
		oil.open(project.for_dir(dir or vim.fn.getcwd()).root)
	end, { desc = "Toggle file explorer" })
end
