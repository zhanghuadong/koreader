--[[--
Typesetting panels for ReaderQuickMenu: a grid of font / spacing / margin controls,
and a paged font picker.
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

local CELL_RADIUS = Screen:scaleBySize(8)
local CELL_BORDER = Size.border.thick
local FONT_ROWS_PER_PAGE = 4

local TapBox = InputContainer:extend{
    callback = nil,
}

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

local SwipeBox = InputContainer:extend{
    swipe_callback = nil,
}

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

local function twoLineLabel(label, value, max_w)
    local face = Font:getFace("cfont", 19)
    return VerticalGroup:new{
        align = "center",
        TextWidget:new{ text = label, face = face, bold = true, max_width = max_w },
        TextWidget:new{ text = value, face = face, bold = true, max_width = max_w },
    }
end

local function stepperCell(w, h, label, value, on_minus, on_plus, show_parent)
    return roundedCell(w, h, function(inner)
        local btn_w = math.min(inner.h, math.floor(inner.w / 3))
        local function stepButton(text, callback)
            return Button:new{
                text = text,
                width = btn_w,
                -- keep clear of the rounded corners, which the button background would paint over
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

local function clamp(v, min_v, max_v)
    return math.max(min_v, math.min(max_v, v))
end

local function round(v, step)
    return math.floor(v / step + 0.5) * step
end

local SCROLLBAR_W = Screen:scaleBySize(4)
local SCROLLBAR_GAP = Screen:scaleBySize(10)

-- Vertical scroll position indicator for a paged list of height h.
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

-- Swipe handler moving menu[page_key] within 1..nb_pages.
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

--- Grid with font, first-line indent, line spacing, paragraph spacing and margins.
-- With opts.column, a paged single column of opts.width filling opts.height (landscape).
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

    local function apply(fn)
        fn()
        menu:refresh()
    end

    local default_text = _("Default")

    -- Font
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

    -- First-line indent (em), applied through generated CSS
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

    -- Line spacing (percent of the font's line height)
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

    -- Paragraph spacing, in multiples of the line distance (1.0x = no extra gap)
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

    -- Margins (unscaled px, as used by ReaderTypeset)
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
            -- keep the list height constant on the last, partially filled page
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

--- Paged font picker.
-- By default a two-column grid replacing the whole bottom bar; with opts.column, a single
-- column of opts.width filling opts.height (landscape, beside the sidebar).
function TypesetPanel.buildFontList(menu, opts)
    opts = opts or {}
    local ui = menu.ui
    local width = opts.width or menu.width
    local side = opts.column and Screen:scaleBySize(16) or menu.side_padding
    local columns = opts.column and 1 or 2
    local cre = require("document/credocument"):engineInit()
    local faces = cre.getFontFaces()
    local current = ui.font.font_face

    -- Header
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
                -- no room for the title in the narrow column
                opts.column and back_button or HorizontalGroup:new{ align = "center", back_button, title },
            },
            RightContainer:new{ dimen = header_dimen:copy(), count },
        },
    }

    -- Grid
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
                -- keep the grid height constant on the last, partially filled page
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
