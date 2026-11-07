local ffi = require("ffi")
local android = require("android")
local BB = require("ffi/blitbuffer")
local C = ffi.C

--[[ configuration for devices with an electric paper display controller ]]--

-- does the device has an e-ink screen?
local has_eink_screen, eink_platform = android.isEink()

-- does the device needs to handle all screen refreshes
local has_eink_full_support = android.isEinkFull()


local full, partial, full_ui, partial_ui, fast, delay_page, delay_ui, delay_fast = android.getEinkConstants()

local framebuffer = {}

-- update a region of the screen
function framebuffer:_updatePartial(mode, delay, x, y, w, h)
    local bb = self.full_bb or self.bb
    x, y, w, h = bb:getBoundedRect(x, y, w, h)
    x, y, w, h = bb:getPhysicalRect(x, y, w, h)

    android.einkUpdate(mode, delay, x, y, (x + w), (y + h))
end

-- update the entire screen
function framebuffer:_updateFull()
    if eink_platform == "rockchip" then
        android.einkUpdate(full)
    else
        self:_updatePartial(full, delay_page, 0, 0, self:getWidth(), self:getHeight())
    end
end

function framebuffer:init()
    -- we present this buffer to the outside
    self.bb = BB.new(android.screen.width, android.screen.height, BB.TYPE_BBRGB32)
    self.bb:fill(BB.COLOR_WHITE)
    self:_updateWindow()
    framebuffer.parent.init(self)
end

-- resize on rotation or split view.
function framebuffer:resize()
    android.screen.width = android.getScreenWidth()
    android.screen.height = android.getScreenHeight()
    local rotation
    local inverse
    if self.bb then
        rotation = self.bb:getRotation()
        inverse = self.bb:getInverse() == 1
        self.bb:free()
    end
    self.bb = BB.new(android.screen.width, android.screen.height, BB.TYPE_BBRGB32)

    -- Rotation and inverse must be inherited
    if rotation then
        self.bb:setRotation(rotation)
    end
    if inverse then
        self.bb:invert()
    end

    self.bb:fill(inverse and BB.COLOR_BLACK or BB.COLOR_WHITE)
    self:_updateWindow()
end

-- 定制：阅读方向只做 KOReader UI/blitbuffer 旋转，不改 Android Activity 屏幕方向
-- （设备 Manifest 已是 nosensor；原先 hasNativeRotation 路径会调 setScreenOrientation）
function framebuffer:getRotationMode()
    return self.cur_rotation_mode
end

function framebuffer:setRotationMode(mode)
    local old = self.cur_rotation_mode
    framebuffer.parent.setRotationMode(self, mode)
    if mode ~= old then
        -- 旋转后清屏并整窗提交，避免旧方向残影与局部刷新坐标错位
        self.bb:fill(BB.COLOR_WHITE)
        if self.viewport then
            self.full_bb:setRotation(self.bb:getRotation())
            self.full_bb:fill(BB.COLOR_WHITE)
        end
        self:_updateWindow()
    end
end

-- 软件旋转时，墨水屏局部刷新的物理坐标容易与逻辑区域不一致，一律整屏刷新
function framebuffer:_refreshEink(mode, delay, x, y, w, h)
    if self.cur_rotation_mode ~= self.DEVICE_ROTATED_UPRIGHT then
        self:_updateFull()
    else
        self:_updatePartial(mode, delay, x, y, w, h)
    end
end

function framebuffer:_updateWindow()
    if android.app.window == nil then
        android.LOGW("cannot blit: no window")
        return
    end

    local buffer = ffi.new("ANativeWindow_Buffer[1]")
    if android.lib.ANativeWindow_lock(android.app.window, buffer, nil) < 0 then
        android.LOGW("Unable to lock window buffer")
        return
    end

    local bb = nil
    if buffer[0].format == C.WINDOW_FORMAT_RGBA_8888
    or buffer[0].format == C.WINDOW_FORMAT_RGBX_8888
    then
        bb = BB.new(buffer[0].width, buffer[0].height, BB.TYPE_BBRGB32, buffer[0].bits, buffer[0].stride*4, buffer[0].stride)
    elseif buffer[0].format == C.WINDOW_FORMAT_RGB_565 then
        bb = BB.new(buffer[0].width, buffer[0].height, BB.TYPE_BBRGB16, buffer[0].bits, buffer[0].stride*2, buffer[0].stride)
    else
        android.LOGE("unsupported window format!")
    end

    if bb then
        local ext_bb = self.full_bb or self.bb
        -- Rotations and inverse are applied in the base ffi/framebuffer class, so our shadow buffer is already inverted and rotated.
        -- All we need is to do is simply clone the invert and rotation settings, so that the blit below becomes 1:1 copy.
        bb:setInverse(ext_bb:getInverse())
        bb:setRotation(ext_bb:getRotation())

        -- getUseCBB should *always* be true on Android, but let's be thorough...
        if bb:getInverse() == 1 and BB:getUseCBB() then
            -- If we're using the CBB (which we should), the invert flag has been thoroughly ignored up until now,
            -- so, simply invert everything *now* ;).
            -- The idea is that we absolutely want to avoid the Lua BB on Android, because it is *extremely* erratic,
            -- because of the mcode alloc issues...

            -- NOTE: CBB's invertblitFrom requires source & dest bb to be of the same type!
            if bb:getType() == ext_bb:getType() then
                -- In practice, this means RGB32, because our self.bb is always RGB32 (c.f., init above)
                bb:invertblitFrom(ext_bb)
            else
                -- On ther other hand, if the window buffer is RGB565, things become uglier...
                bb:blitFrom(ext_bb)
                -- Fair warning, this is inaccurate for anything that isn't pure black or white on RGB565 ;).
                bb:invertRect(0, 0, bb:getWidth(), bb:getHeight())
            end
        else
            bb:blitFrom(ext_bb)
        end
    end

    android.lib.ANativeWindow_unlockAndPost(android.app.window);
end

function framebuffer:refreshFullImp(x, y, w, h) -- luacheck: ignore
    self:_updateWindow()
    if has_eink_screen then
        self:_updateFull()
    end
end

function framebuffer:refreshPartialImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        self:_refreshEink(partial, delay_page, x, y, w, h)
    end
end

function framebuffer:refreshFlashPartialImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        self:_refreshEink(full, delay_page, x, y, w, h)
    end
end

function framebuffer:refreshUIImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        self:_refreshEink(partial_ui, delay_ui, x, y, w, h)
    end
end

function framebuffer:refreshFlashUIImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        self:_refreshEink(full_ui, delay_ui, x, y, w, h)
    end
end

function framebuffer:refreshFastImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        self:_refreshEink(fast, delay_fast, x, y, w, h)
    end
end

return require("ffi/framebuffer"):extend(framebuffer)
