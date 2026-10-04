--.--.   ,--.,--.,--.   ,--.    ,------. ,-----. ,------.      ,---.  ,--. ,--.,--.  ,--.,--.   ,--. ,-----.  ,-----. ,--. ,--.
-- \  `.'  / |  ||   `.'   |    |  .---''  .-.  '|  .--. '    '   .-' |  | |  ||  ,'.|  ||  |   |  |'  .-.  ''  .-.  '|  .'   /
--  \     /  |  ||  |'.'|  |    |  `--, |  | |  ||  '--'.'    `.  `-. |  | |  ||  |' '  ||  |.'.|  ||  | |  ||  | |  ||  .   '
--   \   /   |  ||  |   |  |    |  |`   '  '-'  '|  |\  \     .-'    |'  '-'  '|  | `   ||   ,'.   |'  '-'  ''  '-'  '|  |\   \
--    `-'    `--'`--'   `--'    `--'     `-----' `--' '--'    `-----'  `-----' `--'  `--''--'   '--' `-----'  `-----' `--' '--'
--

if vim.fn.has("nvim-0.12") == 0 then
	error("This configuration requires Neovim 0.12 or newer")
end

-- A shell can retain a deleted working directory; Git cannot clone from it.
if vim.uv.cwd() == nil then
	vim.fn.chdir(vim.fn.expand("~"))
end

-- Resolve symlinks so modules also load when this file is used directly with -u.
local config_file = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2))
vim.opt.runtimepath:prepend(vim.fs.dirname(config_file))

-- Keep initialization order explicit; nopack remains a standalone configuration.
require("options")
require("keymaps")
require("plugins")
require("peerpad").setup({ keymaps = true })
require("ui")
require("context")
require("git")
require("session")
require("clipboard")
require("whichkey")
require("pickers")
require("breadcrumbs")
require("outline")
require("terminal")
require("format")
require("completion")
require("explorer")
require("lsp")
require("buffers")
require("statusline")
require("theme")
