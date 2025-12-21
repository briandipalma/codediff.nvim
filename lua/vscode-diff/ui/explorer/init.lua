-- Git status explorer using nui.nvim
-- Public API for explorer module
local M = {}

-- Import submodules
local nodes = require("vscode-diff.ui.explorer.nodes")
local tree_module = require("vscode-diff.ui.explorer.tree")
local render = require("vscode-diff.ui.explorer.render")
local refresh = require("vscode-diff.ui.explorer.refresh")
local actions = require("vscode-diff.ui.explorer.actions")
-- filter is already standalone, no wiring needed

-- Wire up cross-module dependencies
tree_module._set_nodes_module(nodes)
render._set_nodes_module(nodes)
render._set_tree_module(tree_module)
refresh._set_tree_module(tree_module)
actions._set_refresh_module(refresh)

-- Delegate to render module
M.create = render.create

-- Delegate to refresh module
M.setup_auto_refresh = refresh.setup_auto_refresh
M.refresh = refresh.refresh

-- Delegate to actions module
M.navigate_next = actions.navigate_next
M.navigate_prev = actions.navigate_prev
M.toggle_visibility = actions.toggle_visibility
M.toggle_view_mode = actions.toggle_view_mode

return M
