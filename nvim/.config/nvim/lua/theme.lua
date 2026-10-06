local shared = require("state")

-- =========================================
-- ======= DISPLAY / DEFAULT THEME =======
-- =========================================
-- Default theme and shared picker selection colors; statusline and buffer bar colors belong to their respective modules.
vim.cmd("colorscheme ayu-mirage")
function shared.picker_selection_highlight()
	local normal = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
	if normal.bg == nil then
		normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	end
	local selected = vim.api.nvim_get_hl(0, { name = "PmenuSel", link = false })
	local background = normal.bg or (vim.o.background == "dark" and 0x000000 or 0xffffff)
	local selected_background = selected.bg
	local function channels(color)
		return math.floor(color / 0x10000) % 0x100, math.floor(color / 0x100) % 0x100, color % 0x100
	end
	local red, green, blue = channels(background)
	if selected_background ~= nil then
		local selected_red, selected_green, selected_blue = channels(selected_background)
		local distance =
			math.max(math.abs(red - selected_red), math.abs(green - selected_green), math.abs(blue - selected_blue))
		if distance >= 32 then
			vim.api.nvim_set_hl(0, "NopackPickerSelection", selected)
			return
		end
	end
	local luminance = (red * 299 + green * 587 + blue * 114) / 1000
	local offset = luminance < 128 and 48 or -48
	local function shift(value)
		return math.max(0, math.min(255, value + offset))
	end
	local generated_red, generated_green, generated_blue = shift(red), shift(green), shift(blue)
	local generated = generated_red * 0x10000 + generated_green * 0x100 + generated_blue
	local generated_luminance = (generated_red * 299 + generated_green * 587 + generated_blue * 114) / 1000
	vim.api.nvim_set_hl(0, "NopackPickerSelection", {
		fg = generated_luminance < 128 and 0xffffff or 0x000000,
		bg = generated,
		bold = true,
	})
end
