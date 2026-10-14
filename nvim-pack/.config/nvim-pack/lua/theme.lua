local cmd = vim.cmd

-- =========================================
-- ============== COLORSCHEME ==============
-- =========================================
-- GitHub themes hide inactive statuslines by default; configure only when selected.
vim.api.nvim_create_autocmd("ColorSchemePre", {
	pattern = "github_*",
	once = true,
	callback = function()
		require("github-theme").setup({ options = { hide_nc_statusline = false } })
	end,
})

vim.cmd([[colorscheme catppuccin]])

-- =========================================
-- ============== OPTIONAL THEME ===========
-- =========================================
local display = {
	transparent_window = false,
}

if display.transparent_window then
	cmd("au ColorScheme * hi Normal ctermbg=none guibg=none")
	cmd("au ColorScheme * hi SignColumn ctermbg=none guibg=none")
	cmd("au ColorScheme * hi NormalNC ctermbg=none guibg=none")
	cmd("au ColorScheme * hi MsgArea ctermbg=none guibg=none")
	cmd("au ColorScheme * hi TelescopeBorder ctermbg=none guibg=none")
	cmd("au ColorScheme * hi TelescopeNormal ctermbg=none guibg=none")
	cmd("let &fcs='eob: '")
end
