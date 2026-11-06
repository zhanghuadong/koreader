--[[--
Status bar shown by ReaderFooter while autoturn is running:
clock on the left, the interval as a black pill in the middle, book progress on the right.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local AutoTurnBar = Widget:extend{
    width = nil,
    seconds = 0,
    clock = "",
    percent = nil, -- 0..1
}

function AutoTurnBar.formatInterval(sec)
    if sec < 60 then
        return string.format("%ds", sec)
    elseif sec % 60 == 0 then
        return string.format("%dm", sec / 60)
    end
    return string.format("%dm%ds", math.floor(sec / 60), sec % 60)
end

function AutoTurnBar:init()
    self.height = Screen:scaleBySize(50)
    self.margin = Screen:scaleBySize(16)
    local face = Font:getFace("cfont", 21)
    self.clock_text = TextWidget:new{ text = self.clock, face = face, bold = true }
    self.percent_text = TextWidget:new{
        text = self.percent and string.format("%d%%", math.floor(self.percent * 100 + 0.5)) or "",
        face = face,
        bold = true,
    }
    self.pill_text = TextWidget:new{
        text = AutoTurnBar.formatInterval(self.seconds),
        face = Font:getFace("cfont", 18),
        bold = true,
        fgcolor = Blitbuffer.COLOR_WHITE,
    }
    self.pill_h = Screen:scaleBySize(31)
    self.triangle_w = math.floor(self.pill_h * 0.3)
    self.pill_pad = math.floor(self.pill_h * 0.55)
    self.pill_gap = Screen:scaleBySize(5)
    self.pill_w = 2 * self.pill_pad + self.pill_text:getSize().w + self.pill_gap + self.triangle_w
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

function AutoTurnBar:getSize()
    return self.dimen
end

function AutoTurnBar:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    local function paintCentered(widget, wx)
        widget:paintTo(bb, wx, y + math.floor((self.height - widget:getSize().h) / 2))
    end
    paintCentered(self.clock_text, x + self.margin)
    paintCentered(self.percent_text, x + self.width - self.margin - self.percent_text:getSize().w)

    local px = x + math.floor((self.width - self.pill_w) / 2)
    local py = y + math.floor((self.height - self.pill_h) / 2)
    bb:paintRoundedRect(px, py, self.pill_w, self.pill_h, Blitbuffer.COLOR_BLACK, math.floor(self.pill_h / 2))
    local tx = px + self.pill_pad
    self.pill_text:paintTo(bb, tx, py + math.floor((self.pill_h - self.pill_text:getSize().h) / 2))

    -- play triangle, one column at a time
    local tri_x = tx + self.pill_text:getSize().w + self.pill_gap
    local tri_h = self.triangle_w * 2
    local tri_y = py + math.floor((self.pill_h - tri_h) / 2)
    for i = 0, self.triangle_w - 1 do
        local h = tri_h - 2 * i
        bb:paintRect(tri_x + i, tri_y + i, 1, h, Blitbuffer.COLOR_WHITE)
    end
end

function AutoTurnBar:free()
    self.clock_text:free()
    self.percent_text:free()
    self.pill_text:free()
end

return AutoTurnBar
