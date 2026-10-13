-- Build identity (D91, #225): the tag and short commit hash of the running build, for the title
-- screen and the out-of-date save prompt. Pure: no love.graphics, never raises.
--
-- Resolution order:
--   1. the generated stamp `src/core/version_stamp.lua` (written by the release workflow and by
--      `tools/stamp_version.sh`; gitignored, so absent in source runs);
--   2. a git checkout around LÖVE's source dir, read directly from `.git` with plain io (no
--      subprocess: popen flashes a console window from a GUI build). Gives the hash always, and the
--      tag when HEAD sits exactly on a tag recorded in packed-refs;
--   3. the fallback "dev".

local Version = {}

local SHORT = 7 -- hash characters shown (git's own default abbreviation length)
local FALLBACK = "dev" -- shown in place of a tag when none is known

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local ok, data = pcall(f.read, f, "*a")
  f:close()
  if ok and type(data) == "string" and data ~= "" then
    return data
  end
  return nil
end

local function isHash(s)
  return type(s) == "string" and s:match("^%x+$") ~= nil and #s >= 40
end

--- The text shown for a version table `{ tag, hash, ahead, dirty }`: `0.2.0+3 · a1bdb8c*`.
function Version.format(info)
  info = info or {}
  local tag = info.tag
  if type(tag) ~= "string" or tag == "" then
    tag = FALLBACK
  end
  if (info.ahead or 0) > 0 then
    tag = tag .. "+" .. info.ahead
  end
  local hash = type(info.hash) == "string" and info.hash:sub(1, SHORT) or ""
  local label = tag
  if hash ~= "" then
    label = label .. " · " .. hash
  end
  if info.dirty then
    label = label .. "*"
  end
  return label
end

local function finish(info)
  info.label = Version.format(info)
  return info
end

--- Find the git dir for a checkout root: handles a plain `.git` directory and a worktree's `.git`
--- file ("gitdir: ..."). Returns gitdir, commondir (where refs and packed-refs live) or nil.
function Version.findGitDir(root)
  if readFile(root .. "/.git/HEAD") then
    return root .. "/.git", root .. "/.git"
  end
  local pointer = readFile(root .. "/.git")
  local dir = pointer and pointer:match("^gitdir:%s*([^\r\n]+)")
  if dir and readFile(dir .. "/HEAD") then
    local common = readFile(dir .. "/commondir")
    common = common and trim(common)
    if common and common ~= "" then
      if not (common:match("^/") or common:match("^%a:")) then
        common = dir .. "/" .. common
      end
    else
      common = dir
    end
    return dir, common
  end
  return nil
end

--- Read hash and (exact) tag from a git dir. Returns `{ hash, tag }` or nil.
function Version.readGit(gitdir, commondir)
  commondir = commondir or gitdir
  local head = readFile(gitdir .. "/HEAD")
  if not head then
    return nil
  end
  head = trim(head)
  local packed = readFile(commondir .. "/packed-refs") or ""
  local hash
  local ref = head:match("^ref:%s*(.+)$")
  if ref then
    local loose = readFile(commondir .. "/" .. ref) or readFile(gitdir .. "/" .. ref)
    hash = loose and trim(loose)
    if not isHash(hash) then
      hash = packed:match("(%x+) " .. ref:gsub("%p", "%%%0") .. "[\r\n]")
    end
  else
    hash = head
  end
  if not isHash(hash) then
    return nil
  end
  -- A tag that points at HEAD: annotated tags list the commit on a "^" line under the tag line.
  local tag
  local lastName
  for line in packed:gmatch("[^\r\n]+") do
    local peeled = line:match("^%^(%x+)")
    if peeled then
      if peeled == hash and lastName then
        tag = lastName
      end
    else
      local h, name = line:match("^(%x+) refs/tags/(.+)$")
      lastName = name
      if h == hash and name then
        tag = name
      end
    end
  end
  return { hash = hash, tag = tag }
end

local function fromSource(root)
  local gitdir, commondir
  local dir = root
  for _ = 1, 3 do -- the game folder sits one level under the repository root
    gitdir, commondir = Version.findGitDir(dir)
    if gitdir then
      break
    end
    dir = dir .. "/.."
  end
  if not gitdir then
    return nil
  end
  local found = Version.readGit(gitdir, commondir)
  if not found then
    return nil
  end
  return { tag = found.tag, hash = found.hash, ahead = 0, dirty = false }
end

--- Resolve without caching. `opts.stamp` (table) overrides the stamp module, `opts.root` the source
--- dir; `opts.noStamp` / `opts.noSource` skip a step. Tests use these; the game calls `get()`.
function Version.resolve(opts)
  opts = opts or {}
  local ok, result = pcall(function()
    local stamp = opts.stamp
    if stamp == nil and not opts.noStamp then
      local loaded, mod = pcall(require, "src.core.version_stamp")
      stamp = loaded and type(mod) == "table" and mod or nil
    end
    if type(stamp) == "table" and (stamp.tag or stamp.hash) then
      return finish({
        tag = stamp.tag,
        hash = stamp.hash,
        ahead = tonumber(stamp.ahead) or 0,
        dirty = stamp.dirty == true,
      })
    end
    if not opts.noSource then
      local root = opts.root
      if root == nil and love and love.filesystem and love.filesystem.getSource then
        root = love.filesystem.getSource()
      end
      if type(root) == "string" then
        local info = fromSource((root:gsub("\\", "/"):gsub("/+$", "")))
        if info then
          return finish(info)
        end
      end
    end
    return nil
  end)
  if ok and result then
    return result
  end
  return finish({ ahead = 0, dirty = false })
end

local cached

--- The running build's `{ tag, hash, ahead, dirty, label }`, resolved once.
function Version.get()
  if not cached then
    cached = Version.resolve()
  end
  return cached
end

return Version
