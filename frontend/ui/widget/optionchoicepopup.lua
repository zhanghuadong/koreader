--[[--
居中的单选弹窗：标题 + 关闭按钮，下面是"图标 + 文字"选项行，当前选中项右侧显示对勾，背景变暗。

用于阅读选项页中的翻页方式等选择。
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
local Screen = Device.screen

-- 可点击的选项行容器，子控件为行的显示内容
local ChoiceRow = InputContainer:extend{
    width = nil,
    height = nil,
    callback = nil, -- 点击回调
}

-- 注册整行点击手势
function ChoiceRow:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapChoice = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function ChoiceRow:onTapChoice()
    self.callback()
    return true
end

local OptionChoicePopup = InputContainer:extend{
    title = nil, -- 标题
    -- 选项列表，每项为 { icon = "...", text = "...", value = ... }
    choices = nil,
    selected = nil, -- 当前选中项的 value
    callback = nil, -- function(value)，弹窗关闭后回调
    covers_fullscreen = true, -- 变暗的背景由本控件自行绘制
}

-- 构建标题栏、粗分隔线和选项行（第二行起前面加缩进的细分隔线）；返回键或点击外部关闭
function OptionChoicePopup:init()
    self.width = math.floor(Screen:getWidth() * 0.84)
    local border = Size.border.thick
    local side = Screen:scaleBySize(16)
    local outer_w = self.width - 2 * border
    local inner_w = outer_w - 2 * side
    local icon_size = Screen:scaleBySize(30)
    local icon_gap = Screen:scaleBySize(16)
    local row_h = Screen:scaleBySize(62)

    local close_button = Button:new{
        icon = "close",
        icon_width = Screen:scaleBySize(32),
        icon_height = Screen:scaleBySize(32),
        bordersize = 0,
        padding = Size.padding.small,
        callback = function() self:onClose() end,
        show_parent = self,
    }
    local title = TextWidget:new{
        text = self.title,
        face = Font:getFace("cfont", 22),
        bold = true,
        max_width = inner_w - close_button:getSize().w,
    }
    local header_dimen = Geom:new{ w = inner_w, h = math.max(title:getSize().h, close_button:getSize().h) }

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            widget,
        }
    end

    local content = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.default },
        padded(OverlapGroup:new{
            dimen = header_dimen,
            LeftContainer:new{ dimen = header_dimen:copy(), title },
            RightContainer:new{ dimen = header_dimen:copy(), close_button },
        }),
        VerticalSpan:new{ width = Size.padding.default },
        LineWidget:new{
            dimen = Geom:new{ w = outer_w, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
        },
    }
    local face = Font:getFace("cfont", 22)
    local indent = icon_size + icon_gap
    for i, choice in ipairs(self.choices) do
        if i > 1 then
            table.insert(content, padded(HorizontalGroup:new{
                HorizontalSpan:new{ width = indent },
                LineWidget:new{
                    dimen = Geom:new{ w = inner_w - indent, h = Size.line.medium },
                    background = Blitbuffer.COLOR_BLACK,
                },
            }))
        end
        local row_dimen = Geom:new{ w = inner_w, h = row_h }
        local row = OverlapGroup:new{
            dimen = row_dimen,
            LeftContainer:new{
                dimen = row_dimen:copy(),
                HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{ icon = choice.icon, width = icon_size, height = icon_size },
                    HorizontalSpan:new{ width = icon_gap },
                    TextWidget:new{
                        text = choice.text,
                        face = face,
                        bold = true,
                        max_width = inner_w - indent - icon_size,
                    },
                },
            },
        }
        if choice.value == self.selected then
            -- 当前选中项：右侧对勾
            table.insert(row, RightContainer:new{
                dimen = row_dimen:copy(),
                IconWidget:new{ icon = "check", width = icon_size, height = icon_size },
            })
        end
        table.insert(content, padded(ChoiceRow:new{
            width = inner_w,
            height = row_h,
            callback = function()
                UIManager:close(self)
                self.callback(choice.value)
            end,
            row,
        }))
    end
    table.insert(content, VerticalSpan:new{ width = Size.padding.small })

    self.frame = FrameContainer:new{
        bordersize = border,
        radius = Screen:scaleBySize(10),
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

-- 绘制时先把整屏背景压暗，再绘制弹窗
function OptionChoicePopup:paintTo(bb, x, y)
    -- 只压暗一次：之后的重绘（如按钮点击反馈）不能让背景越来越暗
    if not self.dimmed then
        bb:darkenRect(0, 0, Screen:getWidth(), Screen:getHeight(), 0.2)
        self.dimmed = true
    end
    InputContainer.paintTo(self, bb, x, y)
end

-- 显示/关闭时刷新整屏（背景变暗和恢复）
function OptionChoicePopup:onShow()
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    end)
end

function OptionChoicePopup:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    end)
end

function OptionChoicePopup:onClose()
    UIManager:close(self)
    return true
end

-- 点击弹窗外部时关闭
function OptionChoicePopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

return OptionChoicePopup
