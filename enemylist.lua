--[[
    Enemy List Module
    Displays a list of enemies currently engaged with the player's party.
]]

require('common');
require('helpers');
local imgui = require('imgui');
local debuffHandler = require('debuffhandler');
local progressbar = require('progressbar');
local ashita_settings = require('settings');
local actionTracker = require('actiontracker');

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local BG_RADIUS = 3;

---------------------------------------------------------------------------
-- Local State
---------------------------------------------------------------------------
local allClaimedTargets = {};
local debuffWindowX = {};

-- SP pulse state per enemy (keyed by entity index)
local spPulseAlpha = {};
local spPulseDirectionUp = {};

-- Preview pulse state for config menu
local previewPulseAlpha = 1.0;
local previewPulseDirectionUp = true;

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local enemylist = {};

---------------------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------------------

local function GetIsValidMob(mobIdx)
    local renderflags = AshitaCore:GetMemoryManager():GetEntity():GetRenderFlags0(mobIdx);
    if bit.band(renderflags, 0x200) ~= 0x200 or bit.band(renderflags, 0x4000) ~= 0 then
        return false;
    end
    return true;
end

local function GetPartyMemberIds()
    local partyMemberIds = T{};
    local party = AshitaCore:GetMemoryManager():GetParty();
    for i = 0, 17 do
        if (party:GetMemberIsActive(i) == 1) then
            table.insert(partyMemberIds, party:GetMemberServerId(i));
        end
    end
    return partyMemberIds;
end

-- Calculate pulsing alpha for SP abilities
local function CalculatePulseAlpha(currentAlpha, directionUp, minAlpha, maxAlpha, speed)
    local alpha = currentAlpha;
    local up = directionUp;

    if (up) then
        alpha = alpha + speed;
        if (alpha >= maxAlpha) then
            alpha = maxAlpha;
            up = false;
        end
    else
        alpha = alpha - speed;
        if (alpha <= minAlpha) then
            alpha = minAlpha;
            up = true;
        end
    end

    return alpha, up;
end

---------------------------------------------------------------------------
-- Main Draw Function
---------------------------------------------------------------------------

enemylist.DrawWindow = function(settings)
    imgui.SetNextWindowSize({ settings.barWidth, -1 }, ImGuiCond_Always);

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

    -- Count valid enemies
    local enemyCount = 0;
    for k, v in pairs(allClaimedTargets) do
        local ent = GetEntity(k);
        if (v ~= nil and ent ~= nil and GetIsValidMob(k) and ent.HPPercent > 0 and ent.Name ~= nil) then
            enemyCount = enemyCount + 1;
        end
    end

    -- Check visibility conditions (always show when config menu is open for preview)
    if (showConfig == nil or not showConfig[1]) then
        if (gConfig.hideEnemyListUnderTwo) then
            if (enemyCount < 2) then
                return;
            end
        else
            if (enemyCount == 0) then
                return;
            end
        end
    end

    local windowName = 'EnemyList';
    local imguiPosX, imguiPosY;
    local menuWidth, menuHeight;

    if (imgui.Begin(windowName, true, windowFlags)) then
        imgui.SetWindowFontScale(settings.textScale);
        imguiPosX, imguiPosY = imgui.GetWindowPos();
        local winStartX, winStartY = imguiPosX, imguiPosY;

        -- Get target information
        local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
        local targetIndex, subTargetIndex;
        local subTargetActive = false;

        if (playerTarget ~= nil) then
            subTargetActive = GetSubTargetActive();
            targetIndex, subTargetIndex = GetTargets();
            if (subTargetActive) then
                targetIndex, subTargetIndex = subTargetIndex, targetIndex;
            end
        end

        ----------------------------------------------------------------
        -- Real Enemy List
        ----------------------------------------------------------------
        local enemyIndices = T{};
        for k, v in pairs(allClaimedTargets) do
            local ent = GetEntity(k);
            if (v ~= nil and ent ~= nil and GetIsValidMob(k) and ent.HPPercent > 0 and ent.Name ~= nil) then
                table.insert(enemyIndices, k);
            else
                allClaimedTargets[k] = nil;
            end
        end

        table.sort(enemyIndices);
        local numTargets = #enemyIndices;

        if (numTargets > 0) then
            local anchorX, anchorY = imgui.GetCursorPos();

            -- Calculate row height
            local _, textHeight = imgui.CalcTextSize('Enemy 0');
            local yDist = (textHeight > settings.barHeight) and (textHeight * 2) or (textHeight + settings.barHeight);
            local rowHeight = settings.entrySpacing + yDist + settings.bgPadding + settings.bgTopPadding;

            if (rowHeight < settings.barHeight + settings.entrySpacing) then
                rowHeight = settings.barHeight + settings.entrySpacing;
            end

            local drawn = 0;

            -- Helper function to draw a single enemy row
            local function DrawEnemyRow(k, rowY)
                imgui.SetCursorPos({ anchorX, rowY });

                local ent = GetEntity(k);
                if (ent == nil or not GetIsValidMob(k) or ent.HPPercent <= 0 or ent.Name == nil) then
                    return false;
                end

                local targetNameText = ent.Name;
                local color = GetColorOfTargetRGBA(ent, k);

                -- Entry spacing
                imgui.Dummy({ 0, settings.entrySpacing });
                local rectLength = imgui.GetColumnWidth() + imgui.GetStyle().FramePadding.x;

                -- Background rect
                local winX, winY = imgui.GetCursorScreenPos();
                local cornerOffset = settings.bgTopPadding;
                local _, yDistRow = imgui.CalcTextSize(targetNameText);
                yDistRow = (yDistRow > settings.barHeight) and (yDistRow * 2) or (yDistRow + settings.barHeight);

                draw_rect(
                    { winX + cornerOffset, winY + cornerOffset },
                    { winX + rectLength, winY + yDistRow + settings.bgPadding },
                    { 0, 0, 0, gConfig.enemyListBgAlpha },
                    BG_RADIUS,
                    true
                );

                -- Target/subtarget selection outlines
                if (subTargetIndex ~= nil and k == subTargetIndex) then
                    draw_rect(
                        { winX + cornerOffset, winY + cornerOffset },
                        { winX + rectLength - 1, winY + yDistRow + settings.bgPadding },
                        { 0.5, 0.5, 1, 1 },
                        BG_RADIUS,
                        false
                    );
                elseif (targetIndex ~= nil and k == targetIndex) then
                    draw_rect(
                        { winX + cornerOffset, winY + cornerOffset },
                        { winX + rectLength - 1, winY + yDistRow + settings.bgPadding },
                        { 1, 1, 1, 1 },
                        BG_RADIUS,
                        false
                    );
                end

                -- SP pulse effect for name
                local nameColor = color;
                local spName, spRemaining = actionTracker.GetSpecialForTargetIndex(k);
                local spActive = (spName ~= nil and spRemaining ~= nil and spRemaining > 0) and gConfig.enemyListShowSPPulse;

                if (spActive) then
                    local alpha = spPulseAlpha[k] or 1.0;
                    local up = (spPulseDirectionUp[k] ~= false);
                    alpha, up = CalculatePulseAlpha(alpha, up, 0.3, 1.0, 0.03);
                    spPulseAlpha[k] = alpha;
                    spPulseDirectionUp[k] = up;
                    nameColor = { color[1], color[2], color[3], alpha };
                else
                    spPulseAlpha[k] = nil;
                    spPulseDirectionUp[k] = nil;
                end

                -- Name
                imgui.TextColored(nameColor, targetNameText);

                -- Distance / HP% text
                local percentText = '';
                local fauxX = 0;

                if (gConfig.showEnemyDistance and gConfig.showEnemyHPPText) then
                    percentText = ('D:%.1f %%:%.f'):fmt(math.sqrt(ent.Distance), ent.HPPercent);
                    fauxX, _ = imgui.CalcTextSize('D:1000 %:100');
                elseif (gConfig.showEnemyDistance) then
                    percentText = ('%.1f'):fmt(math.sqrt(ent.Distance));
                    fauxX, _ = imgui.CalcTextSize('1000');
                elseif (gConfig.showEnemyHPPText) then
                    percentText = ('%.f'):fmt(ent.HPPercent);
                    fauxX, _ = imgui.CalcTextSize('100');
                end

                local x, _ = imgui.CalcTextSize(percentText);

                -- Debuffs
                local buffIds = debuffHandler.GetActiveDebuffs(
                    AshitaCore:GetMemoryManager():GetEntity():GetServerId(k)
                );

                if (buffIds ~= nil and #buffIds > 0) then
                    local theme = gConfig.enemyListStatusTheme;

                    if (theme ~= 4) then
                        local posX, posY;
                        local isLeftTheme = (theme == 0 or theme == 2);

                        if (isLeftTheme and debuffWindowX[k] ~= nil) then
                            posX = winX - debuffWindowX[k] + settings.debuffOffsetX;
                            posY = winY + settings.debuffOffsetY;
                        else
                            posX = winStartX + settings.barWidth + settings.debuffOffsetX;
                            posY = winY + settings.debuffOffsetY;
                        end

                        imgui.SetNextWindowPos({ posX, posY });
                        if (imgui.Begin(
                            'EnemyDebuffs' .. k,
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
                            local drawBg = (theme == 0 or theme == 1);
                            imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 1, 1 });
                            DrawStatusIcons(buffIds, settings.debuffIconSize, settings.maxIcons, 1, drawBg);
                            imgui.PopStyleVar(1);
                        end

                        if (isLeftTheme) then
                            local debuffWindowSizeX, _ = imgui.GetWindowSize();
                            debuffWindowX[k] = debuffWindowSizeX;
                        end

                        imgui.End();
                    end
                end

                -- HP text and bar
                imgui.SetCursorPosX(imgui.GetCursorPosX() + fauxX - x);
                imgui.Text(percentText);
                imgui.SameLine();
                imgui.SetCursorPosX(imgui.GetCursorPosX() - 3);

                -- Build HP bar color from claim status (same as targetbar)
                local r = math.floor(color[1] * 255);
                local g = math.floor(color[2] * 255);
                local b = math.floor(color[3] * 255);
                local hpGradientColor = string.format('#%02X%02X%02X', r, g, b);

                progressbar.ProgressBar(
                    { { ent.HPPercent / 100, { hpGradientColor, hpGradientColor } } },
                    { -1, settings.barHeight },
                    { decorate = gConfig.showEnemyListBookends }
                );
                imgui.SameLine();
                imgui.Separator();

                return true;
            end

            -- Draw enemy rows
            local drawnIdx = 0;
            for _, k in ipairs(enemyIndices) do
                local rowY = anchorY + (rowHeight * drawnIdx);
                if DrawEnemyRow(k, rowY) then
                    drawn = drawn + 1;
                    drawnIdx = drawnIdx + 1;
                    if (drawn >= gConfig.maxEnemyListEntries) then
                        break;
                    end
                end
            end
        end

        ----------------------------------------------------------------
        -- Preview Enemy List (config menu open, no real enemies)
        ----------------------------------------------------------------
        if (numTargets == 0 and showConfig ~= nil and showConfig[1]) then
            local maxPreview = math.min(gConfig.maxEnemyListEntries or 5, 5);

            for i = 1, maxPreview do
                imgui.Dummy({ 0, settings.entrySpacing });
                local rectLength = imgui.GetColumnWidth() + imgui.GetStyle().FramePadding.x;

                local winX, winY = imgui.GetCursorScreenPos();
                local cornerOffset = settings.bgTopPadding;

                local previewName = string.format('Enemy %d', i);
                local _, yDist = imgui.CalcTextSize(previewName);
                yDist = (yDist > settings.barHeight) and (yDist * 2) or (yDist + settings.barHeight);

                -- Background
                draw_rect(
                    { winX + cornerOffset, winY + cornerOffset },
                    { winX + rectLength, winY + yDist + settings.bgPadding },
                    { 0, 0, 0, gConfig.enemyListBgAlpha },
                    BG_RADIUS,
                    true
                );

                -- Name with pulse effect on Enemy 3
                local previewNameColor = { 1, 1, 1, 1 };
                if (i == 3 and gConfig.enemyListShowSPPulse) then
                    previewPulseAlpha, previewPulseDirectionUp = CalculatePulseAlpha(
                        previewPulseAlpha, previewPulseDirectionUp, 0.3, 1.0, 0.03
                    );
                    previewNameColor = { 1, 1, 1, previewPulseAlpha };
                end

                imgui.TextColored(previewNameColor, previewName);

                -- Preview debuffs
                local theme = gConfig.enemyListStatusTheme;
                if (theme ~= 4) then
                    local previewBuffIds = { 2, 3, 5, 13, 23 };
                    local isLeftTheme = (theme == 0 or theme == 2);
                    local posX, posY;

                    if (isLeftTheme and debuffWindowX['preview' .. i] ~= nil) then
                        posX = winX - debuffWindowX['preview' .. i] + settings.debuffOffsetX;
                        posY = winY + settings.debuffOffsetY;
                    else
                        posX = winStartX + settings.barWidth + settings.debuffOffsetX;
                        posY = winY + settings.debuffOffsetY;
                    end

                    imgui.SetNextWindowPos({ posX, posY });
                    if (imgui.Begin(
                        'PreviewEnemyDebuffs' .. i,
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
                        local drawBg = (theme == 0 or theme == 1);
                        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 1, 1 });
                        DrawStatusIcons(previewBuffIds, settings.debuffIconSize, settings.maxIcons, 1, drawBg);
                        imgui.PopStyleVar(1);
                    end

                    if (isLeftTheme) then
                        local debuffWindowSizeX, _ = imgui.GetWindowSize();
                        debuffWindowX['preview' .. i] = debuffWindowSizeX;
                    end

                    imgui.End();
                end

                -- HP text and bar
                local percentText = '100';
                local fauxX, _ = imgui.CalcTextSize('100');
                local x, _ = imgui.CalcTextSize(percentText);

                imgui.SetCursorPosX(imgui.GetCursorPosX() + fauxX - x);
                imgui.Text(percentText);
                imgui.SameLine();
                imgui.SetCursorPosX(imgui.GetCursorPosX() - 3);

                -- Preview with different claim colors
                local previewBarColor;
                if (i == 1) then
                    previewBarColor = '#FF6666';  -- Party claimed (red)
                elseif (i == 2) then
                    previewBarColor = '#FF5C72';  -- Alliance claimed (pink)
                elseif (i == 3) then
                    previewBarColor = '#D36BD3';  -- Other claimed (purple)
                else
                    previewBarColor = '#F7ED8D';  -- Unclaimed (yellow)
                end

                progressbar.ProgressBar(
                    { { 1.0, { previewBarColor, previewBarColor } } },
                    { -1, settings.barHeight },
                    { decorate = gConfig.showEnemyListBookends }
                );
                imgui.SameLine();
                imgui.Separator();
            end
        end

        menuWidth, menuHeight = imgui.GetWindowSize();
    end

    imgui.End();

    ----------------------------------------------------------------
    -- Grow Upwards Logic (bottom-anchored window)
    ----------------------------------------------------------------
    if (gConfig.enemyListGrowUpwards and imguiPosX ~= nil) then
        if (gConfig.enemyListState == nil) then
            gConfig.enemyListState = {};
        end

        local state = gConfig.enemyListState;

        if (state.height ~= nil and menuHeight ~= state.height) then
            local newPosY = state.y + state.height - menuHeight;
            imguiPosY = newPosY;
            imgui.SetWindowPos(windowName, { imguiPosX, imguiPosY });
        end

        if (state.x == nil or imguiPosX ~= state.x or imguiPosY ~= state.y
            or menuWidth ~= state.width or menuHeight ~= state.height) then
            gConfig.enemyListState = {
                x = imguiPosX,
                y = imguiPosY,
                width = menuWidth,
                height = menuHeight,
            };
            ashita_settings.save();
        end
    end
end

---------------------------------------------------------------------------
-- Packet Handlers
---------------------------------------------------------------------------

enemylist.HandleActionPacket = function(e)
    if (e == nil) then
        return;
    end

    if (GetIsMobByIndex(e.UserIndex) and GetIsValidMob(e.UserIndex)) then
        local partyMemberIds = GetPartyMemberIds();
        for i = 0, #e.Targets do
            if (e.Targets[i] ~= nil and partyMemberIds:contains(e.Targets[i].Id)) then
                allClaimedTargets[e.UserIndex] = 1;
            end
        end
    end
end

enemylist.HandleMobUpdatePacket = function(e)
    if (e == nil) then
        return;
    end

    if (e.newClaimId ~= nil and GetIsValidMob(e.monsterIndex)) then
        local partyMemberIds = GetPartyMemberIds();
        if (partyMemberIds:contains(e.newClaimId)) then
            allClaimedTargets[e.monsterIndex] = 1;
        end
    end
end

enemylist.HandleZonePacket = function(e)
    allClaimedTargets = T{};
end

return enemylist;