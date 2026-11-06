--[[--
自动翻页时替换底部状态栏的控件（由 ReaderFooter 显示）：
左侧时间，中间黑色胶囊显示翻页间隔和播放三角，右侧阅读进度百分比。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local AutoTurnBar = Widget:extend{
    width = nil,   -- 状态栏宽度
    seconds = 0,   -- 翻页间隔（秒）
    clock = "",    -- 已格式化的时间文字
    percent = nil, -- 阅读进度 0..1
}

-- 把秒数格式化为 "20s"、"2m"、"1m30s"（自动翻页弹窗的刻度也复用此函数）
function AutoTurnBar.formatInterval(sec)
    if sec < 60 then
        return string.format("%ds", sec)
    elseif sec % 60 == 0 then
        return string.format("%dm", sec / 60)
    end
    return string.format("%dm%ds", math.floor(sec / 60), sec % 60)
end

-- 创建三段文字并计算胶囊尺寸
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

-- 绘制：白底 → 左侧时间 / 右侧百分比 → 中间黑色圆角胶囊（间隔文字 + 白色三角）
function AutoTurnBar:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    -- 在 wx 处绘制控件，并在状态栏内垂直居中
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

    -- 播放三角：逐列绘制，每列向内收缩一像素
    local tri_x = tx + self.pill_text:getSize().w + self.pill_gap
    local tri_h = self.triangle_w * 2
    local tri_y = py + math.floor((self.pill_h - tri_h) / 2)
    for i = 0, self.triangle_w - 1 do
        local h = tri_h - 2 * i
        bb:paintRect(tri_x + i, tri_y + i, 1, h, Blitbuffer.COLOR_WHITE)
    end
end

-- 释放文字控件占用的资源
function AutoTurnBar:free()
    self.clock_text:free()
    self.percent_text:free()
    self.pill_text:free()
end

return AutoTurnBar
