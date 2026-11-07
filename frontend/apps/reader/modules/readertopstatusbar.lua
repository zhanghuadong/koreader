--[[--
阅读器顶部状态栏：左侧时间，右侧电量百分比和电池图标。

样式与阅读选项页 / 下拉面板的状态行一致（ReaderOptionsPage:buildStatusRow）。
由阅读选项中的「隐藏状态栏」开关控制显示；默认显示。
占位方式：流式文档加到页上边距，固定版式文档从可视区域顶部扣除高度。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen

local ReaderTopStatusBar = WidgetContainer:extend{}

function ReaderTopStatusBar:init()
    -- nil 或 true：显示；false：隐藏
    self.visible = G_reader_settings:nilOrTrue("reader_top_status_bar")
    self.view.top_status_bar_visible = self.visible
    self.side = Screen:scaleBySize(18)
    self:update()
    self:rescheduleAutoRefresh()
end

function ReaderTopStatusBar:getHeight()
    return self.dimen and self.dimen.h or 0
end

-- 重建内容（时间、电量会变）
function ReaderTopStatusBar:update()
    local ReaderOptionsPage = require("ui/widget/readeroptionspage")
    local width = Screen:getWidth()
    local row = ReaderOptionsPage:buildStatusRow(width, self.side, 1)
    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = width,
        row,
    }
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = size.h }
end

function ReaderTopStatusBar:paintTo(bb, x, y)
    if not self.visible then return end
    self[1]:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
end

function ReaderTopStatusBar:resetLayout()
    self.side = Screen:scaleBySize(18)
    self:update()
end

-- 显示或隐藏；立刻调整正文边距/可视区，并刷新画面
function ReaderTopStatusBar:setVisible(visible)
    visible = not not visible
    if self.visible == visible then return end
    self.visible = visible
    self.view.top_status_bar_visible = visible
    G_reader_settings:saveSetting("reader_top_status_bar", visible)

    -- 流式文档：把状态栏高度算进上边距后立刻重排
    if self.ui.rolling and self.ui.document and self.ui.document.configurable then
        local c = self.ui.document.configurable
        local margins = {
            c.h_page_margins[1],
            c.t_page_margin,
            c.h_page_margins[2],
            c.b_page_margin,
        }
        self.ui:handleEvent(Event:new("SetPageMargins", margins))
    end
    -- 固定版式等：重算可视区域、书签角标位置
    self.ui:handleEvent(Event:new("ReaderTopStatusBarVisibilityChange"))
    self:rescheduleAutoRefresh()
    -- 整页刷新，保证显隐立刻可见（含从选项页返回后）
    UIManager:setDirty(self.view.dialog, "ui")
end

function ReaderTopStatusBar:toggle()
    self:setVisible(not self.visible)
end

-- 每分钟刷新时间和电量（与底部状态栏相同的调度方式）
function ReaderTopStatusBar:rescheduleAutoRefresh()
    if not self.autoRefresh then
        self.autoRefresh = function()
            if self.visible then
                local old_h = self:getHeight()
                self:update()
                -- 高度不变时只刷状态栏区域；高度变了会触发布局，整页刷新
                if self:getHeight() == old_h then
                    UIManager:setDirty(self.view.dialog, function()
                        return "ui", self.dimen
                    end)
                else
                    UIManager:setDirty(self.view.dialog, "partial")
                end
            end
            self:rescheduleAutoRefresh()
        end
    end
    UIManager:unschedule(self.autoRefresh)
    if self.visible then
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefresh)
    end
end

function ReaderTopStatusBar:onResume()
    if self.visible then
        self:update()
        self:rescheduleAutoRefresh()
    end
    return true
end

function ReaderTopStatusBar:onSuspend()
    if self.autoRefresh then
        UIManager:unschedule(self.autoRefresh)
    end
    return true
end

function ReaderTopStatusBar:onCloseWidget()
    if self.autoRefresh then
        UIManager:unschedule(self.autoRefresh)
    end
end

-- 旋转 / 尺寸变化时重建
function ReaderTopStatusBar:onSetDimensions()
    self:resetLayout()
    return true
end

return ReaderTopStatusBar
