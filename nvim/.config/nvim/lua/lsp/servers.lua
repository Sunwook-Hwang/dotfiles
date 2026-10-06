local shared = require("state")

-- Neovim 0.12 built-in client. The executables listed below must already be installed.
-- Search PATH, then existing stdpath(data)/mason/bin directories.
-- Do not load Mason or install tools automatically.
-- .v is ambiguous with the V language; this profile uses it for Verilog.
vim.filetype.add({ extension = { v = "verilog", vh = "verilog", sv = "systemverilog", svh = "systemverilog" } })
local tsserver = shared.resolve_tool("tsserver")
local servers = {
	{ cmd = { "clangd" }, ft = { "c", "cpp", "objc", "objcpp", "cuda" } },
	{ cmd = { "mlir-lsp-server" }, ft = { "mlir" } },
	{ cmd = { "starpls", "server" }, ft = { "bzl" } },
	{ cmd = { "buf", "lsp", "serve" }, ft = { "proto" } },
	{ cmd = { "bash-language-server", "start" }, ft = { "sh" } },
	{
		alternatives = { { "neocmakelsp", "stdio" }, { "cmake-language-server" } },
		ft = { "cmake" },
	},
	{ cmd = { "yaml-language-server", "--stdio" }, ft = { "yaml" } },
	{ cmd = { "texlab" }, ft = { "tex", "plaintex" } },
	{ cmd = { "rust-analyzer" }, ft = { "rust" } },
	{ cmd = { "verible-verilog-ls" }, ft = { "verilog", "systemverilog" } },
	{ alternatives = { { "ty", "server" }, { "pyright-langserver", "--stdio" } }, ft = { "python" } },
	{
		cmd = { "lua-language-server" },
		ft = { "lua" },
		settings = {
			Lua = {
				diagnostics = { globals = { "vim" } },
				completion = { callSnippet = "Replace" },
			},
		},
	},
	{
		cmd = { "typescript-language-server", "--stdio" },
		init_options = tsserver ~= "" and { tsserver = { fallbackPath = tsserver } } or nil,
		ft = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	},
	{ cmd = { "vscode-html-language-server", "--stdio" }, ft = { "html" } },
	{ cmd = { "vscode-css-language-server", "--stdio" }, ft = { "css", "scss", "less" } },
	{
		cmd = { "tailwindcss-language-server", "--stdio" },
		markers = { "tailwind.config.js", "tailwind.config.cjs", "tailwind.config.mjs", "tailwind.config.ts" },
		dependency = "tailwindcss",
		ft = { "html", "css", "javascriptreact", "typescriptreact", "svelte" },
	},
	{ cmd = { "svelteserver", "--stdio" }, ft = { "svelte" } },
	{ cmd = { "graphql-lsp", "server", "-m", "stream" }, ft = { "graphql" } },
	{
		cmd = { "emmet-ls", "--stdio" },
		ft = { "html", "css", "javascriptreact", "typescriptreact" },
		markers = { ".emmet.json", "emmet.json" },
	},
	{ cmd = { "prisma-language-server", "--stdio" }, ft = { "prisma" } },
	{
		cmd = { "vscode-eslint-language-server", "--stdio" },
		markers = {
			"eslint.config.js",
			"eslint.config.mjs",
			"eslint.config.cjs",
			"eslint.config.ts",
			".eslintrc",
			".eslintrc.json",
			".eslintrc.js",
			".eslintrc.cjs",
			".eslintrc.yml",
			".eslintrc.yaml",
		},
		dependency = "eslint",
		ft = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
	},
}

return servers
