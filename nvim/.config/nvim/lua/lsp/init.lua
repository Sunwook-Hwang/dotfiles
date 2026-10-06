-- Keep registration, server definitions and client lifecycle separate.
local policy = require("buffer_policy")
local shared = require("state")
local servers = require("lsp.servers")
local python = require("lsp.python")
local attach = require("lsp.keymaps")
local diagnostic_handlers = require("lsp.diagnostics")
require("lsp.lifecycle")

-- Find executables, then use vim.lsp.config/enable to attach to files of the corresponding language.
-- Do not attach to large files; <leader>ls restarts only clients attached to the current buffer.
-- Auxiliary servers need project evidence; primary language servers also support standalone files.
local function project_uses_server(server, dir)
	if not server.markers or vim.fs.root(dir, server.markers) then
		return true
	end
	if not server.dependency then
		return false
	end
	for _, path in ipairs(vim.fs.find("package.json", { path = dir, upward = true, type = "file", limit = math.huge })) do
		local file = io.open(path, "r")
		if file then
			local content = file:read(65536)
			file:close()
			local ok, package = pcall(vim.json.decode, content or "")
			if ok and type(package) == "table" then
				for _, field in ipairs({ "dependencies", "devDependencies", "peerDependencies" }) do
					if type(package[field]) == "table" and package[field][server.dependency] then
						return true
					end
				end
				if server.dependency == "eslint" and package.eslintConfig then
					return true
				end
			end
		end
	end
	return false
end
for _, server in ipairs(servers) do
	local spec, executable
	for _, candidate in ipairs(server.alternatives or { server.cmd }) do
		local path = shared.resolve_tool(candidate[1])
		if path ~= "" then
			spec, executable = candidate, path
			break
		end
	end
	if spec then
		local name = spec[1]
		local command = vim.deepcopy(spec)
		command[1] = executable
		vim.lsp.config(name, {
			cmd = command,
			handlers = diagnostic_handlers,
			filetypes = server.ft,
			settings = server.settings,
			init_options = server.init_options,
			on_init = function(client)
				if client.name == "ty" or client.name == "pyright-langserver" then
					-- Apply once before workspace/configuration and didOpen, including pending starts.
					python.apply(client)
				end
			end,
			on_attach = attach,
			root_dir = function(buf, on_dir)
				if not policy.allows(buf) then
					return
				end
				local file = vim.api.nvim_buf_get_name(buf)
				if file == "" or not project_uses_server(server, vim.fs.dirname(file)) then
					return
				end
				on_dir((shared.find_project(vim.fs.dirname(file))))
			end,
		})
		vim.lsp.enable(name)
	end
end
