require('common');
local imgui           = require('imgui');
local fonts           = require('fonts');
local primitives      = require('primitives');
local statusHandler   = require('statushandler');
local buffTable       = require('bufftable');
local statusBlacklist = require('statusblacklist');
local progressbar     = require('progressbar');
local encoding        = require('gdifonts.encoding');
local ashita_settings = require('settings');
local actionTracker   = require('actiontracker');

local fullMenuWidth  = {};
local fullMenuHeight = {};
local buffWindowX    = {};
local debuffWindowX  = {};

local partyWindowPrim = {};
partyWindowPrim[1] = { background = {} };
partyWindowPrim[2] = { background = {} };
partyWindowPrim[3] = { background = {} };

local selectionPrim;
local arrowPrim;
local partyTargeted;
local partySubTargeted;
local memberText      = {};
local partyMaxSize    = 6;
local memberTextCount = partyMaxSize * 3;

-- Bars-style SP pulse state for each party slot (0..17)
local spPulseAlpha       = {};
local spPulseDirectionUp = {};
local borderConfig       = { 1, '#243e58' };

local bgImageKeys            = { 'bg', 'tl', 'tr', 'br', 'bl' };
local bgTitleAtlasItemCount  = 4;
local bgTitleItemHeight;
local loadedBg = nil;

local partyList = {};

----------------------------------------------------------------
-- Preview-only random buffs / debuffs
----------------------------------------------------------------

-- Build pools of known buff and debuff IDs from buffTable.statusEffects
local previewBuffIds   = {};
local previewDebuffIds = {};

if (buffTable and buffTable.statusEffects) then
    for id, kind in pairs(buffTable.statusEffects) do
        -- 0 = buff, 1 = debuff (see bufftable.lua comment)
        if kind == 0 then
            table.insert(previewBuffIds, id);
        elseif kind == 1 then
            table.insert(previewDebuffIds, id);
        end
    end
end

-- Cache a random set per member index so it doesn't change every frame
local previewStatusByMember = {};

local function GetRandomPreviewStatusIds()
    -- Fallback if something goes wrong building the pools
    if (#previewBuffIds == 0 or #previewDebuffIds == 0) then
        -- Protect, Haste, Poison, Paralyze (example)
        return { 40, 33, 3, 4 };
    end

    local total = math.random(2, 5); -- 2–5 statuses
    local ids   = {};
    local used  = {};

    local function addUnique(id)
        if not used[id] then
            table.insert(ids, id);
            used[id] = true;
        end
    end

    -- At least one buff and one debuff
    addUnique(previewBuffIds[math.random(1, #previewBuffIds)]);
    addUnique(previewDebuffIds[math.random(1, #previewDebuffIds)]);

    -- Fill the rest with random buffs/debuffs
    while #ids < total do
        local list;
        if (math.random() < 0.5) then
            list = previewBuffIds;
        else
            list = previewDebuffIds;
        end

        addUnique(list[math.random(1, #list)]);
    end

    return ids;
end

-- Convert a simple Lua array (1..N) into a 0-based T{} like the real buff array
local function BuildPreviewBuffArray(ids)
    local arr = T{};
    for i, id in ipairs(ids) do
        arr[i - 1] = id; -- 0-based indexing
    end
    return arr;
end

local function GetPreviewBuffsForMember(memIdx)
    if (previewStatusByMember[memIdx] == nil) then
        local ids = GetRandomPreviewStatusIds();
        previewStatusByMember[memIdx] = BuildPreviewBuffArray(ids);
    end
    return previewStatusByMember[memIdx];
end

local function isStatusBlacklisted(statusId)
    -- If the module is missing or doesn’t define IsBlacklisted, fail safe.
    if statusBlacklist == nil or statusBlacklist.IsBlacklisted == nil then
        return false;
    end
    return statusBlacklist.IsBlacklisted(statusId);
end

local function getScale(partyIndex)
    if (partyIndex == 3) then
        return {
            x    = gConfig.partyList3ScaleX,
            y    = gConfig.partyList3ScaleY,
            icon = gConfig.partyList3JobIconScale,
        };
    elseif (partyIndex == 2) then
        return {
            x    = gConfig.partyList2ScaleX,
            y    = gConfig.partyList2ScaleY,
            icon = gConfig.partyList2JobIconScale,
        };
    else
        return {
            x    = gConfig.partyListScaleX,
            y    = gConfig.partyListScaleY,
            icon = gConfig.partyListJobIconScale,
        };
    end
end

local function showPartyTP(partyIndex)
    if (partyIndex == 3) then
        return gConfig.partyList3TP;
    elseif (partyIndex == 2) then
        return gConfig.partyList2TP;
    else
        return gConfig.partyListTP;
    end
end

local function UpdateTextVisibilityByMember(memIdx, visible)
    memberText[memIdx].hp:SetVisible(visible);
    memberText[memIdx].mp:SetVisible(visible);
    memberText[memIdx].tp:SetVisible(visible);
    memberText[memIdx].name:SetVisible(visible);
end

local function UpdateTextVisibility(visible, partyIndex)
    if partyIndex == nil then
        for i = 0, memberTextCount - 1 do
            UpdateTextVisibilityByMember(i, visible);
        end
    else
        local firstPlayerIndex = (partyIndex - 1) * partyMaxSize;
        local lastPlayerIndex  = firstPlayerIndex + partyMaxSize - 1;
        for i = firstPlayerIndex, lastPlayerIndex do
            UpdateTextVisibilityByMember(i, visible);
        end
    end

    for i = 1, 3 do
        if (partyIndex == nil or i == partyIndex) then
            partyWindowPrim[i].bgTitle.visible = visible and gConfig.showPartyListTitle;
            local backgroundPrim = partyWindowPrim[i].background;
            for _, k in ipairs(bgImageKeys) do
                backgroundPrim[k].visible = visible and backgroundPrim[k].exists;
            end
        end
    end
end

local function GetMemberInformation(memIdx)
    if (showConfig[1] and gConfig.partyListPreview) then
        local memInfo     = {};
        memInfo.hpp       = memIdx == 4 and 0.1 or memIdx == 2 and 0.5 or memIdx == 0 and 0.75 or 1;
        memInfo.maxhp     = 1250;
        memInfo.hp        = math.floor(memInfo.maxhp * memInfo.hpp);
        memInfo.mpp       = memIdx == 1 and 0.1 or 0.75;
        memInfo.maxmp     = 1000;
        memInfo.mp        = math.floor(memInfo.maxmp * memInfo.mpp);
        memInfo.tp        = 1500;
        memInfo.job       = memIdx + 1;
        memInfo.level     = 99;
        memInfo.targeted  = memIdx == 4;
        memInfo.serverid  = 0;
        memInfo.isPreview = true;
        memInfo.buffs     = GetPreviewBuffsForMember(memIdx);
        memInfo.sync      = false;
        memInfo.subTargeted = false;
        memInfo.zone        = 100;
        memInfo.inzone      = memIdx % 4 ~= 0;
        memInfo.name        = 'Player ' .. (memIdx + 1);
        memInfo.leader      = memIdx == 0 or memIdx == 6 or memIdx == 12;
        return memInfo;
    end

    local party  = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (player == nil or party == nil or party:GetMemberIsActive(memIdx) == 0) then
        return nil;
    end

    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();

    local partyIndex   = math.ceil((memIdx + 1) / partyMaxSize);
    local partyLeaderId;
    if (partyIndex == 3) then
        partyLeaderId = party:GetAlliancePartyLeaderServerId3();
    elseif (partyIndex == 2) then
        partyLeaderId = party:GetAlliancePartyLeaderServerId2();
    else
        partyLeaderId = party:GetAlliancePartyLeaderServerId1();
    end

    local memberInfo     = {};
    memberInfo.zone      = party:GetMemberZone(memIdx);
    memberInfo.inzone    = memberInfo.zone == party:GetMemberZone(0);
    memberInfo.name      = party:GetMemberName(memIdx);
    memberInfo.leader    = partyLeaderId == party:GetMemberServerId(memIdx);

    if (memberInfo.inzone == true) then
        memberInfo.hp    = party:GetMemberHP(memIdx);
        memberInfo.hpp   = party:GetMemberHPPercent(memIdx) / 100;
        memberInfo.maxhp = memberInfo.hp / memberInfo.hpp;
        memberInfo.mp    = party:GetMemberMP(memIdx);
        memberInfo.mpp   = party:GetMemberMPPercent(memIdx) / 100;
        memberInfo.maxmp = memberInfo.mp / memberInfo.mpp;
        memberInfo.tp    = party:GetMemberTP(memIdx);
        memberInfo.job   = party:GetMemberMainJob(memIdx);
        memberInfo.level = party:GetMemberMainJobLevel(memIdx);
        memberInfo.serverid = party:GetMemberServerId(memIdx);
        memberInfo.index    = party:GetMemberTargetIndex(memIdx);

        if (playerTarget ~= nil) then
            local t1, t2  = GetTargets();
            local sActive = GetSubTargetActive();
            local thisIdx = party:GetMemberTargetIndex(memIdx);
            memberInfo.targeted     = (t1 == thisIdx and not sActive) or (t2 == thisIdx and sActive);
            memberInfo.subTargeted  = (t1 == thisIdx and sActive);
        else
            memberInfo.targeted    = false;
            memberInfo.subTargeted = false;
        end

        if (memIdx == 0) then
            memberInfo.buffs = player:GetBuffs();
        else
            memberInfo.buffs = statusHandler.get_member_status(memberInfo.serverid);
        end

        memberInfo.sync = bit.band(party:GetMemberFlagMask(memIdx), 0x100) == 0x100;
    else
        memberInfo.hp          = 0;
        memberInfo.hpp         = 0;
        memberInfo.maxhp       = 0;
        memberInfo.mp          = 0;
        memberInfo.mpp         = 0;
        memberInfo.maxmp       = 0;
        memberInfo.tp          = 0;
        memberInfo.job         = '';
        memberInfo.level       = '';
        memberInfo.targeted    = false;
        memberInfo.serverid    = 0;
        memberInfo.buffs       = nil;
        memberInfo.sync        = false;
        memberInfo.subTargeted = false;
        memberInfo.index       = nil;
    end

    return memberInfo;
end

local function DrawMember(memIdx, settings)
    local memInfo = GetMemberInformation(memIdx);
    if (memInfo == nil) then
        -- Dummy data to render an empty space
        memInfo             = {};
        memInfo.hp          = 0;
        memInfo.hpp         = 0;
        memInfo.maxhp       = 0;
        memInfo.mp          = 0;
        memInfo.mpp         = 0;
        memInfo.maxmp       = 0;
        memInfo.tp          = 0;
        memInfo.job         = '';
        memInfo.level       = '';
        memInfo.targeted    = false;
        memInfo.serverid    = 0;
        memInfo.buffs       = nil;
        memInfo.sync        = false;
        memInfo.subTargeted = false;
        memInfo.zone        = '';
        memInfo.inzone      = false;
        memInfo.name        = '';
        memInfo.leader      = false;
    end

    local partyIndex = math.ceil((memIdx + 1) / partyMaxSize);
    local scale      = getScale(partyIndex);
    local showTP     = showPartyTP(partyIndex);

    local subTargetActive = GetSubTargetActive();
    local nameSize        = SIZE.new();
    local hpSize          = SIZE.new();
    memberText[memIdx].name:GetTextSize(nameSize);
    memberText[memIdx].hp:GetTextSize(hpSize);

    -- Get the hp color for bars and text
    local hpNameColor, hpGradient = GetHpColors(memInfo.hpp);

    local bgGradientOverride = { '#000813', '#000813' };

    local hpBarWidth = settings.hpBarWidth * scale.x;
    local mpBarWidth = settings.mpBarWidth * scale.x;
    local tpBarWidth = settings.tpBarWidth * scale.x;
    local barHeight  = settings.barHeight * scale.y;

    local allBarsLengths = hpBarWidth + mpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    if (showTP) then
        allBarsLengths = allBarsLengths + tpBarWidth + imgui.GetStyle().FramePadding.x + imgui.GetStyle().ItemSpacing.x;
    end

    local hpStartX, hpStartY = imgui.GetCursorScreenPos();

    -- Draw the job icon before we draw anything else
    local namePosX     = hpStartX;
    local jobIconSize  = settings.iconSize * 1.1 * scale.icon;
    local offsetStartY = hpStartY - jobIconSize - settings.nameTextOffsetY;
    imgui.SetCursorScreenPos({ namePosX, offsetStartY });
    local jobIcon = statusHandler.GetJobIcon(memInfo.job);
    if (jobIcon ~= nil) then
        namePosX = namePosX + jobIconSize + settings.nameTextOffsetX;
        imgui.Image(jobIcon, { jobIconSize, jobIconSize });
    end
    imgui.SetCursorScreenPos({ hpStartX, hpStartY });

    -- Update the hp text
    memberText[memIdx].hp:SetColor(hpNameColor);
    memberText[memIdx].hp:SetPositionX(hpStartX + hpBarWidth + settings.hpTextOffsetX);
    memberText[memIdx].hp:SetPositionY(hpStartY + barHeight + settings.hpTextOffsetY);
    memberText[memIdx].hp:SetText(tostring(memInfo.hp));

    -- Draw the HP bar
    if (memInfo.inzone) then
        progressbar.ProgressBar(
            { { memInfo.hpp, hpGradient } },
            { hpBarWidth, barHeight },
            {
                borderConfig                = borderConfig,
                backgroundGradientOverride  = bgGradientOverride,
                decorate                    = gConfig.showPartyListBookends,
            }
        );
    elseif (memInfo.zone == '' or memInfo.zone == nil) then
        imgui.Dummy({ allBarsLengths, barHeight });
    else
        imgui.ProgressBar(
            0,
            { allBarsLengths, barHeight },
            encoding:ShiftJIS_To_UTF8(AshitaCore:GetResourceManager():GetString('zones.names', memInfo.zone), true)
        );
    end

    -- Draw the leader icon
    if (memInfo.leader) then
        draw_circle({ hpStartX + settings.dotRadius / 2, hpStartY + settings.dotRadius / 2 }, settings.dotRadius, { 1, 1, .5, 1 }, settings.dotRadius * 3, true);
    end

    -- Update the name text (with SP overlay + pulse)
    local distanceText      = '';
    local highlightDistance = false;

    if (gConfig.showPartyListDistance) then
        if (memInfo.inzone and memInfo.index) then
            local entity   = AshitaCore:GetMemoryManager():GetEntity();
            local distance = math.sqrt(entity:GetDistance(memInfo.index));
            if (distance > 0 and distance <= 50) then
                local percentText = ('%.1f'):fmt(distance);
                distanceText      = ' - ' .. percentText;

                if (gConfig.partyListDistanceHighlight > 0 and distance <= gConfig.partyListDistanceHighlight) then
                    highlightDistance = true;
                end
            end
        end
    end

    -- Base name color (white or cyan if within highlight range)
    local baseNameColor;
    if (highlightDistance) then
        baseNameColor = 0xFF00FFFF;
    else
        baseNameColor = 0xFFFFFFFF;
    end

    -- Start with normal name + distance
    local displayName = tostring(memInfo.name) .. distanceText;
    local nameColor   = baseNameColor;

    ----------------------------------------------------------------
    -- Bars-style SP overlay and pulse for party members
    -- (with preview support on Player 4 when the config option is enabled)
    ----------------------------------------------------------------

    -- memIdx is 0-based; memIdx == 3 is "Player 4" in the list.
    local isPreviewSP = (memInfo.isPreview == true and memIdx == 3);

    if (gConfig.partyListShowSPName and (isPreviewSP or (memInfo.serverid ~= nil and memInfo.serverid ~= 0))) then
        local spName;
        local spRemaining;

        if isPreviewSP then
            -- Preview-mode fake SP:
            --   Player 4 always shows an active SP timer while in preview.
            spName = 'Chainspell';

            -- Make a looping countdown for show:
            --  e.g. 0–89 seconds, repeating.
            local cycle = 90; -- seconds
            local now   = os.time();
            spRemaining = (cycle - (now % cycle));
        else
            -- Normal in-game behavior:
            spName, spRemaining = actionTracker.GetSpecialForServerId(memInfo.serverid);
        end

        local spActive = (spName ~= nil and spRemaining ~= nil and spRemaining > 0);

        if spActive then
            -- Format remaining time as M:SS
            local seconds = math.floor(spRemaining + 0.5);
            local minutes = math.floor(seconds / 60);
            local secPart = seconds % 60;
            local spTimer = string.format('%d:%02d', minutes, secPart);

            -- Alternate like Bars / your targetbar:
            --   "0:59 Chainspell"
            --   "0:58 Playername - 23.4"
            if (seconds % 2 == 0) then
                displayName = string.format('%s %s', spTimer, spName);
            else
                displayName = string.format('%s %s', spTimer, displayName);
            end

            -- Pulse alpha just for this member slot
            local minAlpha = 80;  -- faintest
            local maxAlpha = 255; -- strongest
            local speed    = 3;   -- pulse speed per frame

            local a  = spPulseAlpha[memIdx] or maxAlpha;
            local up = (spPulseDirectionUp[memIdx] ~= false);

            if up then
                a = a + speed;
                if a >= maxAlpha then
                    a  = maxAlpha;
                    up = false;
                end
            else
                a = a - speed;
                if a <= minAlpha then
                    a  = minAlpha;
                    up = true;
                end
            end

            spPulseAlpha[memIdx]       = a;
            spPulseDirectionUp[memIdx] = up;

            -- Replace only the alpha channel of baseNameColor
            local rgb = bit.band(baseNameColor, 0x00FFFFFF);
            nameColor = bit.bor(bit.lshift(a, 24), rgb);
        else
            -- No SP active – reset pulse, use base color
            spPulseAlpha[memIdx]       = 255;
            spPulseDirectionUp[memIdx] = true;
            nameColor                  = baseNameColor;
        end
    else
        nameColor = baseNameColor;
    end

    memberText[memIdx].name:SetColor(nameColor);
    memberText[memIdx].name:SetPositionX(namePosX);
    memberText[memIdx].name:SetPositionY(hpStartY - nameSize.cy - settings.nameTextOffsetY);
    memberText[memIdx].name:SetText(displayName);

    memberText[memIdx].name:GetTextSize(nameSize);
    local offsetSize = nameSize.cy > settings.iconSize and nameSize.cy or settings.iconSize;

    if (memInfo.inzone) then
        imgui.SameLine();

        ----------------------------------------------------------------
        -- MP bar
        ----------------------------------------------------------------
        local mpStartX, mpStartY;
        imgui.SetCursorPosX(imgui.GetCursorPosX());
        mpStartX, mpStartY = imgui.GetCursorScreenPos();

        progressbar.ProgressBar(
            { { memInfo.mpp, { '#9abb5a', '#bfe07d' } } },
            { mpBarWidth, barHeight },
            {
                borderConfig               = borderConfig,
                backgroundGradientOverride = bgGradientOverride,
                decorate                   = gConfig.showPartyListBookends,
            }
        );

        memberText[memIdx].mp:SetColor(gAdjustedSettings.mpColor);
        memberText[memIdx].mp:SetPositionX(mpStartX + mpBarWidth + settings.mpTextOffsetX);
        memberText[memIdx].mp:SetPositionY(mpStartY + barHeight + settings.mpTextOffsetY);
        memberText[memIdx].mp:SetText(tostring(memInfo.mp));

        ----------------------------------------------------------------
        -- TP bar
        ----------------------------------------------------------------
        if (showTP) then
            imgui.SameLine();
            local tpStartX, tpStartY;
            imgui.SetCursorPosX(imgui.GetCursorPosX());
            tpStartX, tpStartY = imgui.GetCursorScreenPos();

            local tpGradient        = { '#3898ce', '#78c4ee' };
            local tpOverlayGradient = { '#0078CC', '#0078CC' };
            local mainPercent;
            local tpOverlay;

            if (memInfo.tp >= 1000) then
                mainPercent = (memInfo.tp - 1000) / 2000;
                if (gConfig.partyListFlashTP) then
                    tpOverlay = { { 1, tpOverlayGradient }, math.ceil(barHeight * 5 / 7), 0, { '#3ECE00', 1 } };
                else
                    tpOverlay = { { 1, tpOverlayGradient }, math.ceil(barHeight * 2 / 7), 1 };
                end
            else
                mainPercent = memInfo.tp / 1000;
            end

            progressbar.ProgressBar(
                { { mainPercent, tpGradient } },
                { tpBarWidth, barHeight },
                {
                    overlayBar                = tpOverlay,
                    borderConfig              = borderConfig,
                    backgroundGradientOverride = bgGradientOverride,
                    decorate                  = gConfig.showPartyListBookends,
                }
            );

            if (memInfo.tp >= 1000) then
                memberText[memIdx].tp:SetColor(gAdjustedSettings.tpFullColor);
            else
                memberText[memIdx].tp:SetColor(gAdjustedSettings.tpEmptyColor);
            end
            memberText[memIdx].tp:SetPositionX(tpStartX + tpBarWidth + settings.tpTextOffsetX);
            memberText[memIdx].tp:SetPositionY(tpStartY + barHeight + settings.tpTextOffsetY);
            memberText[memIdx].tp:SetText(tostring(memInfo.tp));
        end

        ----------------------------------------------------------------
        -- Target / subtarget selection graphics
        ----------------------------------------------------------------
        local entrySize = hpSize.cy + offsetSize + settings.hpTextOffsetY + barHeight + settings.cursorPaddingY1 + settings.cursorPaddingY2;
        if (memInfo.targeted == true) then
            selectionPrim.visible   = true;
            selectionPrim.position_x = hpStartX - settings.cursorPaddingX1;
            selectionPrim.position_y = hpStartY - offsetSize - settings.cursorPaddingY1;
            selectionPrim.scale_x    = (allBarsLengths + settings.cursorPaddingX1 + settings.cursorPaddingX2) / 346;
            selectionPrim.scale_y    = entrySize / 108;
            partyTargeted            = true;
        end

        if ((memInfo.targeted == true and not subTargetActive) or memInfo.subTargeted) then
            arrowPrim.visible = true;
            local newArrowX   = memberText[memIdx].name:GetPositionX() - arrowPrim:GetWidth();
            if (jobIcon ~= nil) then
                newArrowX = newArrowX - jobIconSize;
            end
            arrowPrim.position_x = newArrowX;
            arrowPrim.position_y = (hpStartY - offsetSize - settings.cursorPaddingY1) + (entrySize / 2) - arrowPrim:GetHeight() / 2;
            arrowPrim.scale_x    = settings.arrowSize;
            arrowPrim.scale_y    = settings.arrowSize;
            if (subTargetActive) then
                arrowPrim.color = settings.subtargetArrowTint;
            else
                arrowPrim.color = 0xFFFFFFFF;
            end
            partySubTargeted = true;
        end

        ----------------------------------------------------------------
        -- Party list buff / debuff themes
        ----------------------------------------------------------------
        if (partyIndex == 1 and memInfo.buffs ~= nil and #memInfo.buffs > 0) then
            local theme = gConfig.partyListStatusTheme;

            -- HorizonXI-L / HorizonXI-R / FFXI / FFXI-R
            if (theme == 0 or theme == 1 or theme == 3 or theme == 5) then
                -- Split into buffs (top row) and debuffs (bottom row), skipping blacklisted IDs
                -- (but NOT in preview mode)
                local buffs           = {};
                local debuffs         = {};
                local ignoreBlacklist = (memInfo.isPreview == true);

                for i = 0, #memInfo.buffs do
                    local id = memInfo.buffs[i];

                    -- Skip invalid / sentinel values and (for non-preview) anything on the blacklist
                    if (id ~= nil and id ~= -1 and (ignoreBlacklist or not isStatusBlacklisted(id))) then
                        if (buffTable.IsBuff(id)) then
                            table.insert(buffs, id);
                        else
                            table.insert(debuffs, id);
                        end
                    end
                end

                -- HorizonXI themes draw buff/debuff backgrounds; FFXI themes do not
                local drawBg = (theme == 0 or theme == 1);

                ----------------------------------------------------------------
                -- BUFF ROW (top)
                ----------------------------------------------------------------
                if (buffs ~= nil and #buffs > 0) then
                    -- Left-side: 0 = HorizonXI-L, 3 = FFXI
                    if ((theme == 0 or theme == 3) and buffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({
                            hpStartX - buffWindowX[memIdx] - settings.buffOffset,
                            hpStartY - settings.iconSize * 1.2,
                        });

                    -- Right-side: 1 = HorizonXI-R, 5 = FFXI-R
                    elseif ((theme == 1 or theme == 5) and fullMenuWidth[partyIndex] ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({
                            thisPosX + fullMenuWidth[partyIndex],
                            hpStartY - settings.iconSize * 1.2,
                        });
                    end

                    if (imgui.Begin(
                        'PlayerBuffs' .. memIdx,
                        true,
                        bit.bor(
                            ImGuiWindowFlags_NoDecoration,
                            ImGuiWindowFlags_AlwaysAutoResize,
                            ImGuiWindowFlags_NoFocusOnAppearing,
                            ImGuiWindowFlags_NoNav,
                            ImGuiWindowFlags_NoBackground,
                            ImGuiWindowFlags_NoSavedSettings
                        )
                    )) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 3, 1 });
                        -- Same layout for all of these themes: one long row
                        DrawStatusIcons(buffs, settings.iconSize, 32, 1, drawBg);
                        imgui.PopStyleVar(1);
                    end

                    local buffWindowSizeX, _ = imgui.GetWindowSize();
                    buffWindowX[memIdx]      = buffWindowSizeX;
                    imgui.End();
                end

                ----------------------------------------------------------------
                -- DEBUFF ROW (bottom)
                ----------------------------------------------------------------
                if (debuffs ~= nil and #debuffs > 0) then
                    -- Left-side: 0 = HorizonXI-L, 3 = FFXI
                    if ((theme == 0 or theme == 3) and debuffWindowX[memIdx] ~= nil) then
                        imgui.SetNextWindowPos({
                            hpStartX - debuffWindowX[memIdx] - settings.buffOffset,
                            hpStartY,
                        });

                    -- Right-side: 1 = HorizonXI-R, 5 = FFXI-R
                    elseif ((theme == 1 or theme == 5) and fullMenuWidth[partyIndex] ~= nil) then
                        local thisPosX, _ = imgui.GetWindowPos();
                        imgui.SetNextWindowPos({
                            thisPosX + fullMenuWidth[partyIndex],
                            hpStartY,
                        });
                    end

                    if (imgui.Begin(
                        'PlayerDebuffs' .. memIdx,
                        true,
                        bit.bor(
                            ImGuiWindowFlags_NoDecoration,
                            ImGuiWindowFlags_AlwaysAutoResize,
                            ImGuiWindowFlags_NoFocusOnAppearing,
                            ImGuiWindowFlags_NoNav,
                            ImGuiWindowFlags_NoBackground,
                            ImGuiWindowFlags_NoSavedSettings
                        )
                    )) then
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 3, 1 });
                        DrawStatusIcons(debuffs, settings.iconSize, 32, 1, drawBg);
                        imgui.PopStyleVar(1);
                    end

                    local debuffWindowSizeX, _ = imgui.GetWindowSize();
                    debuffWindowX[memIdx]      = debuffWindowSizeX;
                    imgui.End();
                end

            -- FFXIV-style status row
            elseif (theme == 2) then
                local resetX, resetY = imgui.GetCursorScreenPos();
                imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
                imgui.SetNextWindowPos({ mpStartX, mpStartY - settings.iconSize - settings.xivBuffOffsetY });

                if (imgui.Begin(
                    'XIVStatus' .. memIdx,
                    true,
                    bit.bor(
                        ImGuiWindowFlags_NoDecoration,
                        ImGuiWindowFlags_AlwaysAutoResize,
                        ImGuiWindowFlags_NoFocusOnAppearing,
                        ImGuiWindowFlags_NoNav,
                        ImGuiWindowFlags_NoBackground,
                        ImGuiWindowFlags_NoSavedSettings
                    )
                )) then
                    -- Build filtered lists that respect the blacklist (except in preview)
                    local buffs            = {};
                    local debuffs          = {};
                    local ignoreBlacklist  = (memInfo.isPreview == true);

                    if (memInfo.buffs ~= nil) then
                        for i = 0, #memInfo.buffs do
                            local id = memInfo.buffs[i];
                            if (id ~= nil and id ~= -1 and (ignoreBlacklist or not isStatusBlacklisted(id))) then
                                if (buffTable.IsBuff(id)) then
                                    table.insert(buffs, id);
                                else
                                    table.insert(debuffs, id);
                                end
                            end
                        end
                    end

                    -- Debuffs first, then buffs (single FFXIV-style row)
                    local ordered = {};
                    for _, id in ipairs(debuffs) do
                        table.insert(ordered, id);
                    end
                    for _, id in ipairs(buffs) do
                        table.insert(ordered, id);
                    end

                    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 });
                    DrawStatusIcons(ordered, settings.iconSize, 32, 1);
                    imgui.PopStyleVar(1);
                end

                imgui.PopStyleVar(1);
                imgui.End();
                imgui.SetCursorScreenPos({ resetX, resetY });
            end
        end
    end

    if (memInfo.sync) then
        draw_circle({ hpStartX + settings.dotRadius / 2, hpStartY + barHeight }, settings.dotRadius, { .5, .5, 1, 1 }, settings.dotRadius * 3, true);
    end

    memberText[memIdx].hp:SetVisible(memInfo.inzone);
    memberText[memIdx].mp:SetVisible(memInfo.inzone);
    memberText[memIdx].tp:SetVisible(memInfo.inzone and showTP);

    imgui.Dummy({ 0, settings.entrySpacing[partyIndex] + hpSize.cy + settings.hpTextOffsetY + settings.nameTextOffsetY });

    local lastPlayerIndex = (partyIndex * 6) - 1;
    if (memIdx + 1 <= lastPlayerIndex) then
        imgui.Dummy({ 0, offsetSize });
    end
end

partyList.DrawWindow = function(settings)
    local party  = AshitaCore:GetMemoryManager():GetParty();
    local player = AshitaCore:GetMemoryManager():GetPlayer();

    if (party == nil or player == nil or player.isZoning or player:GetMainJob() == 0) then
        UpdateTextVisibility(false);
        return;
    end

    partyTargeted   = false;
    partySubTargeted = false;

    -- Main party window
    partyList.DrawPartyWindow(settings, party, 1);

    -- Alliance party windows
    if (gConfig.partyListAlliance) then
        partyList.DrawPartyWindow(settings, party, 2);
        partyList.DrawPartyWindow(settings, party, 3);
    else
        UpdateTextVisibility(false, 2);
        UpdateTextVisibility(false, 3);
    end

    selectionPrim.visible = partyTargeted;
    arrowPrim.visible     = partySubTargeted;
end

partyList.DrawPartyWindow = function(settings, party, partyIndex)
    local firstPlayerIndex = (partyIndex - 1) * partyMaxSize;
    local lastPlayerIndex  = firstPlayerIndex + partyMaxSize - 1;

    -- Get the party size by checking active members
    local partyMemberCount = 0;
    if (showConfig[1] and gConfig.partyListPreview) then
        partyMemberCount = partyMaxSize;
    else
        for i = firstPlayerIndex, lastPlayerIndex do
            if (party:GetMemberIsActive(i) ~= 0) then
                partyMemberCount = partyMemberCount + 1;
            else
                break;
            end
        end
    end

    if (partyIndex == 1 and not gConfig.showPartyListWhenSolo and partyMemberCount <= 1) then
        UpdateTextVisibility(false);
        return;
    end

    if (partyIndex > 1 and partyMemberCount == 0) then
        UpdateTextVisibility(false, partyIndex);
        return;
    end

    local bgTitlePrim    = partyWindowPrim[partyIndex].bgTitle;
    local backgroundPrim = partyWindowPrim[partyIndex].background;

    -- Graphic has multiple titles
    -- 0 = Solo
    -- bgTitleItemHeight = Party
    -- bgTitleItemHeight*2 = Party B
    -- bgTitleItemHeight*3 = Party C
    if (partyIndex == 1) then
        bgTitlePrim.texture_offset_y = partyMemberCount == 1 and 0 or bgTitleItemHeight;
    else
        bgTitlePrim.texture_offset_y = bgTitleItemHeight * partyIndex;
    end

    local imguiPosX, imguiPosY;

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav,
        ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoBringToFrontOnFocus
    );
    if (gConfig.lockPositions) then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
    end

    local windowName = 'PartyList';
    if (partyIndex > 1) then
        windowName = windowName .. partyIndex;
    end

    local scale    = getScale(partyIndex);
    local iconSize = 0; -- No extra vertical padding from icon here; member rows handle icons.

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { settings.barSpacing * scale.x, 0 });
    if (imgui.Begin(windowName, true, windowFlags)) then
        imguiPosX, imguiPosY = imgui.GetWindowPos();

        local nameSize = SIZE.new();
        memberText[(partyIndex - 1) * 6].name:GetTextSize(nameSize);
        local offsetSize = nameSize.cy > iconSize and nameSize.cy or iconSize;
        imgui.Dummy({ 0, settings.nameTextOffsetY + offsetSize });

        UpdateTextVisibility(true, partyIndex);

        for i = firstPlayerIndex, lastPlayerIndex do
            local relIndex = i - firstPlayerIndex;
            if ((partyIndex == 1 and settings.expandHeight) or relIndex < partyMemberCount or relIndex < settings.minRows) then
                DrawMember(i, settings);
            else
                UpdateTextVisibilityByMember(i, false);
            end
        end
    end

    local menuWidth, menuHeight = imgui.GetWindowSize();

    fullMenuWidth[partyIndex]  = menuWidth;
    fullMenuHeight[partyIndex] = menuHeight;

    local bgWidth  = fullMenuWidth[partyIndex] + (settings.bgPadding * 2);
    local bgHeight = fullMenuHeight[partyIndex];
    if (partyIndex > 1) then
        bgHeight = bgHeight + (settings.bgPadding * 2);
    end

    backgroundPrim.bg.visible     = backgroundPrim.bg.exists;
    backgroundPrim.bg.position_x  = imguiPosX - settings.bgPadding;
    backgroundPrim.bg.position_y  = imguiPosY - settings.bgPadding;
    backgroundPrim.bg.width       = math.ceil(bgWidth / gConfig.partyListBgScale);
    backgroundPrim.bg.height      = math.ceil(bgHeight / gConfig.partyListBgScale);

    backgroundPrim.br.visible     = backgroundPrim.br.exists;
    backgroundPrim.br.position_x  = backgroundPrim.bg.position_x + bgWidth - math.floor((settings.borderSize * gConfig.partyListBgScale) - (settings.bgOffset * gConfig.partyListBgScale));
    backgroundPrim.br.position_y  = backgroundPrim.bg.position_y + bgHeight - math.floor((settings.borderSize * gConfig.partyListBgScale) - (settings.bgOffset * gConfig.partyListBgScale));
    backgroundPrim.br.width       = settings.borderSize;
    backgroundPrim.br.height      = settings.borderSize;

    backgroundPrim.tr.visible     = backgroundPrim.tr.exists;
    backgroundPrim.tr.position_x  = backgroundPrim.br.position_x;
    backgroundPrim.tr.position_y  = backgroundPrim.bg.position_y - settings.bgOffset * gConfig.partyListBgScale;
    backgroundPrim.tr.width       = backgroundPrim.br.width;
    backgroundPrim.tr.height      = math.ceil((backgroundPrim.br.position_y - backgroundPrim.tr.position_y) / gConfig.partyListBgScale);

    backgroundPrim.tl.visible     = backgroundPrim.tl.exists;
    backgroundPrim.tl.position_x  = backgroundPrim.bg.position_x - settings.bgOffset * gConfig.partyListBgScale;
    backgroundPrim.tl.position_y  = backgroundPrim.tr.position_y;
    backgroundPrim.tl.width       = math.ceil((backgroundPrim.tr.position_x - backgroundPrim.tl.position_x) / gConfig.partyListBgScale);
    backgroundPrim.tl.height      = backgroundPrim.tr.height;

    backgroundPrim.bl.visible     = backgroundPrim.bl.exists;
    backgroundPrim.bl.position_x  = backgroundPrim.tl.position_x;
    backgroundPrim.bl.position_y  = backgroundPrim.br.position_y;
    backgroundPrim.bl.width       = backgroundPrim.tl.width;
    backgroundPrim.bl.height      = backgroundPrim.br.height;

    bgTitlePrim.visible           = gConfig.showPartyListTitle;
    bgTitlePrim.position_x        = imguiPosX + math.floor((bgWidth / 2) - (bgTitlePrim.width * bgTitlePrim.scale_x / 2));
    bgTitlePrim.position_y        = imguiPosY - math.floor((bgTitlePrim.height * bgTitlePrim.scale_y / 2) + (2 / bgTitlePrim.scale_y));

    imgui.End();
    imgui.PopStyleVar(2);

    if (settings.alignBottom and imguiPosX ~= nil) then
        -- Migrate old settings
        if (partyIndex == 1 and gConfig.partyListState ~= nil and gConfig.partyListState.x ~= nil) then
            local oldValues          = gConfig.partyListState;
            gConfig.partyListState   = {};
            gConfig.partyListState[partyIndex] = oldValues;
            ashita_settings.save();
        end

        if (gConfig.partyListState == nil) then
            gConfig.partyListState = {};
        end

        local partyListState = gConfig.partyListState[partyIndex];

        if (partyListState ~= nil) then
            -- Move window if size changed
            if (menuHeight ~= partyListState.height) then
                local newPosY = partyListState.y + partyListState.height - menuHeight;
                imguiPosY     = newPosY;
                imgui.SetWindowPos(windowName, { imguiPosX, imguiPosY });
            end
        end

        -- Update if the state changed
        if (partyListState == nil
            or imguiPosX ~= partyListState.x
            or imguiPosY ~= partyListState.y
            or menuWidth ~= partyListState.width
            or menuHeight ~= partyListState.height) then

            gConfig.partyListState[partyIndex] = {
                x      = imguiPosX,
                y      = imguiPosY,
                width  = menuWidth,
                height = menuHeight,
            };
            ashita_settings.save();
        end
    end
end

partyList.Initialize = function(settings)
    -- Initialize all our font objects we need
    local name_font_settings = deep_copy_table(settings.name_font_settings);
    local hp_font_settings   = deep_copy_table(settings.hp_font_settings);
    local mp_font_settings   = deep_copy_table(settings.mp_font_settings);
    local tp_font_settings   = deep_copy_table(settings.tp_font_settings);

    for i = 0, memberTextCount - 1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);

        local partyListFontOffset = gConfig.partyListFontOffset;
        if (partyIndex == 2) then
            partyListFontOffset = gConfig.partyList2FontOffset;
        elseif (partyIndex == 3) then
            partyListFontOffset = gConfig.partyList3FontOffset;
        end

        name_font_settings.font_height = math.max(settings.name_font_settings.font_height + partyListFontOffset, 1);
        hp_font_settings.font_height   = math.max(settings.hp_font_settings.font_height + partyListFontOffset, 1);
        mp_font_settings.font_height   = math.max(settings.mp_font_settings.font_height + partyListFontOffset, 1);
        tp_font_settings.font_height   = math.max(settings.tp_font_settings.font_height + partyListFontOffset, 1);

        memberText[i]      = {};
        memberText[i].name = fonts.new(name_font_settings);
        memberText[i].hp   = fonts.new(hp_font_settings);
        memberText[i].mp   = fonts.new(mp_font_settings);
        memberText[i].tp   = fonts.new(tp_font_settings);
    end

    -- Initialize images
    loadedBg = nil;

    for i = 1, 3 do
        local backgroundPrim = {};

        for _, k in ipairs(bgImageKeys) do
            backgroundPrim[k]           = primitives:new(settings.prim_data);
            backgroundPrim[k].visible   = false;
            backgroundPrim[k].can_focus = false;
            backgroundPrim[k].exists    = false;
        end

        partyWindowPrim[i].background = backgroundPrim;

        local bgTitlePrim  = primitives.new(settings.prim_data);
        bgTitlePrim.color  = 0xFFC5CFDC;
        bgTitlePrim.texture = string.format('%s/assets/PartyList-Titles.png', addon.path);
        bgTitlePrim.visible  = false;
        bgTitlePrim.can_focus = false;
        bgTitleItemHeight     = bgTitlePrim.height / bgTitleAtlasItemCount;
        bgTitlePrim.height    = bgTitleItemHeight;

        partyWindowPrim[i].bgTitle = bgTitlePrim;
    end

    selectionPrim            = primitives.new(settings.prim_data);
    selectionPrim.color      = 0xFFFFFFFF;
    selectionPrim.texture    = string.format('%s/assets/Selector.png', addon.path);
    selectionPrim.visible    = false;
    selectionPrim.can_focus  = false;

    arrowPrim            = primitives.new(settings.prim_data);
    arrowPrim.color      = 0xFFFFFFFF;
    arrowPrim.visible    = false;
    arrowPrim.can_focus  = false;

    partyList.UpdateFonts(settings);
end

partyList.UpdateFonts = function(settings)
    -- Update fonts
    for i = 0, memberTextCount - 1 do
        local partyIndex = math.ceil((i + 1) / partyMaxSize);

        local partyListFontOffset = gConfig.partyListFontOffset;
        if (partyIndex == 2) then
            partyListFontOffset = gConfig.partyList2FontOffset;
        elseif (partyIndex == 3) then
            partyListFontOffset = gConfig.partyList3FontOffset;
        end

        local name_font_settings_font_height = math.max(settings.name_font_settings.font_height + partyListFontOffset, 1);
        local hp_font_settings_font_height   = math.max(settings.hp_font_settings.font_height + partyListFontOffset, 1);
        local mp_font_settings_font_height   = math.max(settings.mp_font_settings.font_height + partyListFontOffset, 1);
        local tp_font_settings_font_height   = math.max(settings.tp_font_settings.font_height + partyListFontOffset, 1);

        memberText[i].name:SetFontHeight(name_font_settings_font_height);
        memberText[i].hp:SetFontHeight(hp_font_settings_font_height);
        memberText[i].mp:SetFontHeight(mp_font_settings_font_height);
        memberText[i].tp:SetFontHeight(tp_font_settings_font_height);
    end

    -- Update images
    local bgChanged = gConfig.partyListBackgroundName ~= loadedBg;
    loadedBg        = gConfig.partyListBackgroundName;

    local bgColor = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBgColor[4], gConfig.partyListBgColor[1], gConfig.partyListBgColor[2], gConfig.partyListBgColor[3]), 16);
    local borderColor = tonumber(string.format('%02x%02x%02x%02x', gConfig.partyListBorderColor[4], gConfig.partyListBorderColor[1], gConfig.partyListBorderColor[2], gConfig.partyListBorderColor[3]), 16);

    for i = 1, 3 do
        partyWindowPrim[i].bgTitle.scale_x = gConfig.partyListBgScale / 2.30;
        partyWindowPrim[i].bgTitle.scale_y = gConfig.partyListBgScale / 2.30;

        local backgroundPrim = partyWindowPrim[i].background;

        for _, k in ipairs(bgImageKeys) do
            local file_name = string.format('%s-%s.png', gConfig.partyListBackgroundName, k);
            backgroundPrim[k].color = (k == 'bg') and bgColor or borderColor;
            if (bgChanged) then
                -- Keep width/height to prevent flicker when switching to new texture
                local width, height = backgroundPrim[k].width, backgroundPrim[k].height;
                local filepath      = string.format('%s/assets/backgrounds/%s', addon.path, file_name);
                backgroundPrim[k].texture           = filepath;
                backgroundPrim[k].width, backgroundPrim[k].height = width, height;

                backgroundPrim[k].exists = ashita.fs.exists(filepath);
            end
            backgroundPrim[k].scale_x = gConfig.partyListBgScale;
            backgroundPrim[k].scale_y = gConfig.partyListBgScale;
        end
    end

    arrowPrim.texture = string.format('%s/assets/cursors/%s', addon.path, gConfig.partyListCursor);
end

partyList.SetHidden = function(hidden)
    if (hidden == true) then
        UpdateTextVisibility(false);
        selectionPrim.visible = false;
        arrowPrim.visible     = false;
    end
end

partyList.HandleZonePacket = function(e)
    statusHandler.clear_cache();
end

return partyList;
