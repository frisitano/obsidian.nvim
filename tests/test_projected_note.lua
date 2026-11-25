local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["links command reads unsaved authored source, never the generated URI"] = function()
  child.lua [=[
    source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(source, tostring(Obsidian.dir / "Source.md"))
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "[[Unsaved#Heading|Alias]]" })
    viewer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(viewer, "obsidian-bases://6/Source.md")
    vim.api.nvim_buf_set_lines(viewer, 0, -1, false, { "[[Computed]]" })
    vim.b[viewer].document_source = { buffer = source, rows = { 0 } }
    vim.api.nvim_set_current_buf(viewer)
    require("obsidian.picker").select = function(entries) picked = entries end
    vim.cmd "Obsidian links"
  ]=]
  eq({ "[[Unsaved#Heading|Alias]]" }, child.lua_get "picked")
  eq(true, child.lua_get "vim.bo[source].modified")
  eq(true, child.lua_get "require('obsidian.api').current_note().bufnr == source")
end

T["invalid and cyclic projections never become notes"] = function()
  child.lua [=[
    viewer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(viewer, "obsidian-bases://6/Source.md")
    vim.api.nvim_set_current_buf(viewer)
  ]=]
  eq(true, child.lua_get "require('obsidian.api').current_note() == nil")
  child.lua [=[vim.b[viewer].document_source = { buffer = viewer }]=]
  eq(true, child.lua_get "require('obsidian.api').current_note() == nil")
  child.lua [=[vim.b[viewer].document_source = { buffer = 999999 }]=]
  eq(true, child.lua_get "require('obsidian.api').current_note() == nil")
end

T["unreadable file links return empty instead of throwing"] = function()
  eq({}, child.lua [=[return require("obsidian.search").find_links { path = tostring(Obsidian.dir / "missing.md") }]=])
end

T["native relative link resolution uses the authored source directory"] = function()
  child.lua [=[
    local folder = Obsidian.dir / "Folder"
    folder:mkdir()
    vim.fn.writefile({ "# Target", "", "## Heading" }, tostring(folder / "Target.md"))
    source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(source, tostring(folder / "Source.md"))
    viewer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(viewer, "obsidian-bases://6/Source.md")
    vim.b[viewer].document_source = { buffer = source }
    vim.api.nvim_set_current_buf(viewer)
    require("obsidian.lsp.handlers._definition").follow_link("[Alias](Target.md#Heading)", function(_, locations)
      resolved = locations
    end, {})
  ]=]
  h.child_wait(child, "return resolved ~= nil", { desc = "native relative link resolution" })
  eq(true, child.lua_get "resolved[1].uri == vim.uri_from_fname(tostring(Obsidian.dir / 'Folder' / 'Target.md'))")
  eq(2, child.lua_get "resolved[1].range.start.line")
end

return T
