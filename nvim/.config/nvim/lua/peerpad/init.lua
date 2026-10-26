-- Transport and edit algorithms load only when starting/joining a session.
local M = { config = { discovery = true, max_peers = 8, keymaps = false } }
local shortcuts = {
	{ "<leader>Ps", "Peerpad", "Peerpad: start sharing" },
	{ "<leader>Pj", "PeerpadJoin", "Peerpad: join current file" },
	{ "<leader>Pq", "PeerpadStop", "Peerpad: disconnect" },
	{ "<leader>Pi", "PeerpadStatus", "Peerpad: session information" },
}
local registered = {}
local actions = { Peerpad = "start", PeerpadJoin = "join", PeerpadStop = "stop", PeerpadStatus = "status" }
for _, action in pairs(actions) do
	M[action] = function(args)
		return require("peerpad.core")[action](args or {})
	end
end
function M.setup(opts)
	if vim.fn.has("nvim-0.12") == 0 then
		error("peerpad.nvim requires Neovim 0.12 or newer")
	end
	opts = opts or {}
	local config = vim.tbl_extend("force", M.config, opts)
	vim.validate("discovery", config.discovery, "boolean")
	vim.validate("keymaps", config.keymaps, "boolean")
	vim.validate("max_peers", config.max_peers, "number")
	assert(
		config.max_peers >= 2 and config.max_peers <= 64 and config.max_peers == math.floor(config.max_peers),
		"max_peers must be an integer between 2 and 64"
	)
	M.config = config
	for command, action in pairs(actions) do
		vim.api.nvim_create_user_command(command, function(args)
			local ok, err = pcall(M[action], args.fargs)
			if not ok then
				vim.notify(tostring(err), vim.log.levels.ERROR)
			end
		end, { nargs = "*", force = true, desc = "Peerpad: " .. action })
	end
	-- Remove only mappings still owned by us, including after a leader change.
	for lhs, rhs in pairs(registered) do
		if vim.fn.maparg(lhs, "n") == rhs then
			vim.keymap.del("n", lhs)
		end
	end
	registered = {}
	if config.keymaps then
		for _, shortcut in ipairs(shortcuts) do
			local lhs, command, desc = unpack(shortcut)
			if vim.fn.maparg(lhs, "n") == "" then
				local rhs = "<Cmd>" .. command .. "<CR>"
				vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
				registered[vim.fn.maparg(lhs, "n", false, true).lhs] = rhs
			end
		end
	end
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = vim.api.nvim_create_augroup("peerpad-discovery", { clear = true }),
		callback = function(args)
			local path = vim.api.nvim_buf_get_name(args.buf)
			if not M.config.discovery or vim.bo[args.buf].buftype ~= "" or path == "" then
				return
			end
			local sidecar = vim.fs.joinpath(vim.fs.dirname(path), "." .. vim.fs.basename(path) .. ".flash-share")
			vim.uv.fs_lstat(
				sidecar,
				vim.schedule_wrap(function(err, stat)
					if
						err
						or not stat
						or not M.config.discovery
						or vim.api.nvim_get_current_buf() ~= args.buf
						or vim.api.nvim_buf_get_name(args.buf) ~= path
						or not require("peerpad.buffer").is_editor(0)
					then
						return
					end
					local ok, err = pcall(require("peerpad.core").discover, args.buf, true)
					if not ok then
						vim.notify(tostring(err), vim.log.levels.ERROR)
					end
				end)
			)
		end,
	})
end
return M
