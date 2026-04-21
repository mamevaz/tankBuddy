local TB = _G["tankBuddy"]

local frame
local linePool = {}

local function GetLine(parent)
    for _, fs in ipairs(linePool) do
        if not fs:IsShown() then
            fs:SetParent(parent)
            fs:Show()
            return fs
        end
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(510)
    table.insert(linePool, fs)
    return fs
end

local function BuildFrame()
    frame = CreateFrame("Frame", "tankBuddyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(560, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.titleText:SetPoint("CENTER", frame.TitleBg, "CENTER")
    frame.titleText:SetText("tankBuddy — Blood DK")

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(80, 22)
    btn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -4, 0)
    btn:SetText("Scan")
    btn:SetScript("OnClick", function() TB.Refresh() end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     8,  -32)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26,  8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(520)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    frame.content = content
end

local function RenderLines(lines)
    for _, fs in ipairs(linePool) do fs:Hide() end

    local y = -4
    for _, entry in ipairs(lines) do
        local fs = GetLine(frame.content)
        fs:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, y)
        fs:SetText(entry.text)
        if entry.color then
            fs:SetTextColor(unpack(entry.color))
        else
            fs:SetTextColor(1, 1, 1)
        end
        y = y - 18
    end
    frame.content:SetHeight(math.abs(y) + 8)
end

function TB.Refresh()
    if not frame then BuildFrame() end

    local lines = {}
    local function add(text, color)
        table.insert(lines, { text = text, color = color })
    end

    local cfg = tankBuddy_Config
    if not cfg then
        add("No config — ejecuta murlok_scraper.py primero.", {1, 0.2, 0.2})
        RenderLines(lines)
        frame:Show()
        return
    end

    add(string.format("Config: %s  |  %d chars  |  %s", cfg.UpdatedAt, cfg.CharacterCount, cfg.Spec), {0.5, 0.5, 0.5})
    add("")

    -- Upgrades
    local upgrades = TB.FindUpgrades()
    if #upgrades == 0 then
        add("No hay upgrades en tus bolsas.", {0.2, 1, 0.2})
    else
        add(string.format("%d upgrade(s) encontrado(s):", #upgrades), {1, 1, 0})
        add("")
        for i, u in ipairs(upgrades) do
            add(string.format("%d. %s  ilvl %d  +%.1f", i, u.link, u.ilvl, u.diff), {0.2, 1, 0.4})
            add(string.format("   vs %s  (%.1f → %.1f)", u.equippedLink, u.equippedScore, u.score), {0.5, 0.5, 0.5})
            add("")
        end
    end

    -- Equipped
    add("Gear equipado:", {1, 1, 0})
    add("")
    for _, s in ipairs(TB.EQUIP_SLOTS) do
        local link, score = TB.GetEquippedItem(s.id)
        if link and score > 0 then
            add(string.format("%-10s  %s  (%.1f)", s.name, link, score), {0.8, 0.8, 0.8})
        end
    end

    RenderLines(lines)
    frame:Show()
end

-- Slash commands
SLASH_TANKBUDDY1 = "/tb"
SLASH_TANKBUDDY2 = "/tankbuddy"
SlashCmdList["TANKBUDDY"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)") or ""
    if cmd == "" then
        if frame and frame:IsShown() then frame:Hide() else TB.Refresh() end
    elseif cmd == "scan" then
        TB.PrintUpgrades()
    elseif cmd == "gear" then
        TB.PrintEquipped()
    elseif cmd == "help" then
        print("|cff4fc3f7[tankBuddy]|r Comandos:")
        print("  /tb          — abrir/cerrar ventana")
        print("  /tb scan     — upgrades en chat")
        print("  /tb gear     — gear equipado en chat")
        print("  /tb help     — esta ayuda")
    else
        TB.Refresh()
    end
end
