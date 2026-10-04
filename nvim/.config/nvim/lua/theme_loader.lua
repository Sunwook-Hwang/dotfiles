-- Static native colors; no theme plugins, compile caches or retained palette tables.
local directory = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/themes/data/"
local M = {}

function M.apply(variants)
	local snapshot = assert(loadfile(directory .. variants[vim.o.background] .. ".lua"))()
	-- Changing background must not reload the previously selected colorscheme.
	vim.g.colors_name = nil
	vim.o.background = snapshot.background
	vim.cmd("highlight clear")
	if vim.g.syntax_on then
		vim.cmd("syntax reset")
	end
	for name, attributes in pairs(snapshot.highlights) do
		vim.api.nvim_set_hl(0, name, attributes)
	end
	for i = 0, 15 do
		vim.g["terminal_color_" .. i] = snapshot.terminal[tostring(i)]
	end
	vim.g.colors_name = snapshot.name
end

return M
