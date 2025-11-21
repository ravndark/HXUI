require('common');
require('helpers');
local imgui         = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar   = require('progressbar');
local fonts         = require('fonts');
local ffi           = require('ffi');

local subTargetBar = {
    interpolation = {
        currentTargetId = nil,
        currentHpp = 100,
        interpolationDamagePercent = 0,
        hitDelayStartTime = nil,
        lastHitTime = nil,
        lastHitAmount = 0,
        lastFrameTime = nil,
        overlayAlpha = 0,
    },
    hidden = false,
}

-- Font / texture objects reused across frames
local nameText, percentText, distText
local debuffTable = {}

-- Show / hide all floating text for this bar
local function UpdateTextVisibility(isVisible)
    isVisible = isVisible and true or false

    if nameText then nameText:SetVisible(isVisible) end
    if percentText then percentText:SetVisible(isVisible) end
    if distText then distText:SetVisible(isVisible) end
end

subTargetBar.DrawWindow = function(settings)

    -- Use helper functions to decide what the sub-target is
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    local playerEnt    = GetPlayerEntity();

    if (playerTarget == nil or playerEnt == nil) then
        UpdateTextVisibility(false);
        return;
    end

    local t1, t2 = GetTargets();
    local sActive = GetSubTargetActive();
    local isConfigOpen = (showConfig ~= nil and showConfig[1] == true);

    -- Track if we're in preview mode (showing placeholder when no real sub-target exists)
    local isPreviewMode = false;

    -- Decide what index the bar should use
    local secondaryIndex;

    if sActive then
        -- Normal behavior: use spell target (t1)
        secondaryIndex = t1;
    elseif isConfigOpen then
        -- Config is open: draw a preview even if there is no real sub-target
        isPreviewMode = true;
        if t1 ~= nil and t1 ~= 0 then
            -- If we have a main target, just use that
            secondaryIndex = t1;
        else
            -- Otherwise, fall back to the player entity so the bar still appears
            local party = AshitaCore:GetMemoryManager():GetParty();
            if (party ~= nil) then
                local playerIndex = party:GetMemberTargetIndex(0);
                if playerIndex ~= 0 then
                    secondaryIndex = playerIndex;
                end
            end
        end
    else
        -- No sub-target and no config preview: hide as before
        UpdateTextVisibility(false);
        return;
    end

    -- Decide what the sub bar should show based on config:
    --   subTargetBarLegacyBehavior = false (default) → show spell target (t1)
    --   subTargetBarLegacyBehavior = true            → disable subtarget bar (no bar shown)
    local legacy = gConfig and gConfig.subTargetBarLegacyBehavior;

    if not legacy then
        -- Legacy behavior: don't show a sub-target bar at all.
        UpdateTextVisibility(false);
        return;
    end

    -- New behavior: sub bar shows spell target (or preview)
    if (secondaryIndex == nil or secondaryIndex == 0) then
        UpdateTextVisibility(false);
        return;
    end



    local targetEntity = GetEntity(secondaryIndex);

    if (targetEntity == nil or targetEntity.Name == nil) then
        UpdateTextVisibility(false);
        return;
    end

    local currentTime = os.clock();
    local hppPercent  = targetEntity.HPPercent;

    -- If we change targets, reset the interpolation
    if subTargetBar.interpolation.currentTargetId ~= secondaryIndex then
        subTargetBar.interpolation.currentTargetId = secondaryIndex;
        subTargetBar.interpolation.currentHpp = hppPercent;
        subTargetBar.interpolation.interpolationDamagePercent = 0;
        subTargetBar.interpolation.hitDelayStartTime = nil;
        subTargetBar.interpolation.lastHitTime = nil;
        subTargetBar.interpolation.lastHitAmount = 0;
    end

    -- If the target takes damage
    if hppPercent < subTargetBar.interpolation.currentHpp then
        local previousInterpolationDamagePercent = subTargetBar.interpolation.interpolationDamagePercent;
        local damageAmount = subTargetBar.interpolation.currentHpp - hppPercent;

        subTargetBar.interpolation.interpolationDamagePercent =
            subTargetBar.interpolation.interpolationDamagePercent + damageAmount;

        if previousInterpolationDamagePercent > 0
            and subTargetBar.interpolation.lastHitAmount
            and damageAmount > subTargetBar.interpolation.lastHitAmount
        then
            subTargetBar.interpolation.lastHitTime = currentTime;
            subTargetBar.interpolation.lastHitAmount = damageAmount;
        elseif previousInterpolationDamagePercent == 0 then
            subTargetBar.interpolation.lastHitTime = currentTime;
            subTargetBar.interpolation.lastHitAmount = damageAmount;
        end

        if not subTargetBar.interpolation.lastHitTime
            or currentTime > subTargetBar.interpolation.lastHitTime + (settings.hitFlashDuration * 0.25)
        then
            subTargetBar.interpolation.lastHitTime = currentTime;
            subTargetBar.interpolation.lastHitAmount = damageAmount;
        end

        -- If we previously were interpolating with an empty bar, reset the hit delay effect
        if previousInterpolationDamagePercent == 0 then
            subTargetBar.interpolation.hitDelayStartTime = currentTime;
        end
    elseif hppPercent > subTargetBar.interpolation.currentHpp then
        -- If the target heals
        subTargetBar.interpolation.interpolationDamagePercent = 0;
        subTargetBar.interpolation.hitDelayStartTime = nil;
    end

    subTargetBar.interpolation.currentHpp = hppPercent;

    -- Reduce the HP amount to display based on the time passed since last frame
    if subTargetBar.interpolation.interpolationDamagePercent > 0
        and subTargetBar.interpolation.hitDelayStartTime
        and currentTime > subTargetBar.interpolation.hitDelayStartTime + settings.hitDelayDuration
    then
        if subTargetBar.interpolation.lastFrameTime then
            local deltaTime = currentTime - subTargetBar.interpolation.lastFrameTime;

            local animSpeed = 0.1 + (0.9 * (subTargetBar.interpolation.interpolationDamagePercent / 100));
            subTargetBar.interpolation.interpolationDamagePercent =
                subTargetBar.interpolation.interpolationDamagePercent
                - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

            -- Clamp our percent to 0
            subTargetBar.interpolation.interpolationDamagePercent =
                math.max(0, subTargetBar.interpolation.interpolationDamagePercent);
        end
    end

    if gConfig.healthBarFlashEnabled then
        if subTargetBar.interpolation.lastHitTime
            and currentTime < subTargetBar.interpolation.lastHitTime + settings.hitFlashDuration
        then
            local hitFlashTime = currentTime - subTargetBar.interpolation.lastHitTime;
            local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;

            local maxAlphaHitPercent = 20;
            local maxAlpha = math.min(subTargetBar.interpolation.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;

            maxAlpha = math.max(maxAlpha * 0.6, 0.4);

            subTargetBar.interpolation.overlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
        end
    end

    subTargetBar.interpolation.lastFrameTime = currentTime;

    local color     = GetColorOfTarget(targetEntity, secondaryIndex);
    local isMonster = GetIsMob(targetEntity);
    local player    = AshitaCore:GetMemoryManager():GetPlayer();

    -- Draw the main sub-target window
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

    if (imgui.Begin('subTargetBar', true, windowFlags)) then

        -- Obtain and prepare target information..
        local dist  = ('%.2f'):fmt(math.sqrt(targetEntity.Distance));
        local targetNameText;
        
        -- Use placeholder name if in preview mode, otherwise use actual name
        if isPreviewMode then
            targetNameText = "Sub Target";
        else
            targetNameText = targetEntity.Name;
        end
        
        local targetHpPercent = targetEntity.HPPercent .. '%';

        if (gConfig.showEnemyId and isMonster and not isPreviewMode) then
            local targetServerId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(secondaryIndex);
            local targetServerIdHex = string.format('0x%X', targetServerId);
            targetNameText = targetNameText .. " [" .. string.sub(targetServerIdHex, -3) .. "]";
        end

        -- Build the HP bar gradient from the same target color Bars uses
        local r = bit.band(bit.rshift(color, 16), 0xFF);
        local g = bit.band(bit.rshift(color, 8), 0xFF);
        local b = bit.band(color, 0xFF);

        local hpGradientStart = string.format('#%02X%02X%02X', r, g, b);
        local hpGradientEnd   = hpGradientStart;

        local hpPercentData = {
            { targetEntity.HPPercent / 100, { hpGradientStart, hpGradientEnd } }
        };

        if subTargetBar.interpolation.interpolationDamagePercent > 0 then
            local interpolationOverlay;

            if gConfig.healthBarFlashEnabled then
                interpolationOverlay = {
                    '#FFFFFF', -- overlay color,
                    subTargetBar.interpolation.overlayAlpha -- overlay alpha,
                };
            end

            table.insert(
                hpPercentData,
                {
                    subTargetBar.interpolation.interpolationDamagePercent / 100, -- interpolation percent
                    { '#cf3437', '#c54d4d' },
                    interpolationOverlay
                }
            );
        end

        local startX, startY = imgui.GetCursorScreenPos();
        progressbar.ProgressBar(
            hpPercentData,
            { settings.barWidth, settings.barHeight },
            { decorate = gConfig.showsubTargetBarBookends }
        );

        -- Top text: name (left)
        local nameSize = SIZE.new();
        nameText:GetTextSize(nameSize);

        nameText:SetPositionX(startX + settings.barHeight / 2 + settings.topTextXOffset);
        nameText:SetPositionY(startY - settings.topTextYOffset - nameSize.cy);
        nameText:SetColor(color);
        nameText:SetText(targetNameText);
        nameText:SetVisible(true);

        -- Top text: distance (right)
        local distSize = SIZE.new();
        distText:GetTextSize(distSize);

        distText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.topTextXOffset);
        distText:SetPositionY(startY - settings.topTextYOffset - distSize.cy);
        distText:SetText(tostring(dist));
        if gConfig.showSubTargetDistance then
            distText:SetVisible(true);
        else
            distText:SetVisible(false);
        end

        -- Bottom text: HP percent
        if (isMonster or gConfig.alwaysShowHealthPercent) then
            percentText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.bottomTextXOffset);
            percentText:SetPositionY(startY + settings.barHeight + settings.bottomTextYOffset);
            percentText:SetText(tostring(targetHpPercent));
            percentText:SetVisible(true);
            local hpColor, _ = GetHpColors(targetEntity.HPPercent / 100);
            percentText:SetColor(hpColor);
        else
            percentText:SetVisible(false);
        end

        -- Draw buffs and debuffs
        local buffIds;
        local buffTimes = nil;

        if (targetEntity == playerEnt) then
            buffIds = player:GetBuffs();
        elseif (IsMemberOfParty(secondaryIndex)) then
            buffIds = statusHandler.get_member_status(playerTarget:GetServerId(0));
        elseif (isMonster) then
            buffIds, buffTimes = debuffHandler.GetActiveDebuffs(playerTarget:GetServerId(0));
        end

        imgui.NewLine();
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 1, 3 });

        -- Hide any existing debuff timer text objects
        for i = 1, 32 do
            local textObjName = "debuffText" .. tostring(i);
            local textObj = debuffTable[textObjName];
            if textObj then
                textObj:SetVisible(false);
            end
        end

        local buffsX = startX + settings.barHeight / 2;
        local buffsY = startY + settings.barHeight + settings.bottomTextYOffset + 4;

        imgui.SetCursorScreenPos({ buffsX, buffsY });

        DrawStatusIcons(
            buffIds,
            settings.iconSize,
            settings.maxIconColumns,
            3,
            false,
            nil,
            buffTimes,
            settings.distance_font_settings
        );

        imgui.PopStyleVar(1);
    end

    imgui.End();
end

subTargetBar.Initialize = function(settings)
    percentText = fonts.new(settings.percent_font_settings);
    nameText    = fonts.new(settings.name_font_settings);
    distText    = fonts.new(settings.distance_font_settings);
end

subTargetBar.UpdateFonts = function(settings)
    if percentText then
        percentText:SetFontHeight(settings.percent_font_settings.font_height);
    end
    if nameText then
        nameText:SetFontHeight(settings.name_font_settings.font_height);
    end
    if distText then
        distText:SetFontHeight(settings.distance_font_settings.font_height);
    end
end

subTargetBar.SetHidden = function(hidden)
    subTargetBar.hidden = hidden;
end

return subTargetBar;