local policy = require("buffer_policy")
-- =========================================
-- ========= TREESITTER / SYNTAX =========
-- =========================================
-- Use built-in Treesitter when a language parser is included in the installation.
-- Otherwise retain standard syntax highlighting; do not download external parsers or queries.
vim.api.nvim_create_autocmd("FileType", {
	callback = function(args)
		if not policy.allows(args.buf) then
			return
		end
		local lang = vim.treesitter.language.get_lang(vim.bo[args.buf].filetype)
		if lang and pcall(vim.treesitter.language.add, lang) then
			pcall(vim.treesitter.start, args.buf, lang)
		end
	end,
})
