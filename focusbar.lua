require('common');
require('helpers');
local imgui         = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar   = require('progressbar');
local fonts         = require('fonts');
local ffi           = require('ffi');
local actionTracker = require('actiontracker');

local actionTextLeft;
local actionTextRight;
local actionResultText;

local percentText;
local nameText;
local totNameText;
local distText;
local arrowTexture;

local focusbar = {
    interpolation = {},

    -- Pulse state for SP-active target names
    spPulseAlpha       = 255,
    spPulseDirectionUp = true,
};

local function UpdateTextVisibility(visible)
    if percentText ~= nil then
        percentText:SetVisible(visible);
    end
    if nameText ~= nil then
        nameText:SetVisible(visible);
    end
    if totNameText ~= nil then
        totNameText:SetVisible(visible);
    end
    if distText ~= nil then
        distText:SetVisible(visible);
    end

    if actionTextLeft ~= nil then
        actionTextLeft:SetVisible(visible);
    end
    if actionTextRight ~= nil then
        actionTextRight:SetVisible(visible);
    end
    if actionResultText ~= nil then
        actionResultText:SetVisible(visible);
    end
end

focusbar.DrawWindow = function(settings)
    local playerEnt = GetPlayerEntity();
    local player    = AshitaCore:GetMemoryManager():GetPlayer();
    if (playerEnt == nil or player == nil) then
        UpdateTextVisibility(false);
        return;
    end

    -- Detect if the HXUI config window is open.
    local isConfigOpen = (showConfig ~= nil and showConfig[1] == true);

    -- Obtain the focus target entity (independent of current target)
    local focusIndex, focusEntity = GetFocusTargetEntity();

    -- If we don't have a focus target, but the config is open, use the player as a preview target.
    if (focusEntity == nil or focusEntity.Name == nil) and isConfigOpen then
        local party = AshitaCore:GetMemoryManager():GetParty();
        if (party ~= nil) then
            local playerIndex = party:GetMemberTargetIndex(0);
            if playerIndex ~= 0 then
                focusIndex  = playerIndex;
                focusEntity = GetEntity(playerIndex);
            end
        end
    end

    -- Still nothing? Then hide as usual.
    if (focusEntity == nil or focusEntity.Name == nil) then
        UpdateTextVisibility(false);
        return;
    end


    local targetIndex  = focusIndex;
    local targetEntity = focusEntity;

    local currentTime = os.clock();
    local hppPercent  = targetEntity.HPPercent;

    -- If we change targets, reset the interpolation
    if focusbar.interpolation.currentTargetId ~= targetIndex then
        focusbar.interpolation.currentTargetId             = targetIndex;
        focusbar.interpolation.currentHpp                  = hppPercent;
        focusbar.interpolation.interpolationDamagePercent  = 0;
        focusbar.interpolation.lastFrameTime               = nil;
        focusbar.interpolation.hitDelayStartTime           = nil;
        focusbar.interpolation.lastHitTime                 = nil;
        focusbar.interpolation.lastHitAmount               = nil;
        focusbar.interpolation.overlayAlpha                = 0;
    end

    -- If the target takes damage
    if hppPercent < (focusbar.interpolation.currentHpp or hppPercent) then
        local previousInterpolationDamagePercent = focusbar.interpolation.interpolationDamagePercent or 0;
        local damageAmount = (focusbar.interpolation.currentHpp or hppPercent) - hppPercent;

        focusbar.interpolation.interpolationDamagePercent =
            (focusbar.interpolation.interpolationDamagePercent or 0) + damageAmount;

        local lastHitAmount = focusbar.interpolation.lastHitAmount or 0;

        if previousInterpolationDamagePercent > 0 and damageAmount > lastHitAmount then
            focusbar.interpolation.lastHitTime   = currentTime;
            focusbar.interpolation.lastHitAmount = damageAmount;
        elseif previousInterpolationDamagePercent == 0 then
            focusbar.interpolation.lastHitTime   = currentTime;
            focusbar.interpolation.lastHitAmount = damageAmount;
        end

        if not focusbar.interpolation.lastHitTime
            or currentTime > focusbar.interpolation.lastHitTime + (settings.hitFlashDuration * 0.25)
        then
            focusbar.interpolation.lastHitTime   = currentTime;
            focusbar.interpolation.lastHitAmount = damageAmount;
        end

        -- If we previously were interpolating with an empty bar, reset the hit delay effect
        if previousInterpolationDamagePercent == 0 then
            focusbar.interpolation.hitDelayStartTime = currentTime;
        end
    elseif hppPercent > (focusbar.interpolation.currentHpp or hppPercent) then
        -- If the target heals
        focusbar.interpolation.interpolationDamagePercent = 0;
        focusbar.interpolation.hitDelayStartTime          = nil;
    end

    focusbar.interpolation.currentHpp = hppPercent;

    -- Reduce the HP amount to display based on the time passed since last frame
    if (focusbar.interpolation.interpolationDamagePercent or 0) > 0
        and focusbar.interpolation.hitDelayStartTime
        and currentTime > focusbar.interpolation.hitDelayStartTime + settings.hitDelayDuration
    then
        if focusbar.interpolation.lastFrameTime then
            local deltaTime = currentTime - focusbar.interpolation.lastFrameTime;
            local animSpeed = 0.1 + (0.9 * (focusbar.interpolation.interpolationDamagePercent / 100));

            focusbar.interpolation.interpolationDamagePercent =
                focusbar.interpolation.interpolationDamagePercent
                - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

            focusbar.interpolation.interpolationDamagePercent =
                math.max(0, focusbar.interpolation.interpolationDamagePercent);
        end
    end

    if gConfig.healthBarFlashEnabled then
        if focusbar.interpolation.lastHitTime
            and currentTime < focusbar.interpolation.lastHitTime + settings.hitFlashDuration
        then
            local hitFlashTime        = currentTime - focusbar.interpolation.lastHitTime;
            local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;

            local maxAlphaHitPercent  = 20;
            local maxAlpha            =
                math.min(focusbar.interpolation.lastHitAmount or 0, maxAlphaHitPercent) / maxAlphaHitPercent;

            maxAlpha = math.max(maxAlpha * 0.6, 0.4);
            focusbar.interpolation.overlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
        else
            focusbar.interpolation.overlayAlpha = 0;
        end
    end

    focusbar.interpolation.lastFrameTime = currentTime;

    local color     = GetColorOfTarget(targetEntity, targetIndex);
    local isMonster = GetIsMob(targetEntity);

    -- ImGui window for the focus bar
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

    if imgui.Begin('FocusBar', true, windowFlags) then
        local dist          = ('%.2f'):fmt(math.sqrt(targetEntity.Distance));
        local targetNameText = targetEntity.Name;
        local targetHpPercent = targetEntity.HPPercent .. '%';

        if (gConfig.showEnemyId and isMonster) then
            local entMgr       = AshitaCore:GetMemoryManager():GetEntity();
            local targetServerId     = entMgr:GetServerId(targetIndex);
            local targetServerIdHex  = string.format('0x%X', targetServerId);

            targetNameText = targetNameText .. ' [' .. string.sub(targetServerIdHex, -3) .. ']';
        end

        -- Check for active SP on this target once, reuse for name + pulse
        local spName, spRemaining = actionTracker.GetSpecialForTargetIndex(targetIndex);
        local spActive = (spName ~= nil and spRemaining ~= nil and spRemaining > 0)
						 and gConfig.focusBarShowSPName;
        if spActive then
            -- Format remaining time as M:SS
            local seconds  = math.floor(spRemaining + 0.5);
            local minutes  = math.floor(seconds / 60);
            local secPart  = seconds % 60;
            local spTimer  = string.format('%d:%02d', minutes, secPart);

            -- Alternate every second between:
            --   "00:37 Mighty Strikes"
            --   "00:36 <Mob Name>"
            if (seconds % 2 == 0) then
                targetNameText = string.format('%s %s', spTimer, spName);
            else
                targetNameText = string.format('%s %s', spTimer, targetNameText);
            end
        end

        -- Build the HP bar gradient from the target color
        local r = bit.band(bit.rshift(color, 16), 0xFF);
        local g = bit.band(bit.rshift(color, 8), 0xFF);
        local b = bit.band(color, 0xFF);

        local hpGradient = string.format('#%02X%02X%02X', r, g, b);
        local hpPercentData = {
            { targetEntity.HPPercent / 100, { hpGradient, hpGradient } },
        };

        if (focusbar.interpolation.interpolationDamagePercent or 0) > 0 then
            local interpolationOverlay;

            if gConfig.healthBarFlashEnabled then
                interpolationOverlay = {
                    '#FFFFFF',
                    focusbar.interpolation.overlayAlpha or 0,
                };
            end

            table.insert(hpPercentData, {
                focusbar.interpolation.interpolationDamagePercent / 100,
                { '#cf3437', '#c54d4d' },
                interpolationOverlay
            });
        end

        ----------------------------------------------------------------
        -- SP pulse for the target name when an SP is active
        ----------------------------------------------------------------
        local nameColor = color;

        if spActive then
            local minAlpha = 80;
            local maxAlpha = 255;
            local speed    = 3;

            local alpha = focusbar.spPulseAlpha or maxAlpha;
            local up    = (focusbar.spPulseDirectionUp ~= false);

            if up then
                alpha = alpha + speed;
                if alpha >= maxAlpha then
                    alpha = maxAlpha;
                    up    = false;
                end
            else
                alpha = alpha - speed;
                if alpha <= minAlpha then
                    alpha = minAlpha;
                    up    = true;
                end
            end

            focusbar.spPulseAlpha       = alpha;
            focusbar.spPulseDirectionUp = up;

            local rgb = bit.band(color, 0x00FFFFFF);
            nameColor = bit.bor(bit.lshift(alpha, 24), rgb);
        else
            focusbar.spPulseAlpha       = 255;
            focusbar.spPulseDirectionUp = true;
            nameColor                   = color;
        end

        -- Draw main HP bar
        local startX, startY = imgui.GetCursorScreenPos();
        progressbar.ProgressBar(
            hpPercentData,
            { settings.barWidth, settings.barHeight },
            { decorate = gConfig.showFocusBarBookends }
        );

        -- Top text: name (left)
        local nameSize = SIZE.new();
        nameText:GetTextSize(nameSize);

        nameText:SetPositionX(startX + settings.barHeight / 2 + settings.topTextXOffset);
        nameText:SetPositionY(startY - settings.topTextYOffset - nameSize.cy);
        nameText:SetColor(nameColor);
        nameText:SetText(targetNameText);
        nameText:SetVisible(true);

        -- Top text: distance (right)
        local distSize = SIZE.new();
        distText:GetTextSize(distSize);

        distText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.topTextXOffset);
        distText:SetPositionY(startY - settings.topTextYOffset - distSize.cy);
        distText:SetText(tostring(dist));
        distText:SetVisible(gConfig.showFocusDistance);

        -- Bottom text: HP%
        if (isMonster or gConfig.alwaysShowHealthPercent) then
            percentText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.bottomTextXOffset);
            percentText:SetPositionY(startY + settings.barHeight + settings.bottomTextYOffset);
            percentText:SetText(targetHpPercent);
            local hpColor = GetHpColors(targetEntity.HPPercent / 100);
            percentText:SetColor(hpColor);
            percentText:SetVisible(true);
        else
            percentText:SetVisible(false);
        end

        ----------------------------------------------------------------
        -- Action tracker (icon + "Action -> Target" + result)
        ----------------------------------------------------------------
        if (gConfig.showFocusActionTracker and actionTextLeft ~= nil and actionTextRight ~= nil) then
            local iconTexture, actionName, actionTargetName, resultText, resultColor =
                actionTracker.GetActionPartsForTargetIndex(targetIndex);

            if (iconTexture ~= nil and actionName ~= nil and actionName ~= '') then
                local baseX = startX + settings.barHeight / 2 + settings.topTextXOffset;
                local baseY = startY + settings.barHeight + settings.bottomTextYOffset;

                local iconSize = settings.arrowSize * 0.6;
                imgui.SetCursorScreenPos({ baseX, baseY });
                imgui.Image(tonumber(ffi.cast('uint32_t', iconTexture.image)), { iconSize, iconSize });

                actionTextLeft:SetText(actionName);
                local leftSize = SIZE.new();
                actionTextLeft:GetTextSize(leftSize);

                local textX = baseX + iconSize + 4;
                actionTextLeft:SetPositionX(textX);
                actionTextLeft:SetPositionY(baseY);
                actionTextLeft:SetVisible(true);

                local arrowX = textX + leftSize.cx + 4;
                local arrowY = baseY + (leftSize.cy - iconSize) / 2 + 2;

                imgui.SetCursorScreenPos({ arrowX, arrowY });
                imgui.Image(tonumber(ffi.cast('uint32_t', arrowTexture.image)), { iconSize, iconSize });

                if (actionTargetName ~= nil and actionTargetName ~= '') then
                    actionTextRight:SetText(actionTargetName);
                    actionTextRight:SetPositionX(arrowX + iconSize + 4);
                    actionTextRight:SetPositionY(baseY);
                    actionTextRight:SetVisible(true);
                else
                    actionTextRight:SetVisible(false);
                end

                if (resultText ~= nil and resultText ~= '' and actionResultText ~= nil) then
                    actionResultText:SetText(resultText);

                    local rightSize = SIZE.new();
                    actionTextRight:GetTextSize(rightSize);
                    actionResultText:SetPositionX(arrowX + iconSize + 4 + rightSize.cx);
                    actionResultText:SetPositionY(baseY);

                    if (resultColor == 'damage') then
                        actionResultText:SetColor(0xFFFF4444);
                    elseif (resultColor == 'heal') then
                        actionResultText:SetColor(0xFF44FF44);
                    else
                        actionResultText:SetColor(0xFFFFFFFF);
                    end

                    actionResultText:SetVisible(true);
                else
                    actionResultText:SetVisible(false);
                end
            else
                actionTextLeft:SetVisible(false);
                actionTextRight:SetVisible(false);
                actionResultText:SetVisible(false);
            end
        end

        ----------------------------------------------------------------
        -- Buffs / debuffs (using focus target serverId)
        ----------------------------------------------------------------
        local buffIds;
        local buffTimes = nil;
        local entMgr = AshitaCore:GetMemoryManager():GetEntity();

        if (targetEntity == playerEnt) then
            buffIds = player:GetBuffs();
        elseif (IsMemberOfParty(targetIndex)) then
            buffIds = statusHandler.get_member_status(entMgr:GetServerId(targetIndex));
        elseif (isMonster) then
            buffIds, buffTimes = debuffHandler.GetActiveDebuffs(entMgr:GetServerId(targetIndex));
        end

        imgui.NewLine();
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 1, 3 });

        -- Hide any existing debuff timer text objects
        for i = 1, 32 do
            local textObjName = 'debuffText' .. tostring(i);
            local textObj     = debuffTable[textObjName];
            if textObj then
                textObj:SetVisible(false);
            end
        end

        local buffsX = startX + settings.barHeight / 2;

        local buffsY = startY + settings.barHeight + settings.bottomTextYOffset + 4;
        if (gConfig.showFocusActionTracker and actionTextLeft ~= nil and actionTextRight ~= nil) then
            buffsY = buffsY + settings.name_font_settings.font_height + 8;
        end

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

        ----------------------------------------------------------------
        -- Target of target (only when focus target == current target)
        ----------------------------------------------------------------
        local totEntity;
        local totIndex;

        -- Figure out what the *current* main target index is.
        local targetMgr  = AshitaCore:GetMemoryManager():GetTarget();
        local mainIndex  = nil;
        if (targetMgr ~= nil) then
            mainIndex, _ = GetTargets();
        end

        -- Only compute ToT if:
        --   - we actually have a current target, and
        --   - that current target is the same as our focus target.
        if (mainIndex ~= nil and mainIndex == targetIndex) then
            -- This is exactly the same logic as the normal target bar.
            if (targetEntity == playerEnt) then
                totIndex  = targetIndex;
                totEntity = targetEntity;
            end

            if (totEntity == nil) then
                totIndex = targetEntity.TargetedIndex;
                if (totIndex ~= nil) then
                    totEntity = GetEntity(totIndex);
                end
            end
        end

        if (totEntity ~= nil and totEntity.Name ~= nil) then
            -- Anchor ToT to the right of the main target bar
            local totBaseX = startX + settings.barWidth + 10; -- 10px gap after the main bar
            local totBaseY = startY;                          -- align vertically with the main bar

            local totColor = GetColorOfTarget(totEntity, totIndex);

            -- Draw the ToT arrow, vertically centered on the main bar
            local arrowX = totBaseX;
            local arrowY = totBaseY + settings.barHeight / 2 - settings.arrowSize / 2;

            imgui.SetCursorScreenPos({ arrowX, arrowY });
            imgui.Image(tonumber(ffi.cast('uint32_t', arrowTexture.image)), { settings.arrowSize, settings.arrowSize });
            imgui.SameLine();

            -- ToT bar position
            local totX   = select(1, imgui.GetCursorScreenPos());
            local barY   = totBaseY - (settings.totBarHeight / 2) + (settings.barHeight / 2) + settings.totBarOffset;
            imgui.SetCursorScreenPos({ totX, barY });

            local totStartX, totStartY = imgui.GetCursorScreenPos();

            -- ToT HP bar color
            local tr = bit.band(bit.rshift(totColor, 16), 0xFF);
            local tg = bit.band(bit.rshift(totColor, 8), 0xFF);
            local tb = bit.band(totColor, 0xFF);
            local totBarColor = string.format('#%02X%02X%02X', tr, tg, tb);

            progressbar.ProgressBar(
                { { totEntity.HPPercent / 100, { totBarColor, totBarColor } } },
                { settings.barWidth / 3, settings.totBarHeight },
                { decorate = gConfig.showFocusBarBookends }
            );

            -- ToT name text above the bar
            local totNameSize = SIZE.new();
            totNameText:GetTextSize(totNameSize);

            totNameText:SetPositionX(totStartX + settings.barHeight / 2);
            totNameText:SetPositionY(totStartY - totNameSize.cy);
            totNameText:SetColor(totColor);
            totNameText:SetText(totEntity.Name);
            totNameText:SetVisible(true);
        else
            totNameText:SetVisible(false);
        end
    end

    imgui.End();
end

focusbar.Initialize = function(settings)
    percentText   = fonts.new(settings.percent_font_settings);
    nameText      = fonts.new(settings.name_font_settings);
    totNameText   = fonts.new(settings.totName_font_settings);
    distText      = fonts.new(settings.distance_font_settings);
    arrowTexture  = LoadTexture('arrow');

    actionTextLeft   = fonts.new(settings.name_font_settings);
    actionTextRight  = fonts.new(settings.name_font_settings);
    actionResultText = fonts.new(settings.name_font_settings);

    actionTextLeft:SetVisible(false);
    actionTextRight:SetVisible(false);
    actionResultText:SetVisible(false);
end

focusbar.UpdateFonts = function(settings)
    if percentText ~= nil then
        percentText:SetFontHeight(settings.percent_font_settings.font_height);
    end
    if nameText ~= nil then
        nameText:SetFontHeight(settings.name_font_settings.font_height);
    end
    if totNameText ~= nil then
        totNameText:SetFontHeight(settings.totName_font_settings.font_height);
    end
    if distText ~= nil then
        distText:SetFontHeight(settings.distance_font_settings.font_height);
    end

    if (actionTextLeft ~= nil) then
        actionTextLeft:SetFontHeight(settings.name_font_settings.font_height);
    end
    if (actionTextRight ~= nil) then
        actionTextRight:SetFontHeight(settings.name_font_settings.font_height);
    end
    if (actionResultText ~= nil) then
        actionResultText:SetFontHeight(settings.name_font_settings.font_height);
    end
end

focusbar.SetHidden = function(hidden)
    if (hidden == true) then
        UpdateTextVisibility(false);
    end
end

return focusbar;
