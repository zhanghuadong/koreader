--[[--
阅读器快捷菜单（点击屏幕中间或按菜单键打开），覆盖在阅读页上。

竖屏：顶部栏（返回、书名、书签开关）+ 底部标签栏（章节、进度、排版、更多），
点击"进度/排版/更多"在标签栏上方展开对应面板，再次点击收起。
横屏：所有入口变成一条全高的图标侧边栏，面板以全高列的形式显示在侧边栏旁，
侧边栏分隔线上的小三角指向打开该面板的图标。
]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
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
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local TypesetPanel = require("ui/widget/readertypesetpanel")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

-- 标签项：上方图标，下方文字，整块可点击（底部标签栏和"更多"面板共用）
local TabItem = InputContainer:extend{
    icon = nil,
    text = nil,
    width = nil,
    height = nil,   -- 默认为内容高度加上下内边距
    icon_size = 38, -- 图标尺寸（未缩放）
    text_size = 19, -- 文字字号
    callback = nil,
    enabled = true, -- 为 false 时图标和文字变灰，点击无效（如 PDF/DJVU 的排版）
}

-- 构建图标和文字，在给定尺寸内居中，注册点击手势
function TabItem:init()
    local icon_size = Screen:scaleBySize(self.icon_size)
    local v_padding = Screen:scaleBySize(12)
    local content = VerticalGroup:new{
        align = "center",
        IconWidget:new{
            icon = self.icon,
            width = icon_size,
            height = icon_size,
            dim = not self.enabled,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        TextWidget:new{
            text = self.text,
            face = Font:getFace("cfont", self.text_size),
            bold = true,
            max_width = self.width,
            fgcolor = self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        },
    }
    local h = self.height or content:getSize().h + 2 * v_padding
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = h }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = h },
        content,
    }
    self.ges_events = {
        TapTab = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function TabItem:onTapTab()
    if self.enabled and self.callback then
        self.callback()
    end
    return true
end

-- 侧边栏分隔线，可带一个小三角，指向由某个图标打开的面板
local SideLine = Widget:extend{
    height = nil,
    caret_y = nil,  -- 小三角中心的 y 坐标，nil 表示不画
    caret_dir = -1, -- -1：三角朝左，1：朝右
}

function SideLine:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Size.line.thick, h = self.height }
end

function SideLine:getSize()
    return self.dimen
end

-- 画竖线；小三角逐列绘制在线外侧，每列向内收缩
function SideLine:paintTo(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_BLACK)
    if self.caret_y then
        local size = Screen:scaleBySize(9)
        for i = 0, size - 1 do
            local cx = self.caret_dir < 0 and x - 1 - i or x + self.dimen.w + i
            bb:paintRect(cx, y + self.caret_y - (size - i), 1, 2 * (size - i), Blitbuffer.COLOR_BLACK)
        end
    end
end

-- 可点击容器：尺寸取自子控件；enabled 为 false 时点击无效
local TapBox = InputContainer:extend{
    callback = nil,
    enabled = true,
}

-- 按子控件尺寸注册点击手势
function TapBox:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapBox = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function TapBox:onTapBox()
    if self.enabled and self.callback then
        self.callback()
    end
    return true
end

local ReaderQuickMenu = InputContainer:extend{
    ui = nil,
    -- 当前展开的面板：nil（无）、"progress"（进度）、"typeset"（排版）、"font"（字体列表）、"more"（更多）
    bottom_mode = nil,
}

-- 记录屏幕尺寸；返回键或点击菜单以外区域关闭
function ReaderQuickMenu:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    -- 面板可用宽度（竖屏为整屏宽，横屏为侧边栏以外的宽度）
    self.width = self.screen_w
    self.side_padding = Size.padding.fullscreen

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h },
        },
    }
    self:update()
end

-- 构建菜单；竖屏为顶部栏 + 底部栏，top_dimen/bottom_dimen 记录两者区域（用于点击判断和刷新）
function ReaderQuickMenu:update()
    -- PDF/DJVU 等固定版式不能打开排版/字体面板
    if not self.ui.rolling and (self.bottom_mode == "typeset" or self.bottom_mode == "font") then
        self.bottom_mode = nil
    end
    local screen_dimen = Geom:new{ w = self.screen_w, h = self.screen_h }
    if self.screen_w > self.screen_h then
        self:updateLandscape(screen_dimen)
        return
    end
    local top = self:buildTopBar()
    local bottom = self:buildBottomBar()
    local top_h = top:getSize().h
    local bottom_h = bottom:getSize().h
    self.top_dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = top_h }
    self.bottom_dimen = Geom:new{ x = 0, y = self.screen_h - bottom_h, w = self.screen_w, h = bottom_h }
    self[1] = OverlapGroup:new{
        dimen = screen_dimen,
        TopContainer:new{ dimen = screen_dimen:copy(), top },
        BottomContainer:new{ dimen = screen_dimen:copy(), bottom },
    }
end

-- 横屏：全高图标侧边栏位于设备原底边一侧（逆时针旋转时在左侧，否则在右侧），
-- 面板以全高列显示在侧边栏旁，侧边栏分隔线上的小三角指向打开面板的图标。
-- top_dimen 为侧边栏区域，bottom_dimen 为面板区域（无面板时与侧边栏相同）。
function ReaderQuickMenu:updateLandscape(screen_dimen)
    local on_left = Screen:getRotationMode() == Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
    -- 面板对应的侧边栏图标（字体列表由排版打开，三角仍指向排版）
    local column_caret = ({ font = "typeset", typeset = "typeset", more = "more", progress = "progress" })[self.bottom_mode]
    local sidebar = self:buildSideBar(on_left, column_caret)
    local sidebar_w = sidebar:getSize().w
    self.width = self.screen_w - sidebar_w
    self.top_dimen = Geom:new{ x = on_left and 0 or self.width, y = 0, w = sidebar_w, h = self.screen_h }
    self[1] = OverlapGroup:new{
        dimen = screen_dimen,
        on_left and LeftContainer:new{ dimen = screen_dimen:copy(), sidebar }
            or RightContainer:new{ dimen = screen_dimen:copy(), sidebar },
    }
    if column_caret then
        -- 按当前面板生成列内容，并在靠阅读页一侧加一条竖线
        local list
        if self.bottom_mode == "font" then
            list = TypesetPanel.buildFontList(self, {
                column = true,
                width = Screen:scaleBySize(310),
                height = self.screen_h,
            })
        elseif self.bottom_mode == "typeset" then
            list = TypesetPanel.buildSettings(self, {
                column = true,
                width = Screen:scaleBySize(310),
                height = self.screen_h,
            })
        elseif self.bottom_mode == "progress" then
            list = self:buildProgressColumn(Screen:scaleBySize(300), self.screen_h)
        else
            list = self:buildMoreColumn(Screen:scaleBySize(150), self.screen_h)
        end
        local page_line = LineWidget:new{
            dimen = Geom:new{ w = Size.line.thick, h = self.screen_h },
            background = Blitbuffer.COLOR_BLACK,
        }
        local panel = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            on_left and HorizontalGroup:new{ align = "top", list, page_line }
                or HorizontalGroup:new{ align = "top", page_line, list },
        }
        local panel_w = panel:getSize().w
        local panel_x = on_left and sidebar_w or self.width - panel_w
        panel.overlap_offset = { panel_x, 0 }
        -- 插在侧边栏之前绘制，使侧边栏分隔线上的小三角显示在面板上层
        table.insert(self[1], 1, panel)
        self.bottom_dimen = Geom:new{ x = panel_x, y = 0, w = panel_w, h = self.screen_h }
    else
        self.bottom_dimen = self.top_dimen:copy()
    end
end

-- 横屏侧边栏：返回、书签、章节、进度、排版、更多六个图标纵向等分全高；
-- caret_id 为需要显示小三角的图标
function ReaderQuickMenu:buildSideBar(on_left, caret_id)
    local icon_size = Screen:scaleBySize(48)
    local item_w = Screen:scaleBySize(110)
    local items = { "back", "bookmark", "chapters", "progress", "typeset", "more" }
    local item_h = math.floor(self.screen_h / #items)
    local bookmarked = self.ui.bookmark and self.ui.bookmark:isPageBookmarked()
    -- 排版只适用于流式文档（EPUB 等）；PDF/DJVU 等固定版式禁用
    local typeset_enabled = self.ui.rolling ~= nil
    local icons = {
        back = "chevron.left",
        bookmark = bookmarked and "quickmenu.bookmark.filled" or "quickmenu.bookmark",
        chapters = "quickmenu.chapters",
        progress = "quickmenu.progress",
        typeset = "quickmenu.typeset",
        more = "quickmenu.more",
    }
    local actions = self:getTabActions()
    local column = VerticalGroup:new{}
    for _, id in ipairs(items) do
        local enabled = id ~= "typeset" or typeset_enabled
        table.insert(column, TapBox:new{
            callback = actions[id],
            enabled = enabled,
            CenterContainer:new{
                dimen = Geom:new{ w = item_w, h = item_h },
                IconWidget:new{
                    icon = icons[id],
                    width = icon_size,
                    height = icon_size,
                    dim = not enabled,
                },
            },
        })
    end
    local caret_y
    for i, id in ipairs(items) do
        if id == caret_id then
            caret_y = math.floor((i - 0.5) * item_h)
        end
    end
    local line = SideLine:new{
        height = self.screen_h,
        caret_y = caret_y,
        caret_dir = on_left and 1 or -1,
    }
    return FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        on_left and HorizontalGroup:new{ column, line } or HorizontalGroup:new{ line, column },
    }
end

--- 竖屏标签栏和横屏侧边栏共用的操作
function ReaderQuickMenu:getTabActions()
    -- 展开/收起面板：点击已展开的面板时收起
    local function togglePanel(mode)
        self.bottom_mode = self.bottom_mode ~= mode and mode or nil
        self:refresh()
    end
    return {
        back = function()
            self:onClose()
            self.ui:handleEvent(Event:new("Home"))
        end,
        bookmark = function()
            self.ui:handleEvent(Event:new("ToggleBookmark"))
            self:refresh()
        end,
        chapters = function()
            self:onClose()
            self.ui:handleEvent(Event:new("ShowToc"))
        end,
        progress = function()
            togglePanel("progress")
        end,
        typeset = function()
            -- 排版面板只适用于流式文档（EPUB 等）；PDF/DJVU 等固定版式已禁用，点击无效
            if self.ui.rolling then
                togglePanel("typeset")
            end
        end,
        more = function()
            togglePanel("more")
        end,
    }
end

-- 竖屏下当前 bottom_mode 对应的面板，无面板时返回 nil
function ReaderQuickMenu:buildPanel()
    if self.bottom_mode == "font" then
        return TypesetPanel.buildFontList(self)
    elseif self.bottom_mode == "progress" then
        return self:buildProgressPanel()
    elseif self.bottom_mode == "typeset" then
        return TypesetPanel.buildSettings(self)
    elseif self.bottom_mode == "more" then
        return self:buildMorePanel()
    end
end

-- 竖屏顶部栏：返回按钮 + 书名（左），书签开关（右），底部粗分隔线
function ReaderQuickMenu:buildTopBar()
    local icon_size = Screen:scaleBySize(30)
    local actions = self:getTabActions()
    local back_button = Button:new{
        icon = "chevron.left",
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        padding = Size.padding.default,
        callback = actions.back,
        show_parent = self,
    }
    local bookmarked = self.ui.bookmark and self.ui.bookmark:isPageBookmarked()
    local bookmark_button = Button:new{
        icon = bookmarked and "quickmenu.bookmark.filled" or "quickmenu.bookmark",
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        padding = Size.padding.default,
        callback = actions.bookmark,
        show_parent = self,
    }
    local buttons_w = back_button:getSize().w + bookmark_button:getSize().w
    local title = TextWidget:new{
        text = self.ui.doc_props and self.ui.doc_props.display_title or "",
        face = Font:getFace("cfont", 23),
        bold = true,
        max_width = self.width - 2 * self.side_padding - buttons_w - Size.padding.default,
    }
    local row_h = math.max(back_button:getSize().h, title:getSize().h, bookmark_button:getSize().h)
    local inner_w = self.width - 2 * (self.side_padding - Size.padding.default)
    local row_dimen = Geom:new{ w = inner_w, h = row_h }
    local row = OverlapGroup:new{
        dimen = row_dimen,
        LeftContainer:new{
            dimen = row_dimen:copy(),
            HorizontalGroup:new{
                align = "center",
                back_button,
                title,
            },
        },
        RightContainer:new{
            dimen = row_dimen:copy(),
            bookmark_button,
        },
    }
    return FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Size.padding.large },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = self.side_padding - Size.padding.default },
                row,
            },
            VerticalSpan:new{ width = Size.padding.large },
            LineWidget:new{
                dimen = Geom:new{ w = self.width, h = Size.line.thick },
                background = Blitbuffer.COLOR_BLACK,
            },
        },
    }
end

-- 进度数据：全书进度、本章进度（章节内页码，无目录时用全书页码）、累计阅读时间
-- （优先取阅读统计插件的数据，没有时取文档设置中记录的阅读时长）
function ReaderQuickMenu:getProgressValues()
    local ui = self.ui
    local pageno = ui:getCurrentPage()
    local pages = ui.document:getPageCount()
    local book_pct = pages > 0 and math.floor(pageno / pages * 100) or 0

    local chapter_current, chapter_total
    local done = ui.toc and ui.toc:getChapterPagesDone(pageno)
    local count = ui.toc and ui.toc:getChapterPageCount(pageno)
    if done and count and count > 0 then
        chapter_current, chapter_total = done + 1, count
    else
        chapter_current, chapter_total = pageno, pages
    end
    local chapter_pct = chapter_total > 0 and math.floor(chapter_current / chapter_total * 100) or 0

    local read_secs = 0
    local stats = ui.statistics
    if stats and stats.id_curr_book and stats.getBookTotalReadTime then
        read_secs = stats:getBookTotalReadTime(stats.id_curr_book) + (stats.mem_read_time or 0)
    elseif ui.doc_settings then
        read_secs = ui.doc_settings:readSetting("reading_time") or 0
    end
    local hours = math.floor(read_secs / 3600)
    local minutes = math.floor((read_secs % 3600) / 60)

    -- 每项为 { 标签, { 值的各部分 } }：竖屏用" · "拼成一行，横屏每部分各占一行
    return {
        { _("Book progress"), { T("%1%", book_pct) } },
        { _("Chapter progress"), { T("%1%", chapter_pct), T("%1/%2", chapter_current, chapter_total) } },
        { _("Reading time"), { string.format("%dh%02dm", hours, minutes) } },
    }
end

--- 横屏进度列：标签和数值逐行纵向排列
function ReaderQuickMenu:buildProgressColumn(width, height)
    local side = Screen:scaleBySize(20)
    local text_w = width - 2 * side
    local column = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Screen:scaleBySize(18) },
    }
    for i, entry in ipairs(self:getProgressValues()) do
        if i > 1 then
            table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        end
        table.insert(column, TextWidget:new{
            text = entry[1],
            face = Font:getFace("cfont", 18),
            bold = true,
            max_width = text_w,
        })
        table.insert(column, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        for __, line in ipairs(entry[2]) do
            table.insert(column, TextWidget:new{
                text = line,
                face = Font:getFace("cfont", 22),
                bold = true,
                max_width = text_w,
            })
        end
    end
    return HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = side },
        LeftContainer:new{
            dimen = Geom:new{ w = width - side, h = math.min(column:getSize().h, height) },
            column,
        },
    }
end

-- 竖屏进度面板：每项一行，左侧标签，右侧数值
function ReaderQuickMenu:buildProgressPanel()
    local label_face = Font:getFace("cfont", 20)
    local value_face = Font:getFace("cfont", 20)
    local inner_w = self.width - 2 * self.side_padding
    local row_padding = Screen:scaleBySize(8)
    local panel = VerticalGroup:new{
        align = "left",
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.medium },
            background = Blitbuffer.COLOR_BLACK,
        },
        VerticalSpan:new{ width = Size.padding.large },
    }
    for __, entry in ipairs(self:getProgressValues()) do
        local label = TextWidget:new{ text = entry[1], face = label_face, bold = true }
        local value = TextWidget:new{ text = table.concat(entry[2], " · "), face = value_face, bold = true }
        local row_dimen = Geom:new{ w = inner_w, h = math.max(label:getSize().h, value:getSize().h) + 2 * row_padding }
        table.insert(panel, HorizontalGroup:new{
            HorizontalSpan:new{ width = self.side_padding },
            OverlapGroup:new{
                dimen = row_dimen,
                LeftContainer:new{ dimen = row_dimen:copy(), label },
                RightContainer:new{ dimen = row_dimen:copy(), value },
            },
        })
    end
    table.insert(panel, VerticalSpan:new{ width = Size.padding.large })
    return panel
end

-- 触摸翻页是否开启（点击翻页和滑动翻页都未禁用）
local function isTouchPageTurnEnabled()
    return G_reader_settings:nilOrFalse("page_turns_disable_tap")
       and G_reader_settings:nilOrFalse("page_turns_disable_swipe")
end

--- "更多"面板的条目，每项为 { 图标, 文字, 回调 }：
-- 蓝牙连接（仅 Android）、自动翻页（运行中显示激活图标）、触摸开关、高级（阅读选项页）
function ReaderQuickMenu:getMoreItems()
    local entries = {}
    if Device:isAndroid() then
        table.insert(entries, { "quickmenu.bluetooth", _("Bluetooth connection"), function()
            self:onClose()
            UIManager:show(require("ui/widget/bluetoothdialog"):new{})
        end })
    end
    local autoturn = self.ui.autoturn
    if autoturn then
        local active = autoturn:isActive()
        table.insert(entries, { active and "quickmenu.autoturn.active" or "quickmenu.autoturn", _("Auto page turn"), function()
            self:onClose()
            self.ui:handleEvent(Event:new("ShowAutoTurnDialog"))
        end })
    end
    -- 触摸开关：同时开启/禁用点击翻页和滑动翻页，菜单保持打开并刷新图标
    local touch_on = isTouchPageTurnEnabled()
    table.insert(entries, { touch_on and "quickmenu.touch" or "quickmenu.touch.off",
        touch_on and _("Touch on") or _("Touch off"), function()
            G_reader_settings:saveSetting("page_turns_disable_tap", touch_on)
            G_reader_settings:saveSetting("page_turns_disable_swipe", touch_on)
            self:refresh()
        end })
    table.insert(entries, { "quickmenu.advanced", _("Advanced"), function()
        self:onClose()
        UIManager:show(require("ui/widget/readeroptionspage"):new{ ui = self.ui })
    end })
    return entries
end

--- 横屏"更多"列：条目纵向等分全高
function ReaderQuickMenu:buildMoreColumn(width, height)
    local entries = self:getMoreItems()
    local item_h = math.floor(height / #entries)
    local column = VerticalGroup:new{ align = "center" }
    for __, entry in ipairs(entries) do
        table.insert(column, TabItem:new{
            icon = entry[1],
            text = entry[2],
            callback = entry[3],
            width = width,
            height = item_h,
            icon_size = 46,
            text_size = 21,
        })
    end
    return column
end

-- 竖屏"更多"面板：条目横向排成一行，每项占四分之一宽
function ReaderQuickMenu:buildMorePanel()
    local item_w = math.floor(self.width / 4)
    local items = HorizontalGroup:new{ align = "top" }
    for __, entry in ipairs(self:getMoreItems()) do
        table.insert(items, TabItem:new{ icon = entry[1], text = entry[2], width = item_w, callback = entry[3] })
    end
    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            dimen = Geom:new{ w = self.width, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = items:getSize().h },
            items,
        },
    }
end

-- 竖屏底部栏：展开的面板（如有）+ 分隔线 + 四个标签
function ReaderQuickMenu:buildBottomBar()
    local tab_w = math.floor(self.width / 4)
    -- 排版只适用于流式文档（EPUB 等）；PDF/DJVU 等固定版式禁用
    local typeset_enabled = self.ui.rolling ~= nil
    local function tab(icon, text, callback, enabled)
        return TabItem:new{
            icon = icon,
            text = text,
            width = tab_w,
            callback = callback,
            enabled = enabled ~= false,
        }
    end
    local actions = self:getTabActions()
    local tabs = HorizontalGroup:new{
        align = "top",
        tab("quickmenu.chapters", _("Chapters"), actions.chapters),
        tab("quickmenu.progress", _("Progress"), actions.progress),
        tab("quickmenu.typeset", _("Typesetting"), actions.typeset, typeset_enabled),
        tab("quickmenu.more", _("More"), actions.more),
    }
    local group = VerticalGroup:new{ align = "left" }
    local panel = self:buildPanel()
    if self.bottom_mode == "font" then
        -- 字体列表替换整个标签栏
        table.insert(group, panel)
        return FrameContainer:new{
            bordersize = 0,
            padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            group,
        }
    elseif panel then
        table.insert(group, panel)
    end
    table.insert(group, LineWidget:new{
        dimen = Geom:new{ w = self.width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })
    table.insert(group, tabs)
    return FrameContainer:new{
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        group,
    }
end

-- 重建菜单，刷新新旧区域的并集（面板展开/收起时区域大小会变）；
-- 用 "all" 让下层阅读页一起重绘，收起的面板区域会露出正文
function ReaderQuickMenu:refresh()
    local old_top, old_bottom = self.top_dimen, self.bottom_dimen
    self:update()
    local top_region = old_top:combine(self.top_dimen)
    local bottom_region = old_bottom:combine(self.bottom_dimen)
    UIManager:setDirty("all", function()
        return "ui", top_region:combine(bottom_region)
    end)
end

function ReaderQuickMenu:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.top_dimen:combine(self.bottom_dimen)
    end)
end

function ReaderQuickMenu:onCloseWidget()
    local region = self.top_dimen:combine(self.bottom_dimen)
    UIManager:setDirty(nil, function()
        return "ui", region
    end)
end

-- 关闭菜单并通知 ReaderMenu
function ReaderQuickMenu:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

-- 点击菜单以外的区域（阅读页）时关闭
function ReaderQuickMenu:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.top_dimen) and ges.pos:notIntersectWith(self.bottom_dimen) then
        self:onClose()
    end
    return true
end

return ReaderQuickMenu
