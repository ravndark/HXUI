# Updated HXUI

This is a fork of Rag's HXUI (https://github.com/yzyii/HXUI)

It includes the following:

- Rag's changes and combines from other forks
- Implemented a Focus bar.  This create a new target bar that locks on to whatever your current target is.  After focusing your target, you can drop target or change targett and it will continue to show the target in the focus bar.  Live updating everything as long as it is within range of the game to see.
  - Accessible by targeting something and doing "/hxui focus".  Can be cleared by typing "/hxui clearfocus"
- SubTarget bar.  Adds a sub target bar to HXUI.  When using this bar, it creates a new bar on screen that shows who your sub target is, while maintaining your normal target bar.  Can be toggled between this or legacy HXUI SubTarget
- Added an Action Tracker.  This can be toggled on or off.  This tracks the actiton the target is using (works with focus target as well).  It will show the spell/ability/weaponskill that the target is using and who it is using it on.  It will also track the success and failure and indicate this with icons.
- Added new Party List status themes.  FFXI now has a FFXI-R option to move it to the right.  It now also splits the buffs and debuffs like the horizon buff option did to make it easier to identify.  The FFXIV option has also been changed to show debuffs first and then buffs to make them more visible.
  - Buffs are now visible when you have the config menu open and it shows random buffs and debuffs (at least one of each) so you can see how the status theme looks without closing the config menu.
- Added an SP ability tracker.  Tracks SP/2hr abilities on the target/focus and party list.  If a 2hr/SP ability is active on the target (Monster or Player) it will flash and rotate between the name and 2hr/SP ability.  Includes a timer to show how long it lasts.
- Changed colors of Bars to stand out a little more.  Blue = Player / White = Player / Cyan = Party/Alliance / Red = Claimed Mob / Pinkish = Alliance claimed / Purplish = Claimed by other.  Party List still uses the the original HXUI color.
- Added Pet Bar
- Added SP features to Enemylist, as well as new optiotns in the config menu for custotmtization
- More planned

**_These Features are being added with the use of AI_**
