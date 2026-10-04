-- Modified for FLASH: native entry point for exported Ayu definitions.
-- Source and Apache-2.0 license: see lua/themes/README.md.
local style = vim.g.ayucolor or "dark"
local snapshot = style == "dark" and "ayu" or "ayu-" .. style
require("theme_loader").apply({ dark = snapshot, light = snapshot })
