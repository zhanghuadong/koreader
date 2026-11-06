local Event = require("ui/event")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local time = require("ui/time")
local _ = require("gettext")
local T = require("ffi/util").template

local DEFAULT_INTERVAL = 20 -- 定制：未设置间隔时的默认翻页间隔（秒）

local AutoTurn = WidgetContainer:extend{
    name = "autoturn",
    is_doc_only = true,
    autoturn_sec = 0,
    autoturn_distance = 1,
    enabled = false,
    last_action_time = 0,
    task = nil,
}

function AutoTurn:_enabled()
    return self.enabled and self.autoturn_sec > 0
end

function AutoTurn:_schedule()
    if not self:_enabled() then
        logger.dbg("AutoTurn:_schedule is disabled")
        return
    end

    local delay = self.last_action_time + time.s(self.autoturn_sec) - UIManager:getElapsedTimeSinceBoot()

    if delay <= 0 then
        local top_wg = UIManager:getTopmostVisibleWidget() or {}
        if top_wg.name == "ReaderUI" then
            logger.dbg("AutoTurn: go to next page")
            self.ui:handleEvent(Event:new("GotoViewRel", self.autoturn_distance))
            self.last_action_time = UIManager:getElapsedTimeSinceBoot()
        end
        logger.dbg("AutoTurn: schedule in", self.autoturn_sec)
        UIManager:scheduleIn(self.autoturn_sec, self.task)
        self.scheduled = true
    else
        local delay_s = time.to_number(delay)
        logger.dbg("AutoTurn: schedule in", delay_s, "s")
        UIManager:scheduleIn(delay_s, self.task)
        self.scheduled = true
    end
end

function AutoTurn:_unschedule()
    PluginShare.pause_auto_suspend = false
    if self.scheduled then
        logger.dbg("AutoTurn: unschedule")
        UIManager:unschedule(self.task)
        self.scheduled = false
    end
end

function AutoTurn:_start(quiet)
    if self:_enabled() then
        local time_since_boot = UIManager:getElapsedTimeSinceBoot()
        logger.dbg("AutoTurn: start at", time.format_time(time_since_boot))
        PluginShare.pause_auto_suspend = true
        self.last_action_time = time_since_boot
        self:_schedule()
        -- 定制：quiet 时不弹出提示（状态栏已显示自动翻页状态）
        if quiet then return end

        local text
        if self.autoturn_distance == 1 then
            local time_string = datetime.secondsToClockDuration("letters", self.autoturn_sec, false, true, true)
            text = T(_("Autoturn is now active and will automatically turn the page every %1."), time_string)
        else
            text = T(_("Autoturn is now active and will automatically scroll %1 % of the page every %2 seconds."),
                self.autoturn_distance * 100,
                self.autoturn_sec)
        end

        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = text,
            timeout = 3,
        })
    end
end

function AutoTurn:init()
    UIManager.event_hook:registerWidget("InputEvent", self)
    self.autoturn_sec = G_reader_settings:readSetting("autoturn_timeout_seconds", 0)
    self.autoturn_distance = G_reader_settings:readSetting("autoturn_distance", 1)
    self.enabled = G_reader_settings:isTrue("autoturn_enabled")
    self.ui.menu:registerToMainMenu(self)
    self.task = function()
        self:_schedule()
    end
    self:_start(true)
    if self:_enabled() then
        self.onResume = self._onResume
        -- 定制：打开书时自动翻页已开启，则显示自动翻页状态栏；此时文档尚未排版，无需重新排版
        self.ui.view.footer:setAutoTurnBar(self.autoturn_sec, true)
    end
end

-- 定制：按当前状态显示或恢复自动翻页状态栏
function AutoTurn:updateFooterBar()
    self.ui.view.footer:setAutoTurnBar(self:_enabled() and self.autoturn_sec or nil)
end

function AutoTurn:onCloseWidget()
    logger.dbg("AutoTurn: onCloseWidget")
    self:_unschedule()
    self.task = nil
end

function AutoTurn:onCloseDocument()
    logger.dbg("AutoTurn: onCloseDocument")
    self:_unschedule()
end

function AutoTurn:onInputEvent()
    logger.dbg("AutoTurn: onInputEvent")
    self.last_action_time = UIManager:getElapsedTimeSinceBoot()
end

-- We do not want autoturn to turn pages during the suspend process.
-- Unschedule it and restart after resume.
function AutoTurn:onSuspend()
    logger.dbg("AutoTurn: onSuspend")
    self:_unschedule()
end

function AutoTurn:_onResume()
    logger.dbg("AutoTurn: onResume")
    self:_start(true)
end

-- 定制：以下为供快捷菜单、翻页速度弹窗调用的接口

-- 自动翻页是否正在运行
function AutoTurn:isActive()
    return self:_enabled()
end

-- 当前翻页间隔（秒），未设置时返回默认值
function AutoTurn:getInterval()
    return self.autoturn_sec > 0 and self.autoturn_sec or DEFAULT_INTERVAL
end

-- 设置翻页间隔并保存；运行中则按新间隔重新计时
function AutoTurn:setInterval(sec)
    self.autoturn_sec = sec
    G_reader_settings:saveSetting("autoturn_timeout_seconds", sec)
    if self:_enabled() then
        self:_unschedule()
        self:_start(true)
    end
    self:updateFooterBar()
end

-- 开启自动翻页（使用当前或默认间隔），并显示自动翻页状态栏
function AutoTurn:enable()
    self.autoturn_sec = self:getInterval()
    G_reader_settings:saveSetting("autoturn_timeout_seconds", self.autoturn_sec)
    self.enabled = true
    G_reader_settings:makeTrue("autoturn_enabled")
    self:_unschedule()
    self:_start(true)
    self.onResume = self._onResume
    self:updateFooterBar()
end

-- 停止自动翻页，并恢复原状态栏
function AutoTurn:disable()
    self.enabled = false
    G_reader_settings:makeFalse("autoturn_enabled")
    self:_unschedule()
    self.onResume = nil
    self:updateFooterBar()
end

-- 切换自动翻页开关
function AutoTurn:onToggleAutoTurn()
    if self:_enabled() then
        self:disable()
    else
        self:enable()
    end
    return true
end

-- 未开启时先开启自动翻页，再在状态栏上方弹出翻页速度弹窗
function AutoTurn:onShowAutoTurnDialog()
    if not self:_enabled() then
        self:enable()
    end
    local AutoTurnDialog = require("ui/widget/autoturndialog")
    UIManager:show(AutoTurnDialog:new{
        autoturn = self,
        bottom_offset = self.ui.view.footer_visible and self.ui.view.footer:getHeight() or 0,
    })
    return true
end

function AutoTurn:addToMainMenu(menu_items)
    menu_items.autoturn = {
        sorting_hint = "navi",
        text_func = function()
            local time_string = datetime.secondsToClockDuration("letters", self.autoturn_sec, false, true, true)
            return self:_enabled() and T(_("Autoturn: %1"), time_string) or _("Autoturn")
        end,
        checked_func = function() return self:_enabled() end,
        check_callback_updates_menu = true,
        callback = function(menu)
            local DateTimeWidget = require("ui/widget/datetimewidget")
            local autoturn_seconds = G_reader_settings:readSetting("autoturn_timeout_seconds", 30)
            local autoturn_minutes = math.floor(autoturn_seconds * (1/60))
            autoturn_seconds = autoturn_seconds % 60
            local autoturn_spin = DateTimeWidget:new {
                title_text = _("Autoturn time"),
                info_text = _("Enter time in minutes and seconds."),
                min = autoturn_minutes,
                min_max = 60 * 24, -- maximum one day
                min_default = 0,
                sec = autoturn_seconds,
                sec_default = 30,
                keep_shown_on_apply = true,
                ok_text = _("Set timeout"),
                cancel_text = _("Disable"),
                cancel_callback = function()
                    self.enabled = false
                    G_reader_settings:makeFalse("autoturn_enabled")
                    self:_unschedule()
                    menu:updateItems()
                    self.onResume = nil
                    self:updateFooterBar() -- 定制：同步状态栏
                end,
                ok_always_enabled = true,
                callback = function(t)
                    self.autoturn_sec = t.min * 60 + t.sec
                    G_reader_settings:saveSetting("autoturn_timeout_seconds", self.autoturn_sec)
                    self.enabled = true
                    G_reader_settings:makeTrue("autoturn_enabled")
                    self:_unschedule()
                    self:_start()
                    menu:updateItems()
                    self.onResume = self._onResume
                    self:updateFooterBar() -- 定制：同步状态栏
                end,
            }
            UIManager:show(autoturn_spin)
        end,
        hold_callback = function(menu)
            local SpinWidget = require("ui/widget/spinwidget")
            local curr_items = G_reader_settings:readSetting("autoturn_distance") or 1
            local autoturn_spin = SpinWidget:new {
                value = curr_items,
                value_min = -20,
                value_max = 20,
                precision = "%.2f",
                value_step = .1,
                value_hold_step = .5,
                ok_text = _("Set distance"),
                title_text = _("Scrolling distance"),
                callback = function(autoturn_spin)
                    self.autoturn_distance = autoturn_spin.value
                    G_reader_settings:saveSetting("autoturn_distance", autoturn_spin.value)
                    if self.enabled then
                        self:_unschedule()
                        self:_start()
                    end
                    menu:updateItems()
                end,
            }
            UIManager:show(autoturn_spin)
        end,
    }
end

return AutoTurn
