--[[--
读完一本书后显示的卡片（由 ReaderStatus:onEndOfBook 在"显示读完卡片"模式下弹出）。

内容自上而下：标题"读完的第 N 本书" + 关闭按钮、封面、书名、作者、章数页数、
累计时长/累计天数，以及票根样式的底部（读者名、阅读时段、二维码）。
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

-- 卡片主体与票根之间的虚线分隔，两端在卡片边框上挖出半圆缺口（缺口画在本控件之外，覆盖在边框上）
local TicketDivider = Widget:extend{
    width = nil,
    border = nil, -- 卡片边框宽度
}

-- 缺口半径固定，控件高度等于缺口外径
function TicketDivider:init()
    self.notch_r = Screen:scaleBySize(9)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = 2 * (self.notch_r + self.border) }
end

function TicketDivider:getSize()
    return self.dimen
end

-- 先在左右边框上各画一个白底黑边圆，再用白色矩形擦掉卡片外侧的一半，最后画中间的虚线
function TicketDivider:paintTo(bb, x, y)
    local r = self.notch_r
    local b = self.border
    local cy = y + math.floor(self.dimen.h / 2)
    local outer_r = r + b
    for __, cx in ipairs({ x - math.ceil(b / 2), x + self.dimen.w + math.floor(b / 2) }) do
        bb:paintCircle(cx, cy, outer_r, Blitbuffer.COLOR_WHITE)
        bb:paintCircle(cx, cy, outer_r, Blitbuffer.COLOR_BLACK, b)
    end
    -- 只保留缺口在卡片内侧的半圆
    bb:paintRect(x - math.ceil(b / 2) - outer_r - 1, cy - outer_r - 1, outer_r + 1, 2 * outer_r + 3, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x + self.dimen.w + math.floor(b / 2) + 1, cy - outer_r - 1, outer_r + 1, 2 * outer_r + 3, Blitbuffer.COLOR_WHITE)

    -- 虚线：线段 6、间隔 4，两端避开缺口
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
    name = "end_document", -- 与原"读完"对话框同名，ReaderStatus 据此避免重复弹出
    covers_fullscreen = true,
}

-- 阅读统计数据（已读本数、累计时长、累计天数、用户名、阅读时段、二维码内容）
-- 由 Android 宿主应用提供，接口完成前先返回占位值
-- TODO: 接入 Android 阅读统计接口
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

-- 章数：只统计目录中第一级条目
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

-- 构建卡片：宽度为屏幕短边的 85%，白色全屏背景居中显示；返回键或点击卡片外部关闭
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

    -- 文字控件快捷构造，默认最大宽度为卡片内容宽度
    local function text(str, size, bold, max_w)
        return TextWidget:new{
            text = str,
            face = Font:getFace("cfont", size),
            bold = bold,
            max_width = max_w or inner_w,
        }
    end
    -- 在卡片内水平居中
    local function centered(widget)
        return CenterContainer:new{
            dimen = Geom:new{ w = card_w - 2 * border, h = widget:getSize().h },
            widget,
        }
    end

    -- 标题栏："读完的第 N 本书" + 关闭按钮
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

    -- 书籍信息：书名、作者（多位作者用顿号连接）、章数 · 页数（无目录时只显示页数）
    local book_title = text(props.display_title or "", 24, true)
    local authors = props.authors and props.authors:gsub("\n", "、") or ""
    local author = text(authors, 20, true)
    local pages = self.ui.document:getPageCount()
    local chapters = self:getChapterCount()
    local counts = text(chapters > 0 and T(_("%1 chapters · %2 pages"), chapters, pages)
        or T(N_("1 page", "%1 pages", pages), pages), 18, true)

    -- 统计区：累计时长 | 累计天数，中间竖线分隔
    local half_w = math.floor(inner_w / 2)
    -- 单项统计：上方数值，下方标签，在半宽内居中
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

    -- 票根：左侧读者名、阅读时段、提示文字，右侧二维码
    local qr_size = Screen:scaleBySize(110)
    local qr = QRWidget:new{ text = summary.qr_text, width = qr_size, height = qr_size }
    -- 二维码生成失败时用同尺寸空白占位，布局不变
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

    -- 封面：先排好其余内容，封面高度取剩余可用高度（不超过屏幕 30%），保证整张卡片能放进屏幕
    local rest = VerticalGroup:new{
        align = "center",
        spacer(20), centered(header), spacer(18),
        -- 封面插入在这里，即第 4 个位置
        spacer(18), centered(book_title), spacer(6), centered(author),
        spacer(14), centered(counts), spacer(26), centered(stats), spacer(22),
        divider,
        spacer(16), centered(stub), spacer(20),
    }
    local cover_h = math.min(math.floor(screen_h * 0.3), math.floor(screen_h * 0.96) - rest:getSize().h - 2 * border)
    -- 剩余高度太小（小于 60）时不显示封面
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
        -- 上面测量高度时已缓存了不含封面的布局，插入封面后必须重置，否则绘制时会越界崩溃
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

-- 显示时全刷，消除墨水屏残影
function BookFinishedCard:onShow()
    UIManager:setDirty(self, "full")
end

-- 关闭时释放封面和二维码图像，并全刷恢复阅读页面
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

-- 点击卡片外部时关闭
function BookFinishedCard:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.card.dimen) then
        self:onClose()
    end
    return true
end

return BookFinishedCard
