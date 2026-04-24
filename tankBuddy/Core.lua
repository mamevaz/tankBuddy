local ADDON, TB = "tankBuddy", {}
_G[ADDON] = TB

-- Cache de item links de la Cámara de Tesoros
-- Se rellena al abrir la cámara (evento WEEKLY_REWARDS_UPDATE)
local vaultLinkCache = {}   -- [claimID] = itemLink

local vaultEventFrame = CreateFrame("Frame")
vaultEventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
vaultEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
vaultEventFrame:SetScript("OnEvent", function(self, event, ...)
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetItemHyperlink) then return end
    local acts = C_WeeklyRewards.GetActivities()
    if not acts then return end
    for _, act in ipairs(acts) do
        if act.rewards then
            for _, reward in ipairs(act.rewards) do
                if reward.itemDBID and act.claimID and not vaultLinkCache[act.claimID] then
                    local ok, link = pcall(C_WeeklyRewards.GetItemHyperlink, reward.itemDBID)
                    if ok and link and link ~= "" then
                        vaultLinkCache[act.claimID] = link
                    end
                end
            end
        end
    end
end)

-- ilvl por paso de upgrade: primero y último +4, el resto +3
local function IlvlsToMax(currentStep, maxStep)
    local total = 0
    for s = currentStep, maxStep - 1 do
        if s == 1 or s == maxStep - 1 then
            total = total + 4
        else
            total = total + 3
        end
    end
    return total
end

-- Proyecta un score a otro ilvl usando la curva estándar de stats secundarios
local function ProjectScore(score, fromIlvl, toIlvl)
    if not fromIlvl or fromIlvl <= 0 or toIlvl <= fromIlvl then return score end
    return score * (toIlvl / fromIlvl) ^ 2.3
end

-- Detecta gear PvP por la línea de ilvl en arenas/campos de batalla
local function IsPvPGear(itemLink)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return false end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not (data and data.lines) then return false end
    for _, line in ipairs(data.lines) do
        local text = (line.leftText or ""):lower()
        if text:find("arenas") or text:find("campos de batalla") or text:find("modo guerra") then
            return true
        end
    end
    return false
end

-- Lee el paso de upgrade del tooltip: devuelve currentStep, maxStep o nil
local function ParseUpgradeInfo(itemLink)
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not (data and data.lines) then return nil end
    for _, line in ipairs(data.lines) do
        local text = line.leftText or ""
        local cur, max = text:match("(%d+)/(%d+)")
        if cur and max then
            return tonumber(cur), tonumber(max)
        end
    end
    return nil
end

-- Nombres de stats en español → clave de config
local STAT_NAMES = {
    ["celeridad"]          = "haste",
    ["golpe crítico"]      = "crit",
    ["maestría"]           = "mastery",
    ["versatilidad"]       = "versatility",
    ["elusión"]            = "avoidance",
    ["absorción de vida"]  = "leech",
    ["sifón de vida"]      = "leech",
    ["velocidad"]          = "speed",
}

TB.EQUIP_SLOTS = {
    { id = 1,  name = "Head"     },
    { id = 2,  name = "Neck"     },
    { id = 3,  name = "Shoulder" },
    { id = 15, name = "Back"     },
    { id = 5,  name = "Chest"    },
    { id = 9,  name = "Wrist"    },
    { id = 10, name = "Hands"    },
    { id = 6,  name = "Waist"    },
    { id = 7,  name = "Legs"     },
    { id = 8,  name = "Feet"     },
    { id = 11, name = "Ring1"    },
    { id = 12, name = "Ring2"    },
    { id = 13, name = "Trinket1" },
    { id = 14, name = "Trinket2" },
    { id = 16, name = "MainHand" },
    { id = 17, name = "OffHand"  },
}

-- invTypes que ocupan dos slots: se compara contra el peor equipado
local DUAL_SLOT_TYPES = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }


local function GetStatsFromTooltip(itemLink)
    local stats = {}
    if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return stats end
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if not (data and data.lines) then return stats end
    for _, line in ipairs(data.lines) do
        local text = line.leftText or ""
        -- Formato: "+123 nombre stat"
        local amount, statName = text:match("^%+(%d+)%s+(.+)$")
        if amount and statName then
            local cfgKey = STAT_NAMES[statName:lower()]
            if cfgKey then
                stats[cfgKey] = (stats[cfgKey] or 0) + tonumber(amount)
            end
        end
    end
    return stats
end

function TB.ScoreItem(itemLink)
    if not itemLink then return 0 end
    local cfg = tankBuddy_Config
    if not cfg then return 0 end

    local itemStats = GetStatsFromTooltip(itemLink)
    local score = 0
    for cfgKey, amount in pairs(itemStats) do
        local statCfg = cfg.Stats[cfgKey]
        if statCfg and statCfg.weight and amount > 0 then
            score = score + amount * statCfg.weight
        end
    end
    return score
end

function TB.GetEquippedItem(slotId)
    local link = GetInventoryItemLink("player", slotId)
    return link, TB.ScoreItem(link)
end

function TB.ScanBags()
    local items = {}
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(link)
                if invType and invType ~= "" and invType ~= "INVTYPE_NON_EQUIP" and invType ~= "INVTYPE_BAG"
                and not IsPvPGear(link) then
                    local score = TB.ScoreItem(link)
                    local curStep, maxStep = ParseUpgradeInfo(link)
                    table.insert(items, {
                        link    = link,
                        score   = score,
                        ilvl    = ilvl or 0,
                        invType = invType,
                        curStep = curStep,
                        maxStep = maxStep,
                    })
                end
            end
        end
    end
    return items
end

function TB.Debug()
    local lines = {}
    -- Busca el primer item equipable de las bolsas
    local testLink, testInvType, testIlvl
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(link)
                if invType and invType ~= "" and invType ~= "INVTYPE_NON_EQUIP" and invType ~= "INVTYPE_BAG" then
                    testLink, testInvType, testIlvl = link, invType, ilvl
                    break
                end
            end
        end
        if testLink then break end
    end

    if not testLink then
        TB.ShowDebugBox("No se encontro gear equipable en bolsas.")
        return
    end

    table.insert(lines, "Item: " .. testLink)
    table.insert(lines, "invType=" .. testInvType .. "  ilvl=" .. tostring(testIlvl))
    table.insert(lines, "")

    -- Metodo 1: C_Item.GetItemStats
    local s1 = {}
    if C_Item.GetItemStats then
        C_Item.GetItemStats(testLink, s1)
        local parts = {}
        for k, v in pairs(s1) do table.insert(parts, k .. "=" .. tostring(v)) end
        table.insert(lines, "C_Item.GetItemStats: " .. (next(parts) and table.concat(parts, ", ") or "(vacio)"))
    else
        table.insert(lines, "C_Item.GetItemStats: NO EXISTE")
    end

    -- Metodo 2: C_TooltipInfo.GetHyperlink
    table.insert(lines, "")
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(testLink)
        if data and data.lines then
            table.insert(lines, "C_TooltipInfo lineas (" .. #data.lines .. "):")
            for i, line in ipairs(data.lines) do
                local left = line.leftText or ""
                local t    = tostring(line.type or "")
                if left ~= "" then
                    table.insert(lines, string.format("  [%d] type=%s  \"%s\"", i, t, left))
                end
                if i >= 20 then table.insert(lines, "  ...") break end
            end
        else
            table.insert(lines, "C_TooltipInfo.GetHyperlink: sin datos")
        end
    else
        table.insert(lines, "C_TooltipInfo.GetHyperlink: NO EXISTE")
    end

    -- C_WeeklyRewards
    table.insert(lines, "")
    table.insert(lines, "=== C_WeeklyRewards ===")
    if not C_WeeklyRewards then
        table.insert(lines, "C_WeeklyRewards: NO EXISTE")
    else
        -- Listar TODAS las funciones y campos disponibles
        local funcs, others = {}, {}
        for k, v in pairs(C_WeeklyRewards) do
            if type(v) == "function" then table.insert(funcs, k)
            else table.insert(others, k .. "=" .. tostring(v)) end
        end
        table.sort(funcs)
        table.insert(lines, "Funciones (" .. #funcs .. "):")
        for i = 1, #funcs do
            table.insert(lines, "  " .. funcs[i])
        end
        if #others > 0 then
            table.sort(others)
            table.insert(lines, "Valores: " .. table.concat(others, ", "))
        end
        table.insert(lines, "")

        -- Estado general
        local hasRewards   = C_WeeklyRewards.HasAvailableRewards  and C_WeeklyRewards.HasAvailableRewards()
        local hasGenerated = C_WeeklyRewards.HasGeneratedRewards   and C_WeeklyRewards.HasGeneratedRewards()
        local hasInteract  = C_WeeklyRewards.HasInteraction        and C_WeeklyRewards.HasInteraction()
        local canClaim     = C_WeeklyRewards.CanClaimRewards       and C_WeeklyRewards.CanClaimRewards()
        table.insert(lines, "HasAvailableRewards: "  .. tostring(hasRewards))
        table.insert(lines, "HasGeneratedRewards: "  .. tostring(hasGenerated))
        table.insert(lines, "HasInteraction: "       .. tostring(hasInteract))
        table.insert(lines, "CanClaimRewards: "      .. tostring(canClaim))
        table.insert(lines, "")

        -- RequestRewardList si existe
        if C_WeeklyRewards.RequestRewardList then
            table.insert(lines, "Llamando RequestRewardList()...")
            pcall(C_WeeklyRewards.RequestRewardList)
        end

        -- GetExampleRewardItemHyperlinks
        if C_WeeklyRewards.GetExampleRewardItemHyperlinks then
            table.insert(lines, "GetExampleRewardItemHyperlinks:")
            for _, actType in ipairs({1, 2, 3, 4, 5, 6, 7}) do
                local ok, result = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, actType)
                if ok and result then
                    if type(result) == "table" and #result > 0 then
                        for i, v in ipairs(result) do
                            table.insert(lines, "  type=" .. actType .. "[" .. i .. "]=" .. tostring(v))
                        end
                    elseif type(result) == "string" and result ~= "" then
                        table.insert(lines, "  type=" .. actType .. "=" .. result)
                    end
                end
            end
        end
        table.insert(lines, "")

        -- Estado de la caché de links
        local cacheCount = 0
        for _ in pairs(vaultLinkCache) do cacheCount = cacheCount + 1 end
        table.insert(lines, "vaultLinkCache: " .. cacheCount .. " entradas")
        for claimID, link in pairs(vaultLinkCache) do
            table.insert(lines, "  claimID=" .. claimID .. " -> " .. tostring(link))
        end
        table.insert(lines, "")

        -- WeeklyRewardsFrame
        if WeeklyRewardsFrame then
            table.insert(lines, "WeeklyRewardsFrame: existe, shown=" .. tostring(WeeklyRewardsFrame:IsShown()))
        else
            table.insert(lines, "WeeklyRewardsFrame: NO EXISTE")
        end
        table.insert(lines, "")

        -- GetActivities — dump completo de TODOS los campos
        if C_WeeklyRewards.GetActivities then
            local acts = C_WeeklyRewards.GetActivities()
            if acts and #acts > 0 then
                table.insert(lines, "GetActivities (" .. #acts .. " actividades):")
                for ai, act in ipairs(acts) do
                    -- Dump todos los campos del acto
                    local actFields = {}
                    for k, v in pairs(act) do
                        if type(v) ~= "table" then
                            table.insert(actFields, k .. "=" .. tostring(v))
                        end
                    end
                    table.sort(actFields)
                    table.insert(lines, string.format("  [%d] %s", ai, table.concat(actFields, "  ")))

                    -- Dump todos los campos de rewards
                    if type(act.rewards) == "table" then
                        for rk, rv in pairs(act.rewards) do
                            if type(rv) == "table" then
                                local rparts = {}
                                for k, v in pairs(rv) do
                                    table.insert(rparts, k .. "=" .. tostring(v))
                                end
                                table.sort(rparts)
                                table.insert(lines, "      rewards[" .. rk .. "]: " .. table.concat(rparts, "  "))
                            else
                                table.insert(lines, "      rewards[" .. rk .. "]=" .. tostring(rv))
                            end
                        end
                    end

                    -- GetItemHyperlink — itemDBID es el campo correcto (SimC lo usa así)
                    if C_WeeklyRewards.GetItemHyperlink then
                        -- Campo clave: itemDBID (userdata C++, no aparece en pairs())
                        local itemDBID = act.rewards and act.rewards[1] and act.rewards[1].itemDBID
                        table.insert(lines, "      reward.itemDBID=" .. tostring(itemDBID))
                        local toTry = {}
                        if itemDBID then table.insert(toTry, {"itemDBID", itemDBID}) end
                        if act.claimID then table.insert(toTry, {"claimID", act.claimID}) end
                        if act.type and act.index then
                            table.insert(toTry, {"type,index", act.type, act.index})
                        end
                        for _, p in ipairs(toTry) do
                            local label = table.remove(p, 1)
                            local ok2, result = pcall(C_WeeklyRewards.GetItemHyperlink, unpack(p))
                            local res = ok2 and tostring(result) or ("ERROR:" .. tostring(result))
                            table.insert(lines, "      GetItemHyperlink(" .. label .. ")=" .. res)
                        end
                    end

                    -- GetItemInfo con bare itemID
                    if type(act.rewards) == "table" then
                        for _, rw in ipairs(act.rewards) do
                            if rw.id and rw.type == 1 then
                                local name, _, _, ilvl = GetItemInfo("item:" .. rw.id)
                                table.insert(lines, "      GetItemInfo(item:" .. rw.id .. "): name=" .. tostring(name) .. " ilvl=" .. tostring(ilvl))
                            end
                        end
                    end
                end
            else
                table.insert(lines, "GetActivities: sin datos (o 0 actividades)")
            end
        else
            table.insert(lines, "GetActivities: NO EXISTE")
        end
    end

    TB.ShowDebugBox(table.concat(lines, "\n"))
end

local ACTIVITY_TYPE = { MYTHIC_PLUS = 1, RAID = 3, WORLD = 5, DELVES = 6 }
local ACTIVITY_LABEL = { [1] = "M+", [3] = "Raid", [5] = "Mundo", [6] = "Delves" }

function TB.EvaluateVault()
    if not C_WeeklyRewards then
        return nil, "C_WeeklyRewards no disponible"
    end
    if not C_WeeklyRewards.HasAvailableRewards or not C_WeeklyRewards.HasAvailableRewards() then
        return nil, "No hay recompensas disponibles en la Cámara esta semana"
    end

    local acts = C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities()
    if not acts or #acts == 0 then
        return nil, "No se encontraron actividades"
    end

    -- Equipado por invType para comparar
    local equippedByType = {}
    for _, s in ipairs(TB.EQUIP_SLOTS) do
        local link, score = TB.GetEquippedItem(s.id)
        if link then
            local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(link)
            if invType then
                local ex = equippedByType[invType]
                if not ex or (DUAL_SLOT_TYPES[invType] and score < ex.score) then
                    equippedByType[invType] = { link = link, score = score, ilvl = ilvl or 0 }
                end
            end
        end
    end

    local results = {}
    for _, act in ipairs(acts) do
        if act.claimID and act.rewards and #act.rewards > 0 then
            for _, reward in ipairs(act.rewards) do
                if reward.type == 1 and reward.id then
                    local itemLink, fallback

                    -- GetItemHyperlink con itemDBID (campo C++ via __index, igual que SimC)
                    if C_WeeklyRewards.GetItemHyperlink and reward.itemDBID then
                        local ok, link = pcall(C_WeeklyRewards.GetItemHyperlink, reward.itemDBID)
                        if ok and link and link ~= "" then itemLink = link end
                    end
                    -- Caché de evento como segundo intento
                    if not itemLink and vaultLinkCache[act.claimID] then
                        itemLink = vaultLinkCache[act.claimID]
                    end
                    -- Fallback: bare item ID (ilvl incorrecto, stats correctos)
                    if not itemLink then
                        itemLink = "item:" .. reward.id
                        fallback = true
                    end

                    local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(itemLink)
                    local score = TB.ScoreItem(itemLink)
                    local diff, equippedLink, equippedIlvl
                    if invType then
                        local eq = equippedByType[invType]
                        if eq then
                            diff         = score - eq.score
                            equippedLink = eq.link
                            equippedIlvl = eq.ilvl
                        end
                    end
                    table.insert(results, {
                        itemLink     = itemLink,
                        itemID       = reward.id,
                        ilvl         = ilvl or 0,
                        score        = score,
                        diff         = diff,
                        invType      = invType,
                        equippedLink = equippedLink,
                        equippedIlvl = equippedIlvl,
                        actType      = ACTIVITY_LABEL[act.type] or ("type" .. act.type),
                        fallback     = fallback,
                    })
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return (a.diff or -999) > (b.diff or -999)
    end)
    return results, nil
end

function TB.FindUpgrades()
    local equippedByType = {}
    for _, s in ipairs(TB.EQUIP_SLOTS) do
        local link, score = TB.GetEquippedItem(s.id)
        if link then
            local _, _, _, ilvl, _, _, _, _, invType = GetItemInfo(link)
            if invType then
                local existing = equippedByType[invType]
                if not existing then
                    equippedByType[invType] = { link = link, score = score, ilvl = ilvl or 0, slotName = s.name }
                elseif DUAL_SLOT_TYPES[invType] and score < existing.score then
                    equippedByType[invType] = { link = link, score = score, ilvl = ilvl or 0, slotName = s.name }
                end
            end
        end
    end

    local results = {}
    for _, item in ipairs(TB.ScanBags()) do
        local equipped = equippedByType[item.invType]
        if equipped then
            local diff = item.score - equipped.score

            -- Proyección: si el item de mochila tiene menor ilvl que el equipado,
            -- calcula qué score tendría al mismo ilvl que el equipado
            local projScore, projDiff
            if item.ilvl > 0 and equipped.ilvl > item.ilvl then
                projScore = ProjectScore(item.score, item.ilvl, equipped.ilvl)
                projDiff  = projScore - equipped.score
            end

            table.insert(results, {
                link          = item.link,
                score         = item.score,
                ilvl          = item.ilvl,
                diff          = diff,
                invType       = item.invType,
                curStep       = item.curStep,
                maxStep       = item.maxStep,
                equippedLink  = equipped.link,
                equippedScore = equipped.score,
                equippedIlvl  = equipped.ilvl,
                slotName      = equipped.slotName,
                projScore     = projScore,
                projDiff      = projDiff,
            })
        end
    end

    table.sort(results, function(a, b) return a.diff > b.diff end)
    return results
end

function TB.PrintUpgrades()
    local cfg = tankBuddy_Config
    if not cfg then
        print("|cffff4444[tankBuddy]|r No config. Ejecuta murlok_scraper.py primero.")
        return
    end
    local upgrades = TB.FindUpgrades()
    if #upgrades == 0 then
        print("|cff4fc3f7[tankBuddy]|r |cff00ff00No hay upgrades en tus bolsas.|r")
        return
    end
    print(string.format("|cff4fc3f7[tankBuddy]|r |cffffff00%d upgrade(s) encontrado(s):|r", #upgrades))
    for i, u in ipairs(upgrades) do
        print(string.format(
            "  %d. %s |cff888888ilvl %d|r  |cff00ff00+%.1f|r  vs %s",
            i, u.link, u.ilvl, u.diff, u.equippedLink
        ))
    end
end

function TB.PrintEquipped()
    local cfg = tankBuddy_Config
    if not cfg then
        print("|cffff4444[tankBuddy]|r No config. Ejecuta murlok_scraper.py primero.")
        return
    end
    print(string.format(
        "|cff4fc3f7[tankBuddy]|r %s | %d chars | %s",
        cfg.UpdatedAt, cfg.CharacterCount, cfg.Spec
    ))
    for _, s in ipairs(TB.EQUIP_SLOTS) do
        local link, score = TB.GetEquippedItem(s.id)
        if link and score > 0 then
            print(string.format("  |cffaaaaaa%-10s|r %s  |cff888888(%.1f)|r", s.name, link, score))
        end
    end
end
