-- Build label (D91, #225): formatting, the stamp, the fallback, and reading a fake .git dir.
local T = require("harness")
local Version = require("src.core.version")

local HASH = "a1bdb8c0123456789abcdef0123456789abcdef0"
local OTHER = "b2c3d4e50123456789abcdef0123456789abcdef"
local UNTAGGED = "c3d4e5f60123456789abcdef0123456789abcdef"

local function tmpDir(name)
  local dir = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
  dir = dir:gsub("\\", "/") .. "/idler_version_test_" .. name
  return dir
end

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function mkdir(path)
  if package.config:sub(1, 1) == "\\" then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" >nul 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

T.test("version: format shows tag, ahead count, short hash and dirty mark", function()
  T.eq(Version.format({ tag = "0.2.0", hash = HASH }), "0.2.0 · a1bdb8c")
  T.eq(Version.format({ tag = "0.2.0", hash = HASH, ahead = 3 }), "0.2.0+3 · a1bdb8c")
  T.eq(Version.format({ tag = "0.2.0", hash = HASH, dirty = true }), "0.2.0 · a1bdb8c*")
  T.eq(Version.format({ hash = HASH }), "dev · a1bdb8c", "no tag falls back to dev")
  T.eq(Version.format({}), "dev")
  T.eq(Version.format(nil), "dev")
end)

T.test("version: a stamp wins and is read as given", function()
  local v = Version.resolve({ stamp = { tag = "1.2.3", hash = "abcdef1234", ahead = 2, dirty = false } })
  T.eq(v.label, "1.2.3+2 · abcdef1")
  T.eq(v.tag, "1.2.3")
  T.eq(v.ahead, 2)
end)

T.test("version: no stamp and no checkout falls back to dev and never raises", function()
  local v = Version.resolve({ noStamp = true, noSource = true })
  T.eq(v.label, "dev")
  v = Version.resolve({ noStamp = true, root = tmpDir("missing_nothing_here") })
  T.eq(v.label, "dev")
  v = Version.resolve({ noStamp = true, root = 42 })
  T.eq(v.label, "dev", "a nonsense source dir is ignored")
end)

T.test("version: reads a plain .git dir (tag from packed-refs, detached and branch HEAD)", function()
  local root = tmpDir("plain")
  mkdir(root .. "/.git/refs/heads")
  write(root .. "/.git/HEAD", "ref: refs/heads/main\n")
  write(root .. "/.git/refs/heads/main", HASH .. "\n")
  write(root .. "/.git/packed-refs", "# pack-refs\n" .. OTHER .. " refs/tags/0.1.0\n" .. HASH .. " refs/tags/0.2.0\n")
  local v = Version.resolve({ noStamp = true, root = root })
  T.eq(v.hash, HASH)
  T.eq(v.tag, "0.2.0")
  T.eq(v.label, "0.2.0 · a1bdb8c")

  -- Past the tag: HEAD is a commit no tag points at.
  write(root .. "/.git/refs/heads/main", UNTAGGED .. "\n")
  v = Version.resolve({ noStamp = true, root = root })
  T.eq(v.label, "dev · c3d4e5f")

  -- Detached HEAD, annotated tag (peeled line).
  write(root .. "/.git/HEAD", HASH .. "\n")
  write(root .. "/.git/packed-refs", OTHER .. " refs/tags/0.3.0\n^" .. HASH .. "\n")
  v = Version.resolve({ noStamp = true, root = root })
  T.eq(v.label, "0.3.0 · a1bdb8c")

  -- The game folder is one level under the repository root.
  mkdir(root .. "/game")
  v = Version.resolve({ noStamp = true, root = root .. "/game" })
  T.eq(v.label, "0.3.0 · a1bdb8c")
end)

T.test("version: reads a worktree .git file and its common dir", function()
  local root = tmpDir("worktree")
  mkdir(root .. "/wt")
  mkdir(root .. "/main/worktrees/wt")
  write(root .. "/wt/.git", "gitdir: " .. root .. "/main/worktrees/wt\n")
  write(root .. "/main/worktrees/wt/HEAD", "ref: refs/heads/feature\n")
  write(root .. "/main/worktrees/wt/commondir", "../..\n")
  mkdir(root .. "/main/refs/heads")
  write(root .. "/main/refs/heads/feature", HASH .. "\n")
  write(root .. "/main/packed-refs", HASH .. " refs/tags/0.2.0\n")
  local v = Version.resolve({ noStamp = true, root = root .. "/wt" })
  T.eq(v.label, "0.2.0 · a1bdb8c")
end)

T.test("version: resolution is deterministic and get() is cached", function()
  local a = Version.resolve({ stamp = { tag = "1.0.0", hash = HASH } })
  local b = Version.resolve({ stamp = { tag = "1.0.0", hash = HASH } })
  T.eq(a.label, b.label)
  T.truthy(Version.get() == Version.get(), "same table every call")
  T.eq(type(Version.get().label), "string")
end)
