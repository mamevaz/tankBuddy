local TB = _G["tankBuddy"]

local frame
local linePool = {}
local debugFrame

function TB.ShowDebugBox(text)
    if not debugFrame then
        debugFrame = CreateFrame("Frame", "tankBuddyDebugFrame", UIParent, "BasicFrameTemplateWithInset")
        debugFrame:SetSize(600, 400)
        debugFrame:SetPoint("CENTER")
        debugFrame:SetMovable(true)
        debugFrame:EnableMouse(true)
        debugFrame:RegisterForDrag("LeftButton")
        debugFrame:SetScript("OnDragStart", debugFrame.StartMoving)
        debugFrame:SetScript("OnDragStop", debugFrame.StopMovingOrSizing)

        debugFrame.titleText = debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        debugFrame.titleText:SetPoint("CENTER", debugFrame.TitleBg, "CENTER")
        debugFrame.titleText:SetText("tankBuddy Debug — selecciona todo y copia")

        debugFrame.editBox = CreateFrame("EditBox", nil, debugFrame)
        debugFrame.editBox:SetMultiLine(true)
        debugFrame.editBox:SetFontObject(GameFontNormalSmall)
        debugFrame.editBox:SetWidth(570)
        debugFrame.editBox:SetAutoFocus(true)
        debugFrame.editBox:SetPoint("TOPLEFT",     debugFrame, "TOPLEFT",     10, -32)
        debugFrame.editBox:SetPoint("BOTTOMRIGHT", debugFrame, "BOTTOMRIGHT", -10,  10)
        debugFrame.editBox:SetScript("OnEscapePressed", function() debugFrame:Hide() end)
    end
    debugFrame.editBox:SetText(text)
    debugFrame.editBox:HighlightText()
    debugFrame:Show()
end

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
    content:EnableMouse(true)
    content:SetHyperlinksEnabled(true)
    content:SetScript("OnHyperlinkEnter", function(self, linkData, link)
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    content:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)
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

function TB.RefreshVault()
    if not frame then BuildFrame() end

    local lines = {}
    local function add(text, color)
        table.insert(lines, { text = text, color = color })
    end

    add("Cámara de Tesoros — evaluación Blood DK", {1, 0.84, 0})
    add("")

    local results, err = TB.EvaluateVault()
    if err then
        add(err, {1, 0.4, 0.4})
    elseif not results or #results == 0 then
        add("No hay items disponibles para evaluar.", {0.6, 0.6, 0.6})
    else
        add(string.format("%d recompensa(s) disponible(s):", #results), {1, 1, 0})
        add("")
        for i, r in ipairs(results) do
            local scoreStr = r.score > 0 and string.format("%.1f", r.score) or "sin stats"
            local diffStr, diffColor = "", {0.7, 0.7, 0.7}
            if r.diff then
                if r.diff > 0 then
                    diffStr  = string.format("  |cff00ff00+%.1f vs equipado|r", r.diff)
                    diffColor = {0.2, 1, 0.4}
                elseif r.diff < 0 then
                    diffStr  = string.format("  |cffff4444%.1f vs equipado|r", r.diff)
                    diffColor = {1, 0.4, 0.4}
                else
                    diffStr = "  igual al equipado"
                end
            end
            local fallbackNote = r.fallback and " |cffff8800(ilvl aprox)|r" or ""
            add(string.format("%d. [%s] %s  ilvl %d%s  score %s%s",
                i, r.actType, r.itemLink, r.ilvl, fallbackNote, scoreStr, diffStr), diffColor)
            if r.equippedLink then
                add(string.format("   Equipado: %s  ilvl %d", r.equippedLink, r.equippedIlvl or 0), {0.5, 0.5, 0.5})
            end
            add("")
        end
    end

    RenderLines(lines)
    frame:Show()
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

    -- Comparación de bolsas
    local results = TB.FindUpgrades()
    if #results == 0 then
        add("No hay gear equipable en tus bolsas.", {0.5, 0.5, 0.5})
    else
        local nUp = 0
        for _, u in ipairs(results) do if u.diff > 0 then nUp = nUp + 1 end end
        add(string.format("Gear en bolsas (%d items, %d mejoras):", #results, nUp), {1, 1, 0})
        add("")
        for i, u in ipairs(results) do
            local diffStr, itemColor
            if u.diff > 0 then
                diffStr   = string.format("+%.1f", u.diff)
                itemColor = {0.2, 1, 0.4}
            elseif u.diff < 0 then
                diffStr   = string.format("%.1f", u.diff)
                itemColor = {1, 0.3, 0.3}
            else
                diffStr   = "±0"
                itemColor = {0.6, 0.6, 0.6}
            end
            local stepStr = u.curStep and u.maxStep
                and string.format(" [%d/%d]", u.curStep, u.maxStep) or ""
            add(string.format("%d. %s  ilvl %d%s  %s", i, u.link, u.ilvl, stepStr, diffStr), itemColor)
            add(string.format("   vs %s  ilvl %d  (%.1f → %.1f)", u.equippedLink, u.equippedIlvl, u.equippedScore, u.score), {0.5, 0.5, 0.5})

            -- Proyección al mismo ilvl que el equipado
            if u.projDiff then
                local projColor = u.projDiff > 0 and {0.2, 1, 0.4} or {1, 0.3, 0.3}
                local projSign  = u.projDiff > 0 and "+" or ""
                add(string.format("   A ilvl %d (mismo que equipado): %s%.1f", u.equippedIlvl, projSign, u.projDiff), projColor)
            end
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
    elseif cmd == "vault" or cmd == "camara" then
        TB.RefreshVault()
    elseif cmd == "debug" then
        TB.Debug()
    elseif cmd == "help" then
        print("|cff4fc3f7[tankBuddy]|r Comandos:")
        print("  /tb          — abrir/cerrar ventana (bolsas)")
        print("  /tb vault    — evaluar Cámara de Tesoros")
        print("  /tb scan     — upgrades en chat")
        print("  /tb gear     — gear equipado en chat")
        print("  /tb debug    — diagnóstico")
        print("  /tb help     — esta ayuda")
    else
        TB.Refresh()
    end
end
