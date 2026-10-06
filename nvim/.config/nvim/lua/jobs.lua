local shared = require("state")

-- =========================================
-- ========= ASYNC COMMAND RUNNER ========
-- =========================================
-- Shared runner for search, Git and external formatters. A new request with the same key cancels the previous job.
-- Default limits: 5 seconds / 2 MiB stdout. Search accepts partial results; formatting and diffs require complete results.
-- :NopackCancel: cancel queued/running jobs and pickers.
shared.running = {}
local function stop_command_timer(task)
	if task.timer then
		task.timer:stop()
		if not task.timer:is_closing() then
			task.timer:close()
		end
		task.timer = nil
	end
end
function shared.cancel_command(key)
	local task = shared.running[key]
	-- Let an index transaction release its lock normally once writing has begun.
	if task and task.atomic then
		return
	end
	if task then
		task.cancelled = true
		stop_command_timer(task)
		task.chunks = nil
		if task.process then
			task.process:kill(9)
		end
		shared.running[key] = nil
	end
end
local function cancel_commands()
	-- Features own their queued work and invalidation; the runner owns processes.
	vim.api.nvim_exec_autocmds("User", { pattern = "NopackCancel", modeline = false })
	for key in pairs(shared.running) do
		shared.cancel_command(key)
	end
end
vim.api.nvim_create_user_command("NopackCancel", function()
	if shared.active_picker then
		shared.active_picker.close()
	end
	-- Restoring the editor can queue work through BufEnter; cancel after closing.
	cancel_commands()
end, {})
vim.api.nvim_create_autocmd("VimLeavePre", { callback = cancel_commands })
function shared.run_command(key, argv, opts, callback)
	shared.cancel_command(key)
	if shared.running[key] then
		return
	end
	local task = { chunks = {}, bytes = 0, errors = "", limited = false, atomic = opts.atomic }
	shared.running[key] = task
	local limit = opts.max_bytes or 2 * 1024 * 1024
	local ok, process = pcall(vim.system, argv, {
		cwd = opts.cwd,
		stdin = opts.stdin,
		stdout = function(err, data)
			if err then
				task.errors = tostring(err)
			end
			if not data or task.cancelled or task.limited then
				return
			end
			local remaining = limit - task.bytes
			task.chunks[#task.chunks + 1] = data:sub(1, remaining)
			task.bytes = task.bytes + math.min(#data, remaining)
			if #data > remaining then
				task.limited = true
				if task.process then
					task.process:kill(9)
				end
			end
		end,
		stderr = function(err, data)
			local message = data or (err and tostring(err)) or ""
			task.errors = (task.errors .. message):sub(1, 8192)
		end,
	}, function(result)
		vim.schedule(function()
			stop_command_timer(task)
			if task.cancelled then
				return
			end
			shared.running[key] = nil
			if task.limited and not opts.partial then
				task.chunks = nil
				if not opts.quiet then
					vim.notify(key .. ": time/output limit exceeded; result discarded", vim.log.levels.WARN)
				end
				if opts.failed then
					opts.failed()
				end
				return
			end
			if not task.limited and result.code ~= 0 and not (opts.no_match and result.code == 1) then
				task.chunks = nil
				if not opts.quiet then
					vim.notify(
						key .. ": " .. (task.errors ~= "" and task.errors or "command failed (" .. result.code .. ")"),
						vim.log.levels.WARN
					)
				end
				if opts.failed then
					opts.failed()
				end
				return
			end
			if task.limited then
				vim.notify(key .. ": limit reached; partial results", vim.log.levels.WARN)
			end
			local output = table.concat(task.chunks)
			task.chunks = nil
			callback(output, task.limited)
		end)
	end)
	if not ok then
		shared.running[key] = nil
		if not opts.quiet then
			vim.notify(key .. ": " .. tostring(process), vim.log.levels.WARN)
		end
		if opts.failed then
			opts.failed()
		end
		return
	end
	task.process = process
	if task.atomic then
		return
	end
	task.timer = vim.defer_fn(function()
		task.timer = nil
		if shared.running[key] == task and not task.cancelled then
			task.limited = true
			process:kill(9)
		end
	end, opts.timeout or 5000)
end
