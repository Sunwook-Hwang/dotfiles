-- =========================================
-- ============ NATIVE PACKAGES ============
-- =========================================
local packages = {
	-- themes
	{ src = "https://github.com/folke/tokyonight.nvim" },
	{ src = "https://github.com/catppuccin/nvim", name = "catppuccin" },
	{ src = "https://github.com/rebelot/kanagawa.nvim" },
	{ src = "https://github.com/sainnhe/everforest" },
	{ src = "https://github.com/EdenEast/nightfox.nvim" },
	{ src = "https://github.com/rose-pine/neovim", name = "rose-pine" },
	{ src = "https://github.com/projekt0n/github-nvim-theme" },

	-- UI & sessions
	{ src = "https://github.com/folke/snacks.nvim" },
	{ src = "https://github.com/folke/persistence.nvim" },
	{ src = "https://github.com/folke/which-key.nvim" },

	-- git & navigation
	{ src = "https://github.com/lewis6991/gitsigns.nvim" },
	{ src = "https://github.com/stevearc/aerial.nvim" },
	{ src = "https://github.com/stevearc/oil.nvim" },
	{ src = "https://github.com/Sunwook-Hwang/peerpad.nvim" },

	-- formatting & tool management
	{ src = "https://github.com/stevearc/conform.nvim" },
	{ src = "https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim" },
	{ src = "https://github.com/mason-org/mason.nvim" },
}

-- Load at startup; configure dependencies before their consumers below.
-- Update plugins with :lua vim.pack.update()
vim.pack.add(packages, { confirm = false })
