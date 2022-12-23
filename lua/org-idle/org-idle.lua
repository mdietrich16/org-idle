local M = {}

local org_status, org                  = pcall(require, "orgmode")
local org_files_status, orgfiles       = pcall(require, "orgmode.parser.files")
local org_duration_status, orgduration = pcall(require, "orgmode.objects.duration")

if not (org_status and org_files_status and org_duration_status) then
    return
end

if not vim.fn.executable("xprintidle") then
    vim.notify("xprintidle not installed, org-idle depends on it!", vim.log.level.WARN)
    return
end

local function callback(logbook, action, duration, window)
    local active_clock = logbook.items[1]
    if action == "k" then
        return
    elseif action == "K" then
        require("orgmode.clock"):org_clock_out()
    elseif action == "s" then
        require("orgmode.clock"):org_clock_out()
        active_clock.end_clock = active_clock.end_time:subtract({ orgduration.from_seconds(duration) })
        require("orgmode.clock"):org_clock_in()
        -- logbook:recalculate_estimate()
    elseif action == "S" then
        require("orgmode.clock"):org_clock_out()
        active_clock.end_clock = active_clock.end_time:subtract({ orgduration.from_seconds(duration) })
    elseif action == "C" then
        require("orgmode.clock"):org_clock_cancel()
        -- logbook:cancel_active_clock()
    end
    vim.api.nvim_win_close(window, true)
end

M.defaults = {
    timeout = 2,
    idletime = 10,
    callback = function()
        local proc = io.popen("xprintidle", "r")
        if proc then
            local idletime = tonumber(proc:read()) / 1000
            proc:close()

            print(string.format("%s --- %s", idletime, M.idle))

            if idletime > M.config.idletime and not M.idle then
                M.idle = true
                M.last_active = os.time() - math.floor(idletime)
            end

            if M.idle and idletime < M.config.idletime then
                vim.notify("You came back!")
                local headline = orgfiles.get_clocked_headline()
                if headline then
                    local buf = vim.api.nvim_create_buf(false, true)
                    local win = vim.api.nvim_open_win(buf, false, {
                        relative = "editor",
                        width = 60,
                        height = 20,
                        row = 0.25,
                        col = 0.25,
                        border = "rounded",
                    })
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                        "You just returned from being idle {} minutes.",
                        "\t- (k)eep the clocked-in time and stay clocked-in",
                        "\t- (K)eep the clocked-in time clock out",
                        "\t- (s)ubtract the time and stay clocked-in",
                        "\t- (S)ubtract the time and clock out",
                        "\t- (C)ancel the clock altogether",
                    })
                    local logbook = headline.logbook

                    vim.keymap.set("n", "k", function() callback(logbook, "k", idletime) end,
                        { buffer = buf, silent = true, noremap = true, desc = "Keep clock" })
                    vim.keymap.set("n", "K", function() callback(logbook, "K", idletime, win) end,
                        { buffer = buf, silent = true, noremap = true, desc = "Keep clock and clock out" })
                    vim.keymap.set("n", "s", function() callback(logbook, "s", idletime, win) end,
                        { buffer = buf, silent = true, noremap = true, desc = "Subtract from clock" })
                    vim.keymap.set("n", "S", function() callback(logbook, "S", idletime, win) end,
                        { buffer = buf, silent = true, noremap = true, desc = "Subtract from clock and clock out" })
                    vim.keymap.set("n", "C", function() callback(logbook, "C", idletime, win) end,
                        { buffer = buf, silent = true, noremap = true, desc = "Reset clock completely" })
                    vim.keymap.set("n", "q", "<CMD>close<CR>",
                        { buffer = buf, silent = true, noremap = true, desc = "Close window and keep clock" })
                    -- vim.ui.input({
                    --     prompt = ""
                    -- }, {})

                    M.idle = false
                end
            end
        end
    end
}

function M.setup(user_config)
    user_config = user_config or {}
    M.config = vim.tbl_deep_extend("force", M.defaults, user_config)
    M.timer = vim.loop.new_timer()
    if M.timer then
        M.timer:start(M.config.timeout * 1000, M.config.timeout * 1000, vim.schedule_wrap(M.config.callback))
    else
        vim.notify("Timer creation resulted in error!", vim.log.levels.ERROR)
    end
end

function M.stop()
    if M.timer then
        M.timer:stop()
        M.timer:close()
    end
end

return M
