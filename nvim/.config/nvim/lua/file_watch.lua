-- Neovim 0.12 fallback. Watch parent directories so atomic saves keep working.
local api = vim.api
local policy = require("buffer_policy")
local directories, buffer_dirs = {}, {}

local function detach(buf)
	local dir = buffer_dirs[buf]
	if dir then
		local watch = directories[dir]
		buffer_dirs[buf], watch.files[buf] = nil, nil
		if not next(watch.files) then
			watch.handle:close()
			directories[dir] = nil
		end
	end
end

local function attach(buf)
	local path = api.nvim_buf_get_name(buf)
	if not policy.is_source(buf) or path == "" or path:match("^%a[%w+.-]*://") then
		return
	end
	path = vim.uv.fs_realpath(path) or path
	local dir, name = vim.fs.dirname(path), vim.fs.basename(path)
	if buffer_dirs[buf] == dir and directories[dir].files[buf] == name then
		return
	end
	detach(buf)
	local watch = directories[dir]
	if not watch then
		local handle = vim.uv.new_fs_event()
		if not handle then
			return
		end
		watch = { handle = handle, files = {}, pending = {} }
		local started = handle:start(dir, {}, function(err, filename)
			if err then
				return
			end
			for target, basename in pairs(watch.files) do
				if (not filename or filename == basename) and not watch.pending[target] then
					watch.pending[target] = true
					vim.defer_fn(function()
						watch.pending[target] = nil
						if watch.files[target] ~= basename or vim.bo[target].modified then
							return
						end
						local autoread = vim.bo[target].autoread
						if autoread or (autoread == nil and vim.go.autoread) then
							vim.cmd("checktime " .. target)
						end
					end, 100)
				end
			end
		end)
		if not started then
			handle:close()
			return
		end
		directories[dir] = watch
	end
	buffer_dirs[buf], watch.files[buf] = dir, name
end

return function(group)
	api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost", "BufWritePost" }, {
		group = group,
		callback = function(args)
			attach(args.buf)
		end,
	})
	api.nvim_create_autocmd({ "BufUnload", "BufFilePre", "BufWipeout" }, {
		group = group,
		callback = function(args)
			detach(args.buf)
		end,
	})
end
