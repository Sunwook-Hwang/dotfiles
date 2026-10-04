-- ============================================================================
--                   ________    ___   _____ __  __
--                  / ____/ /   /   | / ___// / / /
--                 / /_  / /   / /| | \__ \/ /_/ /
--                / __/ / /___/ ___ |___/ / __  /
--               /_/   /_____/_/  |_/____/_/ /_/
--
--                NO-PACK / SPEED MODE
--                Native Neovim. Zero third-party neovim plugins.
--                Dotfiles by Sunwook Hwang
-- ============================================================================
-- Neovim 0.12+; language servers and formatters are optional external tools.
-- Copy this file with the adjacent lua/ and colors/ directories.
if vim.fn.has("nvim-0.12") == 0 then
	error("This nopack config requires Neovim 0.12 or newer")
end

-- Resolve symlinks so direct -u launches find this profile's modules too.
local config_file = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2))
local config_root = vim.fs.dirname(config_file)
vim.opt.runtimepath:prepend(config_root)
require("state").config_root = config_root

-- Preserve initialization order; shared functions are defined before events run.
require("options")
require("bigfile")
require("keymaps")
require("theme")
require("statusline")
require("indent")
require("explorer")
require("completion")
require("navigation")
require("buffers")
require("project")
require("jobs")
require("pickers")
require("search")
require("editing")
require("terminal")
require("session")
require("dashboard")
require("git")
require("format")
require("tags")
require("lsp")
require("outline")
require("diagnostics")
require("syntax")
require("context")
require("breadcrumbs")
require("whichkey")

-- FLASH integration; reusable peerpad code lives in lua/peerpad/.
require("peerpad.config")
