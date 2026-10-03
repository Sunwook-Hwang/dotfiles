local Snacks = require("snacks")

-- -------------------------------------
-- Snacks pickers: retain the existing search and navigation keys.
-- -------------------------------------
do
	local pickers = {
		sg = { "git_log", "Search Git commits" },
		sc = { "commands", "Search commands" },
		st = { "grep", "Search text" },
		sd = { "diagnostics", "Search diagnostics" },
		sk = { "keymaps", "Search keymaps" },
		sr = { "recent", "Search recent files" },
		t = { "grep_word", "Search word under cursor" },
		["<CR>"] = { "git_files", "Search files in current Git" },
		f = { "files", "Find files" },
		sh = { "help", "Search help" },
		["s/"] = { "grep_buffers", "Search open files" },
		u = { "undo", "Search undo history" },
	}
	for key, picker in pairs(pickers) do
		vim.keymap.set("n", "<leader>" .. key, function()
			Snacks.picker[picker[1]]()
		end, { desc = picker[2] })
	end
	vim.keymap.set("n", "<leader>sp", function()
		local original, background = vim.g.colors_name or "default", vim.o.background
		local confirmed = false
		local function apply(name)
			vim.o.background = background
			vim.cmd("colorscheme " .. name)
		end
		Snacks.picker.colorschemes({
			preview = function(ctx)
				vim.schedule(function()
					apply(ctx.item.text)
				end)
				Snacks.picker.preview.file(ctx)
			end,
			confirm = function(picker, item)
				confirmed = item ~= nil
				picker:close()
				if item then
					vim.schedule(function()
						apply(item.text)
					end)
				end
			end,
			on_close = function()
				if not confirmed then
					vim.schedule(function()
						apply(original)
						vim.o.background = background
					end)
				end
			end,
		})
	end, { desc = "Preview colorschemes" })
	vim.keymap.set("n", "<leader>sn", function()
		Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
	end, { desc = "Search Neovim files" })
end
