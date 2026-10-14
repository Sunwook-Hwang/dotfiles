local M = {}

-- vim.pack's install/update hook and :PackBuildFzf share the same build command.
function M.fzf(path)
	path = path or vim.fn.stdpath("data") .. "/site/pack/core/opt/telescope-fzf-native.nvim"
	local commands = vim.fn.has("win32") == 1
			and {
				{ "cmake", "-S", ".", "-B", "build", "-DCMAKE_BUILD_TYPE=Release" },
				{ "cmake", "--build", "build", "--config", "Release", "--target", "install" },
			}
		or { { "make" } }
	for _, command in ipairs(commands) do
		if vim.fn.executable(command[1]) == 0 then
			vim.notify(
				"fzf-native needs a C compiler and " .. command[1] .. "; run :PackBuildFzf after installing them",
				vim.log.levels.WARN
			)
			return false
		end
		local result = vim.system(command, { cwd = path, text = true }):wait()
		if result.code ~= 0 then
			vim.notify("fzf-native build failed: " .. result.stderr, vim.log.levels.ERROR)
			return false
		end
	end
	return true
end

return M
