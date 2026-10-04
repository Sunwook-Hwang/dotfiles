-- Standalone Neovide terminal profile; independent of pack/nopack editor settings.
vim.o.laststatus = 0
vim.o.cmdheight = 0
vim.o.showtabline = 0
vim.o.showmode = false
vim.o.ruler = false
-- Neovim selects pbcopy (macOS), wl-copy/xclip (Linux), or clip (Windows).
vim.o.clipboard = "unnamedplus"

-- Paste at the outer terminal, before herdr or a nested editor receives the keys.
if vim.g.neovide then
	local function paste()
		vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
	end
	for _, key in ipairs({ "<D-v>", "<C-v>", "<C-S-v>", "<S-Insert>" }) do
		vim.keymap.set("t", key, paste, { silent = true, desc = "Paste system clipboard" })
	end
end

vim.o.number = false
vim.o.relativenumber = false
vim.o.signcolumn = "no"

vim.o.background = "dark"
vim.cmd("colorscheme default")
vim.api.nvim_set_hl(0, "Normal", { fg = "#d0d0d0", bg = "#000000" })

-- The outer GUI renders nested Neovim too; prefer solid-dot Braille glyphs.
vim.o.guifont = "RobotoMono Nerd Font Mono,monospace:h14"

-- Cursor movement duration in seconds (not a 0..1 ratio):
-- 0 disables animation; 0.01 = 10 ms, 0.1 = 100 ms, 1 = 1 second. Higher is slower.
-- Short horizontal moves use Neovide's separate cursor_short_animation_length setting.
vim.g.neovide_cursor_animation_length = 0.01
-- Trail ratio, 0..1: near 0 = shortest trail, smoother motion with more front-edge lag;
-- 1 = front jumps immediately to the destination, with the longest trailing stretch.
-- A small trail value does not disable animation; use animation_length = 0 for that.
vim.g.neovide_cursor_trail_size = 0.01
vim.g.neovide_cursor_vfx_mode = "" -- No particle effects; movement animation is independent.

vim.g.neovide_scale_factor = 1.0

if vim.g.neovide and vim.fn.has("win32") == 1 then
	vim.keymap.set({ "n", "i", "v", "t" }, "<F11>", function()
		vim.g.neovide_fullscreen = not vim.g.neovide_fullscreen
	end, { desc = "Toggle fullscreen (Neovide Windows)" })
end

local function change_scale(delta)
	local new = vim.g.neovide_scale_factor * (1 + delta)
	if new < 0.3 then
		new = 0.3
	end
	vim.g.neovide_scale_factor = new
end

-- Windows/Linux
vim.keymap.set({ "n", "i", "v", "t" }, "<C-=>", function()
	change_scale(0.10)
end, { desc = "Zoom In (Neovide)" })
vim.keymap.set({ "n", "i", "v", "t" }, "<C-->", function()
	change_scale(-0.10)
end, { desc = "Zoom Out (Neovide)" })
vim.keymap.set({ "n", "i", "v", "t" }, "<C-0>", function()
	vim.g.neovide_scale_factor = 1.0
end, { desc = "Zoom Reset (Neovide)" })

-- macOS
vim.keymap.set({ "n", "i", "v", "t" }, "<D-=>", function()
	change_scale(0.10)
end, { desc = "Zoom In (Neovide macOS)" })
vim.keymap.set({ "n", "i", "v", "t" }, "<D-->", function()
	change_scale(-0.10)
end, { desc = "Zoom Out (Neovide macOS)" })
vim.keymap.set({ "n", "i", "v", "t" }, "<D-0>", function()
	vim.g.neovide_scale_factor = 1.0
end, { desc = "Zoom Reset (Neovide macOS)" })

-- terminal 열기
if vim.fn.has("win32") == 1 then
	-- cmd.exe history is session-only; persist PowerShell history after each command.
	local shell = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
	vim.fn.jobstart({
		shell,
		"-NoLogo",
		"-NoExit",
		"-Command",
		"Import-Module PSReadLine; Set-PSReadLineOption -HistorySaveStyle SaveIncrementally",
	}, { term = true, env = { NVIM_APPNAME = "" } })
else
	vim.fn.jobstart(vim.o.shell, { term = true, env = { NVIM_APPNAME = "" } })
end
vim.cmd("startinsert")
