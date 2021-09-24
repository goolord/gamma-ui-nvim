local M = {}

local if_nil = vim.F.if_nil
local deepcopy = vim.deepcopy
local abs = math.abs
local strdisplaywidth = vim.fn.strdisplaywidth
local str_rep = string.rep
local list_extend = vim.list_extend
local concat = table.concat

local function noop () end

_G.gamma_ui = {}

function M.longest_line(tbl)
    local longest = 0
    for _, v in ipairs(tbl) do
        local width = strdisplaywidth(v)
        if width > longest then
            longest = width
        end
    end
    return longest
end

function M.spaces(n)
    return str_rep(" ", n)
end

function M.center(tbl, state)
    -- longest line used to calculate the center.
    -- which doesn't quite give a 'justfieid' look, but w.e
    local longest = M.longest_line(tbl)
    -- div 2
    local left = bit.arshift(state.win_width - longest, 1)
    local padding = M.spaces(left)
    local centered = {}
    for k, v in ipairs(tbl) do
        centered[k] = padding .. v
    end
    return centered, left
end

function M.pad_pargin(tbl, state, margin, shrink)
    local longest = M.longest_line(tbl)
    local left
    if shrink then
        local pot_width = margin + margin + longest
        if (pot_width > state.win_width)
        then left = (state.win_width - pot_width) + margin
        else left = margin
        end
    else
        left = margin
    end
    local padding = M.spaces(left)
    local padded = {}
    for k, v in ipairs(tbl) do
        padded[k] = padding .. v .. padding
    end
    return padded, left
end

function M.highlight(state, end_ln, hl, left)
    local hl_type = type(hl)
    local hl_tbl = {}
    if hl_type == "string" then
        for i = state.line, end_ln do
            table.insert(hl_tbl, {state.buffer, -1, hl, i, 0, -1})
        end
    end
    -- TODO: support multiple lines
    if hl_type == "table" then
        for _, hl_section in ipairs(hl) do
            table.insert(hl_tbl, {
                state.buffer,
                -1,
                hl_section[1],
                state.line,
                left + hl_section[2],
                left + hl_section[3]
            })
        end
    end
    return hl_tbl
end

M.layout_element = {}

function M.resolve(to, el, opts, state)
    local new_el = deepcopy(el)
    new_el.val = el.val()
    return to(new_el, opts, state)
end

function M.layout_element.text (el, opts, state)
    if type(el.val) == "table" then
        local end_ln = state.line + #el.val
        local val = el.val
        local hl = {}
        local padding = { left = 0 }
        if opts.opts and opts.opts.margin and el.opts and (el.opts.position ~= "center") then
            local left
            val, left = M.pad_pargin(val, state, opts.opts.margin, if_nil(el.opts.shrink_margin, true))
            padding.left = padding.left + left
        end
        if el.opts then
            if el.opts.position == "center" then
                val, _ = M.center(val, state)
            end
        -- if el.opts.wrap == "overflow" then
        --     val = trim(val, state)
        -- end
        end
        if el.opts and el.opts.hl then
            hl = M.highlight(state, end_ln, el.opts.hl, 0)
        end
        state.line = end_ln
        return val, hl
    end

    if type(el.val) == "string" then
        local val = {}
        local hl = {}
        for s in el.val:gmatch("[^\r\n]+") do
            val[#val+1] = s
        end
        local padding = { left = 0 }
        if opts.opts and opts.opts.margin and el.opts and (el.opts.position ~= "center") then
            local left
            val, left = M.pad_pargin(val, state, opts.opts.margin, if_nil(el.opts.shrink_margin, true))
            padding.left = padding.left + left
        end
        if el.opts then
            if el.opts.position == "center" then
                val, _ = M.center(val, state)
            end
        end
        local end_ln = state.line + 1
        if el.opts and el.opts.hl then
            hl = M.highlight(state, end_ln, el.opts.hl, padding.left)
        end
        state.line = end_ln
        return val, hl
    end

    if type(el.val) == "function" then return M.resolve(M.layout_element.text, el, opts, state) end
end

function M.layout_element.padding (el, opts, state)
    local lines = 0
    if type(el.val) == "function" then lines = el.val() end
    if type(el.val) == "number" then lines = el.val end
    local val = {}
    for i = 1, lines do
        val[i] = ""
    end
    local end_ln = state.line + lines
    state.line = end_ln
    return val, {}
end

function M.layout_element.button (el, opts, state)
    local val = {}
    local hl = {}
    local padding = {
        left   = 0,
        center = 0,
        right  = 0,
    }
    if el.opts and el.opts.shortcut then
        -- this min lets the padding resize when the window gets smaller
        if el.opts.width then
            local max_width = math.min(el.opts.width, state.win_width)
            if el.opts.align_shortcut == "right"
                then padding.center = max_width - (#el.val + #el.opts.shortcut)
                else padding.right = max_width - (#el.val + #el.opts.shortcut)
            end
        end
        if el.opts.align_shortcut == "right"
            then val = { concat { el.val, M.spaces(padding.center), el.opts.shortcut } }
            else val = { concat { el.opts.shortcut, el.val, M.spaces(padding.right) } }
        end
    else
        val = {el.val}
    end

    -- margin
    if opts.opts and opts.opts.margin and el.opts and (el.opts.position ~= "center") then
        local left
        val, left = M.pad_pargin(val, state, opts.opts.margin, if_nil(el.opts.shrink_margin, true))
        if el.opts.align_shortcut == "right"
            then padding.center = padding.center + left
            else padding.left = padding.left + left
        end
    end

    -- center
    if el.opts then
        if el.opts.position == "center" then
            local left
            val, left = M.center(val, state)
            if el.opts.align_shortcut == "right" then
              padding.center = padding.center + left
            end
            padding.left = padding.left + left
        end
    end

    local row = state.line + 1
    local _, count_spaces = string.find(val[1], "%s*")
    local col = ((el.opts and el.opts.cursor) or 0) + count_spaces
    state.cursor_jumps[#state.cursor_jumps+1] = {row, col}
    state.cursor_jumps_press[#state.cursor_jumps_press+1] = el.on_press
    if el.opts and el.opts.hl_shortcut then
        if type(el.opts.hl_shortcut) == "string"
            then hl = {{el.opts.hl_shortcut, 0, #el.opts.shortcut}}
            else hl = el.opts.hl_shortcut
        end
        if el.opts.align_shortcut == "right"
            then hl = M.highlight(state, state.line, hl, #el.val + padding.center)
            else hl = M.highlight(state, state.line, hl, padding.left)
        end
    end

    if el.opts and el.opts.hl then
        local left = padding.left
        if el.opts.align_shortcut == "left" then left = left + #el.opts.shortcut + 2 end
        list_extend(hl, M.highlight(state, state.line, el.opts.hl, left))
    end
    state.line = state.line + 1
    return val, hl
end

function M.layout_element.group (el, opts, state)
    if type(el.val) == "function" then return M.resolve(M.layout_element.group, el, opts, state) end

    if type(el.val) == "table" then
        local text_tbl = {}
        local hl_tbl = {}
        for _, v in ipairs(el.val) do
            local text, hl = M.layout_element[v.type](v, opts, state)
            if text then list_extend(text_tbl, text) end
            if hl then list_extend(hl_tbl, hl) end
            if el.opts and el.opts.spacing then
                local padding_el = {type = "padding", val = el.opts.spacing}
                local text_1, hl_1 = M.layout_element[padding_el.type](padding_el, opts, state)
                list_extend(text_tbl, text_1)
                list_extend(hl_tbl, hl_1)
            end
        end
        return text_tbl, hl_tbl
    end
end

function M.layout(opts, state)
    -- this is my way of hacking pattern matching
    -- you index the table by its "type"
    local hl = {}
    local text = {}
    for _, el in ipairs(opts.layout) do
        local text_el, hl_el = M.layout_element[el.type](el, opts, state)
        list_extend(text, text_el)
        list_extend(hl, hl_el)
    end
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, text)
    for _, hl_line in ipairs(hl) do
        pcall(vim.api.nvim_buf_add_highlight(hl_line[1],hl_line[2],hl_line[3],hl_line[4],hl_line[5],hl_line[6]))
    end
end

M.keymaps_element = {}

M.keymaps_element.text = noop
M.keymaps_element.padding = noop

function M.keymaps_element.button (el, opts, state)
    if el.opts and el.opts.keymap then
        local map = el.opts.keymap
        vim.api.nvim_buf_set_keymap(state.buffer, map[1],map[2],map[3],map[4])
    end
end

function M.keymaps_element.group (el, opts, state)
    if type(el.val) == "function" then M.resolve(M.keymaps_element.group, el, opts, state) end

    if type(el.val) == "table" then
        for _, v in ipairs(el.val) do
            M.keymaps_element[v.type](v, opts, state)
        end
    end
end

function M.keymaps(opts, state)
    for _, el in ipairs(opts.layout) do
        M.keymaps_element[el.type](el, opts, state)
    end
end

-- dragons
function M.closest_cursor_jump(cursor, cursors, prev_cursor)
    local direction = prev_cursor[1] > cursor[1] -- true = UP, false = DOWN
    -- minimum distance key from jump point
    -- excluding jumps in opposite direction
    local min
    local cursor_row = cursor[1]
    for k, v in ipairs(cursors) do
        local distance = v[1] - cursor_row -- new cursor distance from old cursor
        if (distance <= 0) and direction then
            distance = abs(distance)
            local res = {distance, k}
            if not min then min = res end
            if min[1] > res[1] then min = res end
        end
        if (distance >= 0) and (not direction) then
            local res = {distance, k}
            if not min then min = res end
            if min[1] > res[1] then min = res end
        end
    end
    if not min -- top or bottom
        then
            if direction
                then return 1, cursors[1]
                else return #cursors, cursors[#cursors]
            end
        else
            -- returns the key (stored in a jank way so we can sort the table)
            -- and the {row, col} tuple
            return min[2], cursors[min[2]]
    end
end

local function draw(name, opts, def_opts, state)
    opts = opts or def_opts
    for k in ipairs(state.cursor_jumps) do state.cursor_jumps[k] = nil end
    for k in ipairs(state.cursor_jumps_press) do state.cursor_jumps_press[k] = nil end
    state.win_width = vim.api.nvim_win_get_width(state.window)
    state.line = 0
    -- this is for redraws. i guess the cursor 'moves'
    -- when the screen is cleared and then redrawn
    -- so we save the index before that happens
    local ix = state.cursor_ix
    vim.api.nvim_buf_set_option(state.buffer, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, {})
    M.layout(opts, state)
    vim.api.nvim_buf_set_option(state.buffer, "modifiable", false)
    vim.api.nvim_buf_set_keymap(
    state.buffer,
    "n",
    "<CR>",
    string.format(":call v:lua.gamma_ui.%s.press()<CR>", name),
    {noremap = false, silent = true}
    )
    vim.api.nvim_win_set_cursor(state.window, state.cursor_jumps[ix])
end

local function enable(name, opts)
    -- vim.opt_local behaves inconsistently for window options, it seems.
    -- I don't have the patience to sort out a better way to do this
    -- or seperate out the buffer local options.
    vim.cmd (string.format([[
    silent! setlocal bufhidden=wipe nobuflisted colorcolumn= foldcolumn=0 matchpairs= nocursorcolumn nocursorline nolist nonumber norelativenumber nospell noswapfile signcolumn=no synmaxcol& buftype=nofile ft=%s nowrap

    augroup gamma_ui_temp
    au!
    autocmd BufUnload <buffer> call v:lua.gamma_ui.%s.close()
    autocmd CursorMoved <buffer> call v:lua.gamma_ui.%s.set_cursor()
    augroup END
    ]], name, name, name))

    if opts.opts then
        if if_nil(opts.opts.redraw_on_resize, true) then
            vim.cmd (string.format([[
            autocmd gamma_ui_temp VimResized * call v:lua.gamma_ui.%s.draw()
            autocmd gamma_ui_temp BufLeave,WinEnter,WinNew,WinClosed * call v:lua.gamma_ui.%s.draw()
            ]], name, name))
        end

        if opts.opts.setup then opts.opts.setup() end
    end
end

local function set_cursor(state)
    local cursor = vim.api.nvim_win_get_cursor(state.window)
    local closest_ix, closest_pt = M.closest_cursor_jump(cursor, state.cursor_jumps, state.cursor_jumps[state.cursor_ix])
    state.cursor_ix = closest_ix
    vim.api.nvim_win_set_cursor(state.window, closest_pt)
end

function M.register_ui(name, state)
    local options

    local ui_mod = {}
    ui_mod.set_cursor = function () set_cursor(state) end
    ui_mod.press = function () state.cursor_jumps_press[state.cursor_ix]() end
    ui_mod.enable = function (opts)
        options = options or opts
        enable(name, opts)
    end
    ui_mod.draw = function (opts) draw(name, opts, options, state) end
    ui_mod.close = function ()
        vim.cmd[[au! gamma_ui_temp]]
        _G.gamma_ui[name] = nil
    end
    _G.gamma_ui[name] = ui_mod
end

return M
