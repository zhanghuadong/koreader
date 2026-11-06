--[[--
Card shown when the end of a book is reached: cover, title, author, chapter and page counts,
reading stats, and a ticket-like stub with the reader's name, reading period and a QR code.
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
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local QRWidget = require("ui/widget/qrwidget")
local RenderImage = require("ui/renderimage")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen

-- Dashed separator between the card body and its stub, with half-circle notches cut into the
-- card border at both ends (painted just outside this widget, over the border).
local TicketDivider = Widget:extend{
    width = nil,
    border = nil, -- card border width
}

function TicketDivider:init()
    self.notch_r = Screen:scaleBySize(9)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = 2 * (self.notch_r + self.border) }
end

function TicketDivider:getSize()
    return self.dimen
end

function TicketDivider:paintTo(bb, x, y)
    local r = self.notch_r
    local b = self.border
    local cy = y + math.floor(self.dimen.h / 2)
    local outer_r = r + b
    for __, cx in ipairs({ x - math.ceil(b / 2), x + self.dimen.w + math.floor(b / 2) }) do
        bb:paintCircle(cx, cy, outer_r, Blitbuffer.COLOR_WHITE)
        bb:paintCircle(cx, cy, outer_r, Blitbuffer.COLOR_BLACK, b)
    end
    -- keep only the inner halves of the notches
    bb:paintRect(x - math.ceil(b / 2) - outer_r - 1, cy - outer_r - 1, outer_r + 1, 2 * outer_r + 3, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x + self.dimen.w + math.floor(b / 2) + 1, cy - outer_r - 1, outer_r + 1, 2 * outer_r + 3, Blitbuffer.COLOR_WHITE)

    local dash = Screen:scaleBySize(6)
    local gap = Screen:scaleBySize(4)
    local thickness = Size.line.medium
    local start_x = x + outer_r + gap
    local end_x = x + self.dimen.w - outer_r - gap
    local dash_x = start_x
    while dash_x < end_x do
        bb:paintRect(dash_x, cy - math.floor(thickness / 2), math.min(dash, end_x - dash_x), thickness, Blitbuffer.COLOR_BLACK)
        dash_x = dash_x + dash + gap
    end
end

local BookFinishedCard = InputContainer:extend{
    ui = nil,
    name = "end_document",
    covers_fullscreen = true,
}

-- Reading stats that come from the Android host app; placeholders until that interface is available.
function BookFinishedCard:getReadingSummary()
    return {
        book_count = "--",
        total_time = "--",
        total_days = "--",
        user_name = "--",
        period = "--",
        qr_text = "https://koreader.rocks",
    }
end

function BookFinishedCard:getChapterCount()
    local toc = self.ui.toc
    if not toc then return 0 end
    toc:fillToc()
    local count = 0
    for __, item in ipairs(toc.toc or {}) do
        if item.depth == 1 then
            count = count + 1
        end
    end
    return count
end

function BookFinishedCard:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h },
        },
    }

    local summary = self:getReadingSummary()
    local props = self.ui.doc_props or {}
    local border = Size.border.thick
    local card_w = math.floor(math.min(screen_w, screen_h) * 0.85)
    local side = Screen:scaleBySize(22)
    local inner_w = card_w - 2 * border - 2 * side

    local function text(str, size, bold, max_w)
        return TextWidget:new{
            text = str,
            face = Font:getFace("cfont", size),
            bold = bold,
            max_width = max_w or inner_w,
        }
    end
    local function centered(widget)
        return CenterContainer:new{
            dimen = Geom:new{ w = card_w - 2 * border, h = widget:getSize().h },
            widget,
        }
    end

    -- Header
    local close_size = Screen:scaleBySize(28)
    local close_button = Button:new{
        icon = "close",
        icon_width = close_size,
        icon_height = close_size,
        bordersize = 0,
        padding = 0,
        callback = function() self:onClose() end,
        show_parent = self,
    }
    local title = text(T(_("Book %1 finished"), summary.book_count), 22, true, inner_w - close_size)
    local header_dimen = Geom:new{ w = inner_w, h = math.max(title:getSize().h, close_button:getSize().h) }
    local header = OverlapGroup:new{
        dimen = header_dimen,
        LeftContainer:new{ dimen = header_dimen:copy(), title },
        RightContainer:new{ dimen = header_dimen:copy(), close_button },
    }

    -- Book info
    local book_title = text(props.display_title or "", 24, true)
    local authors = props.authors and props.authors:gsub("\n", "、") or ""
    local author = text(authors, 20, true)
    local pages = self.ui.document:getPageCount()
    local chapters = self:getChapterCount()
    local counts = text(chapters > 0 and T(_("%1 chapters · %2 pages"), chapters, pages)
        or T(N_("1 page", "%1 pages", pages), pages), 18, true)

    -- Stats
    local half_w = math.floor(inner_w / 2)
    local function stat(value, label)
        local group = VerticalGroup:new{
            align = "center",
            text(value, 24, true, half_w),
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            text(label, 19, true, half_w),
        }
        return CenterContainer:new{
            dimen = Geom:new{ w = half_w, h = group:getSize().h },
            group,
        }
    end
    local time_stat = stat(summary.total_time, _("Total time"))
    local days_stat = stat(summary.total_days, _("Total days"))
    local stat_h = time_stat:getSize().h
    local stats = HorizontalGroup:new{
        align = "center",
        time_stat,
        LineWidget:new{
            dimen = Geom:new{ w = Size.line.medium, h = stat_h },
            background = Blitbuffer.COLOR_BLACK,
        },
        days_stat,
    }

    -- Stub
    local qr_size = Screen:scaleBySize(110)
    local qr = QRWidget:new{ text = summary.qr_text, width = qr_size, height = qr_size }
    local qr_widget = qr.image and qr or Widget:new{ dimen = Geom:new{ w = qr_size, h = qr_size } }
    self.qr_widget = qr.image and qr
    local stub_text_w = inner_w - qr_size - Screen:scaleBySize(12)
    local line_gap = Screen:scaleBySize(8)
    local stub_info = VerticalGroup:new{
        align = "left",
        text(summary.user_name, 19, true, stub_text_w),
        VerticalSpan:new{ width = line_gap },
        text(summary.period, 19, true, stub_text_w),
        VerticalSpan:new{ width = line_gap },
        text(_("Scan for more reading stats"), 19, true, stub_text_w),
    }
    local stub_dimen = Geom:new{ w = inner_w, h = math.max(stub_info:getSize().h, qr_widget:getSize().h) }
    local stub = OverlapGroup:new{
        dimen = stub_dimen,
        LeftContainer:new{ dimen = stub_dimen:copy(), stub_info },
        RightContainer:new{ dimen = stub_dimen:copy(), qr_widget },
    }

    local divider = TicketDivider:new{ width = card_w - 2 * border, border = border }
    local function spacer(n) return VerticalSpan:new{ width = Screen:scaleBySize(n) } end

    -- Cover, sized to whatever height is left so the card fits on screen
    local rest = VerticalGroup:new{
        align = "center",
        spacer(20), centered(header), spacer(18),
        -- the cover is inserted here, at index 4
        spacer(18), centered(book_title), spacer(6), centered(author),
        spacer(14), centered(counts), spacer(26), centered(stats), spacer(22),
        divider,
        spacer(16), centered(stub), spacer(20),
    }
    local cover_h = math.min(math.floor(screen_h * 0.3), math.floor(screen_h * 0.96) - rest:getSize().h - 2 * border)
    local cover = self.ui.bookinfo and cover_h >= Screen:scaleBySize(60)
        and self.ui.bookinfo:getCoverImage(self.ui.document)
    if cover then
        local cover_w = math.floor(cover:getWidth() * cover_h / cover:getHeight())
        cover = RenderImage:scaleBlitBuffer(cover, cover_w, cover_h, true)
        self.cover_widget = ImageWidget:new{
            image = cover,
            width = cover_w,
            height = cover_h,
        }
        table.insert(rest, 4, centered(FrameContainer:new{
            bordersize = Size.border.thin,
            padding = 0,
            margin = 0,
            self.cover_widget,
        }))
        -- measuring the card above cached the layout without the cover
        rest:resetLayout()
    end

    self.card = FrameContainer:new{
        bordersize = border,
        radius = Screen:scaleBySize(10),
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        rest,
    }
    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = screen_h },
            self.card,
        },
    }
end

function BookFinishedCard:onShow()
    UIManager:setDirty(self, "full")
end

function BookFinishedCard:onCloseWidget()
    if self.cover_widget then
        self.cover_widget:free()
    end
    if self.qr_widget then
        self.qr_widget:free()
    end
    UIManager:setDirty(nil, "full")
end

function BookFinishedCard:onClose()
    UIManager:close(self)
    return true
end

function BookFinishedCard:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.card.dimen) then
        self:onClose()
    end
    return true
end

return BookFinishedCard
