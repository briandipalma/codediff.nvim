-- Node creation and formatting for explorer
-- Handles file/directory nodes, icons, status symbols, and tree structure
local M = {}

local Tree = require("nui.tree")
local NuiLine = require("nui.line")
local config = require("vscode-diff.config")

-- Merge artifact patterns (created by git mergetool)
local MERGE_ARTIFACT_PATTERNS = {
  "%.orig$",           -- file.orig
  "%.BACKUP%.",        -- file.BACKUP.xxxxx
  "%.BASE%.",          -- file.BASE.xxxxx
  "%.LOCAL%.",         -- file.LOCAL.xxxxx
  "%.REMOTE%.",        -- file.REMOTE.xxxxx
}

-- Status symbols and colors
local STATUS_SYMBOLS = {
  M = { symbol = "M", color = "DiagnosticWarn" },
  A = { symbol = "A", color = "DiagnosticOk" },
  D = { symbol = "D", color = "DiagnosticError" },
  ["??"] = { symbol = "??", color = "DiagnosticInfo" },
  ["!"] = { symbol = "!", color = "DiagnosticError" },  -- Merge conflict
}

-- Indent marker characters (neo-tree style)
local INDENT_MARKERS = {
  edge = "│",      -- Vertical line for non-last items
  item = "├",      -- Branch for non-last items
  last = "└",      -- Branch for last item
  none = " ",      -- Space when parent was last item
}

-- Check if a file path matches merge artifact patterns
local function is_merge_artifact(path)
  for _, pattern in ipairs(MERGE_ARTIFACT_PATTERNS) do
    if path:match(pattern) then
      return true
    end
  end
  return false
end

-- Filter out merge artifacts from file list
function M.filter_merge_artifacts(files)
  if not config.options.diff.hide_merge_artifacts then
    return files
  end
  
  local filtered = {}
  for _, file in ipairs(files) do
    if not is_merge_artifact(file.path) then
      table.insert(filtered, file)
    end
  end
  return filtered
end

-- File icons (basic fallback)
function M.get_file_icon(path)
  local has_devicons, devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    local icon, color = devicons.get_icon(path, nil, { default = true })
    return icon or "", color
  end
  return "", nil
end

-- Folder icon (configurable via config, with nerd font defaults)
function M.get_folder_icon(is_open)
  local explorer_config = config.options.explorer or {}
  local icons = explorer_config.icons or {}
  local defaults = config.defaults.explorer.icons
  if is_open then
    return icons.folder_open or defaults.folder_open, "Directory"
  else
    return icons.folder_closed or defaults.folder_closed, "Directory"
  end
end

-- Create flat file nodes (list mode)
function M.create_file_nodes(files, git_root, group)
  local nodes = {}
  for _, file in ipairs(files) do
    local icon, icon_color = M.get_file_icon(file.path)
    local status_info = STATUS_SYMBOLS[file.status] or { symbol = file.status, color = "Normal" }

    nodes[#nodes + 1] = Tree.Node({
      text = file.path,
      data = {
        path = file.path,
        status = file.status,
        old_path = file.old_path,  -- For renames: original path before rename
        icon = icon,
        icon_color = icon_color,
        status_symbol = status_info.symbol,
        status_color = status_info.color,
        git_root = git_root,
        group = group,
      }
    })
  end
  return nodes
end

-- Create tree nodes with directory hierarchy (tree mode)
function M.create_tree_file_nodes(files, git_root, group)
  -- Build directory structure
  local dir_tree = {}

  for _, file in ipairs(files) do
    local parts = {}
    for part in file.path:gmatch("[^/]+") do
      parts[#parts + 1] = part
    end

    local current = dir_tree
    for i = 1, #parts - 1 do
      local dir_name = parts[i]
      if not current[dir_name] then
        current[dir_name] = { _is_dir = true, _children = {} }
      end
      current = current[dir_name]._children
    end

    -- Add file at leaf
    local filename = parts[#parts]
    current[filename] = {
      _is_dir = false,
      _file = file,
    }
  end

  -- Convert to Tree.Node recursively
  -- indent_state: array of booleans, true = ancestor at that level is last child
  local function build_nodes(subtree, parent_path, indent_state)
    local nodes = {}
    local sorted_keys = {}

    for key in pairs(subtree) do
      sorted_keys[#sorted_keys + 1] = key
    end
    -- Sort: directories first, then files, alphabetically
    table.sort(sorted_keys, function(a, b)
      local a_is_dir = subtree[a]._is_dir
      local b_is_dir = subtree[b]._is_dir
      if a_is_dir ~= b_is_dir then
        return a_is_dir
      end
      return a < b
    end)

    local total = #sorted_keys
    for idx, key in ipairs(sorted_keys) do
      local item = subtree[key]
      local full_path = parent_path ~= "" and (parent_path .. "/" .. key) or key
      local is_last = (idx == total)

      -- Copy parent indent state and add current level
      local node_indent_state = {}
      for i, v in ipairs(indent_state) do
        node_indent_state[i] = v
      end
      node_indent_state[#node_indent_state + 1] = is_last

      if item._is_dir then
        -- Directory node - children need to know this dir's is_last status
        local children = build_nodes(item._children, full_path, node_indent_state)
        nodes[#nodes + 1] = Tree.Node({
          text = key,
          data = {
            type = "directory",
            name = key,
            dir_path = full_path,
            group = group,
            indent_state = node_indent_state,
          }
        }, children)
      else
        -- File node
        local file = item._file
        local icon, icon_color = M.get_file_icon(file.path)
        local status_info = STATUS_SYMBOLS[file.status] or { symbol = file.status, color = "Normal" }

        nodes[#nodes + 1] = Tree.Node({
          text = key,
          data = {
            path = file.path,
            status = file.status,
            old_path = file.old_path,
            icon = icon,
            icon_color = icon_color,
            status_symbol = status_info.symbol,
            status_color = status_info.color,
            git_root = git_root,
            group = group,
            indent_state = node_indent_state,
          }
        })
      end
    end

    return nodes
  end

  return build_nodes(dir_tree, "", {})
end

-- Prepare node for rendering (format display)
function M.prepare_node(node, max_width, selected_path, selected_group)
  local data = node.data
  local line = NuiLine()

  -- Group headers
  if data and data.type == "group" then
    local prefix = node:is_expanded() and "▾ " or "▸ "
    line:append(prefix, "Comment")
    line:append(data.label, "Title")
    line:append(string.format(" (%d)", data.count), "Comment")
    return line
  end

  -- Directory nodes (tree mode only)
  if data and data.type == "directory" then
    -- Build indent guides
    local indent_state = data.indent_state or {}
    local indent = ""
    for i = 1, #indent_state - 1 do
      if indent_state[i] then
        indent = indent .. INDENT_MARKERS.none .. "  "
      else
        indent = indent .. INDENT_MARKERS.edge .. "  "
      end
    end

    -- Add branch marker for current level
    if #indent_state > 0 then
      if indent_state[#indent_state] then
        indent = indent .. INDENT_MARKERS.last .. "─"
      else
        indent = indent .. INDENT_MARKERS.item .. "─"
      end
    end

    line:append(indent, "Comment")

    -- Folder icon
    local folder_icon, folder_color = M.get_folder_icon(node:is_expanded())
    line:append(folder_icon .. " ", folder_color)

    -- Directory name
    line:append(data.name, "Directory")
    return line
  end

  -- File nodes
  if data and data.path then
    local is_selected = (data.path == selected_path and data.group == selected_group)

    -- Build indent guides (tree mode)
    if data.indent_state then
      local indent = ""
      for i = 1, #data.indent_state - 1 do
        if data.indent_state[i] then
          indent = indent .. INDENT_MARKERS.none .. "  "
        else
          indent = indent .. INDENT_MARKERS.edge .. "  "
        end
      end

      if #data.indent_state > 0 then
        if data.indent_state[#data.indent_state] then
          indent = indent .. INDENT_MARKERS.last .. "─"
        else
          indent = indent .. INDENT_MARKERS.item .. "─"
        end
      end
      line:append(indent, "Comment")
    end

    -- Status symbol
    line:append(" " .. data.status_symbol .. " ", is_selected and "Visual" or data.status_color)

    -- File icon
    if data.icon and data.icon ~= "" then
      line:append(data.icon .. " ", is_selected and "Visual" or data.icon_color or "Normal")
    end

    -- File name (or relative path for list mode)
    local display_text
    if data.indent_state then
      -- Tree mode: show just filename
      display_text = node.text
    else
      -- List mode: show full relative path
      display_text = data.path
    end

    -- Handle renamed files (show old -> new)
    if data.old_path then
      display_text = data.old_path .. " → " .. display_text
    end

    -- Truncate if needed (prevent line wrapping)
    local current_len = line:width()
    local remaining = max_width - current_len - 2  -- -2 for safety margin
    if #display_text > remaining and remaining > 10 then
      display_text = display_text:sub(1, remaining - 3) .. "..."
    end

    line:append(display_text, is_selected and "Visual" or "Normal")

    return line
  end

  -- Fallback
  line:append(node.text or "", "Normal")
  return line
end

return M
