local addonName, ns = ...
if ns.off then return end
local L = ns.L
local TITLE = "Pylos Ranks"

local PREFIX = "|cff71d5ff" .. TITLE .. "|r: "
local BANK = Enum.SpellBookSpellBank.Player
local NUM_ACTION_SLOTS = 180
local ROW_HEIGHT = 22
local LOADING_GRACE = 3 -- seconds after PLAYER_ENTERING_WORLD in which bar changes come from the game

local db -- PylosRanksDB from ADDON_LOADED on
local blacklist -- spellID -> label "Name (Rank)", per character in PylosRanksCharDB
local outdatedShown -- the minimap button hint is on (ns.SetAlert)

local spells = {}   -- active spells of the spellbook, all ranks: { id, name, rank, label, search, order, ranked }
local known = {}    -- spellID -> entry of spells
local best = {}     -- name -> spellID of the highest known rank, false if ambiguous
local reported = {} -- spellID -> target rank for which "ignored" was already printed
local failed = {}   -- slot -> target rank that could not be placed (prevents endless loops)
local askSlots = {} -- slot -> true: changed since the last scan, a low rank there is asked about
local asking = {}   -- spellID -> true while the question about this spell is open
local askQueue = {} -- spells with an open question; the first one is in the dialog
local confirmed = {} -- spellID -> true: question answered with "Replace"
local forceReplace  -- the next scan replaces without asking (learned, login, click)
local scanQueued
local hintQueued
local pendingAfterCombat -- a scan fell into combat and runs when combat ends
local lastSpellCount     -- spellbook size at the last SPELLS_CHANGED
local loading = true     -- until shortly after PLAYER_ENTERING_WORLD: bar changes come from the game
local loadingToken = 0   -- only the timer of the latest loading screen ends loading

-- secret values (in combat) must not be touched
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

-- The spellbook lists all ranks; the UI hides low ones via IsSpellBookItemLowRank.
local function ReadSpellBook()
    wipe(spells)
    wipe(known)
    wipe(best)
    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        for slot = (line and line.itemIndexOffset or 0) + 1, line and line.itemIndexOffset + line.numSpellBookItems or 0 do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
            if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID
                and not item.isPassive and not item.isOffSpec and not known[item.spellID] then
                local id, name = item.spellID, item.name
                local rank = item.subName
                if not rank or rank == "" then rank = C_Spell.GetSpellSubtext(id) end
                if rank == "" then rank = nil end
                local label = rank and ("%s (%s)"):format(name, rank) or name
                local spell = { id = id, name = name, rank = rank, label = label, search = label:lower(), order = #spells }
                -- "Rank 2" yes, empty or "Racial" no; only these appear on the options page
                spell.ranked = rank ~= nil and rank:find("%d") ~= nil
                spells[#spells + 1] = spell
                known[id] = spell
                if not C_SpellBook.IsSpellBookItemLowRank(slot, BANK) then
                    -- two different spells with the same name: leave them alone
                    if best[name] == nil then best[name] = id else best[name] = false end
                end
            end
        end
    end
    table.sort(spells, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.order < b.order
    end)
end

-- more than one rank of a spell in the book (otherwise "Shift: all ranks" would promise nothing)
local function HasSeveralRanks()
    local seen = {}
    for _, spell in ipairs(spells) do
        if spell.ranked then
            if seen[spell.name] then return true end
            seen[spell.name] = true
        end
    end
    return false
end

-- spell ID, entry and target rank if a low rank lies on the slot
local function Outdated(slot)
    local actionType, id = GetActionInfo(slot)
    local spell = actionType == "spell" and known[id]
    local target = spell and best[spell.name]
    if target and target ~= id then return id, spell, target end
end

-- minimap button hint while a non-blacklisted low rank lies on the bars
local function UpdateHint()
    hintQueued = false
    if not db.minimap or InCombatLockdown() then return end -- the end of combat triggers it again
    ReadSpellBook()
    local outdated = false
    for slot = 1, NUM_ACTION_SLOTS do
        local id = Outdated(slot)
        if id and not blacklist[id] then
            outdated = true
            break
        end
    end
    outdatedShown = outdated
    ns.SetAlert(outdated)
end

local function QueueHint()
    if hintQueued then return end
    hintQueued = true
    C_Timer.After(1, UpdateHint) -- after the scan (0.5 s) for the same event
end

local Scan

local function QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay or 0.5, Scan)
end

-- Asked when a low rank was placed on a bar by hand. The spell asked about is
-- always askQueue[1]; the scan after the dialog closes applies the answer.
local function ShowQuestion()
    local spell = askQueue[1]
    if spell then StaticPopup_Show("PYLOSRANKS_KEEP", spell.label) end
end

StaticPopupDialogs.PYLOSRANKS_KEEP = {
    text = L["%s is on your action bar, but you know a higher rank.\n\n\"Keep\" puts the spell on the blacklist."],
    button1 = L["Keep"],
    button2 = L["Replace"],
    OnAccept = function()
        local spell = askQueue[1]
        if spell then blacklist[spell.id] = spell.label end
    end,
    OnCancel = function()
        local spell = askQueue[1]
        if spell then confirmed[spell.id] = true end
    end,
    OnHide = function()
        local spell = table.remove(askQueue, 1)
        if spell then asking[spell.id] = nil end
        C_Timer.After(0, ShowQuestion) -- next question only once the dialog is fully closed
        QueueScan()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

local function Ask(spell)
    asking[spell.id] = true
    askQueue[#askQueue + 1] = spell
    if #askQueue == 1 then ShowQuestion() end
end

-- returns the number of replaced spells
function Scan()
    scanQueued = false
    QueueHint()
    local updated = 0
    -- action slots change only out of combat; PLAYER_REGEN_ENABLED rescans
    if InCombatLockdown() then
        pendingAfterCombat = true
        return updated
    end
    pendingAfterCombat = false
    ReadSpellBook()
    local announced = {} -- the same spell on several slots is reported only once
    for slot = 1, NUM_ACTION_SLOTS do
        local id, spell, target = Outdated(slot)
        if id and failed[slot] ~= target then
            if blacklist[id] then
                if reported[id] ~= target then
                    reported[id] = target
                    print(PREFIX .. L["%s ignored."]:format(spell.label))
                end
            elseif asking[id] then
                -- question open: wait
            elseif not forceReplace and not confirmed[id] and (askSlots[slot] or askSlots[0]) then
                Ask(spell)
            elseif GetCursorInfo() then
                -- the player is dragging something, ClearCursor would drop it
                QueueScan(1)
                return updated
            else
                C_Spell.PickupSpell(target)
                if GetCursorInfo() then PlaceAction(slot) end
                ClearCursor() -- the old rank is on the cursor now
                local _, placed = GetActionInfo(slot)
                if placed == target then
                    updated = updated + 1
                    if not announced[id] then
                        announced[id] = true
                        print(PREFIX .. ("%s -> %s"):format(spell.label, known[target].rank or known[target].label))
                    end
                else
                    failed[slot] = target
                end
            end
        end
    end
    wipe(askSlots)
    wipe(confirmed)
    forceReplace = false
    return updated
end

-- minimap button click: scan now and report
local function ScanNow()
    if InCombatLockdown() then
        pendingAfterCombat = true
        print(PREFIX .. L["Not possible in combat, will be done after combat."])
        return
    end
    wipe(reported) -- report ignored spells again
    wipe(failed)
    forceReplace = true
    print(PREFIX .. L["%d spells updated."]:format(Scan()))
end

-- emptyText is shown while the list is empty
local function CreateList(parent, emptyText, onClick)
    local container = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")

    local scrollBar = CreateFrame("EventFrame", nil, container, "MinimalScrollBar")
    scrollBar:SetPoint("TOPRIGHT", -8, -6)
    scrollBar:SetPoint("BOTTOMRIGHT", -8, 6)
    local scrollBox = CreateFrame("Frame", nil, container, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 4, -4)
    scrollBox:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMLEFT", -4, -2)

    local empty = container:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText(emptyText)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, spell)
        if not row.icon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 2, 0)
            row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.label:SetPoint("RIGHT", -2, 0)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(false)
            row:SetHighlightAtlas("search-highlight")
            row:SetScript("OnClick", function(self)
                GameTooltip:Hide() -- the row is about to show another spell
                onClick(self.spell)
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(self.spell.id)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", GameTooltip_Hide)
        end
        row.spell = spell
        row.icon:SetTexture(C_Spell.GetSpellTexture(spell.id))
        row.label:SetText(spell.shown or spell.label)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar)

    function container.SetItems(items)
        empty:SetShown(#items == 0)
        scrollBox:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
    end
    return container
end

-- Options subpage: known spells with search on the left, the blacklist on the right
local function InitBlacklist(frame)
    if not frame.Refresh then
        local note = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        note:SetPoint("TOPLEFT", 7, 0)
        note:SetText(L["The blacklist only applies to this character."])

        local knownHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        knownHeader:SetPoint("TOPLEFT", 7, -26)
        knownHeader:SetText(L["Known spells (click: blacklist, Shift: all ranks)"])

        local blacklistHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        blacklistHeader:SetPoint("TOPLEFT", frame, "TOP", 10, -26)
        blacklistHeader:SetText(L["Blacklist (click: remove, Shift: all ranks)"])

        local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
        search:SetSize(220, 20)
        search:SetPoint("TOPLEFT", 13, -46)
        search:SetAutoFocus(false)

        local resultList, blacklistList

        local function Refresh()
            ReadSpellBook()
            local several = HasSeveralRanks()
            knownHeader:SetText(several and L["Known spells (click: blacklist, Shift: all ranks)"] or L["Known spells (click: blacklist)"])
            blacklistHeader:SetText(several and L["Blacklist (click: remove, Shift: all ranks)"] or L["Blacklist (click: remove)"])
            local filter = search:GetText():lower()
            local results, listed = {}, {}
            for _, spell in ipairs(spells) do
                if spell.ranked and not blacklist[spell.id] and (filter == "" or spell.search:find(filter, 1, true)) then
                    spell.shown = several and spell.label or spell.name
                    results[#results + 1] = spell
                end
            end
            -- only spells the character knows right now (not ones lost e.g. by a talent reset)
            for id, label in pairs(blacklist) do
                if known[id] then listed[#listed + 1] = { id = id, label = label, shown = several and label or known[id].name } end
            end
            table.sort(listed, function(a, b) return a.label < b.label end)
            resultList.SetItems(results)
            blacklistList.SetItems(listed)
        end
        frame.Refresh = Refresh

        -- Shift-click applies to all ranks of the spell in both lists
        resultList = CreateList(frame, L["No matches"], function(spell)
            if IsShiftKeyDown() then
                for _, other in ipairs(spells) do
                    if other.name == spell.name and other.ranked then blacklist[other.id] = other.label end
                end
            else
                blacklist[spell.id] = spell.label
            end
            Refresh()
            QueueHint()
        end)
        resultList:SetPoint("TOPLEFT", 7, -74)
        resultList:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -10, 10)

        blacklistList = CreateList(frame, L["No spells on the blacklist yet"], function(spell)
            local name = IsShiftKeyDown() and known[spell.id] and known[spell.id].name
            for id in pairs(blacklist) do
                if id == spell.id or (name and known[id] and known[id].name == name) then
                    blacklist[id] = nil
                    reported[id] = nil
                end
            end
            Refresh()
            QueueHint() -- no scan: ranks are replaced only on the checked events or by click
        end)
        blacklistList:SetPoint("TOPLEFT", frame, "TOP", 10, -74)
        blacklistList:SetPoint("BOTTOMRIGHT", -10, 10)

        search:HookScript("OnTextChanged", Refresh)
    end
    frame.Refresh()
end

-- Pylos Core builds the options menu, minimap button and /pranks from this
ns.options = {
    savedVariable = "PylosRanksDB",
    title = TITLE,
    intro = L["Replaces spells on the action bars with the highest known rank, except those on the blacklist."],
    icon = "Interface\\AddOns\\PylosRanks\\Button.tga",
    slash = "/pranks",
    slashLeftClick = true, -- /pranks updates, /pranks options opens the options
    defaults = {
        minimapAngle = 225, -- degrees
    },
    onLeftClick = function() ScanNow() end,
    leftClickText = L["Update spell ranks"],
    alertDims = true, -- gray while no outdated rank is on the bars
    onTooltip = function(tooltip)
        if outdatedShown then
            tooltip:AddLine(L["Outdated ranks are on your action bars."], 0.1, 1, 0.1)
        end
    end,
    onLoad = function(saved)
        db = saved
        PylosRanksCharDB = PylosRanksCharDB or {}
        PylosRanksCharDB.blacklist = PylosRanksCharDB.blacklist or {}
        blacklist = PylosRanksCharDB.blacklist
        local frame = ns.eventFrame
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("SPELLS_CHANGED")
        frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end,

    { type = "checkbox", key = "tooltipHint", label = L["Hint in spell tooltip"], default = true,
        tooltip = L["Shows a line at the bottom of the spell tooltip when the rank is on the blacklist."] },
    { type = "color", key = "tooltipColor", label = L["Hint color"], default = "blue" },
    { type = "minimap", onChange = function() QueueHint() end },

    { type = "header", label = L["Update automatically"] },
    { type = "checkbox", key = "onLearn", label = L["New rank learned"], default = true,
        tooltip = L["When a new spell or rank is learned"] },
    { type = "checkbox", key = "onSlotChange", label = L["Action bar changed"], default = false,
        tooltip = L["When a slot on the action bars changes (with confirmation)"] },
    { type = "checkbox", key = "onLogin", label = L["Login and loading screen"], default = false,
        tooltip = L["At login, /reload and after every loading screen"] },

    { type = "page", label = L["Blacklist"], init = InitBlacklist },
}

-- spell tooltip line when the rank is on the blacklist
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
    if not blacklist or not db.tooltipHint or not data then return end
    local id = data.id
    if IsSecret(id) or not id or not blacklist[id] then return end
    local color = ns.GetColor(db.tooltipColor)
    tooltip:AddLine(L["Blacklist: Pylos Ranks keeps this rank."], color[1], color[2], color[3])
end)

local frame = CreateFrame("Frame")
ns.eventFrame = frame
frame:SetScript("OnEvent", function(self, event, arg1)
    QueueHint()
    if event == "PLAYER_ENTERING_WORLD" then
        loading = true
        loadingToken = loadingToken + 1
        local token = loadingToken
        C_Timer.After(LOADING_GRACE, function()
            if token == loadingToken then loading = false end
        end)
        if db.onLogin then
            forceReplace = true
            QueueScan()
        end
    elseif event == "SPELLS_CHANGED" then
        -- also fires at login and without a new spell; only a grown spellbook counts as learned
        ReadSpellBook()
        local count = #spells
        if db.onLearn and lastSpellCount and lastSpellCount > 0 and count > lastSpellCount then
            forceReplace = true
            QueueScan()
        end
        lastSpellCount = count
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingAfterCombat then QueueScan() end
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        -- at login/loading screens the game rebuilds the bars: no question
        if not loading and not IsSecret(arg1) and db.onSlotChange then
            askSlots[arg1] = true -- arg1 = slot, 0 = all
            QueueScan()
        end
    end
end)
