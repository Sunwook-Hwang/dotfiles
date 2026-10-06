local policy = require("buffer_policy")
local shared = require("state")

-- =========================================
-- ============= DIAGNOSTICS =============
-- =========================================
-- <leader>ld/lD/sd: current line, buffer list or all diagnostics; [d/]d: navigate; <leader>lt: toggle display.
shared.map("n", "<leader>ld", policy.guard(vim.diagnostic.open_float), "Line diagnostics")
shared.map(
	"n",
	"<leader>lD",
	policy.guard(function()
		shared.location_picker("Buffer diagnostics", vim.diagnostic.toqflist(vim.diagnostic.get(0)))
	end),
	"Select buffer diagnostic"
)
shared.map("n", "<leader>sd", function()
	shared.location_picker("Diagnostics", vim.diagnostic.toqflist(vim.diagnostic.get()))
end, "Select diagnostic")
shared.map(
	"n",
	"[d",
	policy.guard(function()
		vim.diagnostic.jump({ count = -1 })
	end),
	"Previous diagnostic"
)
shared.map(
	"n",
	"]d",
	policy.guard(function()
		vim.diagnostic.jump({ count = 1 })
	end),
	"Next diagnostic"
)
local diagnostics_enabled = true
shared.map("n", "<leader>lt", function()
	diagnostics_enabled = not diagnostics_enabled
	vim.diagnostic.enable(diagnostics_enabled)
end, "Toggle diagnostics")
