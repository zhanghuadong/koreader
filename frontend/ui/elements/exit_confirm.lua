--[[--
Exit without confirmation (custom build: avoid double prompt on e-ink back key).
]]

local ExitConfirm = {}

function ExitConfirm:confirm(ok_callback)
    ok_callback()
end

return ExitConfirm
