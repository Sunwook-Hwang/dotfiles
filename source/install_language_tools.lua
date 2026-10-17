-- Setup-only installer. FLASH never loads Mason while editing.
local tools = {
	{ "clangd", "clangd" },
	{ "clang-format", "clang-format" },
	{ "mlir-lsp-server" }, -- Supplied by the system LLVM/MLIR package.
	{ "starpls", "starpls" },
	{ "buf", "buf" },
	{ "bash-language-server", "bash-language-server" },
	{ "neocmakelsp", "neocmakelsp" },
	{ "yaml-language-server", "yaml-language-server" },
	{ "texlab", "texlab" },
	{ "rust-analyzer", "rust-analyzer" },
	{ "rustfmt" }, -- Supplied by the system Rust package.
	{ "verible-verilog-ls", "verible" },
	{ "verible-verilog-format", "verible" },
	{ "ty", "ty" },
	{ "lua-language-server", "lua-language-server" },
	{ "typescript-language-server", "typescript-language-server" },
	{ "vscode-html-language-server", "html-lsp" },
	{ "vscode-css-language-server", "css-lsp" },
	{ "tailwindcss-language-server", "tailwindcss-language-server" },
	{ "svelteserver", "svelte-language-server" },
	{ "graphql-lsp", "graphql-language-service-cli" },
	{ "emmet-ls", "emmet-ls" },
	{ "prisma-language-server", "prisma-language-server" },
	{ "vscode-eslint-language-server", "eslint-lsp" },
	{ "stylua", "stylua" },
	{ "ruff", "ruff" },
	{ "prettier", "prettier" },
	{ "buildifier", "buildifier" },
	{ "shfmt", "shfmt" },
	{ "cmake-format", "cmakelang" },
	{ "latexindent", "latexindent" },
	{ "fzf" }, -- Supplied by the system package manager.
}
local temporary
-- Mason's headless command exits directly on failure, so cleanup must also run on exit.
vim.api.nvim_create_autocmd("VimLeavePre", {
	once = true,
	callback = function()
		if temporary then
			vim.fn.delete(temporary, "rf")
		end
	end,
})
local ok, err = xpcall(function()
	local bin = vim.fn.expand("~/.local/bin")
	local mason = vim.fn.stdpath("data") .. "/mason"
	vim.env.PATH = bin .. ":" .. (vim.env.PATH or "") .. ":" .. mason .. "/bin"
	local packages, repair = {}, {}
	for _, tool in ipairs(tools) do
		local missing = vim.fn.exepath(tool[1]) == ""
		if tool[2] and (missing or vim.uv.fs_stat(mason .. "/packages/" .. tool[2])) then
			packages[tool[2]] = true
			repair[tool[2]] = repair[tool[2]] or missing
		end
	end
	if next(packages) then
		temporary = vim.fn.tempname()
		local clone = vim.system({
			"git",
			"clone",
			"--quiet",
			"--depth",
			"1",
			"--branch",
			"v2.3.1",
			"https://github.com/mason-org/mason.nvim.git",
			temporary,
		}, { text = true }):wait(120000)
		assert(clone.code == 0, "Cannot download setup installer: " .. (clone.stderr or "git failed"))
		vim.opt.runtimepath:prepend(temporary)
		require("mason").setup({ install_root_dir = mason, PATH = "append", max_concurrent_installers = 2 })
		local registry = require("mason-registry")
		local refreshed, succeeded, details = false, false, nil
		registry.update(function(success, result)
			succeeded, details, refreshed = success, result, true
		end)
		assert(
			vim.wait(120000, function()
				return refreshed
			end, 100),
			"Mason registry update timed out"
		)
		assert(succeeded, "Cannot update Mason registry: " .. vim.inspect(details))
		local install = {}
		for _, name in ipairs(vim.fn.sort(vim.tbl_keys(packages))) do
			local package = registry.get_package(name)
			if repair[name] or package:get_installed_version() ~= package:get_latest_version() then
				install[#install + 1] = name
			end
		end
		if #install > 0 then
			-- Reinstall outdated packages; leave current versions and external tools alone.
			-- The headless command waits for every installation and fails on any error.
			vim.cmd("MasonInstall --force " .. table.concat(install, " "))
		end
	end
	local missing = {}
	vim.fn.mkdir(bin, "p")
	for _, tool in ipairs(tools) do
		local executable = tool[1]
		if vim.fn.exepath(executable) == "" then
			missing[#missing + 1] = executable
		elseif vim.fn.exepath(executable) == mason .. "/bin/" .. executable then
			-- Expose installed tools to all FLASH profiles without loading Mason.
			local target = bin .. "/" .. executable
			assert(not vim.uv.fs_lstat(target), "Cannot replace existing file: " .. target)
			local linked, reason = vim.uv.fs_symlink(mason .. "/bin/" .. executable, target)
			assert(linked, "Cannot link " .. executable .. ": " .. tostring(reason))
		end
	end
	assert(
		#missing == 0,
		"Language tool installation failed or system package unavailable: "
			.. table.concat(missing, ", ")
			.. ". See "
			.. vim.fn.stdpath("log")
			.. "/mason.log"
	)
end, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit")
else
	vim.cmd("qall")
end
