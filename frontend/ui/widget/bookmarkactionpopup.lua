--[[--
书签操作小弹窗：在书签列表中长按某一条时弹出。

包含标题和关闭按钮、书签内容的单行预览，以及若干"图标 + 文字"操作行（跳转、删除等），行间有分隔线。
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
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local Screen = Device.screen

-- 单个操作行：左侧图标 + 文字，整行可点击
local ActionRow = InputContainer:extend{
    icon = nil,      -- 图标名
    text = nil,      -- 文字
    width = nil,     -- 行宽
    icon_size = nil, -- 图标边长
    icon_gap = nil,  -- 图标与文字间距
    face = nil,      -- 字体
    callback = nil,  -- 点击回调
}

-- 构建行布局并注册整行点击手势
function ActionRow:init()
    local row_padding = Screen:scaleBySize(14)
    local label = TextWidget:new{
        text = self.text,
        face = self.face,
        max_width = self.width - self.icon_size - self.icon_gap,
    }
    local h = math.max(self.icon_size, label:getSize().h) + 2 * row_padding
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = h }
    self[1] = LeftContainer:new{
        dimen = Geom:new{ w = self.width, h = h },
        HorizontalGroup:new{
            align = "center",
            IconWidget:new{
                icon = self.icon,
                width = self.icon_size,
                height = self.icon_size,
            },
            HorizontalSpan:new{ width = self.icon_gap },
            label,
        },
    }
    self.ges_events = {
        TapAction = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function ActionRow:onTapAction()
    if self.callback then
        self.callback()
    end
    return true
end

local BookmarkActionPopup = InputContainer:extend{
    title = nil, -- 标题
    text = nil,  -- 预览文字（书签笔记或原文）
    -- 操作列表，每项为 { icon = "...", text = "...", callback = function() end }
    actions = nil,
    width = nil, -- 弹窗宽度，默认屏幕宽度的 82%
}

-- 构建标题栏、预览、粗分隔线和操作行（第二行起前面加缩进的细分隔线）；返回键或点击外部关闭
function BookmarkActionPopup:init()
    self.width = self.width or math.floor(Screen:getWidth() * 0.82)
    local border = Size.border.window
    local padding_h = Size.padding.large * 2
    local outer_w = self.width - 2 * border
    local inner_w = outer_w - 2 * padding_h
    local icon_size = Screen:scaleBySize(22)
    local icon_gap = Screen:scaleBySize(16)

    local close_button = Button:new{
        icon = "close",
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        padding = Size.padding.default,
        callback = function() self:onClose() end,
        show_parent = self,
    }
    local title = TextWidget:new{
        text = self.title,
        face = Font:getFace("cfont", 20),
        bold = true,
        max_width = inner_w - close_button:getSize().w,
    }
    local header_dimen = Geom:new{ w = inner_w, h = math.max(title:getSize().h, close_button:getSize().h) }
    local header = OverlapGroup:new{
        dimen = header_dimen,
        LeftContainer:new{ dimen = header_dimen:copy(), title },
        RightContainer:new{ dimen = header_dimen:copy(), close_button },
    }

    local preview = TextWidget:new{
        text = util.cleanupSelectedText(self.text or ""):gsub("%s+", " "),
        face = Font:getFace("cfont", 18),
        bold = true,
        max_width = inner_w,
    }

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = padding_h },
            widget,
        }
    end

    local content = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.default },
        padded(header),
        padded(preview),
        VerticalSpan:new{ width = Size.padding.large * 2 },
        LineWidget:new{
            dimen = Geom:new{ w = outer_w, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
        },
    }
    local action_face = Font:getFace("cfont", 18)
    local separator_indent = icon_size + icon_gap
    for i, action in ipairs(self.actions or {}) do
        if i > 1 then
            table.insert(content, padded(HorizontalGroup:new{
                HorizontalSpan:new{ width = separator_indent },
                LineWidget:new{
                    dimen = Geom:new{ w = inner_w - separator_indent, h = Size.line.medium },
                    background = Blitbuffer.COLOR_BLACK,
                },
            }))
        end
        table.insert(content, padded(ActionRow:new{
            icon = action.icon,
            text = action.text,
            width = inner_w,
            icon_size = icon_size,
            icon_gap = icon_gap,
            face = action_face,
            callback = function()
                -- 先关闭弹窗再执行操作，操作内部可能会刷新或关闭书签列表
                UIManager:close(self)
                if action.callback then
                    action.callback()
                end
            end,
        }))
    end

    self.frame = FrameContainer:new{
        bordersize = border,
        radius = Size.radius.window,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }
end

function BookmarkActionPopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
end

function BookmarkActionPopup:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.frame.dimen
    end)
end

function BookmarkActionPopup:onClose()
    UIManager:close(self)
    return true
end

-- 点击弹窗外部时关闭
function BookmarkActionPopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

return BookmarkActionPopup
