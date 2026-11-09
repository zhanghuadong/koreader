--[[--
阅读页底部状态栏：左侧时间、中间当前章节名、右侧全书进度百分比，
文字下方有一条细进度线。由 ReaderFooter 显示；自动翻页时会被 AutoTurnBar 替换。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local ReaderStatusBar = Widget:extend{
    width = nil,     -- 状态栏宽度
    clock = "",      -- 已格式化的时间
    chapter = "",    -- 当前章节标题
    percent = nil,   -- 阅读进度 0..1
}

function ReaderStatusBar:init()
    self.line_h = math.max(1, Screen:scaleBySize(2))
    self.height = Screen:scaleBySize(50)
    self.margin = Screen:scaleBySize(16)
    self.gap = Screen:scaleBySize(12)
    local face = Font:getFace("cfont", 18)

    self.clock_text = TextWidget:new{
        text = self.clock,
        face = face,
    }
    self.percent_text = TextWidget:new{
        text = self.percent and string.format("%d%%", math.floor(self.percent * 100 + 0.5)) or "",
        face = face,
    }

    -- 章节占中间剩余宽度，过长则截断
    local side_w = self.clock_text:getSize().w + self.percent_text:getSize().w + 2 * self.margin + 2 * self.gap
    local chapter_max_w = math.max(0, self.width - side_w)
    self.chapter_text = TextWidget:new{
        text = self.chapter or "",
        face = face,
        bold = true,
        max_width = chapter_max_w,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end

function ReaderStatusBar:getSize()
    return self.dimen
end

-- 绘制：白底 → 左时间 / 中章节 / 右百分比 → 底部细进度线
function ReaderStatusBar:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    -- 文字在进度线上方区域垂直居中
    local text_area_h = self.height - self.line_h
    local function paintCentered(widget, wx)
        widget:paintTo(bb, wx, y + math.floor((text_area_h - widget:getSize().h) / 2))
    end

    paintCentered(self.clock_text, x + self.margin)
    paintCentered(self.percent_text, x + self.width - self.margin - self.percent_text:getSize().w)

    local chapter_w = self.chapter_text:getSize().w
    paintCentered(self.chapter_text, x + math.floor((self.width - chapter_w) / 2))

    -- 底部分隔/进度线：浅灰底轨 + 黑色已读段
    local line_y = y + self.height - self.line_h
    bb:paintRect(x, line_y, self.width, self.line_h, Blitbuffer.COLOR_LIGHT_GRAY)
    local pct = self.percent or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local filled = math.floor(self.width * pct + 0.5)
    if filled > 0 then
        bb:paintRect(x, line_y, filled, self.line_h, Blitbuffer.COLOR_BLACK)
    end
end

function ReaderStatusBar:free()
    self.clock_text:free()
    self.percent_text:free()
    self.chapter_text:free()
end

return ReaderStatusBar
