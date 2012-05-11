----
-- Lsyncd script to update ctags files when files are changed. It requires
-- lsyncd and exuberant ctags to be installed.
--
-- To use, create a file called '.lctags-root.lua' in the same directory as this
-- script containing a single line of the form:
--
--  return '/path/to/root/of/my/code/directory'
--
-- The script will then monitor all files and directories under that directory for
-- any changes. When a change is detected, ctags will be run, and the resulting
-- tags will be placed in the first '.tags' file the script finds when walking up
-- the directory tree from the changed file or folder. If none is found, the tags
-- will not be generated.
--
-- This script runs ctags recursively, and it may generate more tags than you
-- intend. You can use '.tags.exclude' files to prevent ctags from generating
-- any tags for a file or a directory. The '.tags.exclude' file should be in
-- the same directory as the '.tags' file it corresponds to. List the exclusions
-- one per line.
----

----
-- Support functions.
----

function fileExists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

function split(str, pat)
   local t = {}
   local fpat = "(.-)" .. pat
   local last_end = 1
   local s, e, cap = str:find(fpat, 1)
   while s do
      if s ~= 1 or cap ~= "" then
   table.insert(t,cap)
      end
      last_end = e+1
      s, e, cap = str:find(fpat, last_end)
   end
   if last_end <= #str then
      cap = str:sub(last_end)
      table.insert(t, cap)
   end
   return t
end

function splitPath(str)
  return split(str, '[\\/]+')
end

function joinPath(pathComponents)
  return '/' .. table.concat(pathComponents, '/')
end

function findUp(path, name)
  local pathComponents = splitPath(path)

  -- Remove the last element if it's a filename.
  if string.sub(path, -1) ~= '/' then
    table.remove(pathComponents)
  end

  repeat
    local f = joinPath(pathComponents) .. '/' .. name

    -- If the file exists, return both its path and the directory that contains it.
    if fileExists(f) then return f, (joinPath(pathComponents) .. '/') end

    table.remove(pathComponents)
  until next(pathComponents) == nil

  -- We didn't find it anywhere.
  return nil, nil
end

function any(tbl, test)
  for _, v in pairs(tbl) do
    if test(v) then return true end
  end
  return false
end


----
-- Ctags action implementation.
----

function shouldIgnore(event, path)
  local pathComponents = splitPath(path)
  local filename = pathComponents[#pathComponents]

  -- We never ignore directories, and we always ignore the tags file.
  if string.sub(path, -1) == '/'           then return false
  elseif filename == event.config.tagsFile then return true
  else
    local ftypes = assert(event.config.ftypes)

    for k, ft in pairs(ftypes) do
      -- We shouldn't ignore the file if it matches one of ctags' filetypes.
      if string.find(filename, ft) then return false end
    end

    -- By default, we ignore the file.
    return true
  end
end

function findTagsFiles(event)
  local tagsFiles = {}

  for _, path in pairs(event.getPaths()) do
    -- Prepend the source onto the path to yield an absolute path.
    local path = event.config.source .. path

    -- Make sure this is a path ctags cares about.
    -- TODO: Don't call findUp if we've already found a tag file for this directory.
    if not shouldIgnore(event, path) then
      local tagsFile, tagsPath = findUp(path, event.config.tagsFile)
      if tagsFiles ~= nil then tagsFiles[tagsFile] = tagsPath
      else                     log("Error", "Couldn't locate tags file for path '" .. path .. "'.") end                    
    else
      log("Normal", "Ignoring path '" .. path .. "'.")
    end
  end

  return tagsFiles
end

function runCtags(event, tagsFileList)
  local cmdline = ''

  for tagsFile, tagsPath in pairs(tagsFileList) do
    local args = event.config.ctagsArgs

    -- Check for the exclude file.
    local excludeFile = tagsPath .. event.config.tagsExcludeFile
    if fileExists(excludeFile) then args = args .. " --exclude=@'" .. excludeFile .. "'"
    else                            log("Normal", "Couldn't find exclude file '" .. excludeFile .. "'") end

    -- Add this ctags invocation to the command line we're building.
    if cmdline ~= '' then cmdline = cmdline .. ' && ' end
    cmdline = cmdline .. event.config.ctagsCommand .. args .. ' -f "' .. tagsFile .. '" -R ' .. tagsPath
  end

  -- Execute ctags, completing processing of this event.
  log("Normal", "Executing ctags command: " .. cmdline)
  spawnShell(event, cmdline)
end
    
updateCtagsAction =
{
  delay = 5,
  maxProcesses = 1,

  action = function (inlet)
    local eventList = inlet.getEvents()
    local tagsFileList = findTagsFiles(eventList)

    if next(tagsFileList) ~= nil then runCtags(eventList, tagsFileList)
    else
      log('Normal', 'No tags files should be updated; not running ctags update action.')
      
      -- FIXME: Work around an lsyncd bug. Remove once we can discard event lists.
      spawnShell(eventList, '/usr/bin/true')
    end
  end,

  prepare = function (config)
    log("Normal", "Initializing ctags file types...")
    local f = assert(io.popen('ctags --list-maps'))
    local ctagsMaps = f:read('*a')
    f:close()

    local ftypes = {}

    for ftype in ctagsMaps:gmatch(' %S+') do
      ftype = ftype:sub(2):gsub('%.', '%%.'):gsub('%*', '.*') .. '$'
      log("Normal", "Adding ftype " .. ftype)
      table.insert(ftypes, ftype)
    end

    config.ftypes = ftypes

    -- Prepend a space to ctagsArgs to simplify appending it to other sets of arguments.
    config.ctagsArgs = ' ' .. config.ctagsArgs
  end
}

----
-- Sync setup.
----

sync
{
  -- lsyncd configuration.
  updateCtagsAction,
  source = assert(loadfile('.lctags-root.lua'), 'Cannot find .lctags-root.lua!')(),
  exclude = {'.**'},

  -- updateCtags configuration.
  ctagsCommand = '/usr/local/bin/ctags',
  ctagsArgs = '--fields=+afikKlmnsSzt --c-kinds=+p --c++-kinds=+p --extra=+q --sort=foldcase',
  tagsFile = '.tags',
  tagsExcludeFile = '.tags.exclude'
}
