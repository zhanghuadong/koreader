--[[--
Pull-down panel of the reader: clock and battery, brightness and color temperature sliders,
and quick actions (speed mode, full refresh, lock screen, light on/off).
Attached to the top edge; full width in portrait, centered in landscape.
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

-- Continuous slider: thick track left of the knob, thin track right of it. value is in [0, 1].
local LevelTrack = InputContainer:extend{
    width = nil,
    value = 0,
    callback = nil,
}

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

function LevelTrack:onTapTrack(_, ges)
    return self:setAt(ges.pos.x)
end

function LevelTrack:onPanReleaseTrack(_, ges)
    return self:setAt(ges.pos.x)
end

function LevelTrack:onSwipeTrack(_, ges)
    if ges.direction == "east" then
        return self:setAt(ges.pos.x + ges.distance)
    elseif ges.direction == "west" then
        return self:setAt(ges.pos.x - ges.distance)
    end
    return true
end

local ActionItem = InputContainer:extend{
    icon = nil,
    text = nil,
    width = nil,
    callback = nil,
}

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
    close_callback = nil,
}

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

-- Brightness, as a fraction of the frontlight range
function PullDownPanel:getBrightness()
    if not Device:hasFrontlight() then return 0 end
    local p = self.powerd
    if p.fl_max <= p.fl_min then return 0 end
    return (p:frontlightIntensity() - p.fl_min) / (p.fl_max - p.fl_min)
end

function PullDownPanel:setBrightness(v)
    if not Device:hasFrontlight() then return end
    local p = self.powerd
    v = math.max(0, math.min(1, v))
    p:setIntensity(math.floor(p.fl_min + v * (p.fl_max - p.fl_min) + 0.5))
end

-- Color temperature in [0, 100], cool to warm. Devices without natural light only keep the
-- setting until the Android color temperature interface is available.
function PullDownPanel:getWarmth()
    if Device:hasNaturalLight() then
        return self.powerd:frontlightWarmth()
    end
    return G_reader_settings:readSetting("pulldown_warmth") or 50
end

function PullDownPanel:setWarmth(w)
    w = math.max(0, math.min(100, math.floor(w + 0.5)))
    if Device:hasNaturalLight() then
        self.powerd:setWarmth(w)
    else
        G_reader_settings:saveSetting("pulldown_warmth", w)
    end
end

function PullDownPanel.getWarmthText(w)
    local level = math.floor((w - 50) / 10 + 0.5)
    if level < 0 then
        return T(C_("Pulldown", "Cool %1"), -level)
    elseif level > 0 then
        return T(C_("Pulldown", "Warm %1"), level)
    end
    return C_("Pulldown", "Neutral")
end

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
    local function refreshAfter(fn)
        return function(v)
            fn(v)
            self:refresh()
        end
    end

    -- Actions
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
    -- the top border sits just off screen, so the panel hangs from the top edge
    panel.overlap_offset = { panel_x, -border }
    self.panel_dimen = Geom:new{ x = panel_x, y = 0, w = panel_w, h = panel_h - border }
    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        panel,
    }
end

-- Placeholder until the Android e-ink speed mode interface is available: only remembers the state.
function PullDownPanel:toggleSpeedMode()
    local on = not G_reader_settings:isTrue("pulldown_speed_mode")
    G_reader_settings:saveSetting("pulldown_speed_mode", on)
    Notification:notify(on and C_("Pulldown", "Speed mode on") or C_("Pulldown", "Speed mode off"))
end

function PullDownPanel:lockScreen()
    if Device:isAndroid() then
        -- KEYCODE_SLEEP; injecting key events needs the system uid this build runs as
        os.execute("input keyevent 223 &")
    end
end

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

function PullDownPanel:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function PullDownPanel:onTapClose(_, ges)
    if ges.pos:notIntersectWith(self.panel_dimen) then
        self:onClose()
    end
    return true
end

function PullDownPanel:onSwipeClose(_, ges)
    if ges.direction == "north" then
        self:onClose()
    end
    return true
end

return PullDownPanel
