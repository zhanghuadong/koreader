--[[--
打开书籍时的过渡页：全屏白底，居中显示"正在打开…"。

由 ReaderUI:showReaderCoroutine 显示，阅读器创建完成前一直留在屏幕上。
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local Screen = Device.screen

local OpeningScreen = WidgetContainer:extend{
    name = "opening_screen",
    covers_fullscreen = true, -- 全屏覆盖，UIManager 不必重绘下层控件
}

-- 构建白色全屏背景和居中的提示文字
function OpeningScreen:init()
    self.dimen = Screen:getSize()
    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Screen:getSize(),
            TextWidget:new{
                text = _("Opening…"),
                face = Font:getFace("cfont", 24),
                bold = true,
            },
        },
    }
end

-- 显示时整屏刷新一次
function OpeningScreen:onShow()
    UIManager:setDirty(self, "ui")
end

return OpeningScreen
