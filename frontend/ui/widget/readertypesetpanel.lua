--[[--
快捷菜单（ReaderQuickMenu）的排版面板：

- buildSettings：字体、首行缩进、行距、段距、上下/左右边距的设置格子；
- buildFontList：分页的字体选择列表。

竖屏时显示在底部（两列网格）；横屏时显示为侧边栏旁的一列（可滑动翻页，右侧有滚动条）。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FontList = require("fontlist")
local FrameContainer = require("ui/widget/container/framecontainer")
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
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen

local TypesetPanel = {}

local CELL_RADIUS = Screen:scaleBySize(8) -- 格子圆角半径
local CELL_BORDER = Size.border.thick     -- 格子边框宽度
local FONT_ROWS_PER_PAGE = 4              -- 竖屏字体列表每页行数

-- 可点击容器：尺寸取自子控件
local TapBox = InputContainer:extend{
    callback = nil,
}

-- 按子控件尺寸注册点击手势
function TapBox:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self[1]:getSize().w, h = self[1]:getSize().h }
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
    if self.callback then
        self.callback()
    end
    return true
end

-- 可滑动容器：尺寸取自子控件，滑动时以方向（north/south/east/west）回调，用于列表翻页
local SwipeBox = InputContainer:extend{
    swipe_callback = nil,
}

-- 按子控件尺寸注册滑动手势
function SwipeBox:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self[1]:getSize().w, h = self[1]:getSize().h }
    self.ges_events = {
        SwipeBox = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            },
        },
    }
end

function SwipeBox:onSwipeBox(arg, ges)
    if self.swipe_callback then
        self.swipe_callback(ges.direction)
    end
    return true
end

-- 圆角边框格子；content(inner) 根据内部尺寸生成内容；inverted 为真时黑底（选中状态）
local function roundedCell(w, h, content, inverted)
    local inner = Geom:new{ w = w - 2 * CELL_BORDER, h = h - 2 * CELL_BORDER }
    return FrameContainer:new{
        bordersize = CELL_BORDER,
        radius = CELL_RADIUS,
        padding = 0,
        margin = 0,
        background = inverted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = inner,
            content(inner),
        },
    }
end

-- 两行居中文字：上行为名称，下行为当前值
local function twoLineLabel(label, value, max_w)
    local face = Font:getFace("cfont", 19)
    return VerticalGroup:new{
        align = "center",
        TextWidget:new{ text = label, face = face, bold = true, max_width = max_w },
        TextWidget:new{ text = value, face = face, bold = true, max_width = max_w },
    }
end

-- 步进格子：左侧 "−" 按钮，中间名称和当前值，右侧 "+" 按钮
local function stepperCell(w, h, label, value, on_minus, on_plus, show_parent)
    return roundedCell(w, h, function(inner)
        local btn_w = math.min(inner.h, math.floor(inner.w / 3))
        local function stepButton(text, callback)
            return Button:new{
                text = text,
                width = btn_w,
                -- 上下各留出圆角半径，否则按钮背景会盖住格子的圆角
                height = inner.h - 2 * CELL_RADIUS,
                bordersize = 0,
                padding = 0,
                text_font_size = 32,
                text_font_bold = false,
                callback = callback,
                show_parent = show_parent,
            }
        end
        return OverlapGroup:new{
            dimen = inner:copy(),
            CenterContainer:new{
                dimen = inner:copy(),
                twoLineLabel(label, value, inner.w - 2 * btn_w),
            },
            LeftContainer:new{ dimen = inner:copy(), stepButton("−", on_minus) },
            RightContainer:new{ dimen = inner:copy(), stepButton("+", on_plus) },
        }
    end)
end

-- 把 v 限制在 [min_v, max_v]
local function clamp(v, min_v, max_v)
    return math.max(min_v, math.min(max_v, v))
end

-- 把 v 四舍五入到 step 的整数倍
local function round(v, step)
    return math.floor(v / step + 0.5) * step
end

local SCROLLBAR_W = Screen:scaleBySize(4)    -- 滚动条宽度
local SCROLLBAR_GAP = Screen:scaleBySize(10) -- 列表与滚动条的间距

-- 高度为 h 的分页列表的竖向滚动条（浅灰轨道 + 黑色滑块）；只有一页时用空白占位
local function scrollIndicator(h, page, nb_pages)
    if nb_pages <= 1 then
        return HorizontalSpan:new{ width = SCROLLBAR_W }
    end
    local thumb_h = math.max(Screen:scaleBySize(16), math.floor(h / nb_pages))
    local thumb_y = math.floor((h - thumb_h) * (page - 1) / (nb_pages - 1))
    return OverlapGroup:new{
        dimen = Geom:new{ w = SCROLLBAR_W, h = h },
        LineWidget:new{
            dimen = Geom:new{ w = SCROLLBAR_W, h = h },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
        VerticalGroup:new{
            VerticalSpan:new{ width = thumb_y },
            LineWidget:new{
                dimen = Geom:new{ w = SCROLLBAR_W, h = thumb_h },
                background = Blitbuffer.COLOR_BLACK,
            },
        },
    }
end

-- 生成滑动翻页回调：上滑/左滑下一页，下滑/右滑上一页，页码保存在 menu[page_key]（1..nb_pages）
local function pageSwiper(menu, page_key, nb_pages)
    return function(direction)
        local page = menu[page_key] or 1
        if direction == "north" or direction == "west" then
            page = page + 1
        elseif direction == "south" or direction == "east" then
            page = page - 1
        end
        page = clamp(page, 1, nb_pages)
        if page ~= menu[page_key] then
            menu[page_key] = page
            menu:refresh()
        end
    end
end

-- 字体显示名：优先使用字体文件中的本地化名称（如中文名），找不到时返回字体族名
function TypesetPanel.getFontDisplayName(face)
    local cre = require("document/credocument"):engineInit()
    local filename, faceindex = cre.getFontFaceFilenameAndFaceIndex(face)
    if not filename then
        filename, faceindex = cre.getFontFaceFilenameAndFaceIndex(face, nil, true)
    end
    if filename and faceindex then
        return FontList:getLocalizedFontName(filename, faceindex) or face
    end
    return face
end

--- 排版设置格子：字体、首行缩进、行距、段距、上下边距、左右边距。
-- 默认为两列三行网格（竖屏底部）；opts.column 为真时为单列，宽 opts.width、
-- 高度填满 opts.height，放不下时分页（横屏侧边栏旁）。
function TypesetPanel.buildSettings(menu, opts)
    opts = opts or {}
    local ui = menu.ui
    local width = opts.width or menu.width
    local side = opts.column and Screen:scaleBySize(16) or menu.side_padding
    local gap = Screen:scaleBySize(16)
    local cell_w, cell_h
    if opts.column then
        cell_w = width - 2 * side - SCROLLBAR_W - SCROLLBAR_GAP
        cell_h = Screen:scaleBySize(88)
    else
        cell_w = math.floor((width - 2 * side - gap) / 2)
        cell_h = Screen:scaleBySize(72)
    end
    local show_parent = menu

    -- 执行修改后刷新菜单，更新格子中显示的值
    local function apply(fn)
        fn()
        menu:refresh()
    end

    local default_text = _("Default")

    -- 字体：点击切换到字体列表
    local font_cell = TapBox:new{
        callback = function()
            menu.bottom_mode = "font"
            menu.font_page = nil
            menu:refresh()
        end,
        roundedCell(cell_w, cell_h, function(inner)
            return CenterContainer:new{
                dimen = inner:copy(),
                twoLineLabel(_("Font"), TypesetPanel.getFontDisplayName(ui.font.font_face or ""),
                    inner.w - 2 * Size.padding.default),
            }
        end),
    }

    -- 首行缩进（单位 em，0~4），通过生成的 CSS 生效；
    -- 未设置时显示"默认"，第一次点击 −/+ 先设为 2
    local indent = G_reader_settings:readSetting("typeset_text_indent")
    local function setIndent(delta)
        apply(function()
            local v = clamp((indent or 2) + delta, 0, 4)
            G_reader_settings:saveSetting("typeset_text_indent", v)
            ui.styletweak:updateCssText(true)
        end)
    end
    local indent_cell = stepperCell(cell_w, cell_h, _("First-line indent"),
        indent and string.format("%g", indent) or default_text,
        function() setIndent(indent and -1 or 0) end,
        function() setIndent(indent and 1 or 0) end,
        show_parent)

    -- 行距：字体行高的百分比（50%~200%，步长 10%），显示为 1.0x 等
    local line_spacing = ui.font.configurable.line_spacing or 100
    local function setLineSpacing(delta)
        apply(function()
            ui:handleEvent(Event:new("SetLineSpace", clamp(round(line_spacing + delta, 10), 50, 200)))
        end)
    end
    local line_cell = stepperCell(cell_w, cell_h, _("Line spacing"),
        string.format("%.1fx", line_spacing / 100),
        function() setLineSpacing(-10) end,
        function() setLineSpacing(10) end,
        show_parent)

    -- 段距：行距的倍数（1.0x 表示段间无额外间距，范围 1~3，步长 0.5）；
    -- 未设置时显示"默认"，第一次点击 −/+ 先设为 1.0x
    local para = G_reader_settings:readSetting("typeset_paragraph_spacing")
    local function setPara(delta)
        apply(function()
            local v = clamp((para or 1) + delta, 1, 3)
            G_reader_settings:saveSetting("typeset_paragraph_spacing", v)
            ui.styletweak:updateCssText(true)
        end)
    end
    local para_cell = stepperCell(cell_w, cell_h, _("Paragraph spacing"),
        para and string.format("%.1fx", para) or default_text,
        function() setPara(para and -0.5 or 0) end,
        function() setPara(para and 0.5 or 0) end,
        show_parent)

    -- 页边距：未缩放的像素值（与 ReaderTypeset 一致），范围 0~100，步长 5；上下、左右各自对称设置
    local margins = ui.typeset.unscaled_margins
    local configurable = ui.typeset.configurable
    local function setTopBottom(delta)
        apply(function()
            local v = clamp(margins[2] + delta, 0, 100)
            configurable.t_page_margin = v
            configurable.b_page_margin = v
            ui:handleEvent(Event:new("SetPageTopAndBottomMargin", { v, v }))
        end)
    end
    local function setLeftRight(delta)
        apply(function()
            local v = clamp(margins[1] + delta, 0, 100)
            configurable.h_page_margins = { v, v }
            ui:handleEvent(Event:new("SetPageHorizMargins", { v, v }))
        end)
    end
    local tb_cell = stepperCell(cell_w, cell_h, _("Top/bottom margins"),
        T(_("%1px"), margins[2]),
        function() setTopBottom(-5) end,
        function() setTopBottom(5) end,
        show_parent)
    local lr_cell = stepperCell(cell_w, cell_h, _("Left/right margins"),
        T(_("%1px"), margins[1]),
        function() setLeftRight(-5) end,
        function() setLeftRight(5) end,
        show_parent)

    -- 横屏单列：按可用高度计算每页格子数，可滑动翻页，右侧显示滚动条
    if opts.column then
        local cells = { font_cell, indent_cell, line_cell, para_cell, tb_cell, lr_cell }
        local v_gap = Screen:scaleBySize(26)
        local top = Size.padding.large * 2
        local rows = math.max(1, math.floor((opts.height - 2 * top + v_gap) / (cell_h + v_gap)))
        local nb_pages = math.ceil(#cells / rows)
        menu.typeset_page = clamp(menu.typeset_page or 1, 1, nb_pages)
        local list = VerticalGroup:new{ align = "left" }
        local first = (menu.typeset_page - 1) * rows + 1
        for i = first, first + rows - 1 do
            if i > first then
                table.insert(list, VerticalSpan:new{ width = v_gap })
            end
            -- 最后一页不满时用空白占位，保持列表高度不变
            table.insert(list, cells[i] or Widget:new{ dimen = Geom:new{ w = cell_w, h = cell_h } })
        end
        return VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = top },
            SwipeBox:new{
                swipe_callback = pageSwiper(menu, "typeset_page", nb_pages),
                HorizontalGroup:new{
                    align = "top",
                    HorizontalSpan:new{ width = side },
                    list,
                    HorizontalSpan:new{ width = SCROLLBAR_GAP },
                    scrollIndicator(list:getSize().h, menu.typeset_page, nb_pages),
                    HorizontalSpan:new{ width = side },
                },
            },
        }
    end

    -- 竖屏：顶部粗分隔线，下面两列三行网格
    local function row(a, b)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            a,
            HorizontalSpan:new{ width = gap },
            b,
        }
    end
    local v_gap = Screen:scaleBySize(14)
    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            dimen = Geom:new{ w = width, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
        },
        VerticalSpan:new{ width = v_gap + Size.padding.default },
        row(font_cell, indent_cell),
        VerticalSpan:new{ width = v_gap },
        row(line_cell, para_cell),
        VerticalSpan:new{ width = v_gap },
        row(tb_cell, lr_cell),
        VerticalSpan:new{ width = v_gap + Size.padding.default },
    }
end

--- 分页字体选择列表，当前字体黑底白字显示。
-- 默认为两列网格，替换整个底部栏（竖屏）；opts.column 为真时为单列，
-- 宽 opts.width、高度填满 opts.height（横屏，显示在侧边栏旁）。
function TypesetPanel.buildFontList(menu, opts)
    opts = opts or {}
    local ui = menu.ui
    local width = opts.width or menu.width
    local side = opts.column and Screen:scaleBySize(16) or menu.side_padding
    local columns = opts.column and 1 or 2
    local cre = require("document/credocument"):engineInit()
    local faces = cre.getFontFaces()
    local current = ui.font.font_face

    -- 标题栏：返回按钮（回到排版设置）、"字体"标题，右侧字体数量
    local icon_size = Screen:scaleBySize(30)
    local back_button = Button:new{
        icon = "chevron.left",
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        padding = Size.padding.default,
        callback = function()
            menu.bottom_mode = "typeset"
            menu:refresh()
        end,
        show_parent = menu,
    }
    local title = TextWidget:new{
        text = _("Font"),
        face = Font:getFace("cfont", 23),
        bold = true,
    }
    local count = TextWidget:new{
        text = T(N_("1 font", "%1 fonts", #faces), #faces),
        face = Font:getFace("cfont", 19),
        bold = true,
    }
    local header_w = width - 2 * side + Size.padding.default
    local header_h = math.max(back_button:getSize().h, title:getSize().h)
    local header_dimen = Geom:new{ w = header_w, h = header_h }
    local header = HorizontalGroup:new{
        HorizontalSpan:new{ width = side - Size.padding.default },
        OverlapGroup:new{
            dimen = header_dimen,
            LeftContainer:new{
                dimen = header_dimen:copy(),
                -- 横屏单列较窄，放不下标题，只显示返回按钮
                opts.column and back_button or HorizontalGroup:new{ align = "center", back_button, title },
            },
            RightContainer:new{ dimen = header_dimen:copy(), count },
        },
    }

    -- 字体网格：竖屏每页固定 4 行，横屏按可用高度计算行数
    local gap = Screen:scaleBySize(16)
    local v_gap = Screen:scaleBySize(14)
    local grid_w = width - 2 * side - SCROLLBAR_W - SCROLLBAR_GAP
    local cell_w = math.floor((grid_w - (columns - 1) * gap) / columns)
    local cell_h = Screen:scaleBySize(opts.column and 54 or 60)
    local face_font = Font:getFace("cfont", 19)

    local rows = FONT_ROWS_PER_PAGE
    if opts.column then
        local available = opts.height - header_h - Size.padding.large * 4
        rows = math.max(1, math.floor((available + v_gap) / (cell_h + v_gap)))
    end
    local per_page = rows * columns
    local nb_pages = math.max(1, math.ceil(#faces / per_page))
    -- 首次打开时定位到当前字体所在的页
    if not menu.font_page then
        local idx
        for i, face in ipairs(faces) do
            if face == current then idx = i break end
        end
        menu.font_page = idx and math.ceil(idx / per_page) or 1
    end
    menu.font_page = clamp(menu.font_page, 1, nb_pages)

    local grid = VerticalGroup:new{ align = "left" }
    local first = (menu.font_page - 1) * per_page + 1
    for r = 0, rows - 1 do
        local row = HorizontalGroup:new{}
        for c = 0, columns - 1 do
            local face = faces[first + r * columns + c]
            if c > 0 then
                table.insert(row, HorizontalSpan:new{ width = gap })
            end
            if face then
                local selected = face == current
                table.insert(row, TapBox:new{
                    callback = function()
                        -- 切换字体并加入最近使用列表
                        if face ~= ui.font.font_face then
                            ui.font:onSetFont(face)
                            ui.font:addToRecentlySelectedList(face)
                        end
                        menu:refresh()
                    end,
                    roundedCell(cell_w, cell_h, function(inner)
                        return CenterContainer:new{
                            dimen = inner:copy(),
                            TextWidget:new{
                                text = TypesetPanel.getFontDisplayName(face),
                                face = face_font,
                                bold = true,
                                fgcolor = selected and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                                max_width = inner.w - 2 * Size.padding.default,
                            },
                        }
                    end, selected),
                })
            else
                -- 最后一页不满时用空白占位，保持网格高度不变
                table.insert(row, Widget:new{ dimen = Geom:new{ w = cell_w, h = cell_h } })
            end
        end
        if r > 0 then
            table.insert(grid, VerticalSpan:new{ width = v_gap })
        end
        table.insert(grid, row)
    end
    local body = SwipeBox:new{
        swipe_callback = pageSwiper(menu, "font_page", nb_pages),
        HorizontalGroup:new{
            align = "top",
            HorizontalSpan:new{ width = side },
            grid,
            HorizontalSpan:new{ width = SCROLLBAR_GAP },
            scrollIndicator(grid:getSize().h, menu.font_page, nb_pages),
            HorizontalSpan:new{ width = side },
        },
    }

    if opts.column then
        return VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Size.padding.large },
            header,
            VerticalSpan:new{ width = Size.padding.large },
            body,
        }
    end
    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            dimen = Geom:new{ w = width, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
        },
        VerticalSpan:new{ width = Size.padding.large },
        header,
        VerticalSpan:new{ width = Size.padding.large },
        body,
        VerticalSpan:new{ width = Size.padding.large * 2 },
    }
end

return TypesetPanel
