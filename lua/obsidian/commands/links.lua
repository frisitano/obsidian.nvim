local log = require "obsidian.log"
local api = require "obsidian.api"
local actions = require "obsidian.actions"
local picker = require "obsidian.picker"

return function()
  local note = api.current_note(0)
  local source_bufnr = api.source_bufnr(0)
  local projection = vim.b.document_source
  local derived = type(projection) == "table" and type(projection.links) == "table" and projection.links or {}
  if not source_bufnr or (not note and #derived == 0) then
    return log.info "not in a note"
  end

  ---@type (string|obsidian.api.ProjectedLink)[]
  local entries = vim.tbl_map(function(match)
    return match.link
  end, note and note:links() or {})
  local seen = {}
  for _, entry in ipairs(derived) do
    if type(entry) == "table" and type(entry.link) == "string" and type(entry.source_path) == "string" then
      local key = entry.source_path .. "\0" .. entry.link
      if not seen[key] then
        entries[#entries + 1] = entry
        seen[key] = true
      end
    end
  end

  picker.select(entries, {
    prompt = "Links",
    format_item = function(entry)
      if type(entry) == "string" then
        return entry
      end
      return "Table: "
        .. (type(entry.display) == "string" and entry.display or entry.link)
        .. " · "
        .. entry.source_path
    end,
  }, function(items)
    local entry = items[1]
    if type(entry) == "string" then
      actions.follow_link(entry, { bufnr = source_bufnr })
    elseif entry then
      local bufnr = vim.fn.bufadd(entry.source_path)
      vim.fn.bufload(bufnr)
      actions.follow_link(entry.link, { bufnr = bufnr })
    end
  end)
end
