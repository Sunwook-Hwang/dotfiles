;; Modified for FLASH: native entry point for exported static highlight definitions.
;; Native port of https://github.com/folke/tokyonight.nvim; see lua/themes/README.md for source and license.
;; 1:1 Steel port of nvim/.config/nvim/colors/tokyonight-night.lua
(require "theme_loader")
(apply-theme (hash "dark" "tokyonight-night-dark" "light" "tokyonight-night-dark"))
