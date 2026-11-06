--[[--
Small action popup shown when holding an entry in the bookmark list.

Shows a title with a close button, a one-line preview of the bookmark,
and a list of icon + label actions separated by lines.
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

local ActionRow = InputContainer:extend{
    icon = nil,
    text = nil,
    width = nil,
    icon_size = nil,
    icon_gap = nil,
    face = nil,
    callback = nil,
}

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
    title = nil,
    text = nil,
    -- list of { icon = "...", text = "...", callback = function() end }
    actions = nil,
    width = nil,
}

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

function BookmarkActionPopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

return BookmarkActionPopup
