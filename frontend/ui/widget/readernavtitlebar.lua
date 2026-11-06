--[[--
Tab header shared by the reader chapter list and the bookmark list.

Shows the "Chapters" and "Bookmarks" tabs, with an underline below the active one,
and an optional icon button on the right. It replaces TitleBar in Menu, so it
implements the TitleBar methods Menu relies on.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
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
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local NavTab = InputContainer:extend{
    text = nil,
    face = nil,
    active = false,
    callback = nil,
    hold_callback = nil,
}

function NavTab:init()
    local label = TextWidget:new{
        text = self.text,
        face = self.face,
        bold = true,
    }
    local label_w = label:getWidth()
    local underline_h = Screen:scaleBySize(3)
    local underline
    if self.active then
        underline = LineWidget:new{
            dimen = Geom:new{ w = label_w, h = underline_h },
            background = Blitbuffer.COLOR_BLACK,
        }
    else
        underline = VerticalSpan:new{ width = underline_h }
    end
    self[1] = VerticalGroup:new{
        align = "left",
        label,
        VerticalSpan:new{ width = Size.padding.default },
        underline,
    }
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapNavTab = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
        HoldNavTab = {
            GestureRange:new{
                ges = "hold",
                range = function() return self.dimen end,
            },
        },
    }
end

function NavTab:onTapNavTab()
    if self.callback then
        self.callback()
    end
    return true
end

function NavTab:onHoldNavTab()
    if self.hold_callback then
        self.hold_callback()
    end
    return true
end

local ReaderNavTitleBar = OverlapGroup:extend{
    width = nil,
    -- "toc" or "bookmark"
    active_tab = "toc",
    -- called with the tab id ("toc" or "bookmark") when an inactive tab is tapped
    tab_callback = nil,
    -- called when the active tab is held (opens the list options dialog)
    hold_callback = nil,
    right_icon = nil,
    right_icon_tap_callback = nil,
    show_parent = nil,
}

function ReaderNavTitleBar:init()
    self.width = self.width or Screen:getWidth()
    local face = Font:getFace("smalltfont")
    local side_padding = Size.padding.fullscreen
    local top_padding = Size.padding.large

    local function makeTab(tab_id, text)
        local is_active = self.active_tab == tab_id
        return NavTab:new{
            text = text,
            face = face,
            active = is_active,
            callback = function()
                if not is_active and self.tab_callback then
                    self.tab_callback(tab_id)
                end
            end,
            hold_callback = function()
                if is_active and self.hold_callback then
                    self.hold_callback()
                end
            end,
        }
    end

    local tabs = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = side_padding },
        makeTab("toc", _("Chapters")),
        HorizontalSpan:new{ width = Screen:scaleBySize(20) },
        makeTab("bookmark", _("Bookmarks")),
    }
    local tabs_h = tabs:getSize().h

    local icon_size = Screen:scaleBySize(DGENERIC_ICON_SIZE * 0.8)
    if self.right_icon then
        self.right_button = Button:new{
            icon = self.right_icon,
            icon_width = icon_size,
            icon_height = icon_size,
            bordersize = 0,
            padding = Size.padding.default,
            callback = self.right_icon_tap_callback,
            show_parent = self.show_parent,
        }
    end

    local content_h = math.max(tabs_h, self.right_button and self.right_button:getSize().h or 0)
    self.titlebar_height = top_padding + content_h + Size.padding.default
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.titlebar_height }

    local row_dimen = Geom:new{ w = self.width, h = content_h }
    local row = OverlapGroup:new{
        dimen = row_dimen,
        LeftContainer:new{
            dimen = row_dimen:copy(),
            tabs,
        },
    }
    if self.right_button then
        table.insert(row, RightContainer:new{
            dimen = row_dimen:copy(),
            HorizontalGroup:new{
                self.right_button,
                HorizontalSpan:new{ width = side_padding - Size.padding.default },
            },
        })
    end
    self[1] = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = top_padding },
        row,
    }
    OverlapGroup.init(self)
end

function ReaderNavTitleBar:getHeight()
    return self.titlebar_height
end

-- The tabs carry the title; Menu still calls these when switching item tables.
function ReaderNavTitleBar:setTitle() end
function ReaderNavTitleBar:setSubTitle() end
function ReaderNavTitleBar:setLeftIcon() end
function ReaderNavTitleBar:setRightIcon() end

function ReaderNavTitleBar:generateHorizontalLayout()
    if self.right_button then
        return { { self.right_button } }
    end
    return {}
end

function ReaderNavTitleBar:generateVerticalLayout()
    return self:generateHorizontalLayout()
end

return ReaderNavTitleBar
