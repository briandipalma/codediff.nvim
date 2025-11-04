-- Git operations module for vscode-diff
-- All operations are async and atomic
local M = {}

-- Run a git command asynchronously
-- Uses vim.system if available (Neovim 0.10+), falls back to vim.loop.spawn
local function run_git_async(args, opts, callback)
  opts = opts or {}

  -- Use vim.system if available (Neovim 0.10+)
  if vim.system then
    vim.system(
      vim.list_extend({ "git" }, args),
      {
        cwd = opts.cwd,
        text = true,
      },
      function(result)
        if result.code == 0 then
          callback(nil, result.stdout or "")
        else
          callback(result.stderr or "Git command failed", nil)
        end
      end
    )
  else
    -- Fallback to vim.loop.spawn for older Neovim versions
    local stdout_data = {}
    local stderr_data = {}

    local handle
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    ---@diagnostic disable-next-line: missing-fields
    handle = vim.loop.spawn("git", {
      args = args,
      cwd = opts.cwd,
      stdio = { nil, stdout, stderr },
    }, function(code)
      if stdout then stdout:close() end
      if stderr then stderr:close() end
      if handle then handle:close() end

      vim.schedule(function()
        if code == 0 then
          callback(nil, table.concat(stdout_data))
        else
          callback(table.concat(stderr_data) or "Git command failed", nil)
        end
      end)
    end)

    if not handle then
      callback("Failed to spawn git process", nil)
      return
    end

    if stdout then
      stdout:read_start(function(err, data)
        if err then
          callback(err, nil)
        elseif data then
          table.insert(stdout_data, data)
        end
      end)
    end

    if stderr then
      stderr:read_start(function(err, data)
        if err then
          callback(err, nil)
        elseif data then
          table.insert(stderr_data, data)
        end
      end)
    end
  end
end

-- ATOMIC ASYNC OPERATIONS
-- All functions below are simple, atomic git operations

-- Get git root directory for the given file (async)
-- callback: function(err, git_root)
function M.get_git_root(file_path, callback)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  dir = dir:gsub("\\", "/")

  run_git_async(
    { "rev-parse", "--show-toplevel" },
    { cwd = dir },
    function(err, output)
      if err then
        callback("Not in a git repository", nil)
      else
        local git_root = vim.trim(output)
        git_root = git_root:gsub("\\", "/")
        callback(nil, git_root)
      end
    end
  )
end

-- Get relative path of file within git repository (sync, pure computation)
function M.get_relative_path(file_path, git_root)
  local abs_path = vim.fn.fnamemodify(file_path, ":p")
  abs_path = abs_path:gsub("\\", "/")
  git_root = git_root:gsub("\\", "/")
  local rel_path = abs_path:sub(#git_root + 2)
  return rel_path
end

-- Resolve a git revision to its commit hash (async, atomic)
-- revision: branch name, tag, or commit reference
-- git_root: absolute path to git repository root
-- callback: function(err, commit_hash)
function M.resolve_revision(revision, git_root, callback)
  run_git_async(
    { "rev-parse", "--verify", revision },
    { cwd = git_root },
    function(err, output)
      if err then
        callback(string.format("Invalid revision '%s': %s", revision, err), nil)
      else
        local commit_hash = vim.trim(output)
        callback(nil, commit_hash)
      end
    end
  )
end

-- Get file content from a specific git revision (async, atomic)
-- revision: e.g., "HEAD", "HEAD~1", commit hash, branch name, tag
-- git_root: absolute path to git repository root
-- rel_path: relative path from git root (with forward slashes)
-- callback: function(err, lines) where lines is a table of strings
function M.get_file_content(revision, git_root, rel_path, callback)
  local git_object = revision .. ":" .. rel_path

  run_git_async(
    { "show", git_object },
    { cwd = git_root },
    function(err, output)
      if err then
        if err:match("does not exist") or err:match("exists on disk, but not in") then
          callback(string.format("File '%s' not found in revision '%s'", rel_path, revision), nil)
        else
          callback(err, nil)
        end
        return
      end

      local lines = vim.split(output, "\n")
      if lines[#lines] == "" then
        table.remove(lines, #lines)
      end

      callback(nil, lines)
    end
  )
end

return M
