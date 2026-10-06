local policy = require("buffer_policy")
local shared = require("state")
local format_status_cache = {}
shared.format_versions = {}
vim.api.nvim_create_autocmd("User", {
	pattern = "NopackCancel",
	callback = function()
		shared.format_versions = {}
	end,
})

-- =========================================
-- ============== FORMATTING =============
-- =========================================
-- Native Conform replacement: find external tools in PATH, then existing Mason bins; run asynchronously or fall back to LSP.
-- Prefer Ruff for Python, falling back to Black. Formatting is not automatic on save.
-- Apply external results only to changed line ranges; discard them if the buffer changes or is deleted during execution.
local prettier = { { "prettier", "--stdin-filepath", "%" } }
local formatters = {
	lua = { { "stylua", "--stdin-filepath", "%", "-" } },
	c = { { "clang-format", "--assume-filename=%" } },
	cpp = { { "clang-format", "--assume-filename=%" } },
	cuda = { { "clang-format", "--assume-filename=%" } },
	python = {
		{ "ruff", "format", "--stdin-filename", "%", "-" },
		{ "black", "--quiet", "--stdin-filename", "%", "-" },
	},
	javascript = prettier,
	javascriptreact = prettier,
	typescript = prettier,
	typescriptreact = prettier,
	html = prettier,
	css = prettier,
	scss = prettier,
	less = prettier,
	json = prettier,
	jsonc = prettier,
	yaml = prettier,
	markdown = prettier,
	["markdown.mdx"] = prettier,
	graphql = prettier,
	vue = prettier,
	handlebars = prettier,
	bzl = { { "buildifier", "-path", "%", "-" } },
	proto = { { "clang-format", "--assume-filename=%" } },
	sh = { { "shfmt", "-filename", "%" } },
	cmake = { { "cmake-format", "-" } },
	tex = { { "latexindent", "-" } },
	plaintex = { { "latexindent", "-" } },
	rust = { { "rustfmt", "--emit=stdout", "--edition=2021" } },
	verilog = { { "verible-verilog-format", "--stdin_name", "%", "-" } },
	systemverilog = { { "verible-verilog-format", "--stdin_name", "%", "-" } },
}
vim.api.nvim_create_autocmd({ "FileType", "BufFilePost", "BufWritePost", "BufWipeout" }, {
	group = vim.api.nvim_create_augroup("nopack-format-status", { clear = true }),
	callback = function(args)
		format_status_cache[args.buf] = nil
	end,
})
local function invalidate_format_status()
	format_status_cache = {}
end
vim.api.nvim_create_autocmd({ "FocusGained", "ShellCmdPost", "TermLeave", "TermClose" }, {
	group = "nopack-format-status",
	callback = invalidate_format_status,
})
vim.api.nvim_create_autocmd("User", {
	group = "nopack-format-status",
	pattern = "NopackRefresh",
	callback = invalidate_format_status,
})
function _G.NopackFormatStatus()
	if not shared.language_status_visible then
		return ""
	end
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	if not policy.is_source(buf) then
		return ""
	end
	if not vim.bo[buf].modifiable or not policy.allows(buf) then
		return "[FORMAT X]"
	end
	local key = { vim.bo[buf].filetype, vim.env.PATH or "", vim.fn.getcwd(win) }
	local cached = format_status_cache[buf]
	if not cached or not vim.deep_equal(cached.key, key) then
		cached = { key = key }
		for _, candidate in ipairs(formatters[vim.bo[buf].filetype] or {}) do
			if shared.resolve_tool(candidate[1]) ~= "" then
				cached.formatter = candidate[1]
				break
			end
		end
		format_status_cache[buf] = cached
	end
	if cached.formatter then
		return "[FORMAT: " .. cached.formatter .. "]"
	end
	local names = {}
	for _, client in ipairs(shared.status_clients(buf).clients) do
		if client:supports_method("textDocument/formatting", buf) then
			names[client.name:gsub("[%c]", " ")] = true
		end
	end
	local sorted = vim.fn.sort(vim.tbl_keys(names))
	return #sorted > 0 and ("[FORMAT: " .. table.concat(sorted, ", ") .. "]") or "[FORMAT X]"
end
shared.map("n", "<leader>lf", function()
	if not policy.is_source(0) or not vim.bo.modifiable then
		vim.notify("Open an editable file before formatting")
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local context = policy.source_context(buf)
	local file, filetype = context.file, context.filetype
	if not policy.allows(buf) then
		vim.notify("Formatting skipped: large-file protection is active")
		return
	end
	shared.cancel_command("format:" .. buf)
	local version = {}
	shared.format_versions[buf] = version
	local function is_current()
		if shared.format_versions[buf] ~= version or not policy.allows(buf) then
			return false
		end
		if not vim.bo[buf].modifiable or not policy.source_unchanged(context) then
			vim.notify("Buffer changed during formatting; result discarded")
			return false
		end
		return true
	end
	local root = shared.project_root()
	local candidates = formatters[filetype]
	local command
	for _, candidate in ipairs(candidates or {}) do
		local executable = shared.resolve_tool(candidate[1])
		if executable ~= "" then
			command = vim.deepcopy(candidate)
			command[1] = executable
			break
		end
	end
	if not command then
		if candidates then
			vim.notify("Formatter missing; trying LSP")
		end
		local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" })
		if #clients == 0 then
			vim.notify("No formatting provider for this buffer")
			return
		end
		local params = vim.lsp.util.make_formatting_params()
		-- Preserve sequential providers, checking edits and newer requests before each result.
		local function format_next(index)
			local client = clients[index]
			if not client or not is_current() then
				return
			end
			client:request("textDocument/formatting", params, function(err, edits)
				if not is_current() then
					return
				end
				if err then
					vim.notify("LSP formatting: " .. err.message, vim.log.levels.WARN)
					return
				end
				if edits and edits ~= vim.NIL then
					vim.lsp.util.apply_text_edits(edits, buf, client.offset_encoding)
				end
				context.tick = vim.api.nvim_buf_get_changedtick(buf)
				format_next(index + 1)
			end, buf)
		end
		format_next(1)
		return
	end
	local original_endofline = vim.bo[buf].endofline
	local input = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
		.. (original_endofline and "\n" or "")
	local function apply(content)
		if not is_current() then
			return
		end
		local edits = vim.text.diff(input, content, { result_type = "indices" })
		local lines = shared.records(content, "\n")
		for i = #edits, 1, -1 do
			local old_start, old_count, new_start, new_count = unpack(edits[i])
			local start = old_count == 0 and old_start or old_start - 1
			if i < #edits then
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("undojoin")
				end)
			end
			vim.api.nvim_buf_set_lines(
				buf,
				start,
				start + old_count,
				false,
				vim.list_slice(lines, new_start, new_start + new_count - 1)
			)
		end
		vim.bo[buf].endofline = original_endofline
	end
	-- Only formatter arguments contain placeholders; the resolved executable is literal.
	local args = vim.deepcopy(command)
	for i = 2, #args do
		args[i] = args[i]:gsub("%%", function()
			return file
		end)
	end
	shared.run_command("format:" .. buf, args, { stdin = input, cwd = root }, apply)
end, "Format asynchronously with installed tool or LSP")
vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
	callback = function(args)
		shared.format_versions[args.buf] = nil
		shared.cancel_command("format:" .. args.buf)
	end,
})

vim.api.nvim_create_autocmd("User", {
	pattern = "NopackBufferRestricted",
	callback = function(args)
		shared.format_versions[args.data.buf] = nil
		shared.cancel_command("format:" .. args.data.buf)
	end,
})
