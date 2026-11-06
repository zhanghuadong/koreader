# KOReader 界面开发入门（新增 / 修改 UI）

本文按本项目已有的写法（快捷菜单、下拉面板、读完卡片等），用最简单的例子说明：

1. 新增一个界面控件（弹窗）；
2. 给它加一个入口；
3. 修改已有界面；
4. 添加中文翻译；
5. 检查、编译、安装。

完整的参考实现可以直接看 `frontend/ui/widget/` 下的这些文件，从简单到复杂：

| 文件 | 内容 |
|---|---|
| `openingscreen.lua` | 最简单：全屏白底 + 居中文字，无交互 |
| `bookmarkactionpopup.lua` | 居中弹窗：标题、关闭按钮、可点击的操作行 |
| `autoturnbar.lua` | 自己用 `paintTo` 画图形的控件 |
| `pulldownpanel.lua` | 带滑块、按钮、刷新逻辑的面板 |
| `readerquickmenu.lua` | 横竖屏两套布局、多个面板切换 |

---

## 一、核心概念（先看这 6 条）

**1. 界面是一棵控件树。** 每个控件是一个 Lua 表，子控件按数组形式放在里面（`self[1]`、`self[2]` …）。布局靠嵌套"容器"完成，没有 CSS、没有 XML。

```lua
FrameContainer:new{            -- 边框 / 背景 / 圆角
    VerticalGroup:new{         -- 子控件从上到下排
        TextWidget:new{ ... }, -- 文字
        Button:new{ ... },     -- 按钮
    },
}
```

**2. 控件类用 `extend` 定义，用 `new` 创建。** `new` 会自动调用 `init()`，在 `init()` 里搭建控件树。

```lua
local MyWidget = InputContainer:extend{ text = nil }  -- 定义类及默认字段
function MyWidget:init() ... end                       -- 构建界面
UIManager:show(MyWidget:new{ text = "abc" })           -- 创建并显示
```

**3. 显示 / 关闭都通过 UIManager。**

- `UIManager:show(widget)` 把控件压到窗口栈顶。
- `UIManager:close(widget)` 把它移除。

**4. 墨水屏要手动请求刷新。** 内容变了以后调用 `UIManager:setDirty(控件, 刷新模式)`。

| 模式 | 效果 | 用途 |
|---|---|---|
| `"ui"` | 普通局部刷新 | 弹窗出现/关闭、文字变化，最常用 |
| `"partial"` | 局部刷新，可能稍有残影 | 阅读翻页 |
| `"fast"` | 最快，黑白抖动 | 按钮按下反馈 |
| `"full"` | 全屏闪黑刷新，清残影 | 大面积变化（读完卡片、全刷按钮） |

第二个参数也可以是函数，返回 `模式, 区域`，只刷新指定区域：

```lua
UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
```

**5. 尺寸一律用 `Screen:scaleBySize(n)`。** 这样不同 DPI 的设备上大小一致。字体用 `Font:getFace("cfont", 字号)`，字号会自动缩放。

**6. 交互靠"事件"。**

- 手势写在 `self.ges_events`，按键写在 `self.key_events`。
- 事件 `Xxx` 会调用控件的 `onXxx` 方法。
- 方法返回 `true` 表示"已处理，不再往下传"。
- 事件先传给子控件，子控件不处理时才轮到自己。所以按钮先拿到点击，弹窗自己的"点击外部关闭"后拿到。

---

## 二、常用控件速查

| 类别 | 控件（`require` 路径前缀 `ui/widget/`） | 说明 |
|---|---|---|
| 文字 | `textwidget` | 单行文字，`max_width` 超出显示省略号 |
| 文字 | `textboxwidget` | 多行自动换行，需给 `width` |
| 图标 | `iconwidget` | `icon = "close"`，对应 `resources/icons/mdlight/close.svg` |
| 按钮 | `button` | `text` 或 `icon` 二选一；`callback` 点击回调 |
| 线 | `linewidget` | 实心矩形，常用作分隔线 |
| 间距 | `horizontalspan` / `verticalspan` | 空白，参数都叫 `width` |
| 横排 / 竖排 | `horizontalgroup` / `verticalgroup` | `align` 指定对齐方式 |
| 叠放 | `overlapgroup` | 子控件叠在同一区域，常与左/右容器配合做"左标题、右按钮" |
| 外框 | `container/framecontainer` | `bordersize`、`radius`、`padding`、`background` |
| 对齐 | `container/centercontainer`、`leftcontainer`、`rightcontainer`、`topcontainer`、`bottomcontainer` | 在给定 `dimen` 区域内对齐子控件 |
| 可交互基类 | `container/inputcontainer` | 需要手势或按键的控件都继承它 |
| 自绘基类 | `widget` | 重写 `getSize` 和 `paintTo` 自己画 |

其他常用模块：

| 模块（`require` 路径） | 用途 |
|---|---|
| `ffi/blitbuffer` | 颜色 `Blitbuffer.COLOR_BLACK` 等，以及绘图函数 |
| `ui/geometry` | 区域 `Geom:new{ x, y, w, h }` |
| `ui/gesturerange` | 手势范围 |
| `ui/size` | 标准边框、内边距、线宽，如 `Size.border.thick`、`Size.padding.large` |
| `ui/font` | 字体 |
| `gettext` | 翻译函数 `_` |

---

## 三、例子 1：新建一个最简单的弹窗

效果：屏幕中间一个圆角白框，里面是标题、一行文字和"关闭"按钮。点击按钮、点击弹窗外部或按返回键都会关闭。

新建文件 `frontend/ui/widget/hellopopup.lua`：

```lua
--[[--
示例弹窗：标题 + 文字 + 关闭按钮。
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local HelloPopup = InputContainer:extend{
    text = nil, -- 弹窗正文，由调用方传入
}

function HelloPopup:init()
    -- 1. 交互：返回键关闭；点击全屏任意位置时交给 onTapClose 判断是否在弹窗外
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        },
    }

    -- 2. 布局：边框容器里竖排 标题 / 正文 / 按钮
    local inner_w = math.floor(Screen:getWidth() * 0.7)
    self.frame = FrameContainer:new{
        bordersize = Size.border.thick,
        radius = Screen:scaleBySize(10),
        padding = Screen:scaleBySize(16),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text = _("Hello"),
                face = Font:getFace("cfont", 24),
                bold = true,
            },
            VerticalSpan:new{ width = Screen:scaleBySize(12) },
            TextBoxWidget:new{
                text = self.text or "",
                face = Font:getFace("cfont", 20),
                width = inner_w,
                alignment = "center",
            },
            VerticalSpan:new{ width = Screen:scaleBySize(16) },
            Button:new{
                text = _("Close"),
                width = math.floor(inner_w / 2),
                callback = function() self:onClose() end,
                show_parent = self, -- 按钮刷新时以哪个控件为准，固定写 self
            },
        },
    }
    -- 3. 把弹窗放在全屏区域的正中间
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.frame,
    }
end

-- 显示时刷新弹窗区域
function HelloPopup:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

-- 关闭后刷新弹窗原来的区域，让下面的阅读页重新露出来
function HelloPopup:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

-- 返回键（key_events.Close）和关闭按钮都会调到这里
function HelloPopup:onClose()
    UIManager:close(self)
    return true
end

-- 点在弹窗外才关闭；弹窗内部的点击已被按钮等子控件先处理
function HelloPopup:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

return HelloPopup
```

显示它只需要一行：

```lua
UIManager:show(require("ui/widget/hellopopup"):new{ text = _("This is my first widget") })
```

### 自绘控件（可选）

普通控件组合不出来的图形，比如开关、胶囊、三角，可以继承 `Widget`，实现 `getSize` 和 `paintTo`。参考 `readeroptionspage.lua` 的 `ToggleSwitch`：

```lua
local Dot = Widget:extend{ r = 10 }

function Dot:init()
    local d = 2 * Screen:scaleBySize(self.r)
    self.dimen = Geom:new{ x = 0, y = 0, w = d, h = d }
end

function Dot:getSize()
    return self.dimen
end

function Dot:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y -- 记录屏幕位置，供点击判断和局部刷新使用
    local r = math.floor(self.dimen.w / 2)
    bb:paintCircle(x + r, y + r, r, Blitbuffer.COLOR_BLACK) -- 最后再传一个线宽参数就是空心圆
end
```

---

## 四、例子 2：给新界面加入口

### 方式 A：在快捷菜单"更多"里加一项（最简单）

在 `frontend/ui/widget/readerquickmenu.lua` 的 `ReaderQuickMenu:getMoreItems()` 中，`return entries` 之前加一项。格式是 `{ 图标, 文字, 回调 }`：

```lua
table.insert(entries, { "quickmenu.advanced", _("Hello"), function()
    self:onClose() -- 先关菜单，再打开新界面
    UIManager:show(require("ui/widget/hellopopup"):new{ text = _("This is my first widget") })
end })
```

注意：竖屏"更多"面板每项占屏幕宽度的 1/4，超过 4 项会挤出屏幕。到那时需要修改 `buildMorePanel` 中的 `item_w`，或者改为两行显示。横屏列会自动等分高度。

### 方式 B：通过事件打开（可被多处调用，也可绑定手势）

1. 在阅读器模块里加事件处理函数，比如在 `frontend/apps/reader/modules/readermenu.lua` 里：

   ```lua
   function ReaderMenu:onShowHello()
       UIManager:show(require("ui/widget/hellopopup"):new{ text = _("This is my first widget") })
       return true
   end
   ```

2. 任何能拿到 `ui` 的地方都可以发事件打开它：

   ```lua
   self.ui:handleEvent(Event:new("ShowHello"))
   ```

3. 如果希望用户能在"手势管理"里绑定它，就在 `frontend/dispatcher.lua` 的 `settingsList` 里登记：

   ```lua
   show_hello = {category="none", event="ShowHello", title=_("Show hello"), reader=true},
   ```

   并在下方的 `dispatcher_menu_order` 里加上 `"show_hello"`。

---

## 五、例子 3：修改已有界面

改已有界面，一般就是找到构建它的函数，改参数或者往表里插一项。下面是三个典型场景。

**改样式（字号、间距、尺寸）**：直接改构建处的数值。例如把下拉面板的标签字号从 23 改成 26，在 `pulldownpanel.lua` 的 `update()` 里：

```lua
face = Font:getFace("cfont", 26),
```

**在"阅读选项"页加一个开关**：在 `readeroptionspage.lua` 的 `getOptions()` 里插入一项。

- 有 `checked` 字段时，行右侧显示开关；
- 有 `value` 字段时，行右侧显示"当前值 >"。

```lua
table.insert(options, {
    text = _("My switch"),
    checked = G_reader_settings:isTrue("my_switch"),   -- 读取全局设置
    callback = function()
        G_reader_settings:flipNilOrFalse("my_switch")  -- 切换并保存
        self:refresh()                                  -- 重建并刷新本页
    end,
})
```

设置的读写方法：

- 全局设置用 `G_reader_settings`：`readSetting` / `saveSetting` / `isTrue` / `nilOrTrue` / `flipNilOrFalse`；
- 只对当前这本书生效的设置用 `self.ui.doc_settings`。

**修改 KOReader 原有文件时**，在改动处加一行 `-- 定制：……` 中文注释，方便以后合并上游更新时找到。尽量"加分支"而不是删除原逻辑。例如读完动作新增了 `"pop-up"` 卡片，原来的对话框保留为 `"pop-up_dialog"`。

---

## 六、添加中文翻译

**1. 代码里用英文原文包在翻译函数里。**

| 写法 | 含义 |
|---|---|
| `_("Hello")` | 普通翻译 |
| `C_("Pulldown", "Speed up")` | 带上下文的翻译。同一个英文词在不同地方要翻成不同中文时用，需先 `local C_ = _.pgettext` |
| `N_("1 font", "%1 fonts", n)` | 单复数，需先 `local N_ = _.ngettext` |
| `T(_("Book %1 finished"), n)` | 用参数替换 `%1`，需先 `local T = require("ffi/util").template` |

**2. 在 `l10n/zh_CN/koreader.po` 里加条目。** 新条目要放在文件中第一个 `#~` 开头的行（已废弃条目区）之前：

```po
msgid "Hello"
msgstr "你好"

msgctxt "Pulldown"
msgid "Speed up"
msgstr "加速"
```

**3. 检查重复。** 同一个 `msgctxt` + `msgid` 只能出现一次，包括 `#~` 开头的废弃条目，否则编译翻译时报 `duplicate message definition`。添加前先搜一下：

```bash
msgfmt -o /dev/null l10n/zh_CN/koreader.po
```

---

## 七、检查、编译、安装（WSL）

**1. 语法检查**：改完先检查语法，比编译后在设备上崩溃好查得多。用编译环境自带的 minilua 运行 `tools/check-lua-syntax.lua`。这个工具从标准输入读取文件名，每行一个，出错时显示文件名和行号：

```bash
cd /mnt/e/koreader
M=~/ko-build/koreader-base/thirdparty/luajit/source/src/host/minilua
# 检查单个文件
echo frontend/ui/widget/hellopopup.lua | $M tools/check-lua-syntax.lua
# 检查所有未提交的 Lua 改动
git diff --name-only -- '*.lua' | $M tools/check-lua-syntax.lua
```

注意：

- 新建的文件还没被 git 跟踪，不会出现在 `git diff` 的结果里，要用 `echo` 单独检查。
- 在 PowerShell 里通过 `wsl -e bash -c "..."` 执行时，内层的双引号会被吞掉。命令复杂时，最好写成 `.sh` 脚本再用 `wsl -e bash 脚本路径` 执行。

**2. 编译签名 APK**（约几分钟，32 位 arm）：

```bash
./tools/build-android-arm-signed.sh > ~/ko-build/build-android-arm.log 2>&1; echo EXIT=$?
tail -n 4 ~/ko-build/build-android-arm.log
```

生成的 APK 在仓库根目录，文件名形如 `koreader-android-arm-*.apk`。

**3. 安装到设备**（在 Windows PowerShell 中）：

```powershell
D:\android_sdk\platform-tools\adb.exe install -r (Get-ChildItem e:\koreader\koreader-android-arm-*.apk | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
```

如果提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，说明设备上已装的版本签名不同，需要用相同的平台签名 keystore 重新签名。

**4. 看日志排查崩溃**：

```powershell
D:\android_sdk\platform-tools\adb.exe logcat | Select-String "KOReader|luajit|lua:"
```

Lua 报错会带文件名和行号，比如 `verticalgroup.lua:48: attempt to index a nil value`。

---

## 八、常见坑（都是本项目实际遇到过的）

| 现象 | 原因 / 解决 |
|---|---|
| 往 `VerticalGroup` / `HorizontalGroup` 里插入子控件后，绘制时报 `attempt to index a nil value` | Group 第一次 `getSize()` 时会缓存布局。如果先测量再 `table.insert`，必须调用 `group:resetLayout()`（见 `bookfinishedcard.lua` 的封面插入）。 |
| 面板变小后，原来的位置留下残影 | 刷新区域要用新旧区域的并集：`old:combine(new)`（见各控件的 `refresh()`）。 |
| 按钮背景盖住了外框的圆角 | 按钮高度上下各留出圆角半径，比如 `height = footer_h - 2 * radius`。 |
| 弹窗关闭后整屏闪一下 / 下层被重绘 | 想让旧画面保留到下一个界面绘制，先设 `widget.invisible = true` 再 `UIManager:close`（见 `readerui.lua` 中的 OpeningScreen）。 |
| 图片控件内存泄漏 | `ImageWidget`、`QRWidget` 等在 `onCloseWidget` 里调用 `:free()`。 |
| 横屏布局错乱 | 用 `Screen:getWidth() > Screen:getHeight()` 判断横屏，并分别布局（参考 `readerquickmenu.lua` 的 `updateLandscape`）。旋转屏幕前先关闭不会重新布局的全屏页面。 |
| 全屏页面打开后下面的阅读页还在刷新 | 给全屏控件加 `covers_fullscreen = true`，UIManager 就不会再画它下面的控件。 |
| 新加的中文显示成英文 | `.po` 条目的 `msgid` 与代码中的字符串必须完全一致（包括 `…` 等符号）；带上下文的还要 `msgctxt` 一致。 |
| `.sh` 脚本在 WSL 里报 `$'\r': command not found` | 脚本被转成了 CRLF。不要在仓库配置里设 `core.autocrlf`，需要时只在单条命令上加 `git -c core.autocrlf=true`。 |
| 测试时从屏幕最顶端下滑，打开的是安卓系统通知栏 | 从稍靠下的位置（约 y=60）开始滑动，才会被 KOReader 收到。 |
