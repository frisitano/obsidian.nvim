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

T["links picker includes derived links with entry-relative native selection"] = function()
  child.lua [=[
    local folder = Obsidian.dir / "Entries"
    folder:mkdir()
    vim.fn.writefile({ "# Target", "", "## Heading" }, tostring(folder / "Target.md"))
    vim.fn.writefile({ "# Entry" }, tostring(folder / "Entry.md"))
    source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(source, tostring(Obsidian.dir / "Host.md"))
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "[[Authored]]" })
    viewer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(viewer, "obsidian-bases://6/Host.md")
    local derived = { link = "[Related](Target.md#Heading)", display = "Related", source_path = tostring(folder / "Entry.md") }
    vim.b[viewer].document_source = { buffer = source, links = { derived, derived } }
    vim.api.nvim_set_current_buf(viewer)
    require("obsidian.picker").select = function(entries, opts, choose)
      picked = entries
      label = opts.format_item(entries[2])
      choose { entries[2] }
    end
    vim.cmd "Obsidian links"
  ]=]
  h.child_wait(
    child,
    "return vim.api.nvim_buf_get_name(0) == tostring(Obsidian.dir / 'Entries' / 'Target.md')",
    { desc = "derived picker navigation" }
  )
  eq(2, child.lua_get "#picked")
  eq("[[Authored]]", child.lua_get "picked[1]")
  eq(true, child.lua_get "label:find('Table: Related', 1, true) ~= nil")
  eq(3, child.lua_get "vim.api.nvim_win_get_cursor(0)[1]")
  eq(1, child.lua_get "#require('obsidian.api').current_note(source):links()")
  eq(true, child.lua_get "vim.bo[source].modified")
end

T["relative derived targets from different entries are not deduplicated together"] = function()
  child.lua [=[
    source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(source, tostring(Obsidian.dir / "Host.md"))
    viewer = vim.api.nvim_create_buf(false, true)
    vim.b[viewer].document_source = { buffer = source, links = {
      { link = "[[Target]]", source_path = tostring(Obsidian.dir / "Left.md") },
      { link = "[[Target]]", source_path = tostring(Obsidian.dir / "Right.md") },
    } }
    vim.api.nvim_set_current_buf(viewer)
    require("obsidian.picker").select = function(entries) picked = entries end
    vim.cmd "Obsidian links"
  ]=]
  eq(2, child.lua_get "#picked")
end

T["standalone base projections expose derived links without an authored Markdown note"] = function()
  child.lua [=[
    source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(source, tostring(Obsidian.dir / "Tasks.base"))
    viewer = vim.api.nvim_create_buf(false, true)
    vim.b[viewer].document_source = { buffer = source, links = {
      { link = "[[Entry]]", source_path = tostring(Obsidian.dir / "Entry.md") },
    } }
    vim.api.nvim_set_current_buf(viewer)
    require("obsidian.picker").select = function(entries) picked = entries end
    vim.cmd "Obsidian links"
  ]=]
  eq(1, child.lua_get "#picked")
  eq("[[Entry]]", child.lua_get "picked[1].link")
end

return T
