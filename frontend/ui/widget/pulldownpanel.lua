--[[--
阅读器下拉面板（在阅读页从顶部向下滑动打开）。

内容：时间和电量、亮度滑块、色温滑块，以及快捷操作（加速、全刷、锁屏、灯光开关）。
面板贴在屏幕顶部：竖屏时全宽，横屏时宽度 60% 并水平居中。
点击面板外部、向上滑动或按返回键关闭。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Notification = require("ui/widget/notification")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template
local Screen = Device.screen

-- 连续滑块：滑钮左侧为粗轨道，右侧为细轨道，value 取值 [0, 1]
local LevelTrack = InputContainer:extend{
    width = nil,
    value = 0,
    callback = nil, -- 值变化时回调 callback(value)
}

-- 注册点击、拖动松手、快速横滑手势
function LevelTrack:init()
    self.knob_r = Screen:scaleBySize(21)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = 2 * self.knob_r + 2 * Size.border.thick }
    local range = function() return self.dimen end
    self.ges_events = {
        TapTrack = { GestureRange:new{ ges = "tap", range = range } },
        PanReleaseTrack = { GestureRange:new{ ges = "pan_release", range = range } },
        SwipeTrack = { GestureRange:new{ ges = "swipe", range = range } },
    }
end

function LevelTrack:getSize()
    return self.dimen
end

-- 绘制轨道和圆形滑钮（轨道两端各留出滑钮半径，滑钮在端点时不被裁切）
function LevelTrack:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local x0 = x + self.knob_r
    local track_w = self.width - 2 * self.knob_r
    local cy = y + math.floor(self.dimen.h / 2)
    local knob_x = x0 + math.floor(track_w * self.value)
    local thick = Screen:scaleBySize(5)
    local thin = Size.line.medium
    bb:paintRect(knob_x, cy - math.floor(thin / 2), x0 + track_w - knob_x, thin, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x0, cy - math.floor(thick / 2), knob_x - x0, thick, Blitbuffer.COLOR_BLACK)
    bb:paintCircle(knob_x, cy, self.knob_r, Blitbuffer.COLOR_WHITE)
    bb:paintCircle(knob_x, cy, self.knob_r, Blitbuffer.COLOR_BLACK, Size.border.thick)
end

-- 把屏幕坐标 screen_x 换算为 [0, 1] 的值，有变化时回调
function LevelTrack:setAt(screen_x)
    local track_w = self.width - 2 * self.knob_r
    local v = (screen_x - self.dimen.x - self.knob_r) / track_w
    v = math.max(0, math.min(1, v))
    if v ~= self.value then
        self.value = v
        self.callback(v)
    end
    return true
end

-- 点击、拖动松手：滑钮移到手指位置
function LevelTrack:onTapTrack(_, ges)
    return self:setAt(ges.pos.x)
end

function LevelTrack:onPanReleaseTrack(_, ges)
    return self:setAt(ges.pos.x)
end

-- 快速横滑：滑钮移到滑动终点
function LevelTrack:onSwipeTrack(_, ges)
    if ges.direction == "east" then
        return self:setAt(ges.pos.x + ges.distance)
    elseif ges.direction == "west" then
        return self:setAt(ges.pos.x - ges.distance)
    end
    return true
end

-- 快捷操作项：上方图标，下方文字，整块可点击
local ActionItem = InputContainer:extend{
    icon = nil,
    text = nil,
    width = nil,
    callback = nil,
}

-- 构建图标和文字并注册点击手势
function ActionItem:init()
    local icon_size = Screen:scaleBySize(52)
    local content = VerticalGroup:new{
        align = "center",
        IconWidget:new{ icon = self.icon, width = icon_size, height = icon_size },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        TextWidget:new{
            text = self.text,
            face = Font:getFace("cfont", 22),
            bold = true,
            max_width = self.width,
        },
    }
    local h = content:getSize().h + 2 * Screen:scaleBySize(8)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = h }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = h },
        content,
    }
    self.ges_events = {
        TapItem = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function ActionItem:onTapItem()
    self.callback()
    return true
end

local PullDownPanel = InputContainer:extend{
    ui = nil,
    close_callback = nil, -- 关闭后回调（ReaderMenu 用来清除面板引用）
}

-- 返回键、点击（外部）、滑动（向上）手势都在全屏范围注册
function PullDownPanel:init()
    self.powerd = Device:getPowerDevice()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    local screen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = screen } }
    self.ges_events.SwipeClose = { GestureRange:new{ ges = "swipe", range = screen } }
    self:update()
end

-- 亮度：当前前光强度在 [fl_min, fl_max] 范围内的比例，返回 [0, 1]
function PullDownPanel:getBrightness()
    if not Device:hasFrontlight() then return 0 end
    local p = self.powerd
    if p.fl_max <= p.fl_min then return 0 end
    return (p:frontlightIntensity() - p.fl_min) / (p.fl_max - p.fl_min)
end

-- 按比例 v（[0, 1]）设置前光强度
function PullDownPanel:setBrightness(v)
    if not Device:hasFrontlight() then return end
    local p = self.powerd
    v = math.max(0, math.min(1, v))
    p:setIntensity(math.floor(p.fl_min + v * (p.fl_max - p.fl_min) + 0.5))
end

-- 色温 [0, 100]，0 为最冷，100 为最暖。支持冷暖光的设备直接读写硬件；
-- 其他设备暂时只保存设置值，等待 Android 色温接口接入
-- TODO: 接入 Android 色温接口
function PullDownPanel:getWarmth()
    if Device:hasNaturalLight() then
        return self.powerd:frontlightWarmth()
    end
    return G_reader_settings:readSetting("pulldown_warmth") or 50
end

-- 设置色温（四舍五入并限制在 [0, 100]）
function PullDownPanel:setWarmth(w)
    w = math.max(0, math.min(100, math.floor(w + 0.5)))
    if Device:hasNaturalLight() then
        self.powerd:setWarmth(w)
    else
        G_reader_settings:saveSetting("pulldown_warmth", w)
    end
end

-- 色温文字：以 50 为中性，每 10 为一档，低于 50 为"冷光N"，高于 50 为"暖光N"
function PullDownPanel.getWarmthText(w)
    local level = math.floor((w - 50) / 10 + 0.5)
    if level < 0 then
        return T(C_("Pulldown", "Cool %1"), -level)
    elseif level > 0 then
        return T(C_("Pulldown", "Warm %1"), level)
    end
    return C_("Pulldown", "Neutral")
end

-- 构建面板内容：状态栏、亮度、色温、快捷操作
function PullDownPanel:update()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local landscape = screen_w > screen_h
    local border = Size.border.thick
    local panel_w = landscape and math.floor(screen_w * 0.6) or screen_w
    local inner_w = panel_w - 2 * border
    local side = Screen:scaleBySize(26)
    local row_w = inner_w - 2 * side

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            widget,
        }
    end
    local function label(text)
        return padded(TextWidget:new{
            text = text,
            face = Font:getFace("cfont", 23),
            bold = true,
            max_width = row_w,
        })
    end

    local btn_w = Screen:scaleBySize(62)
    -- 滑块行："−" 按钮 + 滑块 + "+" 按钮，按钮每次调整 step
    local function sliderRow(value, on_change, step)
        local function stepButton(text, delta)
            return Button:new{
                text = text,
                width = btn_w,
                bordersize = 0,
                padding = 0,
                text_font_size = 40,
                text_font_bold = false,
                callback = function()
                    on_change(math.max(0, math.min(1, value + delta)))
                end,
                show_parent = self,
            }
        end
        return padded(HorizontalGroup:new{
            align = "center",
            stepButton("−", -step),
            LevelTrack:new{ width = row_w - 2 * btn_w, value = value, callback = on_change },
            stepButton("+", step),
        })
    end

    local brightness = self:getBrightness()
    local warmth = self:getWarmth()
    -- 执行设置后重建面板，更新标签文字和滑钮位置
    local function refreshAfter(fn)
        return function(v)
            fn(v)
            self:refresh()
        end
    end

    -- 快捷操作：四项等分一行
    local light_on = Device:hasFrontlight() and self.powerd:isFrontlightOn()
    local item_w = math.floor(row_w / 4)
    local actions = HorizontalGroup:new{
        align = "top",
        ActionItem:new{
            icon = "pulldown.speed",
            text = C_("Pulldown", "Speed up"),
            width = item_w,
            callback = function() self:toggleSpeedMode() end,
        },
        ActionItem:new{
            icon = "pulldown.refresh",
            text = C_("Pulldown", "Full refresh"),
            width = item_w,
            callback = function()
                -- 先关闭面板，再对阅读页做一次全刷
                self:onClose()
                UIManager:setDirty(nil, "full")
            end,
        },
        ActionItem:new{
            icon = "pulldown.lock",
            text = C_("Pulldown", "Lock screen"),
            width = item_w,
            callback = function()
                self:onClose()
                self:lockScreen()
            end,
        },
        ActionItem:new{
            icon = light_on and "pulldown.light" or "pulldown.light.off",
            text = light_on and C_("Pulldown", "Light on") or C_("Pulldown", "Light off"),
            width = item_w,
            callback = function()
                if Device:hasFrontlight() then
                    self.powerd:toggleFrontlight()
                end
                self:refresh()
            end,
        },
    }

    -- 顶部时间 + 电量行，复用阅读选项页的状态栏，放大 1.25 倍
    local status_row = require("ui/widget/readeroptionspage"):buildStatusRow(inner_w, side, 1.25)
    local content = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Screen:scaleBySize(12) },
        status_row,
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
        label(T(C_("Pulldown", "Brightness %1%"), math.floor(brightness * 100 + 0.5))),
        VerticalSpan:new{ width = Screen:scaleBySize(10) },
        sliderRow(brightness, refreshAfter(function(v) self:setBrightness(v) end), 0.1),
        VerticalSpan:new{ width = Screen:scaleBySize(20) },
        label(T(C_("Pulldown", "Color temperature %1"), PullDownPanel.getWarmthText(warmth))),
        VerticalSpan:new{ width = Screen:scaleBySize(10) },
        sliderRow(warmth / 100, refreshAfter(function(v) self:setWarmth(v * 100) end), 0.1),
        VerticalSpan:new{ width = Screen:scaleBySize(28) },
        padded(actions),
        VerticalSpan:new{ width = Screen:scaleBySize(16) },
    }

    local panel = FrameContainer:new{
        bordersize = border,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    local panel_h = panel:getSize().h
    local panel_x = math.floor((screen_w - panel_w) / 2)
    -- 上边框移到屏幕外，面板看起来是从屏幕顶部垂下来的
    panel.overlap_offset = { panel_x, -border }
    self.panel_dimen = Geom:new{ x = panel_x, y = 0, w = panel_w, h = panel_h - border }
    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        panel,
    }
end

-- 加速模式：Android 墨水屏加速接口接入前只是占位，仅记录开关状态并弹出提示
-- TODO: 接入 Android 墨水屏刷新模式接口
function PullDownPanel:toggleSpeedMode()
    local on = not G_reader_settings:isTrue("pulldown_speed_mode")
    G_reader_settings:saveSetting("pulldown_speed_mode", on)
    Notification:notify(on and C_("Pulldown", "Speed mode on") or C_("Pulldown", "Speed mode off"))
end

-- 锁屏（让设备休眠）
function PullDownPanel:lockScreen()
    if Device:isAndroid() then
        -- 注入 KEYCODE_SLEEP（223）；注入按键需要系统 uid，本应用以系统 uid 1000 运行
        os.execute("input keyevent 223 &")
    end
end

-- 重建面板并刷新新旧区域的并集（面板高度可能变化）
function PullDownPanel:refresh()
    local old = self.panel_dimen
    self:update()
    local region = old:combine(self.panel_dimen)
    UIManager:setDirty("all", function()
        return "ui", region
    end)
end

function PullDownPanel:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.panel_dimen
    end)
end

function PullDownPanel:onCloseWidget()
    local region = self.panel_dimen
    UIManager:setDirty(nil, function()
        return "ui", region
    end)
end

-- 关闭面板并通知 ReaderMenu
function PullDownPanel:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

-- 点击面板外部时关闭
function PullDownPanel:onTapClose(_, ges)
    if ges.pos:notIntersectWith(self.panel_dimen) then
        self:onClose()
    end
    return true
end

-- 向上滑动时关闭（其他方向的滑动被吞掉，避免翻页）
function PullDownPanel:onSwipeClose(_, ges)
    if ges.direction == "north" then
        self:onClose()
    end
    return true
end

return PullDownPanel
