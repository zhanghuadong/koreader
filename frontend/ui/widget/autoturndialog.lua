--[[--
自动翻页"翻页速度"弹窗：自动翻页运行时点击状态栏弹出，紧贴状态栏上方显示。

包含标题栏（自定义间隔、关闭）、分档速度滑块和底部"停止"按钮。
]]

local AutoTurnBar = require("ui/widget/autoturnbar")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

local STOPS = { 20, 12, 8, 6, 4, 3 } -- 滑块各档位（秒），从慢到快

-- 速度滑块：上方刻度文字和刻度线，下方轨道和圆形滑钮
local SpeedSlider = InputContainer:extend{
    width = nil,
    value = nil,    -- 当前间隔（秒）
    callback = nil, -- 档位变化时回调 callback(秒)
}

-- 创建刻度文字，计算轨道位置和高度，注册点击/拖动/滑动手势
function SpeedSlider:init()
    self.knob_r = Screen:scaleBySize(16)
    self.tick_h = Screen:scaleBySize(10)
    self.gap = Screen:scaleBySize(8)
    self.labels = {}
    local max_label_w = 0
    for i, sec in ipairs(STOPS) do
        self.labels[i] = TextWidget:new{
            text = AutoTurnBar.formatInterval(sec),
            face = Font:getFace("cfont", 21),
            bold = true,
        }
        max_label_w = math.max(max_label_w, self.labels[i]:getSize().w)
    end
    self.label_h = self.labels[1]:getSize().h
    self.track_x0 = math.max(self.knob_r, math.ceil(max_label_w / 2))
    self.track_w = self.width - 2 * self.track_x0
    self.height = self.label_h + self.gap + self.tick_h + self.gap + 2 * self.knob_r
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    local range = function() return self.dimen end
    self.ges_events = {
        TapSlider = { GestureRange:new{ ges = "tap", range = range } },
        PanReleaseSlider = { GestureRange:new{ ges = "pan_release", range = range } },
        SwipeSlider = { GestureRange:new{ ges = "swipe", range = range } },
    }
end

function SpeedSlider:getSize()
    return self.dimen
end

-- 第 i 个档位相对控件左边的 x 坐标（各档位等距分布）
function SpeedSlider:stopX(i)
    return self.track_x0 + math.floor(self.track_w * (i - 1) / (#STOPS - 1))
end

-- 当前值对应的滑钮位置：档位的秒数并非等差，所以在相邻两档之间按比例插值（自定义间隔也能落在轨道上）
function SpeedSlider:valueX()
    local v = self.value
    if v >= STOPS[1] then return self:stopX(1) end
    if v <= STOPS[#STOPS] then return self:stopX(#STOPS) end
    for i = 1, #STOPS - 1 do
        local a, b = STOPS[i], STOPS[i + 1]
        if v <= a and v >= b then
            local x1, x2 = self:stopX(i), self:stopX(i + 1)
            return math.floor(x1 + (x2 - x1) * (a - v) / (a - b))
        end
    end
end

-- 绘制刻度文字、刻度线、轨道（滑钮左侧粗黑线，右侧细灰线）和滑钮
function SpeedSlider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local tick_y = y + self.label_h + self.gap
    for i, label in ipairs(self.labels) do
        local sx = x + self:stopX(i)
        label:paintTo(bb, sx - math.floor(label:getSize().w / 2), y)
        bb:paintRect(sx - math.floor(Size.line.medium / 2), tick_y, Size.line.medium, self.tick_h, Blitbuffer.COLOR_BLACK)
    end
    local track_y = tick_y + self.tick_h + self.gap + self.knob_r
    local knob_x = x + self:valueX()
    local thick = Screen:scaleBySize(5)
    local thin = Size.line.medium
    bb:paintRect(knob_x, track_y - math.floor(thin / 2), x + self.track_x0 + self.track_w - knob_x, thin,
        Blitbuffer.COLOR_LIGHT_GRAY)
    bb:paintRect(x + self.track_x0, track_y - math.floor(thick / 2), knob_x - x - self.track_x0, thick,
        Blitbuffer.COLOR_BLACK)
    bb:paintCircle(knob_x, track_y, self.knob_r, Blitbuffer.COLOR_WHITE)
    bb:paintCircle(knob_x, track_y, self.knob_r, Blitbuffer.COLOR_BLACK, Size.border.thick)
end

-- 吸附到离屏幕坐标 screen_x 最近的档位，值有变化时回调
function SpeedSlider:selectAt(screen_x)
    local best, best_d
    for i = 1, #STOPS do
        local d = math.abs(self.dimen.x + self:stopX(i) - screen_x)
        if not best_d or d < best_d then
            best, best_d = i, d
        end
    end
    if STOPS[best] ~= self.value then
        self.value = STOPS[best]
        self.callback(self.value)
    end
    return true
end

-- 点击、拖动松手：选中手指位置的档位
function SpeedSlider:onTapSlider(_, ges)
    return self:selectAt(ges.pos.x)
end

function SpeedSlider:onPanReleaseSlider(_, ges)
    return self:selectAt(ges.pos.x)
end

-- 快速横滑：按滑动终点选择档位
function SpeedSlider:onSwipeSlider(_, ges)
    if ges.direction == "east" then
        return self:selectAt(ges.pos.x + ges.distance)
    elseif ges.direction == "west" then
        return self:selectAt(ges.pos.x - ges.distance)
    end
    return true
end

function SpeedSlider:free()
    for _, label in ipairs(self.labels) do
        label:free()
    end
end

local AutoTurnDialog = InputContainer:extend{
    autoturn = nil,    -- 自动翻页插件实例
    bottom_offset = 0, -- 下方状态栏高度，弹窗显示在其上方
}

-- 宽度为屏幕 84%；返回键或点击弹窗外部关闭
function AutoTurnDialog:init()
    self.width = math.floor(Screen:getWidth() * 0.84)
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }
    self:update()
end

-- 构建弹窗内容：标题栏（标题 + 编辑/关闭图标）、速度滑块、分隔线、"停止"按钮
function AutoTurnDialog:update()
    local border = Size.border.thick
    local radius = Screen:scaleBySize(10)
    local side = Screen:scaleBySize(16)
    local outer_w = self.width - 2 * border
    local inner_w = outer_w - 2 * side

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            widget,
        }
    end

    local icon_size = Screen:scaleBySize(34)
    local function iconButton(icon, callback)
        return Button:new{
            icon = icon,
            icon_width = icon_size,
            icon_height = icon_size,
            bordersize = 0,
            padding = Size.padding.small,
            callback = callback,
            show_parent = self,
        }
    end
    local buttons = HorizontalGroup:new{
        align = "center",
        iconButton("edit", function() self:showCustomInterval() end),
        HorizontalSpan:new{ width = Screen:scaleBySize(14) },
        iconButton("close", function() self:onClose() end),
    }
    local title = TextWidget:new{
        text = _("Page turn speed"),
        face = Font:getFace("cfont", 26),
        bold = true,
        max_width = inner_w - buttons:getSize().w,
    }
    local header_dimen = Geom:new{ w = inner_w, h = math.max(title:getSize().h, buttons:getSize().h) }
    local header = OverlapGroup:new{
        dimen = header_dimen,
        LeftContainer:new{ dimen = header_dimen:copy(), title },
        RightContainer:new{ dimen = header_dimen:copy(), buttons },
    }

    local slider = SpeedSlider:new{
        width = inner_w,
        value = self.autoturn:getInterval(),
        callback = function(sec)
            self.autoturn:setInterval(sec)
            self:refresh()
        end,
    }

    local footer_h = Screen:scaleBySize(66)
    local disable_button = Button:new{
        text = C_("Autoturn", "Stop"),
        width = outer_w - 2 * radius,
        -- 上下左右各留出圆角半径，避免按钮遮住弹窗底部圆角
        height = footer_h - 2 * radius,
        bordersize = 0,
        padding = 0,
        text_font_size = 24,
        callback = function()
            self.autoturn:disable()
            self:onClose()
        end,
        show_parent = self,
    }

    self.frame = FrameContainer:new{
        bordersize = border,
        radius = radius,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Size.padding.large },
            padded(header),
            VerticalSpan:new{ width = Size.padding.large },
            padded(slider),
            VerticalSpan:new{ width = Size.padding.large * 2 },
            LineWidget:new{
                dimen = Geom:new{ w = outer_w, h = Size.line.medium },
                background = Blitbuffer.COLOR_BLACK,
            },
            HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = radius },
                VerticalGroup:new{
                    VerticalSpan:new{ width = radius },
                    disable_button,
                    VerticalSpan:new{ width = radius },
                },
            },
        },
    }
    local gap = Screen:scaleBySize(8)
    self[1] = BottomContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() - self.bottom_offset - gap },
        self.frame,
    }
end

-- 弹出数字选择框，自定义任意翻页间隔（1~3600 秒）
function AutoTurnDialog:showCustomInterval()
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Autoturn time"),
        value = self.autoturn:getInterval(),
        value_min = 1,
        value_max = 3600,
        value_step = 1,
        value_hold_step = 10,
        unit = C_("Time", "s"),
        ok_text = _("Set"),
        callback = function(spin)
            self.autoturn:setInterval(spin.value)
            self:refresh()
        end,
    })
end

-- 重建内容并局部刷新（使用旧区域，避免尺寸变化留下残影）
function AutoTurnDialog:refresh()
    local old_dimen = self.frame.dimen and self.frame.dimen:copy()
    self:update()
    UIManager:setDirty(self, function()
        return "ui", old_dimen or self.frame.dimen
    end)
end

function AutoTurnDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
end

function AutoTurnDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.frame.dimen
    end)
end

function AutoTurnDialog:onClose()
    UIManager:close(self)
    return true
end

-- 点击弹窗外部时关闭
function AutoTurnDialog:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

return AutoTurnDialog
