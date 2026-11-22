-- SPIKE prototype: recursive project watcher -> run the same refresh the config does on FocusGained
local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
local explorer = require("explorer")
local pending, count, events = false, 0, 0
local log = io.open(vim.env.PROTO_LOG, "a")
local handle = assert(vim.uv.new_fs_event())
assert(handle:start(root, { recursive = true }, function(err, filename)
  events = events + 1
  -- git's own lock/refresh churn must not retrigger us
  if err or pending or (filename and (filename:match("%.lock$") or filename:match("^%.git/objects/"))) then return end
  pending = true
  vim.defer_fn(function()
    pending = false
    count = count + 1
    log:write(("refresh #%d (events so far %d) last=%s\n"):format(count, events, tostring(filename))); log:flush()
    vim.api.nvim_exec_autocmds("FocusGained", { modeline = false })
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if explorer.is_buffer(buf) then explorer.refresh(buf) end
    end
  end, 150)
end))
_G.SpikeWatch = handle
