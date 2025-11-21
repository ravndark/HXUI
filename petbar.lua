require('common');
require('helpers');
local imgui = require('imgui');
local fonts = require('fonts');
local progressbar = require('progressbar');

local hpText;
local nameText;
local resetPosNextFrame = false;

local petbar = {};

local function UpdateTextVisibility(visible)
    hpText:SetVisible(visible);
    nameText:SetVisible(visible);
end

petbar.DrawWindow = function(settings)
    -- Create fake pet data for preview mode
    local petEntity = nil;
    local hpp = 0;
    
    if (showConfig[1]) then
        -- Use preview data when config menu is open
        petEntity = {
            Name = "Preview Pet",
            HPPercent = 75
        };
        hpp = 75;
    else
        -- Get the player entity
        local playerEnt = GetPlayerEntity();
        if (playerEnt == nil) then
            UpdateTextVisibility(false);
            return;
        end

        -- Get the pet entity
        petEntity = GetEntity(playerEnt.PetTargetIndex);
        if (petEntity == nil or petEntity.Name == nil or petEntity.HPPercent == nil) then
            -- No pet or invalid entity => hide bar
            UpdateTextVisibility(false);
            return;
        end

        -- Calculate HP percentage
        hpp = petEntity.HPPercent or 0;
        if (hpp < 0) then
            hpp = 0;
        elseif (hpp > 100) then
            hpp = 100;
        end
    end

    -- Get HP color and gradient using the same function as other bars
    local hpNameColor, hpGradient = GetHpColors(hpp / 100);

    UpdateTextVisibility(true);

    -- Draw the pet window
    if (resetPosNextFrame) then
        imgui.SetNextWindowPos({0, 0});
        resetPosNextFrame = false;
    end

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

    if (imgui.Begin('HXUI:PetBar', true, windowFlags)) then
        -- Build HP percent data with gradient, same format as playerbar/targetbar
        local hpPercentData = {{hpp / 100, hpGradient}};

        -- Get cursor position for text placement
        local startX, startY = imgui.GetCursorScreenPos();

        -- Draw the HP bar using progressbar library (same as playerbar/targetbar)
        progressbar.ProgressBar(hpPercentData, {settings.barWidth, settings.barHeight}, {decorate = false});

        -- Position pet name text based on setting
        if (nameText ~= nil) then
            local namePosition = gConfig.petBarNamePosition or 'Side';
            
            -- Handle legacy setting migration
            if (gConfig.petBarShowName == false and namePosition == 'Side') then
                namePosition = 'Disabled';
            end
            
            if (namePosition ~= 'Disabled') then
                -- Get text size for proper positioning
                local nameSize = SIZE.new();
                nameText:SetText(petEntity.Name);
                nameText:GetTextSize(nameSize);
                
                if (namePosition == 'Side') then
                    -- Position to the left of the bar (original behavior)
                    nameText:SetPositionX(startX - settings.barSpacing);
                    nameText:SetPositionY(startY + settings.textYOffset);
                elseif (namePosition == 'Top') then
                    -- Position above the bar (same style as targetbar)
                    -- Add nameSize.cx to anchor from the left edge, extending right
                    nameText:SetPositionX(startX + settings.barHeight / 2 + (settings.topTextXOffset or 0) + nameSize.cx);
                    nameText:SetPositionY(startY - (settings.topTextYOffset or 0) - nameSize.cy);
                elseif (namePosition == 'Bottom') then
                    -- Position below the bar
                    -- Add nameSize.cx to anchor from the left edge, extending right
                    nameText:SetPositionX(startX + settings.barHeight / 2 + (settings.topTextXOffset or 0) + nameSize.cx);
                    nameText:SetPositionY(startY + settings.barHeight + (settings.bottomTextYOffset or 2));
                end
                
                nameText:SetColor(hpNameColor);
                nameText:SetVisible(true);
            else
                nameText:SetVisible(false);
            end
        end

        -- Position HP percentage text based on setting
        if (hpText ~= nil) then
            local hpPosition = gConfig.petBarPercentPosition or 'Side';
            
            -- Handle legacy setting migration
            if (gConfig.petBarShowPercent == false and hpPosition == 'Side') then
                hpPosition = 'Disabled';
            end
            
            if (hpPosition ~= 'Disabled') then
                -- Set text first to get its size
                local hpString = string.format('%d%%', hpp);
                hpText:SetText(hpString);
                
                local hpSize = SIZE.new();
                hpText:GetTextSize(hpSize);
                
                if (hpPosition == 'Side') then
                    -- Position to the right of the bar (original behavior)
                    hpText:SetPositionX(startX + settings.barWidth + settings.barSpacing + hpSize.cx);
                    hpText:SetPositionY(startY + settings.textYOffset);
                elseif (hpPosition == 'Top') then
                    -- Position above the bar on the right side (same style as targetbar)
                    -- Text extends to the left from the right edge
                    hpText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - (settings.topTextXOffset or 0));
                    hpText:SetPositionY(startY - (settings.topTextYOffset or 0) - hpSize.cy);
                elseif (hpPosition == 'Bottom') then
                    -- Position below the bar on the right side
                    -- Text extends to the left from the right edge
                    hpText:SetPositionX(startX + settings.barWidth - settings.barHeight / 2 - (settings.bottomTextXOffset or 0));
                    hpText:SetPositionY(startY + settings.barHeight + (settings.bottomTextYOffset or 2));
                end
                
                hpText:SetColor(hpNameColor);
                hpText:SetVisible(true);
            else
                hpText:SetVisible(false);
            end
        end
    end
    imgui.End();
end

petbar.Initialize = function(settings)
    hpText = fonts.new(settings.font_settings);
    nameText = fonts.new(settings.font_settings);
end

petbar.UpdateFonts = function(settings)
    hpText:SetFontHeight(settings.font_settings.font_height);
    nameText:SetFontHeight(settings.font_settings.font_height);
end

petbar.SetHidden = function(hidden)
    if (hidden == true) then
        UpdateTextVisibility(false);
    end
end

return petbar;