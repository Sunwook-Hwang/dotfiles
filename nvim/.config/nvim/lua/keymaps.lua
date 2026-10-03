local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ============== KEYMAPS: BASE ============
-- =========================================
-- Leave Insert mode with jk
vim.keymap.set("i", "jk", "<esc>", { noremap = true, silent = true })

-- Native pairs for file buffers; prompt input and large files stay literal.
local insert_pairs = { ["("] = ")", ["["] = "]", ["{"] = "}", ["'"] = "'", ['"'] = '"', ["`"] = "`" }
local function pair_escaped(text)
	return #(text:match("\\+$") or "") % 2 == 1
end
local function pair_mapping(key, callback, description)
	local plug = "<Plug>(nopack-pair-" .. key:byte() .. ")"
	-- Flush preceding typed characters before inspecting the cursor and buffer.
	vim.keymap.set("i", key, "<Ignore>" .. plug, { desc = description })
	vim.keymap.set("i", plug, callback, { expr = true })
end
for opening, closing in pairs(insert_pairs) do
	pair_mapping(opening, function()
		if not policy.allows(0) then
			return opening
		end
		local line, col = vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2]
		local before, after = line:sub(1, col), line:sub(col + 1, col + 1)
		if pair_escaped(before) then
			return opening
		end
		if opening == closing and after == closing then
			return "<C-g>U<Right>"
		end
		if after:match("[%w_]") or (opening == "'" and before:match("[%w_]$")) then
			return opening
		end
		return opening .. closing .. "<C-g>U<Left>"
	end, "Insert " .. opening .. closing .. " pair")
	if opening ~= closing then
		pair_mapping(closing, function()
			if policy.allows(0) then
				local line, col = vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2]
				if line:sub(col + 1, col + 1) == closing and not pair_escaped(line:sub(1, col)) then
					return "<C-g>U<Right>"
				end
			end
			return closing
		end, "Skip closing " .. closing)
	end
end
pair_mapping("<BS>", function()
	if policy.allows(0) then
		local line, col = vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0)[2]
		if
			col > 0
			and insert_pairs[line:sub(col, col)] == line:sub(col + 1, col + 1)
			and not pair_escaped(line:sub(1, col - 1))
		then
			return "<BS><Del>"
		end
	end
	return "<BS>"
end, "Delete an empty pair")

-- Clear search highlighting
vim.keymap.set("n", "<ESC>", ":nohl<CR>", { noremap = true, silent = true })

-- Increment/decrement
vim.keymap.set("n", "+", "<C-a>", { noremap = true, silent = true })
vim.keymap.set("n", "-", "<C-x>", { noremap = true, silent = true })

-- Terminal mode exit (double ESC)
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Add undo break-points
vim.keymap.set("i", ",", ",<c-g>u", { noremap = true, silent = true })
vim.keymap.set("i", ".", ".<c-g>u", { noremap = true, silent = true })
vim.keymap.set("i", ";", ";<c-g>u", { noremap = true, silent = true })
vim.keymap.set("i", "<", "<<C-g>u", { noremap = true, silent = true })

-- Window navigation (insert-mode alt-arrows)
vim.keymap.set("i", "<A-Up>", "<C-\\><C-N><C-w>k", { noremap = true, silent = true })
vim.keymap.set("i", "<A-Down>", "<C-\\><C-N><C-w>j", { noremap = true, silent = true })
vim.keymap.set("i", "<A-Left>", "<C-\\><C-N><C-w>h", { noremap = true, silent = true })
vim.keymap.set("i", "<A-Right>", "<C-\\><C-N><C-w>l", { noremap = true, silent = true })

-- Move line/block with Alt-j/k
vim.keymap.set("i", "<A-j>", "<ESC>:m .+1<CR>==gi", { noremap = true, silent = true })
vim.keymap.set("i", "<A-k>", "<ESC>:m .-2<CR>==gi", { noremap = true, silent = true })
vim.keymap.set("n", "<A-j>", ":m .+1<CR>==", { noremap = true, silent = true })
vim.keymap.set("n", "<A-k>", ":m .-2<CR>==", { noremap = true, silent = true })
vim.keymap.set("v", "<A-j>", ":m '>+1<CR>gv-gv", { noremap = true, silent = true })
vim.keymap.set("v", "<A-k>", ":m '<-2<CR>gv-gv", { noremap = true, silent = true })

-- Save
vim.keymap.set("i", "<C-s>", "<ESC><cmd>w<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<C-s>", ":w<CR>", { noremap = true, silent = true })

-- Better window movement (normal mode)
vim.keymap.set("n", "<C-h>", "<C-w>h", { noremap = true, silent = true })
vim.keymap.set("n", "<C-j>", "<C-w>j", { noremap = true, silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { noremap = true, silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { noremap = true, silent = true })
for _, direction in ipairs({ "h", "j", "k", "l" }) do
	vim.keymap.set("t", "<C-" .. direction .. ">", "<C-\\><C-n><C-w>" .. direction, { silent = true })
end

-- Resize with arrows
vim.keymap.set("n", "<S-Up>", ":resize -5<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<S-Down>", ":resize +5<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<S-Left>", ":vertical resize -5<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<S-Right>", ":vertical resize +5<CR>", { noremap = true, silent = true })
vim.keymap.set("t", "<S-Up>", function()
	vim.cmd("resize -5")
end, { silent = true })
vim.keymap.set("t", "<S-Down>", function()
	vim.cmd("resize +5")
end, { silent = true })
vim.keymap.set("t", "<S-Left>", function()
	vim.cmd("vertical resize -5")
end, { silent = true })
vim.keymap.set("t", "<S-Right>", function()
	vim.cmd("vertical resize +5")
end, { silent = true })

-- Leader mappings (yank/paste behavior tweaks)
vim.keymap.set("n", "x", [["_x]], { noremap = true, silent = true })
-- Native Visual P preserves the yank and the selection boundary, including EOL.
vim.keymap.set("x", "p", "P", { noremap = true, silent = true })
vim.keymap.set("x", "P", "P", { noremap = true, silent = true })

-- Search navigation keeps viewport centered
vim.keymap.set("n", "n", "nzzzv", { noremap = true, silent = true })
vim.keymap.set("n", "N", "Nzzzv", { noremap = true, silent = true })

-- Diff all windows
vim.keymap.set("n", "<leader>w", ":windo diffthis<CR>", {
	noremap = true,
	silent = true,
	desc = "Diff all windows",
})

-- Select entire file
vim.keymap.set("n", "<leader>a", "gg<S-v>G", {
	noremap = true,
	silent = true,
	desc = "Select entire file",
})

-- Substitute helpers: preserve registers and escape selected text literally.
for suffix, range in pairs({ Sa = "%", Sf = ".,$" }) do
	vim.keymap.set("n", "<leader>" .. suffix, ":" .. range .. "s/\\<<C-r><C-w>\\>/", { desc = "Substitute word" })
	vim.keymap.set("x", "<leader>" .. suffix, function()
		local saved = vim.fn.getreginfo('"')
		local zero = vim.fn.getreginfo("0")
		vim.cmd("normal! y")
		local pattern = vim.fn.escape(vim.fn.getreg('"'), [[\/]]):gsub("\n", [[\n]])
		vim.fn.setreg("0", zero)
		vim.fn.setreg('"', saved)
		local keys = ":" .. range .. "s/\\V" .. pattern .. "/"
		vim.api.nvim_feedkeys(keys, "ni", true)
	end, { desc = "Substitute selection" })
end

-- Keep selection when indenting
vim.keymap.set("v", "<", "<gv", { noremap = true, silent = true })
vim.keymap.set("v", ">", ">gv", { noremap = true, silent = true })

-- Yank highlight
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
	callback = function()
		shared.highlight_yank()
	end,
})

-- Send SSH/herdr yanks to the viewing terminal; keep p local without OSC52 reads.
if shared.use_osc52 then
	vim.api.nvim_create_autocmd("TextYankPost", {
		group = vim.api.nvim_create_augroup("nopack-osc52-yank", { clear = true }),
		callback = function()
			if vim.v.event.operator == "y" and vim.v.event.regname == "" then
				local lines = vim.deepcopy(vim.v.event.regcontents)
				if vim.v.event.regtype == "V" then
					lines[#lines + 1] = ""
				end
				if #table.concat(lines, "\n") > 100000 then
					vim.notify("OSC52 yank skipped: selection exceeds 100 KB", vim.log.levels.WARN)
					return
				end
				require("vim.ui.clipboard.osc52").copy("+")(lines)
			end
		end,
	})
end

-- =========================================
-- ============ KEYMAP HELPER ============
-- =========================================
-- 이후 공통 키맵에 silent와 설명을 붙이는 작은 헬퍼입니다.
function shared.map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc })
end
