# Native colorscheme snapshots

These are static native Neovim highlight and terminal-color definitions exported
from the theme versions installed in the package-based profile and ayu-vim. They require no
theme plugins, plugin manager, Treesitter, compiler cache or network access.
`colors/*.lua` exposes the same names and selects the dark/light definition.
`theme_loader.lua` reads only the selected snapshot; previewed tables are not
retained in `package.loaded`. The default FLASH colorscheme remains `retrobox`.

The snapshots include upstream highlight groups, including semantic-token and
Treesitter group names. Defining these groups does not load plugins or parsers.
Upstream setup callbacks, configuration APIs and dynamic plugin integrations are
not included. This is a fixed export, not automatic synchronization with pvi updates.
Copy `init.lua`, `lua/` and `colors/` together when transferring FLASH.

## Sources and licenses

TokyoNight and Ayu use Apache-2.0; the other six projects use MIT. Original license
texts and copyright notices are retained in `licenses/` and apply to the derived
definitions. The snapshots replace upstream executable theme logic with static
Neovim highlight tables; they are adapted exports, not the original plugins.

| Source | Exported revision | License |
| --- | --- | --- |
| [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) | [`cdc07ac78467`](https://github.com/folke/tokyonight.nvim/tree/cdc07ac78467a233fd62c493de29a17e0cf2b2b6) | [Apache-2.0](licenses/tokyonight.nvim.txt) |
| [catppuccin](https://github.com/catppuccin/nvim) | [`edefef779ab0`](https://github.com/catppuccin/nvim/tree/edefef779ab08ce1a4a404713e3012b0d202bd35) | [MIT](licenses/catppuccin.txt) |
| [kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim) | [`bb85e4bfc8d8`](https://github.com/rebelot/kanagawa.nvim/tree/bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3) | [MIT](licenses/kanagawa.nvim.txt) |
| [everforest](https://github.com/sainnhe/everforest) | [`85a86eb62409`](https://github.com/sainnhe/everforest/tree/85a86eb62409e3ec88713bff3d1b9d7374e112e4) | [MIT](licenses/everforest.txt) |
| [nightfox.nvim](https://github.com/EdenEast/nightfox.nvim) | [`4dacd3f0185a`](https://github.com/EdenEast/nightfox.nvim/tree/4dacd3f0185a2227bdf3b6c0975a8f0bf87cac9a) | [MIT](licenses/nightfox.nvim.txt) |
| [rose-pine](https://github.com/rose-pine/neovim) | [`ff483051a47e`](https://github.com/rose-pine/neovim/tree/ff483051a47e27d84bdef47703538df1ed9f4a47) | [MIT](licenses/rose-pine.txt) |
| [github-nvim-theme](https://github.com/projekt0n/github-nvim-theme) | [`c106c9472154`](https://github.com/projekt0n/github-nvim-theme/tree/c106c9472154d6b2c74b74565616b877ae8ed31d) | [MIT](licenses/github-nvim-theme.txt) |
| [ayu-vim](https://github.com/ayu-theme/ayu-vim) | [`01faacb4cb76`](https://github.com/ayu-theme/ayu-vim/tree/01faacb4cb76e8cf72ad9858c581d80876260ab3) | [Apache-2.0](licenses/ayu-vim.txt) |

## Colorscheme names

Ayu is exported from its original Vimscript into static native definitions.
Choose `ayu-dark`, `ayu-mirage` or `ayu-light` directly. `ayu` retains the upstream
`vim.g.ayucolor` selector (`dark` by default); the explicit names ignore that selector.

- **tokyonight.nvim**: `tokyonight`, `tokyonight-day`, `tokyonight-moon`, `tokyonight-night`, `tokyonight-storm`
- **catppuccin**: `catppuccin`, `catppuccin-frappe`, `catppuccin-latte`, `catppuccin-macchiato`, `catppuccin-mocha`, `catppuccin-nvim`
- **kanagawa.nvim**: `kanagawa`, `kanagawa-dragon`, `kanagawa-lotus`, `kanagawa-wave`
- **everforest**: `everforest`
- **ayu-vim**: `ayu`, `ayu-dark`, `ayu-mirage`, `ayu-light`
- **nightfox.nvim**: `carbonfox`, `dawnfox`, `dayfox`, `duskfox`, `nightfox`, `nordfox`, `terafox`
- **rose-pine**: `rose-pine`, `rose-pine-dawn`, `rose-pine-main`, `rose-pine-moon`
- **github-nvim-theme**: `github_dark`, `github_dark_colorblind`, `github_dark_default`, `github_dark_dimmed`, `github_dark_high_contrast`, `github_dark_tritanopia`, `github_light`, `github_light_colorblind`, `github_light_default`, `github_light_high_contrast`, `github_light_tritanopia`
