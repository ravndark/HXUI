local M = {};

-- Internal cache
local blacklistTable     = {};
local lastConfigString   = nil;

local function rebuild_from_config()
    blacklistTable = {};

    if (gConfig == nil) then
        return;
    end

    local cfg = gConfig.partyListStatusBlacklist;
    if (cfg == nil or cfg == '') then
        return;
    end

    -- Parse comma / whitespace separated list of numbers
    for token in string.gmatch(cfg, '[^,%s]+') do
        local id = tonumber(token);
        if (id ~= nil) then
            blacklistTable[id] = true;
        end
    end
end

function M.IsBlacklisted(statusId)
    if (gConfig ~= nil) then
        local cfg = gConfig.partyListStatusBlacklist or '';
        if (cfg ~= lastConfigString) then
            lastConfigString = cfg;
            rebuild_from_config();
        end
    end

    return blacklistTable[statusId] == true;
end

return M;
