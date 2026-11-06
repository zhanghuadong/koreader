--[[--
蓝牙连接对话框（Android）：扫描附近设备，分页列出，点击设备即连接。

竖屏为单栏布局；横屏为左右两栏（左侧设备列表，右侧当前连接和按钮）。
平台侧实现在 luajit-launcher 中（BluetoothHelper.kt，通过 android.lua 暴露给 Lua）。
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
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen

local POLL_INTERVAL = 1    -- 扫描/连接期间轮询设备列表的间隔（秒）
local CONNECT_TIMEOUT = 30 -- 连接超时（秒），超时后不再显示"正在连接"

-- 可点击的行容器：尺寸取自子控件
local TapRow = InputContainer:extend{
    callback = nil,
}

-- 按子控件尺寸注册点击手势
function TapRow:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapRow = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function TapRow:onTapRow()
    if self.callback then
        self.callback()
    end
    return true
end

local BluetoothDialog = InputContainer:extend{
    devices = nil,    -- 设备列表，每项为 { address, name, bonded, connected }
    scanning = false, -- 是否正在扫描
    page = 1,         -- 设备列表当前页
    connecting = nil, -- 正在连接的设备 { address = , name = , deadline = 超时时间 }
}

-- 计算对话框尺寸，注册返回键、点击外部关闭和滑动翻页手势
function BluetoothDialog:init()
    self.android = require("android")
    -- 横屏：左侧设备列表，右侧当前连接和按钮
    self.landscape = Screen:getWidth() > Screen:getHeight()
    self.width = math.floor(Screen:getWidth() * (self.landscape and 0.9 or 0.84))
    self.height = math.floor(Screen:getHeight() * (self.landscape and 0.86 or 0.88))
    self.devices = {}

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }
    self.ges_events.Swipe = {
        GestureRange:new{
            ges = "swipe",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }
    self.poll_task = function() self:poll() end

    -- 对话框一显示就开始扫描（见 onShow），首次绘制先显示"正在扫描…"
    self.scanning = true
    self:update()
end

-- 清空列表，开始扫描，并启动轮询
function BluetoothDialog:startScan()
    self.devices = {}
    self.page = 1
    self.scanning = self.android.bluetoothStartScan()
    self:refresh()
    self:schedulePoll()
end

-- 安排下一次轮询（先取消已安排的，避免重复）
function BluetoothDialog:schedulePoll()
    UIManager:unschedule(self.poll_task)
    UIManager:scheduleIn(POLL_INTERVAL, self.poll_task)
end

-- 轮询：更新扫描状态和设备列表；目标设备已连上或超时则结束"正在连接"；
-- 仍在扫描或连接时继续轮询
function BluetoothDialog:poll()
    self.scanning = self.android.bluetoothIsScanning()
    self.devices = self.android.bluetoothGetDevices()
    if self.connecting then
        local connected = self:getConnectedDevice()
        if (connected and connected.address == self.connecting.address) or os.time() > self.connecting.deadline then
            self.connecting = nil
        end
    end
    self:refresh()
    if self.scanning or self.connecting then
        self:schedulePoll()
    end
end

-- 返回列表中第一个已连接的设备，没有则返回 nil
function BluetoothDialog:getConnectedDevice()
    for _, dev in ipairs(self.devices) do
        if dev.connected then
            return dev
        end
    end
end

-- 发起连接：请求成功后记录正在连接的设备（连接时扫描会停止），继续轮询直到连上或超时
function BluetoothDialog:connect(dev)
    if self.android.bluetoothConnect(dev.address) then
        self.connecting = { address = dev.address, name = dev.name, deadline = os.time() + CONNECT_TIMEOUT }
        self.scanning = false
        self:refresh()
        self:schedulePoll()
    end
end

-- "当前连接"行：正在连接显示"正在连接 xxx…"，已连接显示对勾 + 设备名，否则显示"无连接"
function BluetoothDialog:buildCurrentRow(max_w, face, icon_size, icon_gap)
    local text, icon
    local connected = self:getConnectedDevice()
    if self.connecting then
        text = T(_("Connecting to %1…"), self.connecting.name)
    elseif connected then
        text = connected.name
        icon = "check"
    else
        text = _("No connection")
    end
    local row = HorizontalGroup:new{ align = "center" }
    if icon then
        table.insert(row, IconWidget:new{ icon = icon, width = icon_size, height = icon_size })
        table.insert(row, HorizontalSpan:new{ width = icon_gap })
    end
    table.insert(row, TextWidget:new{
        text = text,
        face = face,
        bold = true,
        max_width = max_w - (icon and icon_size + icon_gap or 0),
    })
    return row
end

-- 右上角关闭按钮
function BluetoothDialog:buildCloseButton()
    local size = Screen:scaleBySize(28)
    return Button:new{
        icon = "close",
        icon_width = size,
        icon_height = size,
        bordersize = 0,
        padding = Size.padding.small,
        callback = function() self:onClose() end,
        show_parent = self,
    }
end

-- 横屏两栏布局：左栏为标题和设备列表；右栏为关闭按钮、当前连接，底部"取消 | 确定"
function BluetoothDialog:updateLandscape()
    local border = Size.border.thick
    local radius = Screen:scaleBySize(10)
    local side = Screen:scaleBySize(16)
    local outer_w = self.width - 2 * border
    local outer_h = self.height - 2 * border
    local divider_w = Size.line.medium
    local left_w = math.floor((outer_w - divider_w) / 2)
    local right_w = outer_w - divider_w - left_w
    local left_inner_w = left_w - 2 * side
    local right_inner_w = right_w - 2 * side
    self.corner_radius = radius

    local label_face = Font:getFace("cfont", 16)
    local row_face = Font:getFace("cfont", 21)
    local icon_size = Screen:scaleBySize(26)
    local icon_gap = Screen:scaleBySize(16)
    local row_h = Screen:scaleBySize(80)

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            widget,
        }
    end

    -- 两栏标题区高度一致，使左侧"N 个结果"与右侧"当前连接"对齐，第一个设备与当前连接行对齐
    local close_button = self:buildCloseButton()
    local title = TextWidget:new{
        text = _("Bluetooth connection"),
        face = Font:getFace("cfont", 22),
        bold = true,
        max_width = left_inner_w,
    }
    local header_h = math.max(title:getSize().h, close_button:getSize().h)

    -- 左栏：标题 + 设备列表（无设备时居中显示"正在扫描…"或"无结果"）
    local left_top = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.large },
        padded(LeftContainer:new{ dimen = Geom:new{ w = left_inner_w, h = header_h }, title }),
    }
    local body_h = outer_h - left_top:getSize().h
    local body_dimen = Geom:new{ w = left_w, h = body_h }
    local body
    if #self.devices == 0 then
        body = CenterContainer:new{
            dimen = body_dimen,
            TextWidget:new{
                text = self.scanning and _("Scanning…") or _("No results"),
                face = row_face,
                bold = true,
            },
        }
    else
        body = TopContainer:new{
            dimen = body_dimen,
            self:buildDeviceList(left_inner_w, body_h, side, label_face, row_face, icon_size, icon_gap,
                { row_h = row_h, hide_page_text = true }),
        }
    end
    local left_pane = VerticalGroup:new{
        align = "left",
        left_top,
        body,
    }

    -- 右栏：关闭按钮、"当前连接"标签和当前连接行，底部"取消 | 确定"（两者目前都只关闭对话框）
    local footer_h = Screen:scaleBySize(56)
    local half_w = math.floor(right_w / 2)
    local function footerButton(text, callback)
        return Button:new{
            text = text,
            width = half_w - Size.line.medium,
            -- 上下各留出圆角半径，避免按钮遮住对话框右下圆角
            height = footer_h - 2 * radius,
            bordersize = 0,
            padding = 0,
            text_font_size = 20,
            callback = callback,
            show_parent = self,
        }
    end
    local footer = VerticalGroup:new{
        LineWidget:new{
            dimen = Geom:new{ w = right_w, h = Size.line.medium },
            background = Blitbuffer.COLOR_BLACK,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = right_w, h = footer_h },
            HorizontalGroup:new{
                align = "center",
                footerButton(_("Cancel"), function() self:onClose() end),
                LineWidget:new{
                    dimen = Geom:new{ w = Size.line.medium, h = math.floor(footer_h * 0.4) },
                    background = Blitbuffer.COLOR_BLACK,
                },
                footerButton(C_("Bluetooth", "OK"), function() self:onClose() end),
            },
        },
    }
    local right_top = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.large },
        padded(RightContainer:new{ dimen = Geom:new{ w = right_inner_w, h = header_h }, close_button }),
        VerticalSpan:new{ width = Size.padding.large },
        padded(TextWidget:new{ text = _("Current connection"), face = label_face, bold = true }),
        VerticalSpan:new{ width = Size.padding.default },
        padded(LeftContainer:new{
            dimen = Geom:new{ w = right_inner_w, h = row_h },
            self:buildCurrentRow(right_inner_w, row_face, icon_size, icon_gap),
        }),
    }
    local right_pane = VerticalGroup:new{
        align = "left",
        right_top,
        VerticalSpan:new{ width = outer_h - right_top:getSize().h - footer:getSize().h },
        footer,
    }

    self.frame = FrameContainer:new{
        bordersize = border,
        radius = radius,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        HorizontalGroup:new{
            align = "top",
            left_pane,
            LineWidget:new{
                dimen = Geom:new{ w = divider_w, h = outer_h },
                background = Blitbuffer.COLOR_BLACK,
            },
            right_pane,
        },
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }
end

-- 构建对话框；竖屏为单栏：标题、当前连接、设备列表，底部"关闭 | 重新扫描"
function BluetoothDialog:update()
    if self.landscape then
        return self:updateLandscape()
    end
    local border = Size.border.thick
    local radius = Screen:scaleBySize(10)
    local side = Screen:scaleBySize(16)
    local outer_w = self.width - 2 * border
    local outer_h = self.height - 2 * border
    local inner_w = outer_w - 2 * side
    self.corner_radius = radius

    local function padded(widget)
        return HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            widget,
        }
    end

    -- 标题栏：标题 + 关闭按钮
    local close_button = self:buildCloseButton()
    local title = TextWidget:new{
        text = _("Bluetooth connection"),
        face = Font:getFace("cfont", 22),
        bold = true,
        max_width = inner_w - close_button:getSize().w,
    }
    local header_dimen = Geom:new{ w = inner_w, h = math.max(title:getSize().h, close_button:getSize().h) }
    local header = OverlapGroup:new{
        dimen = header_dimen,
        LeftContainer:new{ dimen = header_dimen:copy(), title },
        RightContainer:new{ dimen = header_dimen:copy(), close_button },
    }

    -- 当前连接
    local label_face = Font:getFace("cfont", 16)
    local row_face = Font:getFace("cfont", 20)
    local icon_size = Screen:scaleBySize(26)
    local icon_gap = Screen:scaleBySize(12)
    local current_row = self:buildCurrentRow(inner_w, row_face, icon_size, icon_gap)

    local top = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.large },
        padded(header),
        VerticalSpan:new{ width = Size.padding.small },
        padded(TextWidget:new{ text = _("Current connection"), face = label_face, bold = true }),
        VerticalSpan:new{ width = Size.padding.large },
        padded(current_row),
        VerticalSpan:new{ width = Size.padding.large },
        padded(LineWidget:new{
            dimen = Geom:new{ w = inner_w, h = Size.line.thick },
            background = Blitbuffer.COLOR_BLACK,
        }),
    }

    -- 底部按钮：关闭 | 重新扫描（扫描中显示"扫描中"且不响应）
    local footer_h = Screen:scaleBySize(56)
    local half_w = math.floor(outer_w / 2)
    local function footerButton(text, callback)
        return Button:new{
            text = text,
            width = half_w - Size.line.medium,
            -- 上下各留出圆角半径，避免按钮遮住对话框底部圆角
            height = footer_h - 2 * radius,
            bordersize = 0,
            padding = 0,
            text_font_size = 20,
            callback = callback,
            show_parent = self,
        }
    end
    local footer = VerticalGroup:new{
        LineWidget:new{
            dimen = Geom:new{ w = outer_w, h = Size.line.medium },
            background = Blitbuffer.COLOR_BLACK,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = outer_w, h = footer_h },
            HorizontalGroup:new{
                align = "center",
                footerButton(_("Close"), function() self:onClose() end),
                LineWidget:new{
                    dimen = Geom:new{ w = Size.line.medium, h = math.floor(footer_h * 0.4) },
                    background = Blitbuffer.COLOR_BLACK,
                },
                footerButton(self.scanning and _("Scanning") or _("Rescan"), function()
                    if not self.scanning then
                        self:startScan()
                    end
                end),
            },
        },
    }

    -- 中间区域：设备列表，或无设备时的状态文字
    local body_h = outer_h - top:getSize().h - footer:getSize().h
    local body_dimen = Geom:new{ w = outer_w, h = body_h }
    local body
    if #self.devices == 0 then
        body = CenterContainer:new{
            dimen = body_dimen,
            TextWidget:new{
                text = self.scanning and _("Scanning…") or _("No results"),
                face = row_face,
                bold = true,
            },
        }
    else
        body = TopContainer:new{
            dimen = body_dimen,
            self:buildDeviceList(inner_w, body_h, side, label_face, row_face, icon_size, icon_gap),
        }
    end

    self.frame = FrameContainer:new{
        bordersize = border,
        radius = radius,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            top,
            body,
            footer,
        },
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }
end

-- 分页设备列表：顶部"N 个结果"（及页码），下方设备行，右侧滚动条指示当前页
-- 每页行数由可用高度 body_h 和行高决定
-- opts.row_h 覆盖默认行高；opts.hide_page_text 为真时不显示页码文字，只用滚动条指示页码
function BluetoothDialog:buildDeviceList(inner_w, body_h, side, label_face, row_face, icon_size, icon_gap, opts)
    opts = opts or {}
    local count_text = TextWidget:new{
        text = T(N_("1 result", "%1 results", #self.devices), #self.devices),
        face = label_face,
        bold = true,
    }
    local list_top = Size.padding.large
    local row_h = opts.row_h or Screen:scaleBySize(54)
    local list_header_h = count_text:getSize().h + Size.padding.default
    local per_page = math.max(1, math.floor((body_h - list_top - list_header_h - Size.padding.large) / row_h))
    local nb_pages = math.max(1, math.ceil(#self.devices / per_page))
    self.page = math.max(1, math.min(self.page, nb_pages))
    self.nb_pages = nb_pages

    local header_dimen = Geom:new{ w = inner_w, h = count_text:getSize().h }
    local list_header = OverlapGroup:new{
        dimen = header_dimen,
        LeftContainer:new{ dimen = header_dimen:copy(), count_text },
    }
    if not opts.hide_page_text then
        table.insert(list_header, RightContainer:new{
            dimen = header_dimen:copy(),
            TextWidget:new{ text = T(_("%1 / %2"), self.page, nb_pages), face = label_face, bold = true },
        })
    end

    local scrollbar_w = Screen:scaleBySize(4)
    local scrollbar_gap = Screen:scaleBySize(8)
    local row_w = inner_w - scrollbar_w - scrollbar_gap
    local rows = VerticalGroup:new{ align = "left" }
    local first = (self.page - 1) * per_page + 1
    for i = first, math.min(first + per_page - 1, #self.devices) do
        local dev = self.devices[i]
        table.insert(rows, TapRow:new{
            callback = function() self:connect(dev) end,
            LeftContainer:new{
                dimen = Geom:new{ w = row_w, h = row_h },
                HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{ icon = "quickmenu.bluetooth", width = icon_size, height = icon_size },
                    HorizontalSpan:new{ width = icon_gap },
                    TextWidget:new{
                        text = dev.name,
                        face = row_face,
                        bold = true,
                        max_width = row_w - icon_size - icon_gap,
                    },
                },
            },
        })
    end
    local list_h = per_page * row_h

    -- 滚动条：浅灰轨道，黑色滑块按当前页定位；只有一页时用空白占位
    local indicator
    if nb_pages > 1 then
        local thumb_h = math.max(Screen:scaleBySize(16), math.floor(list_h / nb_pages))
        local thumb_y = math.floor((list_h - thumb_h) * (self.page - 1) / (nb_pages - 1))
        indicator = OverlapGroup:new{
            dimen = Geom:new{ w = scrollbar_w, h = list_h },
            LineWidget:new{
                dimen = Geom:new{ w = scrollbar_w, h = list_h },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            },
            VerticalGroup:new{
                VerticalSpan:new{ width = thumb_y },
                LineWidget:new{
                    dimen = Geom:new{ w = scrollbar_w, h = thumb_h },
                    background = Blitbuffer.COLOR_BLACK,
                },
            },
        }
    else
        indicator = HorizontalSpan:new{ width = scrollbar_w }
    end

    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = list_top },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            list_header,
        },
        VerticalSpan:new{ width = Size.padding.default },
        HorizontalGroup:new{
            align = "top",
            HorizontalSpan:new{ width = side },
            rows,
            HorizontalSpan:new{ width = scrollbar_gap },
            indicator,
        },
    }
end

-- 重建并刷新对话框区域
function BluetoothDialog:refresh()
    self:update()
    UIManager:setDirty(self, function()
        return "ui", self.frame.dimen
    end)
end

-- 显示后开始扫描
function BluetoothDialog:onShow()
    self:startScan()
end

-- 关闭时停止轮询和扫描
function BluetoothDialog:onCloseWidget()
    UIManager:unschedule(self.poll_task)
    self.android.bluetoothStopScan()
    UIManager:setDirty(nil, function()
        return "ui", self.frame.dimen
    end)
end

function BluetoothDialog:onClose()
    UIManager:close(self)
    return true
end

-- 点击对话框外部时关闭
function BluetoothDialog:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

-- 滑动翻页：上滑/左滑下一页，下滑/右滑上一页
function BluetoothDialog:onSwipe(arg, ges)
    if not self.nb_pages or self.nb_pages <= 1 then return true end
    local page = self.page
    if ges.direction == "north" or ges.direction == "west" then
        page = page + 1
    elseif ges.direction == "south" or ges.direction == "east" then
        page = page - 1
    end
    page = math.max(1, math.min(page, self.nb_pages))
    if page ~= self.page then
        self.page = page
        self:refresh()
    end
    return true
end

return BluetoothDialog
