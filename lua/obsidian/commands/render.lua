---Delegate optional Bases presentation to the standalone plugin.
return function()
  local available, bases = pcall(require, "obsidian_bases")
  if not available then
    vim.notify("Install obsidian-bases.nvim to render Bases", vim.log.levels.WARN)
    return
  end
  bases.render()
end
