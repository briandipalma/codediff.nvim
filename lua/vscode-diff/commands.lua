-- Command implementations for vscode-diff
local M = {}

local git = require("vscode-diff.git")
local diff = require("vscode-diff.diff")
local render = require("vscode-diff.render")

--- Handles diffing the current buffer against a given git revision.
-- @param revision string: The git revision (e.g., "HEAD", commit hash, branch name) to compare the current file against.
-- This function chains async git operations to get git root, resolve revision to hash, and get file content.
local function handle_git_diff(revision)
  local current_file = vim.api.nvim_buf_get_name(0)

  if current_file == "" then
    vim.notify("Current buffer is not a file", vim.log.levels.ERROR)
    return
  end

  -- Determine filetype from current buffer (sync operation, no git involved)
  local filetype = vim.bo[0].filetype
  if not filetype or filetype == "" then
    filetype = vim.filetype.match({ filename = current_file }) or ""
  end

  -- Async chain: get_git_root -> resolve_revision -> get_file_content -> render_diff
  git.get_git_root(current_file, function(err_root, git_root)
    if err_root then
      vim.schedule(function()
        vim.notify(err_root, vim.log.levels.ERROR)
      end)
      return
    end

    local relative_path = git.get_relative_path(current_file, git_root)

    git.resolve_revision(revision, git_root, function(err_resolve, commit_hash)
      if err_resolve then
        vim.schedule(function()
          vim.notify(err_resolve, vim.log.levels.ERROR)
        end)
        return
      end

      git.get_file_content(revision, git_root, relative_path, function(err, lines_git)
        vim.schedule(function()
          if err then
            vim.notify(err, vim.log.levels.ERROR)
            return
          end

          -- Read fresh buffer content right before creating diff view
          local lines_current = vim.api.nvim_buf_get_lines(0, 0, -1, false)

          local lines_diff = diff.compute_diff(lines_git, lines_current)
          if not lines_diff then
            vim.notify("Failed to compute diff", vim.log.levels.ERROR)
            return
          end

          render.create_diff_view(lines_git, lines_current, lines_diff, {
            left_type = render.BufferType.VIRTUAL_FILE,
            left_config = {
              git_root = git_root,
              git_revision = commit_hash,
              relative_path = relative_path,
            },
            right_type = render.BufferType.REAL_FILE,
            right_config = {
              file_path = current_file,
            },
            filetype = filetype,
          })
        end)
      end)
    end)
  end)
end

local function handle_file_diff(file_a, file_b)
  local lines_a = vim.fn.readfile(file_a)
  local lines_b = vim.fn.readfile(file_b)

  local lines_diff = diff.compute_diff(lines_a, lines_b)
  if not lines_diff then
    vim.notify("Failed to compute diff", vim.log.levels.ERROR)
    return
  end

  -- Determine filetype from first file
  local filetype = vim.filetype.match({ filename = file_a }) or ""

  render.create_diff_view(lines_a, lines_b, lines_diff, {
    left_type = render.BufferType.REAL_FILE,
    left_config = { file_path = file_a },
    right_type = render.BufferType.REAL_FILE,
    right_config = { file_path = file_b },
    filetype = filetype,
  })
end

function M.vscode_diff(opts)
  local args = opts.fargs

  if #args == 0 then
    vim.notify("Usage: :CodeDiff <file_a> <file_b> OR :CodeDiff <revision>", vim.log.levels.ERROR)
    return
  end

  if #args == 1 then
    handle_git_diff(args[1])
  elseif #args == 2 then
    handle_file_diff(args[1], args[2])
  else
    vim.notify("Usage: :CodeDiff <file_a> <file_b> OR :CodeDiff <revision>", vim.log.levels.ERROR)
  end
end

return M
