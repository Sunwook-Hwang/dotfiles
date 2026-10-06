local policy = require("buffer_policy")
local shared = require("state")

-- <leader>lv: select the current project's Python LSP environment; remembered per project until restart.
-- Do not create virtual environments or change the shell/formatter PATH; preserve symlink paths.
local python_paths = {}
local python_selection
local function cancel_python_selection(buf)
	local selection = python_selection
	if not selection or (buf and selection.buf ~= buf) then
		return
	end
	python_selection = nil
	shared.cancel_command("conda-envs")
	if selection.picker and shared.active_picker == selection.picker then
		selection.picker.close()
	end
end
local lsp_policy_group = vim.api.nvim_create_augroup("nopack-lsp-policy", { clear = true })
vim.api.nvim_create_autocmd("User", {
	group = lsp_policy_group,
	pattern = "NopackBufferRestricted",
	callback = function(args)
		local buf = args.data.buf
		cancel_python_selection(buf)
	end,
})
vim.api.nvim_create_autocmd({ "BufUnload", "BufFilePost", "FileType" }, {
	group = lsp_policy_group,
	callback = function(args)
		cancel_python_selection(args.buf)
	end,
})
vim.api.nvim_create_autocmd("User", {
	group = lsp_policy_group,
	pattern = "NopackCancel",
	callback = function()
		cancel_python_selection()
	end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = lsp_policy_group,
	callback = function()
		cancel_python_selection()
	end,
})
local function apply_python_path(client, path)
	client.settings = vim.deepcopy(client.settings)
	if client.name == "ty" then
		client.settings.ty = client.settings.ty or {}
		client.settings.ty.configuration = client.settings.ty.configuration or {}
		local configuration = client.settings.ty.configuration
		configuration.environment = configuration.environment or {}
		configuration.environment.python = path
		if not next(configuration.environment) then
			configuration.environment = vim.empty_dict()
		end
	else
		client.settings.python = client.settings.python or vim.empty_dict()
		client.settings.python.pythonPath = path
	end
	client.config.settings = client.settings
end
shared.map("n", "<leader>lv", function()
	if not policy.allows(0) then
		return
	end
	if vim.bo.filetype ~= "python" then
		vim.notify("Open a Python file to select its environment")
		return
	end
	cancel_python_selection()
	local selection = { buf = vim.api.nvim_get_current_buf() }
	python_selection = selection
	local function active()
		return python_selection == selection and policy.allows(selection.buf)
	end
	local root = shared.project_root()
	local choices, seen = {}, {}
	local function add(label, path)
		if path and path ~= "" and not seen[path] and vim.fn.executable(path) == 1 then
			seen[path] = true
			choices[#choices + 1] = { label = label .. ": " .. path, path = path }
		end
	end
	add("Selected", python_paths[root])
	add("Project .venv", root .. "/.venv/bin/python")
	add("Project venv", root .. "/venv/bin/python")
	add("Active venv", vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV .. "/bin/python")
	add("Active Conda", vim.env.CONDA_PREFIX and vim.env.CONDA_PREFIX .. "/bin/python")
	add("PATH python", vim.fn.exepath("python"))
	add("PATH python3", vim.fn.exepath("python3"))
	choices[#choices + 1] = { label = "Enter Python path...", manual = true }
	choices[#choices + 1] = { label = "Automatic (project settings / inherited PATH)" }
	local function select_path(path)
		if not active() then
			return
		end
		python_selection = nil
		local changed = python_paths[root] ~= path
		python_paths[root] = path
		local attached, restarting = false, false
		for _, client in ipairs(vim.lsp.get_clients()) do
			if (client.name == "ty" or client.name == "pyright-langserver") and client.config.root_dir == root then
				attached = true
				if changed then
					if client.name == "ty" then
						-- Restart ty so versions without didChangeConfiguration also reload imports.
						local id = require("lsp.lifecycle").restart(client)
						restarting = id ~= nil
					else
						apply_python_path(client, path)
						client:notify("workspace/didChangeConfiguration", { settings = client.settings })
					end
				end
			end
		end
		vim.notify(
			"Python: "
				.. (path or "automatic")
				.. (restarting and " (restarting ty)" or (attached and "" or " (applies when Python LSP attaches)"))
		)
	end
	local function choose(item)
		if not item or not active() then
			return
		end
		if not item.manual then
			select_path(item.path)
			return
		end
		vim.ui.input({ prompt = "Python executable or venv directory: ", completion = "file" }, function(path)
			if not active() or not path or path == "" then
				return
			end
			path = vim.fs.normalize(path)
			if path:sub(1, 1) ~= "/" then
				path = vim.fs.normalize(root .. "/" .. path)
			end
			if vim.fn.isdirectory(path) == 1 then
				path = path .. "/bin/python"
			end
			if vim.fn.executable(path) ~= 1 then
				vim.notify("Python executable not found: " .. path, vim.log.levels.WARN)
				return
			end
			select_path(path)
		end)
	end
	local function items()
		return vim.tbl_map(function(choice)
			return {
				label = choice.label,
				action = function()
					choose(choice)
				end,
			}
		end, choices)
	end
	local picker = shared.open_picker("Python environment: " .. vim.fn.fnamemodify(root, ":t"), {
		items = items(),
		cancel = function()
			shared.cancel_command("conda-envs")
		end,
		on_cancel = function()
			if python_selection == selection then
				python_selection = nil
			end
		end,
	})
	selection.picker = picker
	local conda = vim.fn.exepath("conda")
	if conda == "" and vim.env.CONDA_EXE and vim.fn.executable(vim.env.CONDA_EXE) == 1 then
		conda = vim.env.CONDA_EXE
	end
	if conda ~= "" then
		shared.run_command(
			"conda-envs",
			{ conda, "env", "list", "--json" },
			{ cwd = root, quiet = true },
			function(output)
				if picker.closed or not active() then
					return
				end
				local ok, result = pcall(vim.json.decode, output)
				if not ok or type(result) ~= "table" or type(result.envs) ~= "table" then
					return
				end
				for _, env in ipairs(result.envs) do
					if type(env) == "string" then
						local path = vim.fs.normalize(env)
						add("Conda " .. vim.fs.basename(path), path .. "/bin/python")
					end
				end
				picker.set_items(items())
			end
		)
	end
end, "Select Python environment for this project")

return {
	apply = function(client)
		apply_python_path(client, python_paths[client.config.root_dir])
	end,
}
