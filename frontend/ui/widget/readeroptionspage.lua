--[[--
全屏"阅读选项"页，从阅读器快捷菜单的 更多 > 高级 打开。

顶部为时间 + 电量状态行和带返回按钮的标题，下面是选项列表：
阅读方向、对齐方式（单选弹窗），断字、抗锯齿、EPUB 图片、灰度图片、夜间模式、隐藏顶部状态栏（开关）。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
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
local OptionChoicePopup = require("ui/widget/optionchoicepopup")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

-- 开关控件（仅显示，点击由所在行处理）：开为黑底白钮靠右，关为白底黑边黑钮靠左
local ToggleSwitch = Widget:extend{
    checked = false,
}

-- 固定尺寸 54×30
function ToggleSwitch:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:scaleBySize(54), h = Screen:scaleBySize(30) }
end

function ToggleSwitch:getSize()
    return self.dimen
end

-- 绘制胶囊形底座和圆形滑钮
function ToggleSwitch:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h = self.dimen.w, self.dimen.h
    local r = math.floor(h / 2)
    local border = Size.border.thick
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_BLACK, r)
    local knob_r = r - border - Screen:scaleBySize(2)
    if self.checked then
        bb:paintCircle(x + w - r, y + r, knob_r, Blitbuffer.COLOR_WHITE)
    else
        bb:paintRoundedRect(x + border, y + border, w - 2 * border, h - 2 * border, Blitbuffer.COLOR_WHITE, r - border)
        bb:paintCircle(x + r, y + r, knob_r, Blitbuffer.COLOR_BLACK)
    end
end

-- 可点击的选项行容器，子控件为行的显示内容
local OptionRow = InputContainer:extend{
    width = nil,
    height = nil,
    callback = nil, -- 点击回调
}

-- 注册整行点击手势
function OptionRow:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TapRow = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function OptionRow:onTapRow()
    self.callback()
    return true
end

-- 阅读方向选项：竖屏、横屏、反向竖屏、反向横屏
local ORIENTATIONS = {
    { value = Screen.DEVICE_ROTATED_UPRIGHT, icon = "options.orient.portrait",
      text = C_("Orientation", "Portrait") },
    { value = Screen.DEVICE_ROTATED_CLOCKWISE, icon = "options.orient.landscape",
      text = C_("Orientation", "Landscape") },
    { value = Screen.DEVICE_ROTATED_UPSIDE_DOWN, icon = "options.orient.portrait.inverted",
      text = C_("Orientation", "Inverted portrait") },
    { value = Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE, icon = "options.orient.landscape.inverted",
      text = C_("Orientation", "Inverted landscape") },
}

-- 对齐方式选项：value 为 typeset_text_align 设置值，nil 表示保持书籍自带的对齐方式
local ALIGNMENTS = {
    { value = nil, icon = "options.align.auto", text = C_("Alignment", "Auto") },
    { value = "left", icon = "options.align.left", text = C_("Alignment", "Left") },
    { value = "center", icon = "options.align.center", text = C_("Alignment", "Center") },
    { value = "right", icon = "options.align.right", text = C_("Alignment", "Right") },
    { value = "justify", icon = "options.align.justify", text = C_("Alignment", "Justify") },
}

-- 返回选项列表中 value 对应的显示文字
local function choiceText(choices, value)
    for _, choice in ipairs(choices) do
        if choice.value == value then
            return choice.text
        end
    end
    return ""
end

local ReaderOptionsPage = InputContainer:extend{
    ui = nil,
    covers_fullscreen = true,
}

-- 返回键关闭页面
function ReaderOptionsPage:init()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:update()
end

-- 生成选项列表。每项为 { text, value（右侧文字）或 checked（开关状态）, callback }
-- 对齐、断字、抗锯齿、EPUB 图片只对流式排版文档（EPUB 等）显示
function ReaderOptionsPage:getOptions()
    local ui = self.ui
    local options = {}
    -- 阅读方向
    table.insert(options, {
        text = _("Reading orientation"),
        value = choiceText(ORIENTATIONS, Screen:getRotationMode()),
        callback = function()
            self:showChoices(_("Reading orientation"), ORIENTATIONS, Screen:getRotationMode(), function(mode)
                if mode ~= Screen:getRotationMode() then
                    -- 只切换 KOReader UI 方向，不改 Android Activity 屏幕方向。
                    -- 先关掉选项页/弹窗，下一拍再旋转，避免旧布局画到新方向上。
                    self:onClose()
                    UIManager:nextTick(function()
                        UIManager:broadcastEvent(Event:new("SetRotationMode", mode))
                    end)
                end
            end)
        end,
    })
    if ui.rolling then
        -- 对齐方式：通过 ReaderStyleTweak 生成的全局 CSS 生效
        local align = G_reader_settings:readSetting("typeset_text_align")
        table.insert(options, {
            text = _("Alignment"),
            value = choiceText(ALIGNMENTS, align),
            callback = function()
                self:showChoices(_("Alignment"), ALIGNMENTS, align, function(value)
                    G_reader_settings:saveSetting("typeset_text_align", value)
                    ui.styletweak:updateCssText(true)
                    self:refresh()
                end)
            end,
        })
        -- 断字
        table.insert(options, {
            text = C_("Reading options", "Enable hyphenation"),
            checked = ui.typography.hyphenation,
            callback = function()
                local v = not ui.typography.hyphenation
                ui.typography.hyphenation = v
                G_reader_settings:saveSetting("hyphenation", v)
                ui.document:setTextHyphenation(v)
                ui:handleEvent(Event:new("UpdatePos"))
                self:refresh()
            end,
        })
        -- 文字抗锯齿（全局设置）
        table.insert(options, {
            text = _("Anti-aliased text"),
            checked = G_reader_settings:nilOrTrue("cre_font_antialiasing"),
            callback = function()
                G_reader_settings:flipNilOrTrue("cre_font_antialiasing")
                ui.styletweak:applyFontAntialiasing()
                ui:handleEvent(Event:new("UpdatePos"))
                self:refresh()
            end,
        })
        -- 显示 EPUB 图片（关闭时通过 CSS 隐藏图片）
        table.insert(options, {
            text = _("EPUB images"),
            checked = not G_reader_settings:isTrue("typeset_hide_images"),
            callback = function()
                G_reader_settings:flipNilOrFalse("typeset_hide_images")
                ui.styletweak:updateCssText(true)
                self:refresh()
            end,
        })
    end
    -- 灰度图片（关闭彩色渲染）
    table.insert(options, {
        text = _("Grayscale images"),
        checked = not Screen:isColorEnabled(),
        callback = function()
            local CanvasContext = require("document/canvascontext")
            local color = not Screen:isColorEnabled()
            G_reader_settings:saveSetting("color_rendering", color)
            CanvasContext:setColorRenderingEnabled(color)
            UIManager:broadcastEvent(Event:new("ColorRenderingUpdate"))
            self:refresh()
        end,
    })
    -- 定制：暗黑/浅色（复用全局夜间模式反色）；开 = 暗黑，关 = 浅色
    table.insert(options, {
        text = _("Night mode"),
        checked = G_reader_settings:isTrue("night_mode"),
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleNightMode"))
            self:refresh()
        end,
    })
    -- 定制：隐藏顶部状态栏（时间 + 电量）；打开开关 = 隐藏；切换后立即改布局
    local top_bar = ui.view.top_status_bar
    if top_bar then
        table.insert(options, {
            text = _("Hide status bar"),
            checked = not top_bar.visible,
            callback = function()
                top_bar:toggle()
                -- 本页顶部留白与阅读页状态栏同步显隐，立刻重绘
                self:refresh("partial")
            end,
        })
    end
    return options
end

-- 弹出单选弹窗
function ReaderOptionsPage:showChoices(title, choices, selected, callback)
    UIManager:show(OptionChoicePopup:new{
        title = title,
        choices = choices,
        selected = selected,
        callback = callback,
    })
end

-- 状态行：左侧时间，右侧电量百分比和电池图标；下拉面板也复用此函数
-- width 为行宽，side 为左右边距，scale 为文字和电池的放大倍数（默认 1）
function ReaderOptionsPage:buildStatusRow(width, side, scale)
    scale = scale or 1
    local face = Font:getFace("cfont", math.floor(17 * scale))
    local h = Screen:scaleBySize(34 * scale)
    local dimen = Geom:new{ w = width, h = h }
    local row = OverlapGroup:new{
        dimen = dimen,
        LeftContainer:new{
            dimen = dimen:copy(),
            HorizontalGroup:new{
                HorizontalSpan:new{ width = side },
                TextWidget:new{
                    text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")),
                    face = face,
                    bold = true,
                },
            },
        },
    }
    if Device:hasBattery() then
        -- 电池图标：细边框外壳，内部按电量比例填充黑色，右侧加一小段正极
        local capacity = Device:getPowerDevice():getCapacity()
        local battery_w, battery_h = Screen:scaleBySize(26 * scale), Screen:scaleBySize(13 * scale)
        local fill_w = math.floor((battery_w - 4 * Size.border.thin) * capacity / 100)
        local battery = HorizontalGroup:new{
            align = "center",
            FrameContainer:new{
                bordersize = Size.border.thin,
                padding = Size.border.thin,
                margin = 0,
                LeftContainer:new{
                    dimen = Geom:new{ w = battery_w - 4 * Size.border.thin, h = battery_h - 4 * Size.border.thin },
                    LineWidget:new{
                        dimen = Geom:new{ w = math.max(fill_w, 1), h = battery_h - 4 * Size.border.thin },
                        background = Blitbuffer.COLOR_BLACK,
                    },
                },
            },
            LineWidget:new{
                dimen = Geom:new{ w = Size.border.thick, h = math.floor(battery_h / 2) },
                background = Blitbuffer.COLOR_BLACK,
            },
        }
        table.insert(row, RightContainer:new{
            dimen = dimen:copy(),
            HorizontalGroup:new{
                align = "center",
                TextWidget:new{ text = capacity .. "%", face = face, bold = true },
                HorizontalSpan:new{ width = Screen:scaleBySize(6) },
                battery,
                HorizontalSpan:new{ width = side },
            },
        })
    end
    return row
end

-- 构建整页：状态行（与阅读页顶部状态栏同步显隐）、标题行、选项行
function ReaderOptionsPage:update()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local side = Screen:scaleBySize(18)
    local inner_w = width - 2 * side

    local content = VerticalGroup:new{
        align = "left",
    }
    -- 定制：与阅读页顶部状态栏一致；隐藏时本页也不再画状态行
    local top_bar = self.ui and self.ui.view and self.ui.view.top_status_bar
    if top_bar and top_bar.visible then
        table.insert(content, self:buildStatusRow(width, side))
    end

    local title_h = Screen:scaleBySize(56)
    local title_dimen = Geom:new{ w = width, h = title_h }
    table.insert(content, OverlapGroup:new{
        dimen = title_dimen,
        CenterContainer:new{
            dimen = title_dimen:copy(),
            TextWidget:new{
                text = _("Reading options"),
                face = Font:getFace("cfont", 23),
                bold = true,
                max_width = width - 4 * title_h,
            },
        },
        LeftContainer:new{
            dimen = title_dimen:copy(),
            HorizontalGroup:new{
                HorizontalSpan:new{ width = side - Size.padding.small },
                Button:new{
                    icon = "chevron.left",
                    icon_width = Screen:scaleBySize(34),
                    icon_height = Screen:scaleBySize(34),
                    bordersize = 0,
                    padding = Size.padding.small,
                    callback = function() self:onClose() end,
                    show_parent = self,
                },
            },
        },
    })

    local row_h = Screen:scaleBySize(66)
    local label_face = Font:getFace("cfont", 22)
    local value_face = Font:getFace("cfont", 19)
    local chevron_size = Screen:scaleBySize(24)
    for i, option in ipairs(self:getOptions()) do
        if i > 1 then
            table.insert(content, HorizontalGroup:new{
                HorizontalSpan:new{ width = side },
                LineWidget:new{
                    dimen = Geom:new{ w = inner_w, h = Size.line.medium },
                    background = Blitbuffer.COLOR_DARK_GRAY,
                },
            })
        end
        local trailing
        if option.checked ~= nil then
            trailing = ToggleSwitch:new{ checked = option.checked }
        else
            trailing = HorizontalGroup:new{
                align = "center",
                TextWidget:new{ text = option.value, face = value_face, bold = true },
                HorizontalSpan:new{ width = Screen:scaleBySize(6) },
                IconWidget:new{ icon = "chevron.right", width = chevron_size, height = chevron_size },
            }
        end
        local row_dimen = Geom:new{ w = inner_w, h = row_h }
        table.insert(content, HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            OptionRow:new{
                width = inner_w,
                height = row_h,
                callback = option.callback,
                OverlapGroup:new{
                    dimen = row_dimen,
                    LeftContainer:new{
                        dimen = row_dimen:copy(),
                        TextWidget:new{
                            text = option.text,
                            face = label_face,
                            bold = true,
                            max_width = inner_w - trailing:getSize().w - side,
                        },
                    },
                    RightContainer:new{ dimen = row_dimen:copy(), trailing },
                },
            },
        })
    end

    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

-- 选项变化后重建并刷新整页；refresh_mode 可选（显隐状态栏时用 partial）
function ReaderOptionsPage:refresh(refresh_mode)
    self:update()
    UIManager:setDirty(self, refresh_mode or "ui")
end

function ReaderOptionsPage:onShow()
    UIManager:setDirty(self, "ui")
end

function ReaderOptionsPage:onCloseWidget()
    -- 关闭后重绘阅读页，使状态栏显隐与边距改动立刻可见
    if self.ui and self.ui.view and self.ui.view.dialog then
        UIManager:setDirty(self.ui.view.dialog, "ui")
    else
        UIManager:setDirty(nil, "ui")
    end
end

function ReaderOptionsPage:onClose()
    UIManager:close(self)
    return true
end

return ReaderOptionsPage
