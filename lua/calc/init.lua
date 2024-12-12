-- Create namespaces and storage
local M = {}
local vnamespace = vim.api.nvim_create_namespace("calc")
local buffer_envs = setmetatable({}, {__mode = "k"})

-- Create math environment for a buffer
local function create_math_env()
    local env = {}
    
    return setmetatable(env, {
        __index = function(_, k)
            -- Restrict access to safe functions
            return math[k] or
                   (k == 'type' and type) or
                   (k == 'tostring' and tostring)
        end
    })
end

-- Process buffer content and evaluate expressions
local function process_buffer_content(content, env)
    local results = {}
    local virt_texts = {}
    
    for i, line in ipairs(content) do
        if not line:match("^%s*$") then
            -- Match assignment or expression
            local var, expr = line:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.+)$")
            if not var and not line:match("^%s*$") then
                -- Convert bare expression to assignment
                expr = line
                var = "anon" .. i
            end
            
            if expr then
                -- Safe evaluation
                local f, err = load("return " .. expr, "expr", "t", env)
                if f then
                    local success, value = pcall(f)
                    if success then
                        env[var] = value
                        results[i] = {value = value, name = var}
                        virt_texts[i] = tostring(value)
                    else
                        results[i] = {error = value}
                    end
                else
                    results[i] = {error = err}
                end
            end
        end
    end
    
    return results, virt_texts
end

-- Update virtual text display
local function update_virtual_text(bufnr, results, virt_texts)
    vim.api.nvim_buf_clear_namespace(bufnr, vnamespace, 0, -1)
    
    for lnum, result in pairs(results) do
        if result.error then
            vim.api.nvim_buf_set_virtual_text(
                bufnr,
                vnamespace,
                lnum - 1,
                {{result.error, "ErrorMsg"}},
                {}
            )
        elseif result.value then
            local display_text = virt_texts[lnum]
            if display_text then
                vim.api.nvim_buf_set_virtual_text(
                    bufnr,
                    vnamespace,
                    lnum - 1,
                    {{display_text, "Special"}},
                    {}
                )
            end
        end
    end
end

-- Handle end of line functionality
function M.go_eol()
    local line = vim.api.nvim_get_current_line()
    local lnum, lcol = unpack(vim.api.nvim_win_get_cursor(0))
    local cur = vim.str_utfindex(line, lcol)
    local last = vim.str_utfindex(line)
    local eol = cur == last-1
    
    if not eol then
        vim.api.nvim_win_set_cursor(0, { lnum, line:len() })
    else
        local env = buffer_envs[0]
        if env and env.virt_texts and env.virt_texts[lnum] then
            -- Highlight current result
            vim.api.nvim_buf_clear_namespace(0, vnamespace, 0, -1)
            for vlnum, vtxt in pairs(env.virt_texts) do
                local hlgroup = vlnum == lnum and "Visual" or "Special"
                vim.api.nvim_buf_set_virtual_text(0, vnamespace, vlnum-1, {{vtxt, hlgroup}}, {})
            end
            
            -- Handle copy action
            vim.schedule(function()
                local key = vim.fn.getchar()
                local c = string.char(key)
                if c == 'y' then
                    vim.api.nvim_command(([[let @+="%s"]]):format(env.virt_texts[lnum]))
                end
                
                -- Restore normal highlighting
                vim.api.nvim_buf_clear_namespace(0, vnamespace, 0, -1)
                for vlnum, vtxt in pairs(env.virt_texts) do
                    vim.api.nvim_buf_set_virtual_text(0, vnamespace, vlnum-1, {{vtxt, "Special"}}, {})
                end
            end)
        end
    end
end

-- Initialize session
function M.StartSession()
    local bufnr = 0
    local env = create_math_env()
    buffer_envs[bufnr] = env
    
    -- Set up buffer
    vim.api.nvim_command("set ft=lua")
    vim.cmd [[set buftype=nowrite]]
    vim.api.nvim_buf_set_keymap(0, "n", "$", [[:lua require"calc".go_eol()<CR>]], { silent=true })
    
    -- Attach buffer callback
    vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = vim.schedule_wrap(function(...)
            local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
            local results, virt_texts = process_buffer_content(content, env)
            env.virt_texts = virt_texts  -- Store for go_eol
            update_virtual_text(bufnr, results, virt_texts)
        end)
    })
end

return M
