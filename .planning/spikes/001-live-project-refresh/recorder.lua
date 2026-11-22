-- Screen recorder: logs every screen change with a timestamp; control via files in $TCTL
local bin, cfg, out, ctl = vim.env.TBIN, vim.env.TCFG, vim.env.TOUT, vim.env.TCTL
vim.o.columns, vim.o.lines = 110, 18
local chan = vim.fn.jobstart({ bin, "-u", cfg .. "/init.lua", "-i", "NONE", "src/alpha.py" }, { term = true, env = { TERM = "xterm-256color" } })
local fh = io.open(out, "w")
local t0 = vim.uv.hrtime()
local function now() return math.floor((vim.uv.hrtime() - t0) / 1e6) end
local last = {}
local function poll()
  local lines = vim.api.nvim_buf_get_lines(0, 0, 16, false)
  for i, l in ipairs(lines) do
    l = l:gsub("%s+$", "")
    if last[i] ~= l then fh:write(("%6d SCREEN %2d| %s\n"):format(now(), i, l)); last[i] = l end
  end
  fh:flush()
end
vim.wait(2500, function() return false end)
vim.fn.chansend(chan, ":lua require('explorer').open(vim.fn.getcwd())\r"); vim.wait(800, function() return false end)
vim.fn.chansend(chan, "\23l"); vim.wait(500, function() return false end)  -- back to the file window
poll()
local stop = false
while not stop do
  vim.wait(40, function() return false end)
  poll()
  for name in vim.fs.dir(ctl) do
    local p = ctl .. "/" .. name
    local f = io.open(p); local body = f:read("*a"); f:close(); os.remove(p)
    fh:write(("%6d ACTION %s\n"):format(now(), name)); fh:flush()
    if name:match("quit") then stop = true elseif name:match("keys") then vim.fn.chansend(chan, body) end
  end
end
vim.fn.chansend(chan, "\27:qa!\r"); vim.wait(500, function() return false end); fh:close(); vim.cmd("qa!")
