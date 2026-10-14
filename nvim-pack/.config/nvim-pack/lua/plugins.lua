-- =========================================
-- ============ NATIVE PACKAGES ============
-- =========================================
local packages = {
	-- themes
	{ src = "https://github.com/ayu-theme/ayu-vim" },
	{ src = "https://github.com/folke/tokyonight.nvim" },
	{ src = "https://github.com/catppuccin/nvim", name = "catppuccin" },
	{ src = "https://github.com/rebelot/kanagawa.nvim" },
	{ src = "https://github.com/sainnhe/everforest" },
	{ src = "https://github.com/EdenEast/nightfox.nvim" },
	{ src = "https://github.com/rose-pine/neovim", name = "rose-pine" },
	{ src = "https://github.com/projekt0n/github-nvim-theme" },

	-- UI & sessions
	{ src = "https://github.com/goolord/alpha-nvim" },
	{ src = "https://github.com/nvim-mini/mini.notify" },
	{ src = "https://github.com/MunifTanjim/nui.nvim" },
	{ src = "https://github.com/lukas-reineke/indent-blankline.nvim" },
	{ src = "https://github.com/nvim-mini/mini.indentscope" },
	{ src = "https://github.com/nvim-mini/mini.animate" },
	{ src = "https://github.com/nvim-mini/mini.bufremove" },
	{ src = "https://github.com/folke/twilight.nvim" },

	-- Search and its native fuzzy sorter
	{ src = "https://github.com/nvim-lua/plenary.nvim" },
	{ src = "https://github.com/nvim-telescope/telescope.nvim" },
	{ src = "https://github.com/nvim-telescope/telescope-fzf-native.nvim" },
	{ src = "https://github.com/nvim-telescope/telescope-ui-select.nvim" },
	{ src = "https://github.com/debugloop/telescope-undo.nvim" },
	{ src = "https://github.com/folke/persistence.nvim" },
	{ src = "https://github.com/folke/which-key.nvim" },

	-- git & navigation
	{ src = "https://github.com/lewis6991/gitsigns.nvim" },
	{ src = "https://github.com/stevearc/aerial.nvim" },
	{ src = "https://github.com/stevearc/oil.nvim" },
	{ src = "https://github.com/malewicz1337/oil-git.nvim" },
	{ src = "https://github.com/Sunwook-Hwang/peerpad.nvim" },

	-- formatting & tool management
	{ src = "https://github.com/stevearc/conform.nvim" },
	{ src = "https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim" },
	{ src = "https://github.com/mason-org/mason.nvim" },
}

-- Rebuild the native sorter only when its source changes, never on ordinary startup.
vim.api.nvim_create_autocmd("PackChanged", {
	group = vim.api.nvim_create_augroup("PackNativeBuild", { clear = true }),
	callback = function(ev)
		if ev.data.spec.name == "telescope-fzf-native.nvim" and ev.data.kind ~= "delete" then
			require("native_build").fzf(ev.data.path)
		end
	end,
})

-- Configure dependencies before their consumers below.
-- Update plugins with :lua vim.pack.update()
vim.pack.add(packages, { confirm = false })
