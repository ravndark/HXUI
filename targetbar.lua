require('common');
require('helpers');
local imgui = require('imgui');
local statusHandler = require('statushandler');
local debuffHandler = require('debuffhandler');
local progressbar = require('progressbar');
local fonts = require('fonts');
local ffi = require("ffi");
local actionTextLeft;
local actionTextRight;
local actionResultText;
local actionTracker = require('actiontracker');

-- TODO: Calculate these instead of manually setting them

local bgAlpha = 0.4;
local bgRadius = 3;

local arrowTexture;
local percentText;
local nameText;
local totNameText;
local distText;
local targetbar = {
    interpolation = {},

    -- Bars-style pulse state for SP-active target names
    spPulseAlpha        = 255,
    spPulseDirectionUp  = true,
};


local function UpdateTextVisibility(visible)
	percentText:SetVisible(visible);
	nameText:SetVisible(visible);
	totNameText:SetVisible(visible);
	distText:SetVisible(visible);
	if (actionTextLeft ~= nil) then
		actionTextLeft:SetVisible(visible);
	end
	if (actionTextRight ~= nil) then
		actionTextRight:SetVisible(visible);
	end
	if (actionResultText ~= nil) then
		actionResultText:SetVisible(visible);
	end
end

local _HXUI_DEV_DEBUG_INTERPOLATION = false;
local _HXUI_DEV_DEBUG_INTERPOLATION_DELAY = 1;
local _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = 100;
local _HXUI_DEV_DAMAGE_SET_TIMES = {};

targetbar.DrawWindow = function(settings)
    -- Obtain the player entity..
    local playerEnt = GetPlayerEntity();
	local player = AshitaCore:GetMemoryManager():GetPlayer();
    if (playerEnt == nil or player == nil) then
		UpdateTextVisibility(false);
        return;
    end

    -- Obtain the player target entity (account for subtarget)
	local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
	local targetIndex;
    local targetEntity;
    if (playerTarget ~= nil) then
		local t1, t2 = GetTargets();
		local sActive = GetSubTargetActive();
		local legacy = gConfig and gConfig.subTargetBarLegacyBehavior;
		
		if legacy then
			-- Checkbox ON: use NEW behavior.
			-- Main bar stays on the original main target.
			if (sActive) then
				-- When a sub-target is active:
				--   t1 = sub-target, t2 = main target
				if (t2 ~= nil and t2 ~= 0) then
					targetIndex = t2;      -- keep main bar on the main target
				else
					targetIndex = t1;      -- fallback
				end
			else
				-- Normal case: t1 is the main target
				targetIndex = t1;
			end
		else
			-- Checkbox OFF: act like original / legacy behavior.
			-- Main bar follows the spell / sub target (t1).
			targetIndex = t1;
		end


        if (targetIndex ~= nil and targetIndex ~= 0) then
            targetEntity = GetEntity(targetIndex);
        end
    end


    if (targetEntity == nil or targetEntity.Name == nil) then
		UpdateTextVisibility(false);
        for i=1,32 do
            local textObjName = "debuffText" .. tostring(i)
            textObj = debuffTable[textObjName]
            if textObj then
                textObj:SetVisible(false)
            end
        end
		targetbar.interpolation.interpolationDamagePercent = 0;

        return;
    end

	local currentTime = os.clock();

	local hppPercent = targetEntity.HPPercent;

	-- Mimic damage taken
	if _HXUI_DEV_DEBUG_INTERPOLATION then
		if _HXUI_DEV_DAMAGE_SET_TIMES[1] and currentTime > _HXUI_DEV_DAMAGE_SET_TIMES[1][1] then
			_HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT = _HXUI_DEV_DAMAGE_SET_TIMES[1][2];

			table.remove(_HXUI_DEV_DAMAGE_SET_TIMES, 1);
		end

		if #_HXUI_DEV_DAMAGE_SET_TIMES == 0 then
			local previousHitTime = currentTime + 1;
			local previousHp = 100;

			local totalDamageInstances = 10;

			for i = 1, totalDamageInstances do
				local hitDelay = math.random(0.25 * 100, 1.25 * 100) / 100;
				local damageAmount = math.random(1, 20);

				if i > 1 and i < totalDamageInstances then
					previousHp = math.max(previousHp - damageAmount, 0);
				end

				if i < totalDamageInstances then
					previousHitTime = previousHitTime + hitDelay;
				else
					previousHitTime = previousHitTime + _HXUI_DEV_DEBUG_INTERPOLATION_DELAY;
				end

				_HXUI_DEV_DAMAGE_SET_TIMES[i] = {previousHitTime, previousHp};
			end
		end

		hppPercent = _HXUI_DEV_DEBUG_HP_PERCENT_PERSISTENT;
	end

	-- If we change targets, reset the interpolation
	if targetbar.interpolation.currentTargetId ~= targetIndex then
		targetbar.interpolation.currentTargetId = targetIndex;
		targetbar.interpolation.currentHpp = hppPercent;
		targetbar.interpolation.interpolationDamagePercent = 0;
	end

	-- If the target takes damage
	if hppPercent < targetbar.interpolation.currentHpp then
		local previousInterpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent;

		local damageAmount = targetbar.interpolation.currentHpp - hppPercent;

		targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent + damageAmount;

		if previousInterpolationDamagePercent > 0 and targetbar.interpolation.lastHitAmount and damageAmount > targetbar.interpolation.lastHitAmount then
			targetbar.interpolation.lastHitTime = currentTime;
			targetbar.interpolation.lastHitAmount = damageAmount;
		elseif previousInterpolationDamagePercent == 0 then
			targetbar.interpolation.lastHitTime = currentTime;
			targetbar.interpolation.lastHitAmount = damageAmount;
		end

		if not targetbar.interpolation.lastHitTime or currentTime > targetbar.interpolation.lastHitTime + (settings.hitFlashDuration * 0.25) then
			targetbar.interpolation.lastHitTime = currentTime;
			targetbar.interpolation.lastHitAmount = damageAmount;
		end

		-- If we previously were interpolating with an empty bar, reset the hit delay effect
		if previousInterpolationDamagePercent == 0 then
			targetbar.interpolation.hitDelayStartTime = currentTime;
		end
	elseif hppPercent > targetbar.interpolation.currentHpp then
		-- If the target heals
		targetbar.interpolation.interpolationDamagePercent = 0;
		targetbar.interpolation.hitDelayStartTime = nil;
	end

	targetbar.interpolation.currentHpp = hppPercent;

	-- Reduce the HP amount to display based on the time passed since last frame
	if targetbar.interpolation.interpolationDamagePercent > 0 and targetbar.interpolation.hitDelayStartTime and currentTime > targetbar.interpolation.hitDelayStartTime + settings.hitDelayDuration then
		if targetbar.interpolation.lastFrameTime then
			local deltaTime = currentTime - targetbar.interpolation.lastFrameTime;

			local animSpeed = 0.1 + (0.9 * (targetbar.interpolation.interpolationDamagePercent / 100));

			-- animSpeed = math.max(settings.hitDelayMinAnimSpeed, animSpeed);

			targetbar.interpolation.interpolationDamagePercent = targetbar.interpolation.interpolationDamagePercent - (settings.hitInterpolationDecayPercentPerSecond * deltaTime * animSpeed);

			-- Clamp our percent to 0
			targetbar.interpolation.interpolationDamagePercent = math.max(0, targetbar.interpolation.interpolationDamagePercent);
		end
	end

	if gConfig.healthBarFlashEnabled then
		if targetbar.interpolation.lastHitTime and currentTime < targetbar.interpolation.lastHitTime + settings.hitFlashDuration then
			local hitFlashTime = currentTime - targetbar.interpolation.lastHitTime;
			local hitFlashTimePercent = hitFlashTime / settings.hitFlashDuration;

			local maxAlphaHitPercent = 20;
			local maxAlpha = math.min(targetbar.interpolation.lastHitAmount, maxAlphaHitPercent) / maxAlphaHitPercent;

			maxAlpha = math.max(maxAlpha * 0.6, 0.4);

			targetbar.interpolation.overlayAlpha = math.pow(1 - hitFlashTimePercent, 2) * maxAlpha;
		end
	end

	targetbar.interpolation.lastFrameTime = currentTime;

	local color = GetColorOfTarget(targetEntity, targetIndex);
	local isMonster = GetIsMob(targetEntity);

	-- Draw the main target window
	local windowFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_NoBringToFrontOnFocus);
	if (gConfig.lockPositions) then
		windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove);
	end
    if (imgui.Begin('TargetBar', true, windowFlags)) then
        
		-- Obtain and prepare target information..
		local dist  = ('%.2f'):fmt(math.sqrt(targetEntity.Distance));
		local targetNameText = targetEntity.Name;
		local targetHpPercent = targetEntity.HPPercent..'%';

		if (gConfig.showEnemyId and isMonster) then
			local targetServerId = AshitaCore:GetMemoryManager():GetEntity():GetServerId(targetIndex);
			local targetServerIdHex = string.format('0x%X', targetServerId);

			targetNameText = targetNameText .. " [".. string.sub(targetServerIdHex, -3) .."]";
		end

        -- Bars-style SP name / timer overlay on the target bar.
        local spName, spRemaining = actionTracker.GetSpecialForTargetIndex(targetIndex);
        local spActive = (spName ~= nil and spRemaining ~= nil and spRemaining > 0);

        if gConfig.targetBarShowSPName and spActive then
            -- Format remaining time as M:SS
            local seconds = math.floor(spRemaining + 0.5);
            local minutes = math.floor(seconds / 60);
            local secPart = seconds % 60;
            local spTimer = string.format('%d:%02d', minutes, secPart);

            -- Alternate every second between:
            --   "00:37 Mighty Strikes"
            --   "00:36 <Mob Name>"
            if (seconds % 2 == 0) then
                targetNameText = string.format('%s %s', spTimer, spName);
            else
                targetNameText = string.format('%s %s', spTimer, targetNameText);
            end
        end


        -- Build the HP bar gradient from the same target color Bars uses
        -- `color` is the 0xAARRGGBB value from GetColorOfTarget(targetEntity, targetIndex)
        local r = bit.band(bit.rshift(color, 16), 0xFF);
        local g = bit.band(bit.rshift(color, 8), 0xFF);
        local b = bit.band(color, 0xFF);

        -- Solid bar in the target color (both gradient stops the same),
        -- just like Bars uses `cm` for the meter background.
        local hpGradientStart = string.format('#%02X%02X%02X', r, g, b);
        local hpGradientEnd   = hpGradientStart;

        local hpPercentData = {{targetEntity.HPPercent / 100, {hpGradientStart, hpGradientEnd}}};

		if _HXUI_DEV_DEBUG_INTERPOLATION then
			hpPercentData[1][1] = targetbar.interpolation.currentHpp / 100;
		end

		if targetbar.interpolation.interpolationDamagePercent > 0 then
			local interpolationOverlay;

			if gConfig.healthBarFlashEnabled then
				interpolationOverlay = {
					'#FFFFFF', -- overlay color,
					targetbar.interpolation.overlayAlpha -- overlay alpha,
				};
			end

			table.insert(
				hpPercentData,
				{
					targetbar.interpolation.interpolationDamagePercent / 100, -- interpolation percent
					{'#cf3437', '#c54d4d'},
					interpolationOverlay
				}
			);
		end
		
		----------------------------------------------------------------
        -- Bars-style pulse for the target name when an SP is active
        ----------------------------------------------------------------
                local nameColor = color;

        do
            local spName2, spRemaining2 = actionTracker.GetSpecialForTargetIndex(targetIndex);
            local spActive2 = (spName2 ~= nil and spRemaining2 ~= nil and spRemaining2 > 0)
                              and gConfig.targetBarShowSPName;

            if spActive2 then
                -- Pulse settings (tweak these to taste)
                local minAlpha = 80;   -- lowest opacity (0–255)
                local maxAlpha = 255;  -- highest opacity
                local speed    = 3;    -- how fast it pulses per frame

                local alpha = targetbar.spPulseAlpha or maxAlpha;
                local up    = (targetbar.spPulseDirectionUp ~= false);

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

                targetbar.spPulseAlpha       = alpha;
                targetbar.spPulseDirectionUp = up;

                -- Replace just the AA part of 0xAARRGGBB with our pulsed alpha
                local rgb = bit.band(color, 0x00FFFFFF);
                nameColor = bit.bor(bit.lshift(alpha, 24), rgb);
            else
                -- No SP active: reset to original color / full alpha
                targetbar.spPulseAlpha       = 255;
                targetbar.spPulseDirectionUp = true;
                nameColor = color;
            end
        end

		
		local startX, startY = imgui.GetCursorScreenPos();
		progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight}, {decorate = gConfig.showTargetBarBookends});

		local nameSize = SIZE.new();
		nameText:GetTextSize(nameSize);

		nameText:SetPositionX(startX + settings.barHeight / 2 + settings.topTextXOffset);
		nameText:SetPositionY(startY - settings.topTextYOffset - nameSize.cy);
		nameText:SetColor(nameColor);
		nameText:SetText(targetNameText);
		nameText:SetVisible(true);

		local distSize = SIZE.new();
		distText:GetTextSize(distSize);

		distText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - settings.topTextXOffset);
		distText:SetPositionY(startY - settings.topTextYOffset - distSize.cy);
		distText:SetText(tostring(dist));
		if (gConfig.showTargetDistance) then
			distText:SetVisible(true);
		else
			distText:SetVisible(false);
		end

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

        -- Show the current action the target is using, with icon texture and arrow between
        -- icon + action name and the right target name.
        if (gConfig.showTargetActionTracker and actionTextLeft ~= nil and actionTextRight ~= nil) then
            local iconTexture, actionName, targetName, resultText, resultColor = actionTracker.GetActionPartsForTargetIndex(targetIndex);
            if (iconTexture ~= nil and actionName ~= nil and actionName ~= '') then
                local baseX = startX + settings.barHeight / 2 + settings.topTextXOffset;  -- same as nameText X
                local baseY = startY + settings.barHeight + settings.bottomTextYOffset;   -- just under the bar

                -- Draw the status icon (casting/completed/interrupted)
                local iconSize = settings.arrowSize * 0.6;  -- match the arrow size used for action tracker
                imgui.SetCursorScreenPos({ baseX, baseY });
                imgui.Image(
                    tonumber(ffi.cast("uint32_t", iconTexture.image)),
                    { iconSize, iconSize }
                );

                -- Action name text right after the icon
                actionTextLeft:SetText(actionName);
                local leftSize = SIZE.new();
                actionTextLeft:GetTextSize(leftSize);

                local textX = baseX + iconSize + 4;  -- small gap after icon
                actionTextLeft:SetPositionX(textX);
                actionTextLeft:SetPositionY(baseY);
                actionTextLeft:SetVisible(true);

                -- Arrow texture position: horizontally after the action text,
                -- vertically centered using the actual text height
                local arrowX = textX + leftSize.cx + 4;  -- small gap after action text
                local arrowY = baseY + (leftSize.cy - iconSize) / 2 + 2;

                imgui.SetCursorScreenPos({ arrowX, arrowY });
                imgui.Image(
                    tonumber(ffi.cast("uint32_t", arrowTexture.image)),
                    { iconSize, iconSize }
                );

                -- Right side: target name
                if (targetName ~= nil and targetName ~= '') then
                    actionTextRight:SetText(targetName);
                    actionTextRight:SetPositionX(arrowX + iconSize + 4); -- gap after arrow
                    actionTextRight:SetPositionY(baseY);
                    actionTextRight:SetVisible(true);
                else
                    actionTextRight:SetVisible(false);
                end
                
                -- Result text (damage/healing)
                if (resultText ~= nil and resultText ~= '' and actionResultText ~= nil) then
                    actionResultText:SetText(resultText);
                    local rightSize = SIZE.new();
                    actionTextRight:GetTextSize(rightSize);
                    actionResultText:SetPositionX(arrowX + iconSize + 4 + rightSize.cx);
                    actionResultText:SetPositionY(baseY);
                    
                    -- Set color based on result type
                    if (resultColor == 'damage') then
                        actionResultText:SetColor(0xFFFF4444); -- Red for damage
                    elseif (resultColor == 'heal') then
                        actionResultText:SetColor(0xFF44FF44); -- Green for healing
                    else
                        actionResultText:SetColor(0xFFFFFFFF); -- White for status
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

        -- Draw buffs and debuffs
        local buffIds;
        local buffTimes = nil;

        if (targetEntity == playerEnt) then
            buffIds = player:GetBuffs();
        elseif (IsMemberOfParty(targetIndex)) then
            buffIds = statusHandler.get_member_status(playerTarget:GetServerId(0));
        elseif (isMonster) then
            buffIds, buffTimes = debuffHandler.GetActiveDebuffs(playerTarget:GetServerId(0));
        end

        imgui.NewLine();
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, {1, 3});

        -- Hide any existing debuff timer text objects
        for i = 1, 32 do
            local textObjName = "debuffText" .. tostring(i);
            local textObj = debuffTable[textObjName];
            if textObj then
                textObj:SetVisible(false);
            end
        end

        local buffsX = startX + settings.barHeight / 2;

        -- Base position for buffs: just under the target bar
        -- Add a little extra so they don't overlap, even when the action tracker is OFF
        local buffsY = startY + settings.barHeight + settings.bottomTextYOffset + 4; -- tweak this 4 as desired

        -- Push buffs further down only if the action tracker is enabled (and drawn)
        if (gConfig.showTargetActionTracker and actionTextLeft ~= nil and actionTextRight ~= nil) then
            buffsY = buffsY + settings.name_font_settings.font_height + 10; -- extra padding under action text
        end

        imgui.SetCursorScreenPos({ buffsX, buffsY });

        -- xOffset (6th arg) controls horizontal offset, so we pass nil and let
        -- the SetCursorScreenPos call above fully control position.
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

		-- Obtain our target of target (not always accurate)
		local totEntity;
		local totIndex
		if (targetEntity == playerEnt) then
			totIndex = targetIndex
			totEntity = targetEntity;
		end
		if (totEntity == nil) then
			totIndex = targetEntity.TargetedIndex;
			if (totIndex ~= nil) then
				totEntity = GetEntity(totIndex);
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
            imgui.Image(tonumber(ffi.cast("uint32_t", arrowTexture.image)), { settings.arrowSize, settings.arrowSize });
            imgui.SameLine();

            -- Position the ToT HP bar just to the right of the arrow
            local totX, _ = imgui.GetCursorScreenPos();
            local barY = totBaseY - (settings.totBarHeight / 2) + (settings.barHeight / 2) + settings.totBarOffset;

            imgui.SetCursorScreenPos({ totX, barY });

            local totStartX, totStartY = imgui.GetCursorScreenPos();

            -- Build the ToT bar color from the Bars-style target color
            local tr = bit.band(bit.rshift(totColor, 16), 0xFF);
            local tg = bit.band(bit.rshift(totColor, 8), 0xFF);
            local tb = bit.band(totColor, 0xFF);
            local totBarColor = string.format('#%02X%02X%02X', tr, tg, tb);

            progressbar.ProgressBar(
                { { totEntity.HPPercent / 100, { totBarColor, totBarColor } } },
                { settings.barWidth / 3, settings.totBarHeight },
                { decorate = gConfig.showTargetBarBookends }
            );

            -- ToT name above its mini-bar
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
	local winPosX, winPosY = imgui.GetWindowPos();
    imgui.End();
end

targetbar.Initialize = function(settings)
    percentText = fonts.new(settings.percent_font_settings);
	nameText = fonts.new(settings.name_font_settings);
	totNameText = fonts.new(settings.totName_font_settings);
	distText = fonts.new(settings.distance_font_settings);
	arrowTexture = LoadTexture("arrow");
    actionTextLeft  = fonts.new(settings.name_font_settings);
    actionTextRight = fonts.new(settings.name_font_settings);
    actionResultText = fonts.new(settings.name_font_settings);
    actionTextLeft:SetVisible(false);
    actionTextRight:SetVisible(false);
    actionResultText:SetVisible(false);

end

targetbar.UpdateFonts = function(settings)
    percentText:SetFontHeight(settings.percent_font_settings.font_height);
	nameText:SetFontHeight(settings.name_font_settings.font_height);
	totNameText:SetFontHeight(settings.totName_font_settings.font_height);
	distText:SetFontHeight(settings.distance_font_settings.font_height);
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

targetbar.SetHidden = function(hidden)
	if (hidden == true) then
		UpdateTextVisibility(false);
	end
end

return targetbar;