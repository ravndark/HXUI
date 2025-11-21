require ("common");
require('helpers');
local statusHandler = require('statushandler');
local imgui = require("imgui");

local config = {};

config.DrawWindow = function(us)
    imgui.PushStyleColor(ImGuiCol_WindowBg, {0,0.06,.16,.9});
	imgui.PushStyleColor(ImGuiCol_TitleBg, {0,0.06,.16, .7});
	imgui.PushStyleColor(ImGuiCol_TitleBgActive, {0,0.06,.16, .9});
	imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, {0,0.06,.16, .5});
    imgui.PushStyleColor(ImGuiCol_Header, {0,0.06,.16,.7});
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, {0,0.06,.16, .9});
    imgui.PushStyleColor(ImGuiCol_HeaderActive, {0,0.06,.16, 1});
    imgui.PushStyleColor(ImGuiCol_FrameBg, {0,0.06,.16, 1});
    imgui.SetNextWindowSize({ 600, 600 }, ImGuiCond_FirstUseEver);
    if(showConfig[1] and imgui.Begin(("HXUI Config"):fmt(addon.version), showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
        if(imgui.Button("Restore Defaults", { 130, 20 })) then
            ResetSettings();
            UpdateSettings();
        end
        imgui.SameLine();
        if(imgui.Button("Patch Notes", { 130, 20 })) then
            gConfig.patchNotesVer = -1;
            gShowPatchNotes = { true; }
            UpdateSettings();
        end
        imgui.BeginChild("Config Options", { 0, 0 }, true);
        if (imgui.CollapsingHeader("General")) then
            imgui.BeginChild("GeneralSettings", { 0, 210 }, true);
            if (imgui.Checkbox('Lock HUD Position', { gConfig.lockPositions })) then
                gConfig.lockPositions = not gConfig.lockPositions;
                UpdateSettings();
            end
            -- Status Icon Theme
            local status_theme_paths = statusHandler.get_status_theme_paths();
            if (imgui.BeginCombo('Status Icon Theme', gConfig.statusIconTheme)) then
                for i = 1,#status_theme_paths,1 do
                    local is_selected = i == gConfig.statusIconTheme;

                    if (imgui.Selectable(status_theme_paths[i], is_selected) and status_theme_paths[i] ~= gConfig.statusIconTheme) then
                        gConfig.statusIconTheme = status_theme_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The folder to pull status icons from. [HXUI\\assets\\status]');

            -- Job Icon Theme
            local job_theme_paths = statusHandler.get_job_theme_paths();
            if (imgui.BeginCombo('Job Icon Theme', gConfig.jobIconTheme)) then
                for i = 1,#job_theme_paths,1 do
                    local is_selected = i == gConfig.jobIconTheme;

                    if (imgui.Selectable(job_theme_paths[i], is_selected) and job_theme_paths[i] ~= gConfig.jobIconTheme) then
                        gConfig.jobIconTheme = job_theme_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The folder to pull job icons from. [HXUI\\assets\\jobs]');

            if (imgui.Checkbox('Show Health Bar Flash Effects', { gConfig.healthBarFlashEnabled })) then
                gConfig.healthBarFlashEnabled = not gConfig.healthBarFlashEnabled;
                UpdateSettings();
            end

            local noBookendRounding = { gConfig.noBookendRounding };
            if (imgui.SliderInt('Basic Bar Roundness', noBookendRounding, 0, 10)) then
                gConfig.noBookendRounding = noBookendRounding[1];
                UpdateSettings();
            end
            imgui.ShowHelp('For bars with no bookends, how round they should be.');

            local tooltipScale = { gConfig.tooltipScale };
            if (imgui.SliderFloat('Tooltip Scale', tooltipScale, 0.1, 3.0, '%.2f')) then
                gConfig.tooltipScale = tooltipScale[1];
                UpdateSettings();
            end
            imgui.ShowHelp('Scales the size of the tooltip. Note that text may appear blured if scaled too large.');

            if (imgui.Checkbox('Hide During Events', { gConfig.hideDuringEvents })) then
                gConfig.hideDuringEvents = not gConfig.hideDuringEvents;
                UpdateSettings();
            end

            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Player Bar")) then
            imgui.BeginChild("PlayerBarSettings", { 0, 210 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showPlayerBar })) then
                gConfig.showPlayerBar = not gConfig.showPlayerBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showPlayerBarBookends })) then
                gConfig.showPlayerBarBookends = not gConfig.showPlayerBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.playerBarHideDuringEvents })) then
                gConfig.playerBarHideDuringEvents = not gConfig.playerBarHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Always Show MP Bar', { gConfig.alwaysShowMpBar })) then
                gConfig.alwaysShowMpBar = not gConfig.alwaysShowMpBar;
                UpdateSettings();
            end
            imgui.ShowHelp('Always display the MP Bar even if your current jobs cannot cast spells.'); 
            local scaleX = { gConfig.playerBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.playerBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.playerBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.playerBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.playerBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.playerBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Pet Bar")) then
            imgui.BeginChild("PetBarSettings", { 0, 210 }, true);

            if (imgui.Checkbox('Enabled', { gConfig.showPetBar })) then
                gConfig.showPetBar = not gConfig.showPetBar;
                UpdateSettings();
            end

            -- Pet Name Position dropdown
            local petNamePositions = { 'Disabled', 'Side', 'Top', 'Bottom' };
            local currentPosition = gConfig.petBarNamePosition or 'Side';
            if (imgui.BeginCombo('Pet Name Position', currentPosition)) then
                for i = 1, #petNamePositions do
                    local is_selected = petNamePositions[i] == currentPosition;
                    if (imgui.Selectable(petNamePositions[i], is_selected)) then
                        gConfig.petBarNamePosition = petNamePositions[i];
                        UpdateSettings();
                    end
                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Position of the pet name: Disabled (hidden), Side (left of bar), Top (above bar), Bottom (below bar).');
			
            -- Pet Health Percent Position dropdown
            local petPercentPositions = { 'Disabled', 'Side', 'Top', 'Bottom' };
            local currentPercentPosition = gConfig.petBarPercentPosition or 'Side';
            if (imgui.BeginCombo('Health Percent Position', currentPercentPosition)) then
                for i = 1, #petPercentPositions do
                    local is_selected = petPercentPositions[i] == currentPercentPosition;
                    if (imgui.Selectable(petPercentPositions[i], is_selected)) then
                        gConfig.petBarPercentPosition = petPercentPositions[i];
                        UpdateSettings();
                    end
                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Position of the health percent: Disabled (hidden), Side (right of bar), Top (above bar), Bottom (below bar).');
			
			if (imgui.Checkbox('Hide During Events', { gConfig.petBarHideDuringEvents })) then
                gConfig.petBarHideDuringEvents = not gConfig.petBarHideDuringEvents;
                UpdateSettings();
            end

            local petScaleX = { gConfig.petBarScaleX };
            if (imgui.SliderFloat('Scale X', petScaleX, 0.1, 3.0, '%.1f')) then
                gConfig.petBarScaleX = petScaleX[1];
                UpdateSettings();
            end

            local petScaleY = { gConfig.petBarScaleY };
            if (imgui.SliderFloat('Scale Y', petScaleY, 0.1, 3.0, '%.1f')) then
                gConfig.petBarScaleY = petScaleY[1];
                UpdateSettings();
            end

            local petFontOffset = { gConfig.petBarFontOffset };
            if (imgui.SliderInt('Font Scale', petFontOffset, -5, 10)) then
                gConfig.petBarFontOffset = petFontOffset[1];
                UpdateSettings();
            end

            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Target Bar")) then
            imgui.BeginChild("TargetBarSettings", { 0, 380 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showTargetBar })) then
                gConfig.showTargetBar = not gConfig.showTargetBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Distance', { gConfig.showTargetDistance })) then
                gConfig.showTargetDistance = not gConfig.showTargetDistance;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showTargetBarBookends })) then
                gConfig.showTargetBarBookends = not gConfig.showTargetBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.targetBarHideDuringEvents })) then
                gConfig.targetBarHideDuringEvents = not gConfig.targetBarHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Enemy Id', { gConfig.showEnemyId })) then
                gConfig.showEnemyId = not gConfig.showEnemyId;
                UpdateSettings();
            end
            imgui.ShowHelp('Display the internal ID of the monster next to its name.'); 
            if (imgui.Checkbox('Always Show Health Percent', { gConfig.alwaysShowHealthPercent })) then
                gConfig.alwaysShowHealthPercent = not gConfig.alwaysShowHealthPercent;
                UpdateSettings();
            end
            imgui.ShowHelp('Always display the percent of HP remanining regardless if the target is an enemy or not.');
			
			if (imgui.Checkbox('Show Target Actions', { gConfig.showTargetActionTracker })) then
				gConfig.showTargetActionTracker = not gConfig.showTargetActionTracker;
				UpdateSettings();
			end
			imgui.ShowHelp('Show the current spell/ability line under the target bar.');
            if (imgui.Checkbox('Show SP Timer in Name', { gConfig.targetBarShowSPName })) then
                gConfig.targetBarShowSPName = not gConfig.targetBarShowSPName;
                UpdateSettings();
            end
            imgui.ShowHelp('Show special ability timer overlay in the target name when a SP is active.');

            local scaleX = { gConfig.targetBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.targetBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.targetBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.targetBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            local iconScale = { gConfig.targetBarIconScale };
            if (imgui.SliderFloat('Icon Scale', iconScale, 0.1, 3.0, '%.1f')) then
                gConfig.targetBarIconScale = iconScale[1];
                UpdateSettings();
            end
            local iconFontOffset = { gConfig.targetBarIconFontOffset };
            if (imgui.SliderInt('Icon Font Scale', iconFontOffset, -5, 10)) then
                gConfig.targetBarIconFontOffset = iconFontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
		        if (imgui.CollapsingHeader("Sub Target Bar")) then
            imgui.BeginChild("SubTargetBarSettings", { 0, 220 }, true);

			if (imgui.Checkbox('Enabled', { gConfig.subTargetBarLegacyBehavior })) then
				gConfig.subTargetBarLegacyBehavior = not gConfig.subTargetBarLegacyBehavior;
				UpdateSettings();
			end

            if (imgui.Checkbox('Show Distance', { gConfig.showSubTargetDistance })) then
                gConfig.showSubTargetDistance = not gConfig.showSubTargetDistance;
                UpdateSettings();
            end

            if (imgui.Checkbox('Show Bookends', { gConfig.showsubTargetBarBookends })) then
                gConfig.showsubTargetBarBookends = not gConfig.showsubTargetBarBookends;
                UpdateSettings();
            end

            local scaleX = { gConfig.subTargetBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.subTargetBarScaleX = scaleX[1];
                UpdateSettings();
            end

            local scaleY = { gConfig.subTargetBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.subTargetBarScaleY = scaleY[1];
                UpdateSettings();
            end

            local fontOffset = { gConfig.subTargetBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.subTargetBarFontOffset = fontOffset[1];
                UpdateSettings();
            end

            local iconScale = { gConfig.subTargetBarIconScale };
            if (imgui.SliderFloat('Icon Scale', iconScale, 0.1, 3.0, '%.1f')) then
                gConfig.subTargetBarIconScale = iconScale[1];
                UpdateSettings();
            end

            imgui.EndChild();
        end

		    if (imgui.CollapsingHeader("Focus Bar")) then
            imgui.BeginChild("FocusBarSettings", { 0, 390 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showFocusTargetBar })) then
                gConfig.showFocusTargetBar = not gConfig.showFocusTargetBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Distance', { gConfig.showFocusDistance })) then
                gConfig.showFocusDistance = not gConfig.showFocusDistance;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showFocusBarBookends })) then
                gConfig.showFocusBarBookends = not gConfig.showFocusBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.focusBarHideDuringEvents })) then
                gConfig.focusBarHideDuringEvents = not gConfig.focusBarHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Enemy Id', { gConfig.showEnemyId })) then
                gConfig.showEnemyId = not gConfig.showEnemyId;
                UpdateSettings();
            end
            imgui.ShowHelp('Display the internal ID of the monster next to its name.');
            if (imgui.Checkbox('Always Show Health Percent', { gConfig.alwaysShowHealthPercent })) then
                gConfig.alwaysShowHealthPercent = not gConfig.alwaysShowHealthPercent;
                UpdateSettings();
            end
            imgui.ShowHelp('Always display the percent of HP remaining regardless if the target is an enemy or not.');
			if (imgui.Checkbox('Show Focus Actions', { gConfig.showFocusActionTracker })) then
				gConfig.showFocusActionTracker = not gConfig.showFocusActionTracker;
				UpdateSettings();
			end
			imgui.ShowHelp('Show the current spell/ability line under the focus bar.');
            if (imgui.Checkbox('Show SP Timer in Name', { gConfig.focusBarShowSPName })) then
                gConfig.focusBarShowSPName = not gConfig.focusBarShowSPName;
                UpdateSettings();
            end
            imgui.ShowHelp('Show special ability timer overlay in the focus bar name when a SP is active.');

            local scaleX = { gConfig.focusBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.focusBarScaleX = scaleX[1];
                UpdateSettings();
            end

            local scaleY = { gConfig.focusBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.focusBarScaleY = scaleY[1];
                UpdateSettings();
            end

            local fontOffset = { gConfig.focusBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.focusBarFontOffset = fontOffset[1];
                UpdateSettings();
            end

            local iconScale = { gConfig.focusBarIconScale };
            if (imgui.SliderFloat('Icon Scale', iconScale, 0.1, 3.0, '%.1f')) then
                gConfig.focusBarIconScale = iconScale[1];
                UpdateSettings();
            end

            -- Shared with target bar; adjusts buff timer text under both bars
            local iconFontOffset = { gConfig.targetBarIconFontOffset };
            if (imgui.SliderInt('Icon Font Scale', iconFontOffset, -5, 10)) then
                gConfig.targetBarIconFontOffset = iconFontOffset[1];
                UpdateSettings();
            end

            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Enemy List")) then
            imgui.BeginChild("EnemyListSettings", { 0, 450 }, true);

            -- Enable/Disable
            if (imgui.Checkbox('Enabled', { gConfig.showEnemyList })) then
                gConfig.showEnemyList = not gConfig.showEnemyList;
                UpdateSettings();
            end

            imgui.Separator();

            -- Display Toggles
            if (imgui.Checkbox('Show Distance', { gConfig.showEnemyDistance })) then
                gConfig.showEnemyDistance = not gConfig.showEnemyDistance;
                UpdateSettings();
            end

            if (imgui.Checkbox('Show HP% Text', { gConfig.showEnemyHPPText })) then
                gConfig.showEnemyHPPText = not gConfig.showEnemyHPPText;
                UpdateSettings();
            end

            if (imgui.Checkbox('Show Bookends', { gConfig.showEnemyListBookends })) then
                gConfig.showEnemyListBookends = not gConfig.showEnemyListBookends;
                UpdateSettings();
            end

            if (imgui.Checkbox('Show SP Pulse Effect', { gConfig.enemyListShowSPPulse })) then
                gConfig.enemyListShowSPPulse = not gConfig.enemyListShowSPPulse;
                UpdateSettings();
            end
            imgui.ShowHelp('Enemy names pulse when they use a special ability.');

            imgui.Separator();

            -- Behavior Toggles
            if (imgui.Checkbox('Hide When Less Than 2 Enemies', { gConfig.hideEnemyListUnderTwo })) then
                gConfig.hideEnemyListUnderTwo = not gConfig.hideEnemyListUnderTwo;
                UpdateSettings();
            end
            imgui.ShowHelp('Only show the enemy list when there are 2 or more enemies.');

            if (imgui.Checkbox('Grow Upwards', { gConfig.enemyListGrowUpwards })) then
                gConfig.enemyListGrowUpwards = not gConfig.enemyListGrowUpwards;
                UpdateSettings();
            end
            imgui.ShowHelp('New enemies appear above earlier ones; window grows upward.');

            imgui.Separator();

            -- Dropdowns
            local statusThemeItems = T{
                [0] = 'HorizonXI-L',
                [1] = 'HorizonXI-R',
                [2] = 'FFXI',
                [3] = 'FFXI-R',
                [4] = 'Disabled'
            };
            gConfig.enemyListStatusTheme = math.clamp(gConfig.enemyListStatusTheme, 0, 4);
            if (imgui.BeginCombo('Status Theme', statusThemeItems[gConfig.enemyListStatusTheme])) then
                for i = 0, #statusThemeItems do
                    local is_selected = (i == gConfig.enemyListStatusTheme);
                    if (imgui.Selectable(statusThemeItems[i], is_selected) and gConfig.enemyListStatusTheme ~= i) then
                        gConfig.enemyListStatusTheme = i;
                        UpdateSettings();
                    end
                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('Theme for debuff icons on enemies.');

            imgui.Separator();

            -- Sliders
            local entrySpacing = { gConfig.enemyListEntrySpacing };
            if (imgui.SliderInt('Entry Spacing', entrySpacing, -10, 30)) then
                gConfig.enemyListEntrySpacing = entrySpacing[1];
                UpdateSettings();
            end

            local bgAlpha = { gConfig.enemyListBgAlpha };
            if (imgui.SliderFloat('Background Alpha', bgAlpha, 0.0, 1.0, '%.2f')) then
                gConfig.enemyListBgAlpha = bgAlpha[1];
                UpdateSettings();
            end

            local scaleX = { gConfig.enemyListScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListScaleX = scaleX[1];
                UpdateSettings();
            end

            local scaleY = { gConfig.enemyListScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListScaleY = scaleY[1];
                UpdateSettings();
            end

            local fontScale = { gConfig.enemyListFontScale };
            if (imgui.SliderFloat('Font Scale', fontScale, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListFontScale = fontScale[1];
                UpdateSettings();
            end

            local iconScale = { gConfig.enemyListIconScale };
            if (imgui.SliderFloat('Icon Scale', iconScale, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListIconScale = iconScale[1];
                UpdateSettings();
            end

            local debuffScale = { gConfig.enemyListDebuffScale };
            if (imgui.SliderFloat('Debuff Icon Scale', debuffScale, 0.1, 3.0, '%.1f')) then
                gConfig.enemyListDebuffScale = debuffScale[1];
                UpdateSettings();
            end

            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Party List")) then
            imgui.BeginChild("PartyListSettings", { 0, 460 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showPartyList })) then
                gConfig.showPartyList = not gConfig.showPartyList;
                UpdateSettings();
            end
            if (imgui.Checkbox('Preview Full Party (when config open)', { gConfig.partyListPreview })) then
                gConfig.partyListPreview = not gConfig.partyListPreview;
                UpdateSettings();
            end
            if (imgui.Checkbox('Flash TP at 100%', { gConfig.partyListFlashTP })) then
                gConfig.partyListFlashTP = not gConfig.partyListFlashTP;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Distance', { gConfig.showPartyListDistance })) then
                gConfig.showPartyListDistance = not gConfig.showPartyListDistance;
                UpdateSettings();
            end
            local distance = { gConfig.partyListDistanceHighlight };
            if (imgui.SliderFloat('Distance Highlighting', distance, 0.0, 50.0, '%.1f')) then
                gConfig.partyListDistanceHighlight = distance[1];
                UpdateSettings();
            end
			if (imgui.Checkbox('Show SP Timer in Names', { gConfig.partyListShowSPName })) then
                gConfig.partyListShowSPName = not gConfig.partyListShowSPName;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showPartyListBookends })) then
                gConfig.showPartyListBookends = not gConfig.showPartyListBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show When Solo', { gConfig.showPartyListWhenSolo })) then
                gConfig.showPartyListWhenSolo = not gConfig.showPartyListWhenSolo;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Title', { gConfig.showPartyListTitle })) then
                gConfig.showPartyListTitle = not gConfig.showPartyListTitle;
                UpdateSettings();
            end
            if (imgui.Checkbox('Hide During Events', { gConfig.partyListHideDuringEvents })) then
                gConfig.partyListHideDuringEvents = not gConfig.partyListHideDuringEvents;
                UpdateSettings();
            end
            if (imgui.Checkbox('Align Bottom', { gConfig.partyListAlignBottom })) then
                gConfig.partyListAlignBottom = not gConfig.partyListAlignBottom;
                UpdateSettings();
            end
            if (imgui.Checkbox('Expand Height', { gConfig.partyListExpandHeight })) then
                gConfig.partyListExpandHeight = not gConfig.partyListExpandHeight;
                UpdateSettings();
            end
            if (imgui.Checkbox('Alliance Windows', { gConfig.partyListAlliance })) then
                gConfig.partyListAlliance = not gConfig.partyListAlliance;
                UpdateSettings();
            end

            -- Background
            local bgScale = { gConfig.partyListBgScale };
            if (imgui.SliderFloat('Background Scale', bgScale, 0.1, 3.0, '%.2f')) then
                gConfig.partyListBgScale = bgScale[1];
                UpdateSettings();
            end

            local bgColor = { gConfig.partyListBgColor[1] / 255, gConfig.partyListBgColor[2] / 255, gConfig.partyListBgColor[3] / 255, gConfig.partyListBgColor[4] / 255 };
            if (imgui.ColorEdit4('Background Color', bgColor, ImGuiColorEditFlags_AlphaBar)) then
                gConfig.partyListBgColor[1] = bgColor[1] * 255;
                gConfig.partyListBgColor[2] = bgColor[2] * 255;
                gConfig.partyListBgColor[3] = bgColor[3] * 255;
                gConfig.partyListBgColor[4] = bgColor[4] * 255;
                UpdateSettings();
            end

            local borderColor = { gConfig.partyListBorderColor[1] / 255, gConfig.partyListBorderColor[2] / 255, gConfig.partyListBorderColor[3] / 255, gConfig.partyListBorderColor[4] / 255 };
            if (imgui.ColorEdit4('Border Color', borderColor, ImGuiColorEditFlags_AlphaBar)) then
                gConfig.partyListBorderColor[1] = borderColor[1] * 255;
                gConfig.partyListBorderColor[2] = borderColor[2] * 255;
                gConfig.partyListBorderColor[3] = borderColor[3] * 255;
                gConfig.partyListBorderColor[4] = borderColor[4] * 255;
                UpdateSettings();
            end

            local bg_theme_paths = statusHandler.get_background_paths();
            if (imgui.BeginCombo('Background', gConfig.partyListBackgroundName)) then
                for i = 1,#bg_theme_paths,1 do
                    local is_selected = i == gConfig.partyListBackgroundName;

                    if (imgui.Selectable(bg_theme_paths[i], is_selected) and bg_theme_paths[i] ~= gConfig.partyListBackgroundName) then
                        gConfig.partyListBackgroundName = bg_theme_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The image to use for the party list background. [Resolution: 512x512 @ HXUI\\assets\\backgrounds]'); 
            
            -- Arrow
            local cursor_paths = statusHandler.get_cursor_paths();
            if (imgui.BeginCombo('Cursor', gConfig.partyListCursor)) then
                for i = 1,#cursor_paths,1 do
                    local is_selected = i == gConfig.partyListCursor;

                    if (imgui.Selectable(cursor_paths[i], is_selected) and cursor_paths[i] ~= gConfig.partyListCursor) then
                        gConfig.partyListCursor = cursor_paths[i];
                        statusHandler.clear_cache();
                        UpdateSettings();
                    end

                    if (is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end
            imgui.ShowHelp('The image to use for the party list cursor. [@ HXUI\\assets\\cursors]'); 
            

            local comboBoxItems = {};
            comboBoxItems[0] = 'HorizonXI';
            comboBoxItems[1] = 'HorizonXI-R';
            comboBoxItems[2] = 'FFXIV';
            comboBoxItems[3] = 'FFXI';
            comboBoxItems[4] = 'FFXI-R';
            comboBoxItems[5] = 'Disabled';
            gConfig.partyListStatusTheme = math.clamp(gConfig.partyListStatusTheme, 0, 5);
            if(imgui.BeginCombo('Status Theme', comboBoxItems[gConfig.partyListStatusTheme])) then
                for i = 0,#comboBoxItems do
                    local is_selected = i == gConfig.partyListStatusTheme;

                    if (imgui.Selectable(comboBoxItems[i], is_selected) and gConfig.partyListStatusTheme ~= i) then
                        gConfig.partyListStatusTheme = i;
                        UpdateSettings();
                    end
                    if(is_selected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end

                        local buffScale = { gConfig.partyListBuffScale };
            if (imgui.SliderFloat('Status Icon Scale', buffScale, 0.1, 3.0, '%.1f')) then
                gConfig.partyListBuffScale = buffScale[1];
                UpdateSettings();
            end

            -- NEW: status blacklist editor
            local blacklistStr = { gConfig.partyListStatusBlacklist or '' };
            if (imgui.InputText('Status Blacklist##PartyList', blacklistStr, 512)) then
                gConfig.partyListStatusBlacklist = blacklistStr[1];
                UpdateSettings();
            end
            imgui.ShowHelp('Comma-separated list of status IDs to HIDE from the party list. Example: 71, 72, 73');

            imgui.EndChild();

            if true then
                imgui.BeginChild('PartyListSettings.Party1', { 0, 230 }, true);
                imgui.Text('Party');

                if (imgui.Checkbox('Show TP', { gConfig.partyListTP })) then
                    gConfig.partyListTP = not gConfig.partyListTP;
                    UpdateSettings();
                end

                local minRows = { gConfig.partyListMinRows };
                if (imgui.SliderInt('Min Rows', minRows, 1, 6)) then
                    gConfig.partyListMinRows = minRows[1];
                    UpdateSettings();
                end

                local scaleX = { gConfig.partyListScaleX };
                if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.2f')) then
                    gConfig.partyListScaleX = scaleX[1];
                    UpdateSettings();
                end
                local scaleY = { gConfig.partyListScaleY };
                if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.2f')) then
                    gConfig.partyListScaleY = scaleY[1];
                    UpdateSettings();
                end

                local fontOffset = { gConfig.partyListFontOffset };
                if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                    gConfig.partyListFontOffset = fontOffset[1];
                    UpdateSettings();
                end

                local jobIconScale = { gConfig.partyListJobIconScale };
                if (imgui.SliderFloat('Job Icon Scale', jobIconScale, 0.1, 3.0, '%.1f')) then
                    gConfig.partyListJobIconScale = jobIconScale[1];
                    UpdateSettings();
                end

                local entrySpacing = { gConfig.partyListEntrySpacing };
                if (imgui.SliderInt('Entry Spacing', entrySpacing, -20, 20)) then
                    gConfig.partyListEntrySpacing = entrySpacing[1];
                    UpdateSettings();
                end

                imgui.EndChild();
            end

            if (gConfig.partyListAlliance) then
                imgui.BeginChild('PartyListSettings.Party2', { 0, 205 }, true);
                imgui.Text('Party B (Alliance)');

                if (imgui.Checkbox('Show TP', { gConfig.partyList2TP })) then
                    gConfig.partyList2TP = not gConfig.partyList2TP;
                    UpdateSettings();
                end

                local scaleX = { gConfig.partyList2ScaleX };
                if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.2f')) then
                    gConfig.partyList2ScaleX = scaleX[1];
                    UpdateSettings();
                end
                local scaleY = { gConfig.partyList2ScaleY };
                if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.2f')) then
                    gConfig.partyList2ScaleY = scaleY[1];
                    UpdateSettings();
                end

                local fontOffset = { gConfig.partyList2FontOffset };
                if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                    gConfig.partyList2FontOffset = fontOffset[1];
                    UpdateSettings();
                end

                local jobIconScale = { gConfig.partyList2JobIconScale };
                if (imgui.SliderFloat('Job Icon Scale', jobIconScale, 0.1, 3.0, '%.1f')) then
                    gConfig.partyList2JobIconScale = jobIconScale[1];
                    UpdateSettings();
                end

                local entrySpacing = { gConfig.partyList2EntrySpacing };
                if (imgui.SliderInt('Entry Spacing', entrySpacing, -20, 20)) then
                    gConfig.partyList2EntrySpacing = entrySpacing[1];
                    UpdateSettings();
                end

                imgui.EndChild();
            end

            if (gConfig.partyListAlliance) then
                imgui.BeginChild('PartyListSettings.Party3', { 0, 205 }, true);
                imgui.Text('Party C (Alliance)');

                if (imgui.Checkbox('Show TP', { gConfig.partyList3TP })) then
                    gConfig.partyList3TP = not gConfig.partyList3TP;
                    UpdateSettings();
                end

                local scaleX = { gConfig.partyList3ScaleX };
                if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.2f')) then
                    gConfig.partyList3ScaleX = scaleX[1];
                    UpdateSettings();
                end
                local scaleY = { gConfig.partyList3ScaleY };
                if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.2f')) then
                    gConfig.partyList3ScaleY = scaleY[1];
                    UpdateSettings();
                end

                local fontOffset = { gConfig.partyList3FontOffset };
                if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                    gConfig.partyList3FontOffset = fontOffset[1];
                    UpdateSettings();
                end

                local jobIconScale = { gConfig.partyList3JobIconScale };
                if (imgui.SliderFloat('Job Icon Scale', jobIconScale, 0.1, 3.0, '%.1f')) then
                    gConfig.partyList3JobIconScale = jobIconScale[1];
                    UpdateSettings();
                end

                local entrySpacing = { gConfig.partyList3EntrySpacing };
                if (imgui.SliderInt('Entry Spacing', entrySpacing, -20, 20)) then
                    gConfig.partyList3EntrySpacing = entrySpacing[1];
                    UpdateSettings();
                end

                imgui.EndChild();
            end
        end
        if (imgui.CollapsingHeader("Exp Bar")) then
            imgui.BeginChild("ExpBarSettings", { 0, 300 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showExpBar })) then
                gConfig.showExpBar = not gConfig.showExpBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Limit Points Mode', { gConfig.expBarLimitPointsMode })) then
                gConfig.expBarLimitPointsMode = not gConfig.expBarLimitPointsMode;
                UpdateSettings();
            end
            imgui.ShowHelp('Shows Limit Points if character is set to earn Limit Points in the game.');
            if (imgui.Checkbox('Inline Mode', { gConfig.expBarInlineMode })) then
                gConfig.expBarInlineMode = not gConfig.expBarInlineMode;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showExpBarBookends })) then
                gConfig.showExpBarBookends = not gConfig.showExpBarBookends;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Text', { gConfig.expBarShowText })) then
                gConfig.expBarShowText = not gConfig.expBarShowText;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Percent', { gConfig.expBarShowPercent })) then
                gConfig.expBarShowPercent = not gConfig.expBarShowPercent;
                UpdateSettings();
            end
            local scaleX = { gConfig.expBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.2f')) then
                gConfig.expBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.expBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.2f')) then
                gConfig.expBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local textScaleX = { gConfig.expBarTextScaleX };
            if (imgui.SliderFloat('Text Scale X', textScaleX, 0.1, 3.0, '%.2f')) then
                gConfig.expBarTextScaleX = textScaleX[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.expBarFontOffset };
            if (imgui.SliderInt('Font Height', fontOffset, -5, 10)) then
                gConfig.expBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Gil Tracker")) then
            imgui.BeginChild("GilTrackerSettings", { 0, 160 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showGilTracker })) then
                gConfig.showGilTracker = not gConfig.showGilTracker;
                UpdateSettings();
            end
            local scale = { gConfig.gilTrackerScale };
            if (imgui.SliderFloat('Scale', scale, 0.1, 3.0, '%.1f')) then
                gConfig.gilTrackerScale = scale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.gilTrackerFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.gilTrackerFontOffset = fontOffset[1];
                UpdateSettings();
            end
            if (imgui.Checkbox('Right Align', { gConfig.gilTrackerRightAlign })) then
                gConfig.gilTrackerRightAlign = not gConfig.gilTrackerRightAlign;
                UpdateSettings();
            end
            local posOffset = { gConfig.gilTrackerPosOffset[1], gConfig.gilTrackerPosOffset[2] };
            if (imgui.InputInt2('Position Offset', posOffset)) then
                gConfig.gilTrackerPosOffset[1] = posOffset[1];
                gConfig.gilTrackerPosOffset[2] = posOffset[2];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Inventory Tracker")) then
            imgui.BeginChild("InventoryTrackerSettings", { 0, 210 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showInventoryTracker })) then
                gConfig.showInventoryTracker = not gConfig.showInventoryTracker;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Count', { gConfig.inventoryShowCount })) then
                gConfig.inventoryShowCount = not gConfig.inventoryShowCount;
                UpdateSettings();
            end
            local columnCount = { gConfig.inventoryTrackerColumnCount };
            if (imgui.SliderInt('Columns', columnCount, 1, 80)) then
                gConfig.inventoryTrackerColumnCount = columnCount[1];
                UpdateSettings();
            end
            local rowCount = { gConfig.inventoryTrackerRowCount };
            if (imgui.SliderInt('Rows', rowCount, 1, 80)) then
                gConfig.inventoryTrackerRowCount = rowCount[1];
                UpdateSettings();
            end
            local opacity = { gConfig.inventoryTrackerOpacity };
            if (imgui.SliderFloat('Opacity', opacity, 0, 1.0, '%.2f')) then
                gConfig.inventoryTrackerOpacity = opacity[1];
                UpdateSettings();
            end
            local scale = { gConfig.inventoryTrackerScale };
            if (imgui.SliderFloat('Scale', scale, 0.1, 3.0, '%.1f')) then
                gConfig.inventoryTrackerScale = scale[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.inventoryTrackerFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.inventoryTrackerFontOffset = fontOffset[1];
                UpdateSettings();
            end
            imgui.EndChild();
        end
        if (imgui.CollapsingHeader("Cast Bar")) then
            imgui.BeginChild("CastBarSettings", { 0, 320 }, true);
            if (imgui.Checkbox('Enabled', { gConfig.showCastBar })) then
                gConfig.showCastBar = not gConfig.showCastBar;
                UpdateSettings();
            end
            if (imgui.Checkbox('Show Bookends', { gConfig.showCastBarBookends })) then
                gConfig.showCastBarBookends = not gConfig.showCastBarBookends;
                UpdateSettings();
            end
            local scaleX = { gConfig.castBarScaleX };
            if (imgui.SliderFloat('Scale X', scaleX, 0.1, 3.0, '%.1f')) then
                gConfig.castBarScaleX = scaleX[1];
                UpdateSettings();
            end
            local scaleY = { gConfig.castBarScaleY };
            if (imgui.SliderFloat('Scale Y', scaleY, 0.1, 3.0, '%.1f')) then
                gConfig.castBarScaleY = scaleY[1];
                UpdateSettings();
            end
            local fontOffset = { gConfig.castBarFontOffset };
            if (imgui.SliderInt('Font Scale', fontOffset, -5, 10)) then
                gConfig.castBarFontOffset = fontOffset[1];
                UpdateSettings();
            end
            if (imgui.Checkbox('Enable Fast Cast / True Display', { gConfig.castBarFastCastEnabled })) then
                gConfig.castBarFastCastEnabled = not gConfig.castBarFastCastEnabled;
                UpdateSettings();
            end
            local castBarFCRDMSJ = { gConfig.castBarFastCastRDMSJ };
            if (imgui.SliderFloat('Fast Cast - RDM SubJob', castBarFCRDMSJ, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCastRDMSJ = castBarFCRDMSJ[1];
                UpdateSettings();
            end
            local castBarFC1 = { gConfig.castBarFastCast[1] };
            if (imgui.SliderFloat('Fast Cast - WAR', castBarFC1, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[1] = castBarFC1[1];
                UpdateSettings();
            end
            local castBarFC2 = { gConfig.castBarFastCast[2] };
            if (imgui.SliderFloat('Fast Cast - MNK', castBarFC2, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[2] = castBarFC2[1];
                UpdateSettings();
            end
            local castBarFC3 = { gConfig.castBarFastCast[3] };
            if (imgui.SliderFloat('Fast Cast - WHM', castBarFC3, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[3] = castBarFC3[1];
                UpdateSettings();
            end
            local castBarFC4 = { gConfig.castBarFastCast[4] };
            if (imgui.SliderFloat('Fast Cast - BLM', castBarFC4, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[4] = castBarFC4[1];
                UpdateSettings();
            end
            local castBarFC5 = { gConfig.castBarFastCast[5] };
            if (imgui.SliderFloat('Fast Cast - RDM', castBarFC5, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[5] = castBarFC5[1];
                UpdateSettings();
            end
            local castBarFC6 = { gConfig.castBarFastCast[6] };
            if (imgui.SliderFloat('Fast Cast - THF', castBarFC6, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[6] = castBarFC6[1];
                UpdateSettings();
            end
            local castBarFC7 = { gConfig.castBarFastCast[7] };
            if (imgui.SliderFloat('Fast Cast - PLD', castBarFC7, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[7] = castBarFC7[1];
                UpdateSettings();
            end
            local castBarFC8 = { gConfig.castBarFastCast[8] };
            if (imgui.SliderFloat('Fast Cast - DRK', castBarFC8, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[8] = castBarFC8[1];
                UpdateSettings();
            end
            local castBarFC9 = { gConfig.castBarFastCast[9] };
            if (imgui.SliderFloat('Fast Cast - BST', castBarFC9, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[9] = castBarFC9[1];
                UpdateSettings();
            end
            local castBarFC10 = { gConfig.castBarFastCast[10] };
            if (imgui.SliderFloat('Fast Cast - BRD', castBarFC10, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[10] = castBarFC10[1];
                UpdateSettings();
            end
            local castBarFC11 = { gConfig.castBarFastCast[11] };
            if (imgui.SliderFloat('Fast Cast - RNG', castBarFC11, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[11] = castBarFC11[1];
                UpdateSettings();
            end
            local castBarFC12 = { gConfig.castBarFastCast[12] };
            if (imgui.SliderFloat('Fast Cast - SAM', castBarFC12, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[12] = castBarFC12[1];
                UpdateSettings();
            end
            local castBarFC13 = { gConfig.castBarFastCast[13] };
            if (imgui.SliderFloat('Fast Cast - NIN', castBarFC13, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[13] = castBarFC13[1];
                UpdateSettings();
            end
            local castBarFC14 = { gConfig.castBarFastCast[14] };
            if (imgui.SliderFloat('Fast Cast - DRG', castBarFC14, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[14] = castBarFC14[1];
                UpdateSettings();
            end
            local castBarFC15 = { gConfig.castBarFastCast[15] };
            if (imgui.SliderFloat('Fast Cast - SMN', castBarFC15, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[15] = castBarFC15[1];
                UpdateSettings();
            end
            local castBarFC16 = { gConfig.castBarFastCast[16] };
            if (imgui.SliderFloat('Fast Cast - BLU', castBarFC16, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[16] = castBarFC16[1];
                UpdateSettings();
            end
            local castBarFC17 = { gConfig.castBarFastCast[17] };
            if (imgui.SliderFloat('Fast Cast - COR', castBarFC17, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[17] = castBarFC17[1];
                UpdateSettings();
            end
            local castBarFC18 = { gConfig.castBarFastCast[18] };
            if (imgui.SliderFloat('Fast Cast - PUP', castBarFC18, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[18] = castBarFC18[1];
                UpdateSettings();
            end
            local castBarFC19 = { gConfig.castBarFastCast[19] };
            if (imgui.SliderFloat('Fast Cast - DNC', castBarFC19, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[19] = castBarFC19[1];
                UpdateSettings();
            end
            local castBarFC20 = { gConfig.castBarFastCast[20] };
            if (imgui.SliderFloat('Fast Cast - SCH', castBarFC20, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[20] = castBarFC20[1];
                UpdateSettings();
            end
            local castBarFC21 = { gConfig.castBarFastCast[21] };
            if (imgui.SliderFloat('Fast Cast - GEO', castBarFC21, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[21] = castBarFC21[1];
                UpdateSettings();
            end
            local castBarFC22 = { gConfig.castBarFastCast[22] };
            if (imgui.SliderFloat('Fast Cast - RUN', castBarFC22, 0.00, 1.00, '%.2f')) then
                gConfig.castBarFastCast[22] = castBarFC22[1];
                UpdateSettings();
            end


            imgui.EndChild();
        end
        imgui.EndChild();
    end
    imgui.PopStyleColor(8);
	imgui.End();
end

return config;