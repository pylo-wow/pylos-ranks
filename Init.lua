local addonName, ns = ...

-- Pylos Core is an optional dependency: without it the game would show a load error, here it is one chat line
-- with a link that opens a box to copy the CurseForge address from.
if not rawget(_G, "PylosCore") then
    ns.off = true
    local CHAT_LINK = "addon:PylosRanks:core"
    local URL = "https://www.curseforge.com/wow/addons/pylos-core"
    StaticPopupDialogs.PYLOSRANKS_LINK = {
        text = "Copy the link with Ctrl+C:",
        button1 = "Close",
        hasEditBox = 1,
        editBoxWidth = 320,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(dialog, data)
            local box = dialog:GetEditBox()
            box:SetText(data)
            box:HighlightText()
            box:SetFocus()
        end,
        EditBoxOnTextChanged = function(box, data)
            if data and box:GetText() ~= data then
                box:SetText(data)
                box:HighlightText()
            end
        end,
        EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
    }
    EventRegistry:RegisterCallback("SetItemRef", function(_, link)
        if link == CHAT_LINK then StaticPopup_Show("PYLOSRANKS_LINK", nil, nil, URL) end
    end, ns)
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        print("|cffffd100Pylos Ranks|r: needs Pylos Core, which is not installed. Get it on CurseForge: |cff99d9ff|H"
            .. CHAT_LINK .. "|h[Link]|h|r")
    end)
    return
end

-- Announces the addon to Pylos Core (ns.L, options page from ns.options, ns.off).
if not PylosCore.Module(addonName, ns, { requires = { core = "1.0" } }) then return end
