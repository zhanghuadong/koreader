-- 检查 Lua 文件语法（只编译不运行），任一文件出错时退出码为 1
-- minilua 不支持命令行参数，文件名从标准输入读取，每行一个。用法（WSL，仓库根目录）：
--   echo frontend/ui/widget/hellopopup.lua | ~/ko-build/koreader-base/thirdparty/luajit/source/src/host/minilua tools/check-lua-syntax.lua
--   git diff --name-only -- '*.lua' | ~/ko-build/koreader-base/thirdparty/luajit/source/src/host/minilua tools/check-lua-syntax.lua
local failed = false
local count = 0
for line in io.lines() do
    local f = line:gsub("%s+$", "")
    if f ~= "" then
        count = count + 1
        local fn, err = loadfile(f)
        io.stdout:write((fn and "OK  " or "ERR ") .. f .. (err and ("\n    " .. err) or "") .. "\n")
        if not fn then failed = true end
    end
end
if count == 0 then
    io.stdout:write("no files given on stdin\n")
end
os.exit(failed and 1 or 0)
