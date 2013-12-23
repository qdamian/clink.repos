--
-- Copyright (c) 2013 Damian Quiroga
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

--------------------------------------------------------------------------------
PATH_SEP = '\\'

--------------------------------------------------------------------------------
function match_by_cmd(text, _, __)
    -- Try not to interfere with clink's default match generators
    if #(clink.find_files(text..'*', true)) > 0 then
        return false
    end

    -- Assuming a one-word command (which may not be the case)
    local cmd = rl_state.line_buffer:match('(.-) ')

    local match_dirs_only = (cmd == 'cd')
    return match_in_manifest(text, match_dirs_only)
end

clink.register_match_generator(match_by_cmd, 10)

--------------------------------------------------------------------------------
function match_in_manifest(text, match_dirs_only)
    local current_dir = clink.get_cwd()
    local files, dirs = _get_hg_or_git_paths(current_dir)
    local pattern = _convert_glob_to_lua_pattern(text)

    local matches = {}
    if match_dirs_only then
        local search_patterns = {
            PATH_SEP..pattern..PATH_SEP..'$',
            pattern..PATH_SEP..'$',
            pattern..'[%w_-]*'..PATH_SEP..'$',
        }
        matches = _match_trying_patterns(dirs, search_patterns)
        clink.suppress_char_append() -- i.e. don't add a trailing space
    else
        local search_patterns = {
            current_dir..pattern,
            PATH_SEP..pattern,
            pattern,
        }
        matches = _match_trying_patterns(files, search_patterns)
    end
    matches = _make_subpaths_relative(matches, current_dir)
    return _add_matches_for_readline(matches, text)
end

--------------------------------------------------------------------------------
function _i_find(text, pattern)
    return text:lower():find(pattern:lower())
end

--------------------------------------------------------------------------------
function _call(cmd)
    for line in io.popen(cmd..' 2> NUL'):lines() do
        return line
    end
    return ''
end

--------------------------------------------------------------------------------
function _convert_glob_to_lua_pattern(text)
    -- Ref: http://www.lua.org/pil/20.2.html
    return text:gsub('%.', '%%.'):gsub('*', '.*'):gsub('?', '.')
end

--------------------------------------------------------------------------------
local cache = {
    id = nil,
    files = nil,
    dirs = nil
}

function _get_hg_or_git_paths(current_dir)
    local id = _call('hg id --id 2> NUL || git rev-parse HEAD 2> NUL')
    if id == '' then -- not in a repo
        return {}, {}
    end

    if id ~= cache.id then
        cache.files = _get_repo_files()
        cache.dirs = _identify_dirs(cache.files)
        cache.id = id
    end
    return cache.files, cache.dirs
end

--------------------------------------------------------------------------------
function _get_repo_files()
    local paths = {}

    repo_root = _call('hg root 2> NUL || git rev-parse --show-toplevel')
    repo_root = repo_root:gsub('/', PATH_SEP)

    get_files_cmd = 'hg manifest 2> NUL || git ls-files 2> NUL'
    for line in io.popen(get_files_cmd):lines() do
        full_path = repo_root..PATH_SEP..(line:gsub('/', PATH_SEP))
        table.insert(paths, full_path)
    end
    return paths
end

--------------------------------------------------------------------------------
function _identify_dirs(files)
    local unique_dirs = {}
    for _, file_path in ipairs(files) do
        file_dir = file_path:match('.*'..PATH_SEP)
        unique_dirs[file_dir] = true
    end

    local dirs = {}
    for dir, _ in pairs(unique_dirs) do
        table.insert(dirs, dir)
    end
    return dirs
end

--------------------------------------------------------------------------------
function _filter_list(list, pattern)
    local filtered = {}
    for _, value in ipairs(list) do
        if _i_find(value, pattern) then
            table.insert(filtered, value)
        end
    end
    return filtered
end

--------------------------------------------------------------------------------
function _match_trying_patterns(paths, search_patterns)
    local matches = {}
    for _, pattern in ipairs(search_patterns) do
        matches = _filter_list(paths, pattern)
        if #matches > 0 then
            break
        end
    end
    return matches
end

--------------------------------------------------------------------------------
function _make_subpaths_relative(paths, current_dir)
    local relative_paths = {}
    for _, path in ipairs(paths) do
        relative_path = string.gsub(path, current_dir..PATH_SEP, '')
        table.insert(relative_paths, relative_path)
    end
    return relative_paths
end

--------------------------------------------------------------------------------
function _add_matches_for_readline(matches, text)
    if #matches == 0 then
        return false
    elseif #matches == 1 then
        clink.add_match(matches[1])
    elseif #matches > 1 then
        -- Prevent readline from altering the typed text
        clink.add_match(text)
        for _, m in ipairs(matches) do
            clink.add_match(m)
        end
    end
    return true
end
