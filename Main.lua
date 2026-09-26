--==============================================================
-- WindUI Library (inlined, v1.6.65, MIT, by Footagesus)
-- https://github.com/Footagesus/WindUI
--==============================================================
local WindUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"
))()
-- ==============================================================
-- ANIMAL HOSPITAL | made by kryx 🏥
-- (top part = WindUI v1.6.65 library baked inside the file,
--  copied from the proven offline pattern — no download, no outages)
-- Target features: full ESP pack, player buffs, auto pack (BETA),
-- item grabber, room teleports, door wiper
-- rebuilt kryx-style: guard against stacked copies, tracked
-- connections, everything pcall'd, mobile-friendly
-- ==============================================================

-- INSTANCE GUARD: kill older copies of this script
-- (the nox original STACKED esp loops on re-execute = lag city)
local genv = (getgenv and getgenv()) or _G
if genv.__AHOSP_CLEANUP then
    pcall(genv.__AHOSP_CLEANUP)
    task.wait(0.1)
end

-- Services
local players = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local replicatedStorage = game:GetService("ReplicatedStorage")
local marketplaceService = game:GetService("MarketplaceService")
local guiService = game:GetService("GuiService")
local virtualInputManager = game:GetService("VirtualInputManager")
local virtualUser = game:GetService("VirtualUser")
local lighting = game:GetService("Lighting")

local localPlayer = players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui", 15)
if not playerGui then return end
local camera = workspace.CurrentCamera

-- lobby check: this script only makes sense inside the real game
local TARGET_PLACE_ID = 111304265646194
local isInLobby = false
local okInfo, productInfo = pcall(function()
    return marketplaceService:GetProductInfo(game.PlaceId)
end)
if okInfo and productInfo and productInfo.Name then
    local n = string.lower(productInfo.Name)
    if string.find(n, "lobby") or string.find(n, "start") or string.find(n, "menu") then
        isInLobby = true
    end
end
if game.PlaceId == TARGET_PLACE_ID then
    isInLobby = false
end

-- kill switch: cleanup flips this, every loop bails out
local dead = false
local cleanupDone = false

-- State Variables
local state = {
    anomaliesESP = false,
    patientsESP = false,
    itemsESP = false,
    playerESP = false,
    drawLines = false,
    infSanity = false,
    thirdPerson = false,
    fasterActions = false,
    autoMinigames = false,
    autoTasks = false,
    autoHeal = false,
    mouseFree = false,
    noClip = false,
    shrink = false,
    followPlayer = false,
    followTarget = nil,
    followDistance = 6,
    followSpeed = 20,
    followThroughWalls = true,
    wallhackEnabled = false,
    wallhackLevel = 1,
    antiAfk = true,
    fullbright = false,
    lowGraphics = false,
    hideNpcGraphics = true,
    fov = 70,
    characterScale = 0.7,
    fixedFlight = false,
    fixedFlightHeight = 0,
    ghostMode = false,
    vehicleGrip = 1,
    vehicleBrake = 1,
    vehicleLaunch = 1,
    vehicleSteering = 3,
    vehicleGlass = 0.65,
    vehicleExhaust = false,
    vehicleBrakeHeld = false,
    maxGraphics = false,
    highQualityEdges = true,
    driftEffects = false,
    playerPushForce = 35,
    objectPushEnabled = false,
    objectPushMode = "local",
    objectPushItemName = "",
    objectPushDistance = 10,
    language = "vi",
    speed = 16,
}

local highlightCache = {}
local lineCache = {}
local promptDurations = {}
local minigameClicked = {}
local minigameQueue = {}
local sanityConns = {}
local helperParts = {}
local worldScanDirty = true
local cachedCandidates = {}
local cachedPrompts = {}
local autoTaskRunId = 0
local autoHealRunId = 0
local savedLighting = nil
local savedLowGraphics = {}
local savedTerrainColors = {}
local savedLowLighting = nil
local savedCameraFov = nil
local lowGraphicsDescendantConn = nil
local noClipLastUpdate = 0
local playerEspLastUpdate = 0
local fixedFlightCFrame = nil
local lowGraphicsRunId = 0
local thirdPersonYaw = 0
local thirdPersonPitch = 0
local thirdPersonMouseLook = false
local ghostBodyHeight = nil
local vehicleSavedProperties = {}
local vehicleSavedVisuals = {}
local vehicleLastModel = nil
local vehicleLastGrip = nil
local vehicleLastApply = 0
local vehicleLastLaunch = nil
local vehicleLastSteering = nil
local vehicleLastGlass = nil
local vehicleLastExhaust = nil
local vehicleExhaustParts = {}
local dragTargetPlayer = nil
local objectPushCooldown = 0
local savedMaxGraphics = nil
local savedMaxPartSettings = {}
local savedQualityLevel = nil
local maxGraphicsDescendantConn = nil
local driftEffectParts = {}
local followLastUpdate = 0
local manualPromptConnections = {}
local automationBusy = false
local automationPhase = "Idle"
local debugEnabled = false
local debugLogLines = {}
local DEBUG_LOG_LIMIT = 300
local itemInventory = {}
local inventoryButtons = {}

local connections = {}
local function track(conn) table.insert(connections, conn) return conn end
local notify

local function debugLog(message, ...)
    if not debugEnabled then return end
    local details = {...}
    if #details > 0 then
        local values = {}
        for index, value in ipairs(details) do
            values[index] = tostring(value)
        end
        message = message .. " | " .. table.concat(values, " | ")
    end
    local line = string.format("[%0.3f][%s] %s", os.clock(), automationPhase, tostring(message))
    table.insert(debugLogLines, line)
    if #debugLogLines > DEBUG_LOG_LIMIT then
        table.remove(debugLogLines, 1)
    end
    print("[AH DEBUG] " .. line)
end

local function logEnvironmentSnapshot(label)
    local camera = workspace.CurrentCamera
    local promptCount = 0
    local modelCount = 0
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("ProximityPrompt") then promptCount += 1 end
        if instance:IsA("Model") then modelCount += 1 end
    end
    debugLog("Environment", label,
        "PlaceId=" .. tostring(game.PlaceId),
        "Camera=" .. tostring(camera and camera.CameraType),
        "FOV=" .. tostring(camera and camera.FieldOfView),
        "Players=" .. tostring(#players:GetPlayers()),
        "WorkspaceChildren=" .. tostring(#workspace:GetChildren()),
        "WorkspaceDescendants=" .. tostring(#workspace:GetDescendants()),
        "Models=" .. tostring(modelCount),
        "Prompts=" .. tostring(promptCount))
end

local function hookManualPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") or manualPromptConnections[prompt] then return end
    manualPromptConnections[prompt] = prompt.Triggered:Connect(function(player)
        if player == localPlayer then
            debugLog("Manual prompt", prompt:GetFullName(),
                "Action=" .. tostring(prompt.ActionText),
                "Object=" .. tostring(prompt.ObjectText),
                "Parent=" .. tostring(prompt.Parent and prompt.Parent:GetFullName()))
        end
    end)
end

local function copyDebugLog()
    local text = #debugLogLines > 0
        and table.concat(debugLogLines, "\n")
        or "[AH DEBUG] Chưa có log. Hãy bật Debug rồi thực hiện thao tác."
    if setclipboard then
        local ok = pcall(function() setclipboard(text) end)
        if ok then
            notify("Debug", "Đã sao chép " .. tostring(#debugLogLines) .. " dòng log.", 3)
            return true
        end
    end
    notify("Debug", "Không hỗ trợ sao chép clipboard trong môi trường này.", 4)
    return false
end

local function logError(tag, message, ...)
    local parts = { ... }
    local extra = ""
    if #parts > 0 then
        local values = {}
        for i, value in ipairs(parts) do
            values[i] = tostring(value)
        end
        extra = " | " .. table.concat(values, " | ")
    end
    local line = string.format("[AH ERROR][%s] %s%s", tostring(tag), tostring(message), extra)
    print(line)
    debugLog("ERROR " .. tostring(tag), tostring(message), unpack(parts))
end

notify = function(t, c, d)
    pcall(function()
        WindUI:Notify({ Title = t, Content = c, Duration = d or 3 })
    end)
end

-- character helpers
local function getChar() return localPlayer.Character end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHumanoid()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local applyCharacterScale
local applyThirdPerson

local function applyNoClip(enabled)
    state.noClip = enabled
    debugLog("NoClip", enabled and "enabled" or "disabled")
    local char = getChar()
    if not char then
        logError("NoClip", "Character not found while toggling NoClip")
        return false
    end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if enabled then
                pcall(function()
                    if part:GetAttribute("CanCollideBackup") == nil then
                        part:SetAttribute("CanCollideBackup", part.CanCollide)
                    end
                    if part:GetAttribute("CanTouchBackup") == nil then
                        part:SetAttribute("CanTouchBackup", part.CanTouch)
                    end
                    part.CanCollide = false
                    part.CanTouch = false
                    part.Massless = true
                end)
            else
                pcall(function()
                    local originalCollide = part:GetAttribute("CanCollideBackup")
                    local originalTouch = part:GetAttribute("CanTouchBackup")
                    if originalCollide ~= nil then
                        part.CanCollide = originalCollide
                        part:SetAttribute("CanCollideBackup", nil)
                    else
                        part.CanCollide = true
                    end
                    if originalTouch ~= nil then
                        part.CanTouch = originalTouch
                        part:SetAttribute("CanTouchBackup", nil)
                    else
                        part.CanTouch = true
                    end
                    part.Massless = false
                end)
            end
        end
    end

    return true
end

track(runService.Heartbeat:Connect(function()
    if dead or not state.noClip then return end
    if os.clock() - noClipLastUpdate < 0.08 then return end
    noClipLastUpdate = os.clock()
    local char = getChar()
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.Massless = true
        end
    end
end))

track(localPlayer.CharacterAdded:Connect(function(newChar)
    if not newChar then return end
    task.delay(0.2, function()
        pcall(function()
            if state.noClip then
                applyNoClip(true)
            end
            if state.shrink then
                applyCharacterScale(true)
            end
            if state.thirdPerson then
                applyThirdPerson()
            elseif workspace.CurrentCamera then
                workspace.CurrentCamera.FieldOfView = state.fov
            end
        end)
    end)
end))
local function setFullbright(enabled)
    debugLog("Fullbright", enabled and "enabled" or "disabled")
    if enabled then
        if not savedLighting then
            savedLighting = {
                Brightness = lighting.Brightness,
                ClockTime = lighting.ClockTime,
                FogEnd = lighting.FogEnd,
                GlobalShadows = lighting.GlobalShadows,
                Ambient = lighting.Ambient,
                OutdoorAmbient = lighting.OutdoorAmbient,
            }
        end
        lighting.Brightness = 2
        lighting.ClockTime = 14
        lighting.FogEnd = 100000
        lighting.GlobalShadows = false
        lighting.Ambient = Color3.fromRGB(255, 255, 255)
        lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
    elseif savedLighting then
        for property, value in pairs(savedLighting) do
            lighting[property] = value
        end
        savedLighting = nil
    end
end

local function rebuildWorldScanCache()
    cachedCandidates = {}
    cachedPrompts = {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child ~= localPlayer.Character then
            table.insert(cachedCandidates, child)
        else
            local name = string.lower(child.Name)
            if string.find(name, "item") or string.find(name, "tool")
                or string.find(name, "npc") or string.find(name, "patient") then
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("Model") then
                        table.insert(cachedCandidates, desc)
                    end
                end
            end
        end
    end
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            table.insert(cachedPrompts, desc)
        end
    end
    worldScanDirty = false
end


track(workspace.DescendantAdded:Connect(function(inst)
    hookManualPrompt(inst)
    if state.lowGraphics then return end
    if not inst:IsA("Highlight") then
        worldScanDirty = true
    end
end))

track(workspace.DescendantRemoving:Connect(function(inst)
    if state.lowGraphics then return end
    if not inst:IsA("Highlight") then
        worldScanDirty = true
    end
end))

-- ==========================================
-- ANOMALY DETECTOR
-- skinwalkers can't hide: attribute flags, camera effects,
-- and the classic face-swap tell
-- ==========================================
local function isAnomaly(model)
    if model:GetAttribute("Always Patient") == true then return false end
    if model:GetAttribute("Skinwalker") == true
        or model:GetAttribute("SkinwalkerEasy") == true
        or model:GetAttribute("PenaltyWhenLettingIn") == true
        or model:GetAttribute("HasCameraEffect") == true then
        return true
    end
    local camFx = model:GetAttribute("Camera Effect")
    local photoFx = model:GetAttribute("Photo Effect")
    if (camFx and camFx ~= "" and camFx ~= "None")
        or (photoFx and photoFx ~= "" and photoFx ~= "None") then
        return true
    end
    local originalFace = model:GetAttribute("OriginalFace")
    local head = model:FindFirstChild("Head")
    local decal = head and head:FindFirstChildOfClass("Decal")
    if originalFace and decal then
        if tostring(decal.Texture) ~= tostring(originalFace) then
            return true
        end
    end
    return false
end

-- ==========================================
-- ESP HIGHLIGHTS (cached: create once, recolor cheap)
-- ==========================================
local function applyHighlight(target, fillColor, espType)
    if not target or not target.Parent then return end
    if not state.wallhackEnabled then
        if highlightCache[target] and highlightCache[target].Parent then
            highlightCache[target]:Destroy()
            highlightCache[target] = nil
        end
        return
    end
    local fillTransparency = ({ [1] = 0.55, [2] = 0.35, [3] = 0.15 })[state.wallhackLevel] or 0.55
    if highlightCache[target] then
        highlightCache[target].FillColor = fillColor
        highlightCache[target].FillTransparency = fillTransparency
        highlightCache[target].OutlineTransparency = state.wallhackLevel >= 2 and 0 or 0.25
        highlightCache[target]:SetAttribute("ESPType", espType)
        return
    end
    local hl = Instance.new("Highlight")
    hl.FillColor = fillColor
    hl.FillTransparency = fillTransparency
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.OutlineTransparency = state.wallhackLevel >= 2 and 0 or 0.25
    hl.Adornee = target
    hl:SetAttribute("ESPType", espType)
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- glow through walls
    hl.Parent = target
    highlightCache[target] = hl
end

local function clearESPByType(espType)
    for target, hl in pairs(highlightCache) do
        if hl and hl.Parent and hl:GetAttribute("ESPType") == espType then
            hl:Destroy()
            highlightCache[target] = nil
        end
    end
end

local function clearLinesByType(espType)
    for target, entry in pairs(lineCache) do
        if entry.ESPType == espType then
            if entry.Frame then entry.Frame:Destroy() end
            lineCache[target] = nil
        end
    end
end

local function applyObjectHighlight(part, fillColor)
    if not part or not part.Parent then return end
    local target = (part:IsA("Model") and part) or part.Parent
    applyHighlight(target, fillColor, "ObjectItem")
end

-- ==========================================
-- ESP DRAW LINES (screen-bottom beams to targets)
-- ==========================================
local espLineGui = Instance.new("ScreenGui")
espLineGui.Name = "\0\1\2\3\8"
espLineGui.ResetOnSpawn = false
espLineGui.IgnoreGuiInset = true
espLineGui.DisplayOrder = 9999
espLineGui.Parent = (gethui and gethui()) or playerGui

local function addLineFor(target, color, espType)
    if not target or not target.Parent then return end
    if lineCache[target] then
        lineCache[target].Frame.BackgroundColor3 = color
        lineCache[target].ESPType = espType
        return
    end
    local frame = Instance.new("Frame")
    frame.BorderSizePixel = 0
    frame.BackgroundColor3 = color
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Visible = false
    frame.Parent = espLineGui
    lineCache[target] = { Frame = frame, ESPType = espType }
end

local function clearAllLines()
    for _, entry in pairs(lineCache) do
        if entry.Frame then entry.Frame:Destroy() end
    end
    lineCache = {}
end

local function rememberLowGraphicsValue(instance, property)
    if not savedLowGraphics[instance] then
        savedLowGraphics[instance] = {}
    end
    if savedLowGraphics[instance][property] == nil then
        local ok, value = pcall(function()
            return instance[property]
        end)
        if ok then
            savedLowGraphics[instance][property] = value
        end
    end
end

local function simplifyLowGraphicsInstance(instance)
    if not instance or not instance.Parent then return end

    local function setProperty(property, value)
        rememberLowGraphicsValue(instance, property)
        pcall(function() instance[property] = value end)
    end
    local function hasVisualName()
        local current = instance
        local probe = instance
        for _ = 1, 12 do
            if not probe then break end
            if probe:IsA("Model") then
                if probe:FindFirstChildOfClass("Humanoid")
                    or probe:FindFirstChildWhichIsA("ProximityPrompt", true)
                    or probe:FindFirstChildWhichIsA("ClickDetector", true) then
                    return false
                end
            end
            probe = probe.Parent
        end
        for _ = 1, 12 do
            if not current then break end
            local name = string.lower(current.Name)
            if name:find("tree", 1, true) or name:find("plant", 1, true)
                or name:find("leaf", 1, true) or name:find("foliage", 1, true)
                or name:find("bush", 1, true) or name:find("shrub", 1, true)
                or name:find("grass", 1, true) or name:find("weed", 1, true)
                or name:find("vegetation", 1, true) or name:find("decor", 1, true)
                or name:find("decoration", 1, true) or name:find("prop", 1, true)
                or name:find("foliage", 1, true) or name:find("flower", 1, true)
                or name:find("rock", 1, true) or name:find("statue", 1, true)
                or name:find("fountain", 1, true) then
                return true
            end
            current = current.Parent
        end
        return false
    end

    if instance:IsA("BasePart") then
        if hasVisualName() then
            setProperty("LocalTransparencyModifier", 1)
        else
            local partName = string.lower(instance.Name)
            if partName:find("ground", 1, true) or partName:find("soil", 1, true)
                or partName:find("dirt", 1, true) then
                setProperty("Color", Color3.fromRGB(183, 151, 112))
            end
            setProperty("Material", Enum.Material.Plastic)
            setProperty("Reflectance", 0)
            setProperty("CastShadow", false)
        end
    elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail")
        or instance:IsA("Beam") or instance:IsA("Smoke")
        or instance:IsA("Fire") or instance:IsA("Sparkles") then
        setProperty("Enabled", false)
    elseif instance:IsA("PostEffect") or instance:IsA("Highlight") then
        setProperty("Enabled", false)
    elseif instance:IsA("SelectionBox") or instance:IsA("BoxHandleAdornment") then
        setProperty("Visible", false)
    elseif instance:IsA("Clouds") then
        setProperty("Enabled", false)
    elseif instance:IsA("Sky") then
        setProperty("CelestialBodiesShown", false)
        setProperty("StarCount", 0)
        setProperty("SunAngularSize", 0)
        setProperty("MoonAngularSize", 0)
        setProperty("SkyboxBk", "")
        setProperty("SkyboxDn", "")
        setProperty("SkyboxFt", "")
        setProperty("SkyboxLf", "")
        setProperty("SkyboxRt", "")
        setProperty("SkyboxUp", "")
    elseif instance:IsA("Terrain") then
        setProperty("Decoration", false)
        setProperty("WaterColor", Color3.fromRGB(126, 177, 190))
    elseif instance:IsA("Atmosphere") then
        setProperty("Color", Color3.fromRGB(176, 214, 240))
        setProperty("Decay", Color3.fromRGB(176, 214, 240))
        setProperty("Density", 0.12)
        setProperty("Haze", 0)
        setProperty("Glare", 0)
    end
end

local function isInteractiveModel(model)
    return model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildWhichIsA("ProximityPrompt", true)
        or model:FindFirstChildWhichIsA("ClickDetector", true)
end

local function isSimpleProxyModel(model)
    if not model or not model:IsA("Model") or isInteractiveModel(model) then
        return false
    end
    local current = model
    for _ = 1, 4 do
        if not current then break end
        local name = string.lower(current.Name)
        if name:find("tree", 1, true) or name:find("plant", 1, true)
            or name:find("leaf", 1, true) or name:find("grass", 1, true)
            or name:find("bush", 1, true) or name:find("shrub", 1, true)
            or name:find("foliage", 1, true) or name:find("vegetation", 1, true)
            or name:find("building", 1, true) or name:find("house", 1, true)
            or name:find("apartment", 1, true) or name:find("structure", 1, true)
            or name:find("decor", 1, true) or name:find("decoration", 1, true)
            or name:find("prop", 1, true) or name:find("rock", 1, true)
            or name:find("statue", 1, true) or name:find("fountain", 1, true) then
            return true
        end
        current = current.Parent
    end
    return false
end

local function simplifyDecorationModel(model)
    if not state.lowGraphics or not isSimpleProxyModel(model) then return end
    pcall(function()
        if model:GetAttribute("StreamedOut") then return end
        model:SetAttribute("StreamedOut", true)
    end)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            pcall(function()
                rememberLowGraphicsValue(descendant, "LocalTransparencyModifier")
                descendant.LocalTransparencyModifier = 1
            end)
        end
    end
end

local function hideNpcModel(model)
    if not state.lowGraphics or not state.hideNpcGraphics
        or not model or not model:IsA("Model")
        or model == localPlayer.Character
        or string.lower(model.Name):find("npcvisit", 1, true) ~= nil
        or not model:FindFirstChildOfClass("Humanoid")
        or model:FindFirstChildWhichIsA("ProximityPrompt", true)
        or model:FindFirstChildWhichIsA("ClickDetector", true) then
        return
    end
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            rememberLowGraphicsValue(descendant, "LocalTransparencyModifier")
            descendant.LocalTransparencyModifier = 1
        elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
            rememberLowGraphicsValue(descendant, "Transparency")
            descendant.Transparency = 1
        end
    end
end

local function applyFov(value)
    local numeric = tonumber(value)
    if not numeric then return false end
    state.fov = math.clamp(numeric, 40, 120)
    local cam = workspace.CurrentCamera
    if not cam then return false end
    if savedCameraFov == nil then savedCameraFov = cam.FieldOfView end
    cam.FieldOfView = state.fov
    return true
end

local function setMaxGraphics(enabled)
    state.maxGraphics = enabled
    if enabled then
        if not savedMaxGraphics then
            savedMaxGraphics = {
                GlobalShadows = lighting.GlobalShadows,
                Technology = lighting.Technology,
                EnvironmentDiffuseScale = lighting.EnvironmentDiffuseScale,
                EnvironmentSpecularScale = lighting.EnvironmentSpecularScale,
                TerrainDecoration = workspace.Terrain.Decoration,
            }
        end
        local okSettings, userGameSettings = pcall(function()
            return UserSettings():GetService("UserGameSettings")
        end)
        if okSettings and userGameSettings and savedQualityLevel == nil then
            pcall(function() savedQualityLevel = userGameSettings.SavedQualityLevel end)
            if state.highQualityEdges then
                pcall(function() userGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel10 end)
            end
        end
        pcall(function() lighting.GlobalShadows = true end)
        pcall(function() lighting.Technology = Enum.Technology.Future end)
        pcall(function() lighting.EnvironmentDiffuseScale = 1 end)
        pcall(function() lighting.EnvironmentSpecularScale = 1 end)
        pcall(function() workspace.Terrain.Decoration = true end)
        for _, instance in ipairs(workspace:GetDescendants()) do
            if instance:IsA("MeshPart") then
                if savedMaxPartSettings[instance] == nil then
                    savedMaxPartSettings[instance] = {
                        RenderFidelity = instance.RenderFidelity,
                        CastShadow = instance.CastShadow,
                    }
                end
                pcall(function() instance.RenderFidelity = Enum.RenderFidelity.Precise end)
                pcall(function() instance.CastShadow = true end)
            elseif instance:IsA("BasePart") then
                if savedMaxPartSettings[instance] == nil then
                    savedMaxPartSettings[instance] = { CastShadow = instance.CastShadow }
                end
                pcall(function() instance.CastShadow = true end)
            end
        end
        if not maxGraphicsDescendantConn then
            maxGraphicsDescendantConn = workspace.DescendantAdded:Connect(function(instance)
                if not state.maxGraphics then return end
                if instance:IsA("MeshPart") then
                    pcall(function() instance.RenderFidelity = Enum.RenderFidelity.Precise end)
                    pcall(function() instance.CastShadow = true end)
                elseif instance:IsA("BasePart") then
                    pcall(function() instance.CastShadow = true end)
                end
            end)
        end
    elseif savedMaxGraphics then
        if maxGraphicsDescendantConn then
            maxGraphicsDescendantConn:Disconnect()
            maxGraphicsDescendantConn = nil
        end
        for property, value in pairs(savedMaxGraphics) do
            if property ~= "TerrainDecoration" then
                pcall(function() lighting[property] = value end)
            end
        end
        pcall(function() workspace.Terrain.Decoration = savedMaxGraphics.TerrainDecoration end)
        for instance, properties in pairs(savedMaxPartSettings) do
            if instance and instance.Parent then
                for property, value in pairs(properties) do
                    pcall(function() instance[property] = value end)
                end
            end
        end
        savedMaxPartSettings = {}
        if savedQualityLevel then
            pcall(function()
                UserSettings():GetService("UserGameSettings").SavedQualityLevel = savedQualityLevel
            end)
            savedQualityLevel = nil
        end
        savedMaxGraphics = nil
    end
end

local function processLowGraphicsBatch(runId)
    if not state.lowGraphics or runId ~= lowGraphicsRunId then return end

    local batch = {}
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") then
            local name = string.lower(instance.Name)
            if instance:FindFirstChildOfClass("Humanoid")
                or name:find("npc", 1, true)
                or name:find("visitor", 1, true)
                or name:find("patient", 1, true)
                or isSimpleProxyModel(instance) then
                table.insert(batch, instance)
            end
        elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail")
            or instance:IsA("Beam") or instance:IsA("Smoke")
            or instance:IsA("Fire") or instance:IsA("Sparkles")
            or instance:IsA("PostEffect") or instance:IsA("Highlight")
            or instance:IsA("Clouds") or instance:IsA("Sky")
            or instance:IsA("Atmosphere") or instance:IsA("SelectionBox")
            or instance:IsA("BoxHandleAdornment") then
            table.insert(batch, instance)
        end
    end

    for index, instance in ipairs(batch) do
        if not state.lowGraphics or runId ~= lowGraphicsRunId then return end
        if instance:IsA("Model") then
            simplifyDecorationModel(instance)
            hideNpcModel(instance)
        else
            simplifyLowGraphicsInstance(instance)
        end
        if index % 60 == 0 then
            task.wait()
        end
    end
end

local function setLowGraphics(enabled)
    state.lowGraphics = enabled
    lowGraphicsRunId = lowGraphicsRunId + 1
    local runId = lowGraphicsRunId
    debugLog("Low graphics", enabled and "enabled" or "disabled")

    if enabled then
        if not savedLowLighting then
            savedLowLighting = {
                Ambient = lighting.Ambient,
                OutdoorAmbient = lighting.OutdoorAmbient,
                ColorShift_Top = lighting.ColorShift_Top,
                ColorShift_Bottom = lighting.ColorShift_Bottom,
                FogColor = lighting.FogColor,
                FogEnd = lighting.FogEnd,
                GlobalShadows = lighting.GlobalShadows,
            }
        end
        lighting.Ambient = Color3.fromRGB(145, 190, 225)
        lighting.OutdoorAmbient = Color3.fromRGB(145, 190, 225)
        lighting.ColorShift_Top = Color3.fromRGB(0, 0, 0)
        lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
        lighting.FogColor = Color3.fromRGB(145, 190, 225)
        lighting.FogEnd = 100000
        lighting.GlobalShadows = false
        local terrain = workspace.Terrain
        for _, material in ipairs({ Enum.Material.Grass, Enum.Material.Ground,
            Enum.Material.LeafyGrass, Enum.Material.Mud, Enum.Material.Sand }) do
            if savedTerrainColors[material] == nil then
                savedTerrainColors[material] = terrain:GetMaterialColor(material)
            end
            terrain:SetMaterialColor(material, Color3.fromRGB(183, 151, 112))
        end
        task.spawn(processLowGraphicsBatch, runId)

        if not lowGraphicsDescendantConn then
            lowGraphicsDescendantConn = workspace.DescendantAdded:Connect(function(instance)
                if state.lowGraphics then
                    local shouldProcess = instance:IsA("ParticleEmitter")
                        or instance:IsA("Trail") or instance:IsA("Beam")
                        or instance:IsA("Smoke") or instance:IsA("Fire")
                        or instance:IsA("Sparkles") or instance:IsA("PostEffect")
                        or instance:IsA("Highlight") or instance:IsA("Clouds")
                        or instance:IsA("Sky") or instance:IsA("Atmosphere")
                        or instance:IsA("SelectionBox") or instance:IsA("BoxHandleAdornment")
                        or (instance:IsA("Model") and string.lower(instance.Name):find("npcvisit", 1, true) ~= nil)
                        or (instance:IsA("Model") and isSimpleProxyModel(instance))
                        or (instance:IsA("Model") and state.hideNpcGraphics
                            and instance:FindFirstChildOfClass("Humanoid") ~= nil)
                    if not shouldProcess and instance:IsA("BasePart") then
                        local name = string.lower(instance.Name)
                        shouldProcess = name:find("tree", 1, true) ~= nil
                            or name:find("leaf", 1, true) ~= nil
                            or name:find("grass", 1, true) ~= nil
                            or name:find("bush", 1, true) ~= nil
                            or name:find("decor", 1, true) ~= nil
                            or name:find("prop", 1, true) ~= nil
                    end
                    if shouldProcess then
                        task.defer(function()
                            if instance:IsA("Model") then
                                simplifyDecorationModel(instance)
                                hideNpcModel(instance)
                            else
                                simplifyLowGraphicsInstance(instance)
                            end
                        end)
                    end
                end
            end)
        end
    else
        if lowGraphicsDescendantConn then
            lowGraphicsDescendantConn:Disconnect()
            lowGraphicsDescendantConn = nil
        end
        for instance, properties in pairs(savedLowGraphics) do
            if instance and instance.Parent then
                for property, value in pairs(properties) do
                    pcall(function() instance[property] = value end)
                end
            end
        end
        savedLowGraphics = {}
        for _, instance in ipairs(workspace:GetDescendants()) do
            if instance:IsA("Model") and instance:GetAttribute("StreamedOut") then
                pcall(function() instance:SetAttribute("StreamedOut", nil) end)
            end
        end
        for material, color in pairs(savedTerrainColors) do
            pcall(function() workspace.Terrain:SetMaterialColor(material, color) end)
        end
        savedTerrainColors = {}
        if savedLowLighting then
            for property, value in pairs(savedLowLighting) do
                pcall(function() lighting[property] = value end)
            end
            savedLowLighting = nil
        end
    end

    if enabled then
        state.anomaliesESP = false
        state.patientsESP = false
        state.itemsESP = false
        state.playerESP = false
        state.drawLines = false
        clearAllLines()
        clearESPByType("Anomaly")
        clearESPByType("Patient")
        clearESPByType("ObjectItem")
        for _, player in ipairs(players:GetPlayers()) do
            local char = player.Character
            local highlight = char and char:FindFirstChild("AnchorMarker")
            if highlight then highlight:Destroy() end
            if char and lineCache[char] then
                if lineCache[char].Frame then lineCache[char].Frame:Destroy() end
                lineCache[char] = nil
            end
        end
    end
end

local function clearLineFor(target)
    if lineCache[target] then
        if lineCache[target].Frame then
            lineCache[target].Frame:Destroy()
        end
        lineCache[target] = nil
    end
end

-- line projector (every frame but EARLY-OUT when lines are off)
track(runService.RenderStepped:Connect(function()
    if dead then return end
    if not state.drawLines then
        if next(lineCache) then clearAllLines() end
        return
    end
    local vpSize = camera.ViewportSize
    local screenBottom = Vector2.new(vpSize.X / 2, vpSize.Y)
    for target, entry in pairs(lineCache) do
        if not target or not target.Parent then
            clearLineFor(target)
        else
            local part = nil
            if target:IsA("Model") then
                part = target:FindFirstChild("HumanoidRootPart")
                    or target:FindFirstChildWhichIsA("BasePart")
            elseif target:IsA("BasePart") then
                part = target
            end
            if part and part.Parent and part:IsDescendantOf(workspace) then
                local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local target2D = Vector2.new(screenPos.X, screenPos.Y)
                    local delta = target2D - screenBottom
                    local dist = delta.Magnitude
                    local angle = math.atan2(delta.Y, delta.X)
                    entry.Frame.Size = UDim2.new(0, dist, 0, 1.5)
                    entry.Frame.Position = UDim2.new(0, (screenBottom.X + target2D.X) / 2,
                        0, (screenBottom.Y + target2D.Y) / 2)
                    entry.Frame.Rotation = math.deg(angle)
                    entry.Frame.Visible = true
                else
                    entry.Frame.Visible = false
                end
            else
                entry.Frame.Visible = false
            end
        end
    end
end))

-- ==========================================
-- ESP SCAN LOOP (0.5s heartbeat, prunes dead targets first)
-- ==========================================
task.spawn(function()
    task.wait(6)

    while not dead do
        task.wait(state.lowGraphics and 2 or 1.2)
        if state.lowGraphics then
            continue
        end

        local anyEspOn = state.anomaliesESP or state.patientsESP
            or state.itemsESP or state.drawLines or state.playerESP

        if worldScanDirty and anyEspOn then
            rebuildWorldScanCache()
        end
        -- prune gone targets from the cache
        for target, hl in pairs(highlightCache) do
            if not target or not target.Parent then
                if hl and hl.Parent then hl:Destroy() end
                highlightCache[target] = nil
            end
        end

        if not anyEspOn then
            task.wait(0.2)
            continue
        end

        if not state.anomaliesESP then
            clearESPByType("Anomaly")
            clearLinesByType("Anomaly")
        end
        if not state.patientsESP then
            clearESPByType("Patient")
            clearLinesByType("Patient")
        end
        if not state.itemsESP then
            clearESPByType("ObjectItem")
            clearLinesByType("ObjectItem")
        end

        -- patients & anomalies live as top-level models AND inside
        -- any folder named npc / patient / item / tool (dive in!)
        for _, model in ipairs(cachedCandidates) do
            if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
                if not players:GetPlayerFromCharacter(model) then
                    if isAnomaly(model) then
                        if state.anomaliesESP then
                            if highlightCache[model]
                                and highlightCache[model]:GetAttribute("ESPType") == "Patient" then
                                highlightCache[model]:Destroy()
                                highlightCache[model] = nil
                            end
                            applyHighlight(model, Color3.fromRGB(255, 0, 0), "Anomaly")
                            if state.drawLines then
                                addLineFor(model, Color3.fromRGB(255, 0, 0), "Anomaly")
                            end
                        end
                    else
                        if state.patientsESP then
                            if highlightCache[model]
                                and highlightCache[model]:GetAttribute("ESPType") == "Anomaly" then
                                highlightCache[model]:Destroy()
                                highlightCache[model] = nil
                            end
                            applyHighlight(model, Color3.fromRGB(0, 255, 0), "Patient")
                            if state.drawLines then
                                addLineFor(model, Color3.fromRGB(0, 255, 0), "Patient")
                            end
                        end
                    end
                end
            end
        end

        -- items = loose prompts that don't belong to a breathing creature
        if state.itemsESP then
            pcall(function()
                for _, desc in ipairs(cachedPrompts) do
                    if desc:IsA("ProximityPrompt") then
                        local parent = desc.Parent
                        if parent then
                            local hasHumanoid =
                                (parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid"))
                                or (parent:FindFirstChild("Humanoid"))
                                or (parent.Name == "Head" and parent.Parent
                                    and parent.Parent:FindFirstChild("Humanoid"))
                                or (parent.Parent and parent.Parent:IsA("Model")
                                    and parent.Parent:FindFirstChildOfClass("Humanoid"))
                            if not hasHumanoid then
                                local target = (parent:IsA("Model") or parent:IsA("BasePart"))
                                    and parent or nil
                                if target then
                                    applyObjectHighlight(target, Color3.fromRGB(255, 255, 0))
                                    if state.drawLines then
                                        addLineFor(target, Color3.fromRGB(255, 255, 0), "ObjectItem")
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- ==========================================
-- PLAYER ESP (cyan, applies when someone respawns too)
-- ==========================================
local function applyPlayerESP(player)
    local char = player.Character
    if not char or char == localPlayer.Character then return end
    if not char:FindFirstChild("AnchorMarker") then
        local hl = Instance.new("Highlight")
        hl.Name = "AnchorMarker"
        hl.Adornee = char
        hl.FillColor = Color3.fromRGB(0, 255, 255)
        hl.FillTransparency = 0.6
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = char
    end
    if state.drawLines then
        addLineFor(char, Color3.fromRGB(0, 255, 255), "Player")
    end
end

local function removePlayerESP(player)
    local char = player.Character
    if char then
        local hl = char:FindFirstChild("AnchorMarker")
        if hl then hl:Destroy() end
        clearLineFor(char)
    end
end

track(runService.RenderStepped:Connect(function()
    if dead then return end
    if not (state.playerESP or state.drawLines) then return end
    if os.clock() - playerEspLastUpdate < 0.15 then return end
    playerEspLastUpdate = os.clock()
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer then
            if state.playerESP then
                applyPlayerESP(p)
            else
                local char = p.Character
                if char then
                    local hl = char:FindFirstChild("AnchorMarker")
                    if hl then hl:Destroy() end
                end
            end
            if state.drawLines then
                local char = p.Character
                if char then
                    addLineFor(char, Color3.fromRGB(0, 255, 255), "Player")
                end
            else
                clearLineFor(p.Character)
            end
        end
    end
end))

-- ==========================================
-- WALKSPEED (change-only writes, never spam)
-- cola boost window overrides your target speed while active
-- ==========================================
local colaBoostUntil = 0
local COLA_SPEED = 32

task.spawn(function()
    while not dead do
        task.wait(0.4)
        local hum = getHumanoid()
        if hum and hum.WalkSpeed ~= 0 then
            local target = (os.clock() < colaBoostUntil) and COLA_SPEED or state.speed
            if hum.WalkSpeed ~= target then
                hum.WalkSpeed = target
            end
        end
    end
end)

-- ==========================================
-- INF SANITY (attributes + stray value objects, locked at 100)
-- ==========================================
local function hookSanityValue(valueObj)
    if valueObj:IsA("ValueBase") then
        local name = string.lower(valueObj.Name)
        if string.find(name, "sanity") or string.find(name, "sanidad")
            or string.find(name, "cordura") then
            valueObj.Value = 100
            if not sanityConns[valueObj] then
                sanityConns[valueObj] = valueObj.Changed:Connect(function(newVal)
                    if state.infSanity and newVal ~= 100 then
                        valueObj.Value = 100
                    end
                end)
            end
        end
    end
end

task.spawn(function()
    while not dead do
        task.wait(0.25)
        if state.infSanity then
            pcall(function()
                if localPlayer:GetAttribute("Sanity") ~= 100 then
                    localPlayer:SetAttribute("Sanity", 100)
                end
                if localPlayer:GetAttribute("Sanidad") ~= 100 then
                    localPlayer:SetAttribute("Sanidad", 100)
                end
                local char = getChar()
                if char then
                    if char:GetAttribute("Sanity") ~= 100 then
                        char:SetAttribute("Sanity", 100)
                    end
                    if char:GetAttribute("Sanidad") ~= 100 then
                        char:SetAttribute("Sanidad", 100)
                    end
                    for _, child in ipairs(char:GetChildren()) do
                        hookSanityValue(child)
                    end
                end
                local stats = localPlayer:FindFirstChild("leaderstats")
                    or localPlayer:FindFirstChild("Data")
                    or localPlayer:FindFirstChild("Stats")
                if stats then
                    for _, child in ipairs(stats:GetChildren()) do
                        hookSanityValue(child)
                    end
                end
            end)
        end
    end
end)

-- ==========================================
-- 3RD PERSON CAMERA
-- ==========================================
applyThirdPerson = function()
    local char = getChar()
    if state.thirdPerson and char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.LocalTransparencyModifier = 0
            end
        end
    end
    local hum = getHumanoid()
    if hum then
        hum.CameraOffset = state.thirdPerson and Vector3.new(0, 2, 0) or Vector3.new(0, 0, 0)
    end

    local cam = workspace.CurrentCamera
    if cam then
        if savedCameraFov == nil then savedCameraFov = cam.FieldOfView end
        if state.thirdPerson then
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CameraSubject = hum
        else
            cam.CameraType = Enum.CameraType.Custom
            if hum then cam.CameraSubject = hum end
        end
        cam.FieldOfView = state.fov
    end
end

track(runService.RenderStepped:Connect(function()
    if dead then return end
    local char = getChar()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local cam = workspace.CurrentCamera
    if not root or not cam then return end

    if state.ghostMode then
        local ghostY = root.Position.Y
        local rotationX, rotationY, rotationZ = root.CFrame:ToEulerAnglesXYZ()
        root.CFrame = CFrame.new(root.Position.X, ghostY, root.Position.Z) * CFrame.Angles(rotationX, rotationY, rotationZ)
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.AutoRotate = false
        end
    end

    if not (state.thirdPerson or state.ghostMode) then return end

    local baseYaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)
    local desiredYaw = baseYaw + thirdPersonYaw
    local desiredPitch = math.clamp(thirdPersonPitch, -1.15, 1.15)

    local orbit = CFrame.fromEulerAnglesYXZ(desiredPitch, desiredYaw, 0)
    local distance = state.ghostMode and 11 or 10
    local height = state.ghostMode and 3.2 or 4.5
    local offset = orbit:VectorToWorldSpace(Vector3.new(0, height, -distance))
    local targetPos = root.Position + offset
    local lookAt = root.Position + Vector3.new(0, 1.7, 0)
    local desiredCF = CFrame.lookAt(targetPos, lookAt)

    cam.CFrame = cam.CFrame:Lerp(desiredCF, 0.18)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.CameraOffset = Vector3.new(0, 2, 0)
    end
    cam.Focus = CFrame.new(lookAt)
end))

track(userInputService.InputChanged:Connect(function(input, processed)
    if dead or processed then return end

    if thirdPersonMouseLook then
        local delta = input.Delta
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            thirdPersonYaw = thirdPersonYaw - delta.X * 0.005
            thirdPersonPitch = thirdPersonPitch - delta.Y * 0.0025
        elseif input.UserInputType == Enum.UserInputType.Touch and delta.Magnitude > 0 then
            thirdPersonYaw = thirdPersonYaw - delta.X * 0.005
            thirdPersonPitch = thirdPersonPitch - delta.Y * 0.0025
        end
    end
end))

track(userInputService.InputBegan:Connect(function(input, processed)
    if dead then return end

    if input.KeyCode == Enum.KeyCode.Space then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        thirdPersonMouseLook = state.thirdPerson
    end
end))

track(userInputService.InputEnded:Connect(function(input, processed)
    if dead then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        thirdPersonMouseLook = false
    end
end))

local function applyGhostMode(enabled)
    state.ghostMode = false
    return false
end

local function getNearestPlayerTarget()
    local localRoot = getRoot()
    if not localRoot then return nil end
    local bestPlayer, bestDist = nil, math.huge
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and p.Character then
            local targetRoot = p.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local dist = (targetRoot.Position - localRoot.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestPlayer = p
                end
            end
        end
    end
    return bestPlayer
end

local function getSelectedPushItem()
    local chosenName = tostring(state.objectPushItemName or ""):lower()
    local char = getChar()
    local backpack = localPlayer and localPlayer:FindFirstChildOfClass("Backpack")

    local function matchCandidate(candidate)
        if not candidate or not candidate:IsA("Tool") then return false end
        if chosenName == "" then return true end
        return string.lower(candidate.Name) == chosenName
    end

    if char then
        for _, child in ipairs(char:GetChildren()) do
            if matchCandidate(child) then
                return child
            end
        end
    end
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if matchCandidate(child) then
                return child
            end
        end
    end

    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                return child
            end
        end
    end
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                return child
            end
        end
    end
    return nil
end

local function applyLocalObjectPush(targetPlayer)
    local localRoot = getRoot()
    local targetCharacter = targetPlayer and targetPlayer.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not localRoot or not targetRoot then return false end

    local now = os.clock()
    if now - objectPushCooldown < 0.12 then return false end
    objectPushCooldown = now

    local pushTool = getSelectedPushItem()
    local origin = pushTool and pushTool:FindFirstChild("Handle")
    local fromPos = origin and origin.Position or localRoot.Position
    local toTarget = targetRoot.Position - fromPos
    if toTarget.Magnitude > (state.objectPushDistance or 10) then return false end

    local direction = toTarget
    if direction.Magnitude < 0.001 then
        direction = localRoot.CFrame.LookVector
    else
        direction = Vector3.new(direction.X, 0, direction.Z)
        if direction.Magnitude < 0.001 then
            direction = localRoot.CFrame.LookVector
        else
            direction = direction.Unit
        end
    end

    local force = tonumber(state.playerPushForce) or 35
    local existing = targetRoot:FindFirstChild("LocalPushVelocity")
    if existing and existing:IsA("BodyVelocity") then
        existing:Destroy()
    end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "LocalPushVelocity"
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = direction * force
    bv.Parent = targetRoot

    task.delay(0.2, function()
        if bv and bv.Parent then
            bv:Destroy()
        end
    end)

    return true
end

local function setFollowTarget(player)
    state.followTarget = player
    if player and player.Character then
        debugLog("Follow target", player.Name)
    end
end

local function registerInventoryItem(itemName)
    local name = tostring(itemName or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end
    for _, existing in ipairs(itemInventory) do
        if string.lower(existing) == string.lower(name) then
            return true
        end
    end
    table.insert(itemInventory, name)
    debugLog("Inventory add", name)
    if refreshInventoryButtons then
        refreshInventoryButtons()
    end
    return true
end

track(runService.RenderStepped:Connect(function()
    if dead or not state.followPlayer then return end
    local targetPlayer = state.followTarget or getNearestPlayerTarget()
    if not targetPlayer then return end
    local targetChar = targetPlayer.Character
    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    local localRoot = getRoot()
    if not targetRoot or not localRoot then return end

    local followAlpha = math.clamp(0.12 + (state.followSpeed / 60) * 0.24, 0.08, 0.38)
    local desiredOffset = targetRoot.CFrame.LookVector * math.max(state.followDistance, 1)
    local targetPos = targetRoot.Position - desiredOffset + Vector3.new(0, 2, 0)
    local desiredCF = CFrame.lookAt(targetPos, targetRoot.Position + Vector3.new(0, 2, 0))
    localRoot.CFrame = localRoot.CFrame:Lerp(desiredCF, followAlpha)
end))

track(runService.RenderStepped:Connect(function()
    if dead or not state.fixedFlight then return end
    local root = getRoot()
    local cam = workspace.CurrentCamera
    if not root or not cam then return end

    if not fixedFlightCFrame then
        fixedFlightCFrame = root.CFrame
    end

    local moveX = (userInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
        - (userInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
    local moveZ = (userInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
        - (userInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)

    local forward = cam.CFrame.LookVector
    local right = cam.CFrame.RightVector
    local flatForward = Vector3.new(forward.X, 0, forward.Z)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    if flatForward.Magnitude < 0.001 then flatForward = Vector3.new(0, 0, -1) end
    if flatRight.Magnitude < 0.001 then flatRight = Vector3.new(1, 0, 0) end
    flatForward = flatForward.Unit
    flatRight = flatRight.Unit

    local moveVec = (flatForward * moveZ) + (flatRight * moveX)
    local speed = math.clamp(state.speed * 0.9, 3, 28)
    local targetY = fixedFlightCFrame.Position.Y + state.fixedFlightHeight

    if moveVec.Magnitude > 0 then
        local desiredPos = root.Position + (moveVec.Unit * speed)
        desiredPos = Vector3.new(desiredPos.X, targetY, desiredPos.Z)
        root.CFrame = CFrame.new(desiredPos, desiredPos + Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z))
    else
        local current = root.CFrame
        root.CFrame = CFrame.new(current.Position.X, targetY, current.Position.Z)
            * CFrame.Angles(current:ToEulerAnglesXYZ())
    end

    if userInputService:IsKeyDown(Enum.KeyCode.Space) then
        local current = root.CFrame
        root.CFrame = CFrame.new(current.Position.X, current.Position.Y + 0.35, current.Position.Z)
    elseif userInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        local current = root.CFrame
        root.CFrame = CFrame.new(current.Position.X, current.Position.Y - 0.35, current.Position.Z)
    end

    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
end))

local function getVehicleSeat()
    local char = getChar()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.SeatPart
    return seat and seat:IsA("VehicleSeat") and seat or nil
end

local function pushNearestTargetPlayer(force)
    local localRoot = getRoot()
    if not localRoot then return false end

    local nearestPlayer, nearestDist = nil, math.huge
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local dist = (targetRoot.Position - localRoot.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearestPlayer = player
                end
            end
        end
    end

    if not nearestPlayer then
        notify("Đẩy người", "Không có người chơi nào gần để đẩy.", 2)
        return false
    end

    local targetCharacter = nearestPlayer.Character
    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return false end

    local direction = (targetRoot.Position - localRoot.Position)
    if direction.Magnitude < 0.001 then
        direction = localRoot.CFrame.LookVector
    end
    direction = direction.Unit

    local existing = targetRoot:FindFirstChild("LocalDragVelocity")
    if existing and existing:IsA("BodyVelocity") then
        existing:Destroy()
    end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "LocalDragVelocity"
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Velocity = direction * (tonumber(force) or state.playerPushForce or 35)
    bv.Parent = targetRoot

    task.delay(0.2, function()
        if bv and bv.Parent then
            bv:Destroy()
        end
    end)

    dragTargetPlayer = nearestPlayer
    notify("Đẩy người", "Đã kéo " .. nearestPlayer.Name .. " theo hướng của bạn (local).", 2)
    return true
end

track(runService.RenderStepped:Connect(function()
    if dead or not state.objectPushEnabled then return end
    local target = getNearestPlayerTarget()
    if not target then return end
    applyLocalObjectPush(target)
end))

local function findWheelParts(model)
    local wheels = {}
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local name = string.lower(part.Name)
            if name:find("wheel", 1, true) or name:find("tire", 1, true)
                or name:find("tyre", 1, true) then
                table.insert(wheels, part)
            end
        end
    end
    return wheels
end

local function setDriftEffects(model, enabled)
    if not state.driftEffects or not model then
        for wheel, emitter in pairs(driftEffectParts) do
            if emitter and emitter.Parent then emitter:Destroy() end
            driftEffectParts[wheel] = nil
        end
        return
    end

    local wheels = findWheelParts(model)
    for _, wheel in ipairs(wheels) do
        local emitter = driftEffectParts[wheel]
        if enabled and not emitter then
            emitter = Instance.new("ParticleEmitter")
            emitter.Name = "GroundDustEmitter"
            emitter.Enabled = false
            emitter.Rate = 18
            emitter.Lifetime = NumberRange.new(0.25, 0.5)
            emitter.Speed = NumberRange.new(2, 5)
            emitter.SpreadAngle = Vector2.new(35, 35)
            emitter.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.35),
                NumberSequenceKeypoint.new(1, 0),
            })
            emitter.Color = ColorSequence.new(Color3.fromRGB(178, 155, 115))
            emitter.Transparency = NumberSequence.new(0.25, 1)
            emitter.Parent = wheel
            driftEffectParts[wheel] = emitter
        end
        if emitter then emitter.Enabled = enabled end
    end
end

local function restoreVehicleProperties()
    for part, properties in pairs(vehicleSavedProperties) do
        if part and part.Parent then
            pcall(function() part.CustomPhysicalProperties = properties end)
        end
    end
    vehicleSavedProperties = {}
    for part, values in pairs(vehicleSavedVisuals) do
        if part and part.Parent then
            pcall(function()
                part.Color = values.Color
                part.Transparency = values.Transparency
                part.Material = values.Material
            end)
        end
    end
    vehicleSavedVisuals = {}
    vehicleLastModel = nil
    vehicleLastGrip = nil
    vehicleLastApply = 0
    vehicleLastLaunch = nil
    vehicleLastSteering = nil
    vehicleLastGlass = nil
    vehicleLastExhaust = nil
    for part, effect in pairs(vehicleExhaustParts) do
        if effect and effect.Parent then effect:Destroy() end
    end
    vehicleExhaustParts = {}
    for wheel, emitter in pairs(driftEffectParts) do
        if emitter and emitter.Parent then emitter:Destroy() end
    end
    driftEffectParts = {}
end

local function applyVehicleHandling(seat)
    local model = seat and seat:FindFirstAncestorOfClass("Model")
    if not model then return end
    if vehicleLastModel and vehicleLastModel ~= model then
        restoreVehicleProperties()
    end
    if model == vehicleLastModel and vehicleLastGrip == state.vehicleGrip
        and vehicleLastLaunch == state.vehicleLaunch
        and vehicleLastSteering == state.vehicleSteering
        and vehicleLastGlass == state.vehicleGlass
        and vehicleLastExhaust == state.vehicleExhaust
        and os.clock() - vehicleLastApply < 0.5 then
        return
    end
    vehicleLastModel = model
    vehicleLastGrip = state.vehicleGrip
    vehicleLastLaunch = state.vehicleLaunch
    vehicleLastSteering = state.vehicleSteering
    vehicleLastGlass = state.vehicleGlass
    vehicleLastExhaust = state.vehicleExhaust
    vehicleLastApply = os.clock()
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            if vehicleSavedProperties[part] == nil then
                vehicleSavedProperties[part] = part.CustomPhysicalProperties
            end
            local grip = math.clamp(state.vehicleGrip, 1, 10)
            local physical = part.CurrentPhysicalProperties
            part.CustomPhysicalProperties = PhysicalProperties.new(
                physical.Density,
                math.clamp(0.7 + (grip - 1) * 0.15, 0.7, 2),
                physical.Elasticity,
                physical.FrictionWeight,
                physical.ElasticityWeight
            )
            local partName = string.lower(part.Name)
            if partName:find("window", 1, true) or partName:find("glass", 1, true)
                or partName:find("windshield", 1, true) then
                if vehicleSavedVisuals[part] == nil then
                    vehicleSavedVisuals[part] = {
                        Color = part.Color,
                        Transparency = part.Transparency,
                        Material = part.Material,
                    }
                end
                part.Color = Color3.fromRGB(18, 24, 30)
                part.Transparency = math.clamp(state.vehicleGlass, 0.05, 0.9)
                part.Material = Enum.Material.Glass
            end
        end
    end
    pcall(function() seat.MaxSpeed = math.max(seat.MaxSpeed, 60 * state.vehicleLaunch) end)
    pcall(function() seat.Torque = math.max(seat.Torque, 10000 * state.vehicleLaunch) end)

    if state.vehicleExhaust then
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                local name = string.lower(part.Name)
                if (name:find("exhaust", 1, true) or name:find("muffler", 1, true)
                    or name:find("pipe", 1, true)) and not vehicleExhaustParts[part] then
                    local fire = Instance.new("Fire")
                    fire.Name = "ExhaustFireEmitter"
                    fire.Heat = 4
                    fire.Size = 3
                    fire.Color = Color3.fromRGB(255, 125, 25)
                    fire.SecondaryColor = Color3.fromRGB(255, 230, 120)
                    fire.Parent = part
                    vehicleExhaustParts[part] = fire
                end
            end
        end
    end
end

track(runService.Heartbeat:Connect(function()
    if dead then return end
    local seat = getVehicleSeat()
    if not seat then
        if vehicleLastModel then restoreVehicleProperties() end
        return
    end
    applyVehicleHandling(seat)

    local model = seat:FindFirstAncestorOfClass("Model")
    local velocity = seat.AssemblyLinearVelocity
    local speed = velocity.Magnitude
    local sidewaysSpeed = math.abs(seat.CFrame.RightVector:Dot(velocity))
    local steerStrength = 1.6 + (state.vehicleSteering * 0.9)
    local drifting = speed > 8 and sidewaysSpeed > 8 and math.abs(seat.SteerFloat) > 0.12
    if model then setDriftEffects(model, drifting) end

    local rootPart = model and model:FindFirstChildWhichIsA("BasePart")
    if rootPart and math.abs(seat.SteerFloat) > 0.01 then
        rootPart.AssemblyAngularVelocity = Vector3.new(
            0,
            seat.SteerFloat * steerStrength,
            0
        )
    end

    if state.vehicleBrakeHeld and state.vehicleBrake > 1 then
        local currentVel = seat.AssemblyLinearVelocity
        local brake = math.clamp(1 - state.vehicleBrake * 0.035, 0.55, 0.96)
        seat.AssemblyLinearVelocity = currentVel * brake
    end
end))

track(userInputService.InputBegan:Connect(function(input, processed)
    if dead or processed then return end
    if input.KeyCode == Enum.KeyCode.S then
        state.vehicleBrakeHeld = true
    end
end))

track(userInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.S then
        state.vehicleBrakeHeld = false
    end
end))

local characterModelScaleCache = {}

applyCharacterScale = function(enabled)
    state.shrink = enabled
    local char = getChar()
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if not char.ScaleTo or not char.GetScale then
        logError("Shrink", "This character rig does not support local Model scaling")
        return false
    end

    local ok, currentScale = pcall(function()
        return char:GetScale()
    end)
    if enabled and characterModelScaleCache[char] == nil then
        characterModelScaleCache[char] = (ok and currentScale) or 1
    end
    local targetScale = enabled and ((characterModelScaleCache[char] or 1) * state.characterScale)
        or (characterModelScaleCache[char] or 1)
    local scaled, scaleError = pcall(function()
        char:ScaleTo(targetScale)
    end)
    if not scaled then
        logError("Shrink", "Character:ScaleTo failed", scaleError)
    elseif not enabled then
        characterModelScaleCache[char] = nil
    end

    local verifyOk, scale = pcall(function() return char:GetScale() end)
    local expectedScale = enabled and ((characterModelScaleCache[char] or 1) * state.characterScale)
        or (characterModelScaleCache[char] or 1)
    if enabled and verifyOk and math.abs(scale - expectedScale) > 0.05 then
        logError("Shrink", "Rig did not accept the requested scale", scale, "expected=" .. tostring(expectedScale))
        return false
    end
    return true
end

-- ==========================================
-- FASTER ACTIONS (every prompt fires instantly)
-- ==========================================
local function applyFasterActions()
    debugLog("Faster actions", state.fasterActions and "enabled" or "disabled")
    pcall(function()
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                if state.fasterActions then
                    if promptDurations[desc] == nil then
                        promptDurations[desc] = desc.HoldDuration
                    end
                    desc.HoldDuration = 0
                elseif promptDurations[desc] ~= nil then
                    desc.HoldDuration = promptDurations[desc]
                    promptDurations[desc] = nil
                end
            end
        end
    end)
end

track(workspace.DescendantAdded:Connect(function(inst)
    if dead then return end
    if state.fasterActions and inst:IsA("ProximityPrompt") then
        task.wait(0.1)
        pcall(function()
            promptDurations[inst] = inst.HoldDuration
            inst.HoldDuration = 0
        end)
    end
end))

-- ==========================================
-- ANTI AFK
-- ==========================================
track(localPlayer.Idled:Connect(function()
    if dead or not state.antiAfk then return end
    pcall(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new())
    end)
end))

-- ==========================================
-- AUTO MINIGAMES
-- clicks the heartbeat game buttons, queues the color game,
-- skips exits and danger buttons like they owe us money
-- ==========================================
local minigameLastTrigger = os.clock()

local function clickGuiButton(btn)
    if not btn or not btn.Parent then return end
    if minigameClicked[btn] then return end
    local absPos = btn.AbsolutePosition
    local absSize = btn.AbsoluteSize
    if absSize.X == 0 or absSize.Y == 0 or (absPos.X == 0 and absPos.Y == 0) then
        return
    end
    minigameClicked[btn] = true
    task.spawn(function()
        pcall(function()
            local inset = guiService:GetGuiInset()
            local x = absPos.X + (absSize.X / 2) + inset.X
            local y = absPos.Y + (absSize.Y / 2) + inset.Y
            virtualInputManager:SendMouseMoveEvent(x, y, game)
            task.wait(0.04)
            virtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.01)
            virtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
        pcall(function()
            if firesignal then
                firesignal(btn.MouseButton1Click)
                firesignal(btn.Activated)
            end
        end)
    end)
    task.delay(1.5, function() minigameClicked[btn] = nil end)
end

local function hookColorMinigame()
    local rooms = workspace:FindFirstChild("Rooms")
    local emergency = rooms and rooms:FindFirstChild("Emergency")
    local emergRooms = emergency and emergency:FindFirstChild("Rooms")
    local room6 = emergRooms and emergRooms:FindFirstChild("Room6")
    local minigame = room6 and room6:FindFirstChild("Minigame")
    if minigame and minigame:FindFirstChild("Colors") then
        for _, colorBtn in ipairs(minigame.Colors:GetChildren()) do
            local button = colorBtn:FindFirstChild("Button")
            if button and not button:GetAttribute("SignalBound") then
                button:SetAttribute("SignalBound", true)
                button:SetAttribute("InitialColor", tostring(button.Color))
                track(button:GetPropertyChangedSignal("Color"):Connect(function()
                    if state.autoMinigames then
                        local origStr = button:GetAttribute("InitialColor")
                        if origStr and tostring(button.Color) ~= origStr then
                            if not minigameClicked[button] then
                                table.insert(minigameQueue, button)
                                minigameLastTrigger = os.clock()
                            end
                        end
                    end
                end))
            end
        end
    end
end

local function isExitButton(btn)
    local name = string.lower(btn.Name)
    local text = (btn:IsA("TextButton") and string.lower(btn.Text)) or ""
    return string.find(name, "close") or string.find(name, "exit")
        or string.find(name, "leave") or string.find(name, "salir")
        or name == "x" or text == "x" or string.find(text, "salir")
end

local function isDangerButton(btn)
    local name = string.lower(btn.Name)
    return string.find(name, "danger") or btn:FindFirstChild("Skull")
        or btn:FindFirstChild("skull")
end

-- heartbeat minigame + button minigame auto clicks
track(runService.Heartbeat:Connect(function()
    if dead or not state.autoMinigames then return end
    local hbUI = playerGui:FindFirstChild("HeartbeatMinigameUI")
    if hbUI then
        local frame = hbUI:FindFirstChild("Frame")
        if frame and frame.Visible then
            for _, desc in ipairs(frame:GetDescendants()) do
                if desc:IsA("GuiButton") and desc.Visible
                    and desc.Parent.Name ~= "Folder" then
                    if not isExitButton(desc) and not isDangerButton(desc) then
                        clickGuiButton(desc)
                    end
                end
            end
        end
    end
    local mg = playerGui:FindFirstChild("Minigame")
    if mg then
        local frame = mg:FindFirstChild("Frame")
        if frame and frame.Visible then
            local holder = frame:FindFirstChild("ButtonsHolder")
            if holder then
                for _, btn in ipairs(holder:GetChildren()) do
                    if btn:IsA("GuiButton") and btn.Visible then
                        clickGuiButton(btn)
                    end
                end
            end
        end
    end
end))

-- color minigame queue: fires the world prompt after the UI goes quiet
task.spawn(function()
    while not dead do
        if state.autoMinigames and #minigameQueue > 0
            and (os.clock() - minigameLastTrigger) > 3 then
            for _, btn in ipairs(minigameQueue) do
                if btn and btn.Parent then
                    local cd = btn:FindFirstChild("ClickDetector")
                    local pp = btn:FindFirstChild("PP")
                        or btn:FindFirstChildOfClass("ProximityPrompt")
                    pcall(function()
                        if cd and fireclickdetector then
                            fireclickdetector(cd)
                        elseif pp and fireproximityprompt then
                            fireproximityprompt(pp)
                        end
                    end)
                    task.wait(0.6)
                end
            end
            minigameQueue = {}
            minigameClicked = {}
        end
        task.wait(0.2)
    end
end)

-- drop buttons from the clicked-set once they're gone
task.spawn(function()
    while not dead do
        task.wait(0.25)
        if state.autoMinigames then
            for btn in pairs(minigameClicked) do
                if not btn or not btn.Parent or btn.Visible == false
                    or (btn.Parent and btn.Parent.Name == "Folder") then
                    minigameClicked[btn] = nil
                end
            end
        end
    end
end)

-- ==========================================
-- AUTO TASKS (BETA)
-- the full checkin dance: form, camera, computer, badge,
-- printer, photo — and it slams the shutter on skinwalkers
-- ==========================================
local taskStepCFrames = {
    [1] = {
        Camera = CFrame.new(-104.082085, 5.211154, 0.033473, 0.999763, 0.012997, -0.017454, 0, 0.802057, -0.597106, 0.021762, 0.597248, 0.801867),
        Root   = CFrame.new(-104.073357, 3.412531, -0.367461, 0.999763, 0, -0.021764, 0, 1, 0, 0.021764, 0, 0.999763),
    },
    [2] = {
        Camera = CFrame.new(-108.414391, 5.097577, 0.123036, 0.991486, -0.048192, 0.12097, 0, 0.928995, 0.370083, -0.130216, -0.366942, 0.921085),
        Root   = CFrame.new(-108.474876, 3.412531, -0.337506, 0.991485, 0, 0.130218, 0, 1, 0, -0.130218, 0, 0.991485),
    },
    [3] = {
        Camera = CFrame.new(-99.982895, 5.015163, 0.411147, 0.706237, 0.145322, -0.6929, 0, 0.978707, 0.205264, 0.707976, -0.144965, 0.69119),
        Root   = CFrame.new(-99.636444, 3.412531, 0.065548, 0.706236, 0, -0.707976, 0, 1, 0, 0.707976, 0, 0.706236),
    },
    [4] = {
        Camera = CFrame.new(-99.491142, 5.3251, 1.201594, -0.018005, 0.825005, -0.564838, 0, 0.56493, 0.825139, 0.999838, 0.014857, -0.010172),
        Root   = CFrame.new(-99.208725, 3.412531, 1.20668, -0.018005, 0, -0.999838, 0, 1, 0, 0.999838, 0, -0.018005),
    },
    [5] = {
        Camera = CFrame.new(-106.80722, 5.164389, -6.988466, 0.04727, 0.513142, -0.857001, 0, 0.85796, 0.513117, 0.998882, -0.024283, 0.040556),
        Root   = CFrame.new(-106.378723, 3.407531, -7.008744, 0.047271, 0, -0.998882, 0, 1, 0, 0.998882, 0, 0.047271),
    },
    [6] = {
        Root = CFrame.new(-99.208725, 3.412531, 1.20668, -0.018005, 0, -0.999838, 0, 1, 0, 0.999838, 0, -0.018005),
    },
}

local checkinSubTargets = { "Form", "Camera", "Computer", "PatientBadgeBase", "Printer", "Photo" }
local lastTaskDiagnostic = ""
local lastTaskDiagnosticAt = 0

local function taskDiagnostic(message)
    debugLog("Diagnostic", message)
    local now = os.clock()
    if lastTaskDiagnostic == message and now - lastTaskDiagnosticAt < 8 then
        return
    end
    lastTaskDiagnostic = message
    lastTaskDiagnosticAt = now
    notify("Auto Tasks", message, 3)
end

local function setAutomationPhase(phase)
    automationPhase = phase
    debugLog("Phase", phase)
end

local function isPatientModel(model)
    if not model or not model:IsA("Model") then return false end
    if model == localPlayer.Character or players:GetPlayerFromCharacter(model) then
        return false
    end

    local hasHumanoid = model:FindFirstChildOfClass("Humanoid") ~= nil
    local hasBodyPart = model:FindFirstChild("HumanoidRootPart") ~= nil or model:FindFirstChildWhichIsA("BasePart", true) ~= nil
    if not hasHumanoid and not hasBodyPart then
        return false
    end

    local name = string.lower(model.Name)
    local attrFlags = {
        "Patient",
        "IsPatient",
        "PatientNPC",
        "Skinwalker",
        "SkinwalkerEasy",
        "PenaltyWhenLettingIn",
        "HasCameraEffect",
        "IsNPC",
        "NPC",
        "Visitor",
        "Guest",
    }

    local isPatient = false
    for _, key in ipairs(attrFlags) do
        if model:GetAttribute(key) == true then
            isPatient = true
            break
        end
    end

    if not isPatient then
        for _, token in ipairs({ "patient", "npc", "guest", "visitor" }) do
            if name:find(token, 1, true) ~= nil then
                isPatient = true
                break
            end
        end
    end

    if debugEnabled and isPatient then
        debugLog("Patient candidate", model:GetFullName(), "Name=" .. model.Name, "Humanoid=" .. tostring(hasHumanoid), "BodyPart=" .. tostring(hasBodyPart))
    end

    return isPatient
end

local function findDescendantByNames(root, names)
    if not root then return nil end
    local wanted = {}
    for _, name in ipairs(names) do
        wanted[string.lower(name)] = true
    end
    if wanted[string.lower(root.Name)] then return root end
    for _, descendant in ipairs(root:GetDescendants()) do
        if wanted[string.lower(descendant.Name)] then
            return descendant
        end
    end
    return nil
end

local function findPrompt(root)
    if not root then return nil end
    if root:IsA("ProximityPrompt") then return root end
    local named = root:FindFirstChild("PP", true)
    if named and named:IsA("ProximityPrompt") then return named end
    return root:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function isHealPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return false end
    local text = string.lower(tostring(prompt.Name) .. " " .. tostring(prompt.ActionText) .. " " .. tostring(prompt.ObjectText))
    if text:find("curtain", 1, true) or text:find("shutter", 1, true)
        or text:find("door", 1, true) or text:find("open", 1, true)
        or text:find("close", 1, true) then
        return false
    end
    return text:find("heal", 1, true) or text:find("treat", 1, true)
        or text:find("patient", 1, true) or text:find("bed", 1, true)
        or text:find("diagn", 1, true) or text:find("room", 1, true)
end

local function findTaskPrompt(root, targetName)
    local prompt = findPrompt(findDescendantByNames(root, { targetName }))
    if prompt then return prompt end
    if not root then return nil end
    local needle = string.lower(targetName):gsub("[^%w]", "")
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            local values = {
                descendant.Name,
                descendant.ActionText,
                descendant.ObjectText,
            }
            for _, value in ipairs(values) do
                local normalized = string.lower(tostring(value)):gsub("[^%w]", "")
                if normalized:find(needle, 1, true) then
                    return descendant
                end
            end
        end
    end
    return nil
end

local function fireTaskPrompt(prompt)
    if not prompt then
        logError("Prompt", "Attempted to fire nil prompt")
        return false
    end
    if not prompt:IsA("ProximityPrompt") then
        logError("Prompt", "Object is not a ProximityPrompt", tostring(prompt.ClassName), prompt:GetFullName())
        return false
    end
    if prompt.Enabled == false then
        debugLog("Prompt skipped", "disabled", getPromptDescription(prompt))
        return false
    end
    if not fireproximityprompt then
        logError("Prompt", "fireproximityprompt unavailable", getPromptDescription(prompt))
        notify("Auto Tasks", "Môi trường hiện tại không hỗ trợ fireproximityprompt.", 4)
        return false
    end
    local ok, err = pcall(function()
        fireproximityprompt(prompt)
    end)
    if ok then
        debugLog("Prompt fired", getPromptDescription(prompt), "enabled=" .. tostring(prompt.Enabled))
    else
        logError("Prompt", "fireproximityprompt raised an error", getPromptDescription(prompt), err)
        debugLog("Prompt error", getPromptDescription(prompt), tostring(err))
    end
    return ok
end

local function scanWorkspaceNames()
    local matches = {}
    local tokens = {
        "patient", "npc", "checkin", "check in", "check-in", "form", "camera",
        "computer", "printer", "photo", "badge", "reception", "nurse", "doctor",
        "medical", "treatment", "room", "desk", "shutter"
    }

    for _, descendant in ipairs(workspace:GetDescendants()) do
        local name = tostring(descendant.Name)
        local lower = string.lower(name)
        local hits = {}
        for _, token in ipairs(tokens) do
            if lower:find(token, 1, true) then
                table.insert(hits, token)
            end
        end

        if #hits > 0 then
            local info = string.format("%s | class=%s | hits=%s",
                name,
                tostring(descendant.ClassName),
                table.concat(hits, ", "))
            table.insert(matches, info)
            print("[AH SCAN] " .. info)
        end

        if descendant:IsA("ProximityPrompt") then
            local promptInfo = string.format("PROMPT %s | action=%s | object=%s",
                tostring(descendant:GetFullName()),
                tostring(descendant.ActionText),
                tostring(descendant.ObjectText))
            print("[AH SCAN] " .. promptInfo)
            table.insert(matches, promptInfo)
        end
    end

    return matches
end

local function findCheckinFolder()
    local checkNames = { "CheckIn", "Checkin", "Check-in", "Check In", "CheckInDesk", "CheckInRoom", "Check In Room", "Check In Station" }
    local found = findDescendantByNames(workspace, checkNames)
    if found then return found end

    local fallbackCandidates = {}
    for _, descendant in ipairs(workspace:GetDescendants()) do
        local isContainer = descendant:IsA("Model") or descendant:IsA("Folder")
        if isContainer then
            local name = string.lower(tostring(descendant.Name))
            local isCheckinCandidate = name:find("checkin", 1, true)
                or name:find("check in", 1, true)
                or name:find("check-in", 1, true)
                or name:find("reception", 1, true)
                or name:find("waiting", 1, true)
            if isCheckinCandidate then
                table.insert(fallbackCandidates, descendant)
            end
        end
    end

    if #fallbackCandidates > 0 then
        table.sort(fallbackCandidates, function(a, b)
            local aName = string.lower(tostring(a.Name))
            local bName = string.lower(tostring(b.Name))
            if aName:find("checkin", 1, true) and not bName:find("checkin", 1, true) then return true end
            if bName:find("checkin", 1, true) and not aName:find("checkin", 1, true) then return false end
            return aName < bName
        end)
        return fallbackCandidates[1]
    end

    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("Model") or descendant:IsA("Folder") then
            local lower = string.lower(descendant.Name)
            local hasCheckStep = lower:find("form", 1, true) or lower:find("camera", 1, true)
                or lower:find("computer", 1, true) or lower:find("printer", 1, true)
                or lower:find("photo", 1, true) or lower:find("badge", 1, true)
            if hasCheckStep and descendant.Parent then
                return descendant.Parent
            end
        end
    end

    print("[AH SCAN] No check-in folder matched. Full workspace scan started.")
    scanWorkspaceNames()
    return nil
end

local function findActiveNpc()
    local folder = findDescendantByNames(workspace, { "NPCs", "NPC", "Patients", "Patient" })
    local candidates = {}

    if folder then
        for _, child in ipairs(folder:GetDescendants()) do
            if child:IsA("Model") and isPatientModel(child) then
                table.insert(candidates, child)
            end
        end
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") and isPatientModel(child) then
                table.insert(candidates, child)
            end
        end
        if isPatientModel(folder) then
            table.insert(candidates, folder)
        end
    end

    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("Model") and isPatientModel(descendant) then
            table.insert(candidates, descendant)
        end
    end

    if #candidates > 0 then
        table.sort(candidates, function(a, b)
            local aName = tostring(a.Name):lower()
            local bName = tostring(b.Name):lower()
            local aScore = 0
            local bScore = 0
            if aName:find("patient", 1, true) then aScore = aScore + 5 end
            if aName:find("npc", 1, true) then aScore = aScore + 4 end
            if a:GetAttribute("Patient") == true then aScore = aScore + 3 end
            if bName:find("patient", 1, true) then bScore = bScore + 5 end
            if bName:find("npc", 1, true) then bScore = bScore + 4 end
            if b:GetAttribute("Patient") == true then bScore = bScore + 3 end
            return aScore > bScore
        end)
        return candidates[1]
    end

    return nil
end

local function getPromptDescription(prompt)
    return string.format("%s | Action=%s | Object=%s", prompt:GetFullName(), prompt.ActionText, prompt.ObjectText)
end

local function diagnoseAutomation()
    debugLog("Diagnostic started")
    print("[AH SCAN] Running exhaustive workspace scan for patient/checkin names.")
    scanWorkspaceNames()

    local patientCount = 0
    local promptCount = 0
    local patientNames = {}
    for _, descendant in ipairs(workspace:GetDescendants()) do
        if descendant:IsA("Model") and isPatientModel(descendant) then
            patientCount = patientCount + 1
            if #patientNames < 8 then table.insert(patientNames, descendant.Name) end
        elseif descendant:IsA("ProximityPrompt") then
            promptCount = promptCount + 1
        end
    end
    local roomFolder = findDescendantByNames(workspace, { "Rooms", "PatientRooms", "Patient Rooms" })
    local checkinFolder = findCheckinFolder()
    taskDiagnostic(string.format(
        "Chẩn đoán: %d bệnh nhân, %d prompt, Rooms=%s, Checkin=%s, phase=%s",
        patientCount,
        promptCount,
        roomFolder and roomFolder:GetFullName() or "không có",
        checkinFolder and checkinFolder:GetFullName() or "không có",
        automationPhase
    ))
    if #patientNames > 0 then
        taskDiagnostic("Bệnh nhân: " .. table.concat(patientNames, ", "))
    end
    debugLog("Diagnostic finished", patientCount, promptCount)
end

local function moveToPrompt(root, prompt, distance)
    if not root or not prompt or not prompt.Parent then
        debugLog("Move failed", "missing root or prompt")
        return false
    end
    local target = prompt.Parent:IsA("BasePart") and prompt.Parent
        or prompt.Parent:FindFirstChildWhichIsA("BasePart", true)
    if not target then
        debugLog("Move failed", "no target part", prompt:GetFullName())
        return false
    end
    root.CFrame = target.CFrame * CFrame.new(0, 0, distance or 2)
    debugLog("Moved to prompt", getPromptDescription(prompt))
    return true
end

local function doTaskAtPrompt(prompt, stepIndex)
    debugLog("Task step started", stepIndex, getPromptDescription(prompt))
    local char = getChar()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not prompt or not hum then return end
    local oldCFrame = root.CFrame
    local wasAnchored = root.Anchored
    root.Anchored = true
    local step = taskStepCFrames[stepIndex]
    if step then
        if step.Camera then camera.CFrame = step.Camera end
        if step.Root then root.CFrame = step.Root end
        if stepIndex == 6 and prompt.Parent then
            local targetPos = prompt.Parent:GetPivot().Position
            root.CFrame = step.Root
            camera.CFrame = CFrame.lookAt(Vector3.new(-99.208725, 5, 1.20668), targetPos)
        end
    end
    if prompt.Parent then
        local target = prompt.Parent:IsA("BasePart") and prompt.Parent
            or prompt.Parent:FindFirstChildWhichIsA("BasePart", true)
        if target then
            root.CFrame = CFrame.new(target.Position + Vector3.new(0, 0, 2))
            camera.CFrame = CFrame.lookAt(root.Position, target.Position)
        end
    end
    task.wait(0.6)
    fireTaskPrompt(prompt)
    task.wait(0.6)
    camera.CameraSubject = hum
    root.Anchored = wasAnchored
    if not prompt.Enabled then
        root.CFrame = oldCFrame
    end
    debugLog("Task step finished", stepIndex, "enabled=" .. tostring(prompt.Enabled))
end

local function autoTasksLoop(runId)
    if automationBusy then
        state.autoTasks = false
        taskDiagnostic("Đang có một tác vụ tự động khác chạy.")
        return
    end
    automationBusy = true
    setAutomationPhase("Auto Tasks")
    local checkinFolder = findCheckinFolder()
    debugLog("Auto Tasks checkin resolved", checkinFolder and checkinFolder:GetFullName() or "nil")
    -- invisible helper blocks (marker spots from the original dance)
    local cubo1 = Instance.new("Part")
    cubo1.Name = "Cubo1Ref"
    cubo1.Size = Vector3.new(2, 2, 2)
    cubo1.Position = Vector3.new(-107.448, 7.435, 7.999)
    cubo1.Anchored = true
    cubo1.Transparency = 1
    cubo1.CanCollide = false
    cubo1.Parent = workspace
    table.insert(helperParts, cubo1)

    while state.autoTasks and autoTaskRunId == runId and not dead do
        local npc = findActiveNpc()
        local checkinFolder = findCheckinFolder()
        if not npc then
            taskDiagnostic("Không tìm thấy NPC bệnh nhân đang hoạt động.")
            logError("AutoTasks", "No active patient NPC found.", checkinFolder and checkinFolder:GetFullName() or "No checkin folder")
        elseif not checkinFolder then
            taskDiagnostic("Không tìm thấy khu Check-in trong Workspace.")
            logError("AutoTasks", "Checkin folder missing.", npc:GetFullName())
        else
                debugLog("Auto Tasks target", npc:GetFullName(), checkinFolder:GetFullName())
                local isAnom = (npc:GetAttribute("Skinwalker") == true)
                    or (npc:GetAttribute("SkinwalkerEasy") == true)
                    or (npc:GetAttribute("PenaltyWhenLettingIn") == true)
                    or (npc:GetAttribute("HasCameraEffect") == true)
                debugLog("Auto Tasks patient status", npc:GetFullName(), "anomaly=" .. tostring(isAnom), "patient=" .. tostring(npc:GetAttribute("Patient")))
                if isAnom then
                    -- skinwalker at the door? shutter SLAMS
                    local shutter = findDescendantByNames(checkinFolder, { "ShutterButton", "Shutter" })
                    local pp = findPrompt(shutter)
                    if pp then
                        debugLog("Auto Tasks skinwalker shutter", pp:GetFullName())
                        fireTaskPrompt(pp)
                        task.wait(4)
                        fireTaskPrompt(pp)
                    else
                        taskDiagnostic("Không tìm thấy nút đóng cửa cho NPC bất thường.")
                        logError("AutoTasks", "Skinwalker shutter missing", checkinFolder:GetFullName())
                    end
                else
                    for idx, name in ipairs(checkinSubTargets) do
                        if not state.autoTasks or dead then break end
                        local pp = findTaskPrompt(checkinFolder, name)
                        if pp then
                            debugLog("Auto Tasks step", idx, name, pp:GetFullName())
                            doTaskAtPrompt(pp, idx)
                            task.wait(1.4)
                        else
                            taskDiagnostic("Không tìm thấy bước Check-in: " .. name)
                            logError("AutoTasks", "Missing check-in prompt step", name, checkinFolder:GetFullName())
                        end
                    end
                    task.wait(2)
                end
        end
        local char = getChar()
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root and cubo1 and cubo1.Parent then
            root.Anchored = true
            root.CFrame = CFrame.new(cubo1.Position + Vector3.new(0, 3, 0))
            task.wait(0.1)
            root.Anchored = false
        end
        task.wait(0.5)
    end

    if cubo1 and cubo1.Parent then cubo1:Destroy() end
    automationBusy = false
    setAutomationPhase("Idle")
end

-- ==========================================
-- AUTO HEAL (BETA)
-- walks the whole fix-a-patient circuit by itself
-- ==========================================
local function autoHealLoop(runId)
    if automationBusy then
        state.autoHeal = false
        taskDiagnostic("Đang có một tác vụ tự động khác chạy.")
        return
    end
    automationBusy = true
    setAutomationPhase("Auto Heal")
    while state.autoHeal and autoHealRunId == runId and not dead do
        local rooms = findDescendantByNames(workspace, { "Rooms", "PatientRooms", "Patient Rooms" })
        local prompt, roomParent
        if rooms then
            for _, candidate in ipairs(rooms:GetDescendants()) do
                if candidate:IsA("Model") then
                    local candidatePrompt = findPrompt(candidate)
                    if isHealPrompt(candidatePrompt) then
                        prompt, roomParent = candidatePrompt, candidate
                        debugLog("Auto Heal candidate", candidate:GetFullName(), getPromptDescription(candidatePrompt))
                        break
                    end
                end
            end
        end

        if prompt and roomParent then
            debugLog("Auto Heal room selected", roomParent:GetFullName(), getPromptDescription(prompt))
            local root = getRoot()
            if root then
                moveToPrompt(root, prompt, 2)
                task.wait(0.3)
                fireTaskPrompt(prompt)
                task.wait(4)

                local analyzer = findDescendantByNames(roomParent, { "Analyzer", "Processor", "Analyze" })
                local analyzerPP = findPrompt(analyzer)
                if analyzerPP and analyzerPP.Enabled then
                    debugLog("Auto Heal analyzer", getPromptDescription(analyzerPP))
                    moveToPrompt(root, analyzerPP, 2)
                    task.wait(0.3)
                    fireTaskPrompt(analyzerPP)
                    task.wait(5)
                end

                local comp = findDescendantByNames(roomParent, { "Computer", "PC", "Diagnosis" })
                local compPP = findPrompt(comp)
                if compPP and compPP.Enabled then
                    debugLog("Auto Heal computer", getPromptDescription(compPP))
                    moveToPrompt(root, compPP, 3)
                    task.wait(0.3)
                    fireTaskPrompt(compPP)
                    task.wait(1.5)
                end

                local supplies = findDescendantByNames(workspace, { "Supplies", "Medical Supplies", "Medicine" })
                if supplies then
                    for _, desc in ipairs(supplies:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") and desc.Enabled then
                            debugLog("Auto Heal supply", getPromptDescription(desc))
                            moveToPrompt(root, desc, 3)
                            task.wait(0.3)
                            fireTaskPrompt(desc)
                            task.wait(1)
                            break
                        end
                    end
                end
            end
        elseif not rooms then
            taskDiagnostic("Không tìm thấy khu phòng bệnh nhân.")
        else
            taskDiagnostic("Không tìm thấy bệnh nhân hoặc prompt chữa trị đang bật.")
        end
        task.wait(1)
    end
    automationBusy = false
    setAutomationPhase("Idle")
end

-- ==========================================
-- RUN FAST COLA
-- first hunt for the REAL cola tool and clone it; if the game
-- hides it, craft our own: drink = zoom + purple sparkles, 30s
-- ==========================================
local function findRealCola()
    local lowered = function(s) return string.lower(s) end
    for _, spot in ipairs({ replicatedStorage, workspace, game:GetService("Lighting") }) do
        for _, d in ipairs(spot:GetDescendants()) do
            if d:IsA("Tool") then
                local n = lowered(d.Name)
                if string.find(n, "cola") or string.find(n, "run fast")
                    or string.find(n, "speed boost") then
                    return d
                end
            end
        end
    end
    return nil
end

local function craftCola()
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return false end

    local tool = Instance.new("Tool")
    tool.Name = "Run Fast Cola"
    tool.ToolTip = "🥤 zoom juice — 30s of purple speed"
    tool.RequiresHandle = true

    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.8, 1.4, 0.8)
    handle.Color = Color3.fromRGB(160, 60, 255)
    handle.Parent = tool

    local drinking = false
    tool.Activated:Connect(function()
        if drinking or dead then return end
        drinking = true
        local char = localPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            -- open the 30 second zoom window (the speed loop holds it)
            colaBoostUntil = os.clock() + 30
            local sparkles = Instance.new("Sparkles")
            sparkles.SparkleColor = Color3.fromRGB(170, 0, 255)
            local torso = char:FindFirstChild("UpperTorso")
                or char:FindFirstChild("Torso")
                or char:FindFirstChild("HumanoidRootPart")
            if torso then sparkles.Parent = torso end
            task.delay(30, function()
                if sparkles and sparkles.Parent then
                    pcall(function() sparkles:Destroy() end)
                end
            end)
        end
        task.wait(2) -- sip break, no chugging the whole six pack
        drinking = false
    end)

    tool.Parent = backpack
    return true
end

local function getRunFastCola()
    -- real one first: if the game offers the tool, take the legit copy
    local real = findRealCola()
    if real then
        local backpack = localPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            local okClone = pcall(function()
                real:Clone().Parent = backpack
            end)
            if okClone then return true end
        end
    end
    -- no cola lying around? we brew our own
    return craftCola()
end

-- ==========================================
-- GET OBJECT (the snatch-and-return trick:
-- hop in, fire the prompt, hop back like nothing happened)
-- ==========================================
local busy = false
local function fetchObject(itemName)
    debugLog("Fetch object started", itemName)
    if busy then return false end
    busy = true

    local char = getChar()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local head = char and char:FindFirstChild("Head")
    if not root or not hum or not head then
        busy = false
        return false
    end

    local wasNoClip = state.noClip
    if wasNoClip then
        applyNoClip(false)
    end

    local savedCFrame = root.CFrame
    local savedWalkSpeed = hum.WalkSpeed
    local savedPlatformStand = hum.PlatformStand
    local savedVelocity = root.AssemblyLinearVelocity
    local savedAngular = root.AssemblyAngularVelocity

    local function restoreCharacterState()
        if root and root.Parent then
            root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            root.CFrame = savedCFrame
        end
        if hum and hum.Parent then
            hum.WalkSpeed = savedWalkSpeed
            hum.PlatformStand = savedPlatformStand
        end
        if workspace.CurrentCamera then
            workspace.CurrentCamera.CameraSubject = hum
        end
    end

    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            if desc.ActionText == itemName or desc.ObjectText == itemName then
                local parent = desc.Parent
                local basePart = (parent:IsA("BasePart") and parent)
                    or parent:FindFirstChildWhichIsA("BasePart")
                if basePart then
                    local savedLOS = desc.RequiresLineOfSight
                    local savedCollide = basePart.CanCollide

                    hum.WalkSpeed = 0
                    hum.PlatformStand = true
                    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

                    desc.RequiresLineOfSight = false
                    basePart.CanCollide = false
                    pcall(function() desc.HoldDuration = 0 end)

                    local targetPos = basePart.Position
                    local attachment = parent:FindFirstChildOfClass("Attachment")
                    if attachment then targetPos = attachment.WorldPosition end

                    local platform = Instance.new("Part")
                    platform.Size = Vector3.new(5, 1, 5)
                    platform.Anchored = true
                    platform.Transparency = 1
                    platform.CanCollide = true
                    platform.CFrame = CFrame.new(targetPos + Vector3.new(0, -2, 0))
                    platform.Parent = workspace

                    local pickupCFrame = CFrame.new(targetPos + Vector3.new(0, 2.2, 0), targetPos + Vector3.new(0, 1.2, 2))
                    root.CFrame = pickupCFrame
                    task.wait(0.05)
                    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

                    task.wait(0.2)
                    if workspace.CurrentCamera then
                        workspace.CurrentCamera.CFrame = CFrame.lookAt(head.Position, targetPos)
                    end
                    task.wait(0.05)
                    pcall(function()
                        if fireproximityprompt then fireproximityprompt(desc) end
                    end)

                    task.wait(0.3)
                    desc.RequiresLineOfSight = savedLOS
                    basePart.CanCollide = savedCollide
                    platform:Destroy()

                    restoreCharacterState()
                    task.wait(0.05)
                    if wasNoClip then
                        applyNoClip(true)
                    end

                    busy = false
                    debugLog("Fetch object succeeded", itemName, desc:GetFullName())
                    return true
                end
            end
        end
    end

    restoreCharacterState()
    if wasNoClip then
        applyNoClip(true)
    end

    busy = false
    debugLog("Fetch object failed", itemName)
    return false
end

local function scanUsableObjects()
    local found = {}
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local label = prompt.ObjectText ~= "" and prompt.ObjectText or prompt.ActionText
            if label ~= "" then
                table.insert(found, string.format("%s | %s", label, prompt:GetFullName()))
            end
        end
    end
    print("[AH OBJECTS] " .. tostring(#found) .. " usable prompts")
    for _, entry in ipairs(found) do
        print("[AH OBJECTS] " .. entry)
    end
    notify("Đồ vật", "Đã quét " .. tostring(#found) .. " đồ vật/prompt. Xem log để biết tên thật.", 4)
    return found
end

-- ==========================================
-- ROOM TELEPORTS (every wall of the hospital mapped)
-- ==========================================
local roomCFrames = {
    ["checkzone"]            = CFrame.new(-107.333389, 3.412531, 8.237826, -0.954479, 0, -0.298277, 0, 1, 0, 0.298277, 0, -0.954479),
    ["entrance"]             = CFrame.new(-78.983574, 3.407531, -12.504811, -0.021113, 0, -0.999777, 0, 1, 0, 0.999777, 0, -0.021113),
    ["room halfway A (1-5)"] = CFrame.new(-145.037628, 3.457531, -65.147362, -0.996587, 0, 0.08254, 0, 1, 0, -0.082549, 0, -0.996587),
    ["room 1"]               = CFrame.new(-169.766663, 3.457531, -50.727806, 0.025003, 0, -0.999687, 0, 1, 0, 0.999687, 0, 0.025003),
    ["room 2"]               = CFrame.new(-123.374763, 3.457531, -51.833504, -0.611116, 0, 0.79154, 0, 1, 0, -0.791541, 0, -0.611116),
    ["room 3"]               = CFrame.new(-173.209396, 3.457531, -90.922246, 0.008945, 0, -0.99996, 0, 1, 0, 0.99996, 0, 0.008945),
    ["room 4"]               = CFrame.new(-117.447639, 3.457531, -89.03093, 0.020848, 0, 0.999783, 0, 1, 0, -0.999783, 0, 0.020848),
    ["room 5"]               = CFrame.new(-145.94075, 3.457531, -113.268204, 0.999244, 0, 0.03886, 0, 1, 0, -0.038867, 0, 0.999244),
    ["shop"]                 = CFrame.new(-166.514618, 3.45753, -12.773237, 0.012568, 0, 0.999921, 0, 1, 0, -0.999921, 0, 0.012568),
    ["halfway B (6-8)"]      = CFrame.new(-144.837326, 3.45753, 36.86932, 0.99922, 0, 0.039477, 0, 1, 0, -0.039477, 0, 0.99922),
    ["room 6"]               = CFrame.new(-171.039078, 3.45753, 52.27216, 0.399193, 0, -0.916867, 0, 1, 0, 0.916867, 0, 0.399193),
    ["room 7"]               = CFrame.new(-124.463058, 3.45753, 45.395046, -0.985264, 0, -0.171038, 0, 1, 0, 0.171038, 0, -0.985264),
    ["room 8"]               = CFrame.new(-145.123749, 3.45753, 77.844215, -0.999892, 0, 0.014681, 0, 1, 0, -0.014681, 0, -0.999892),
}

local tpCooldown = false
local function teleportTo(roomName)
    debugLog("Teleport requested", roomName)
    if tpCooldown then
        notify("📍", "Chill, cooldown! ⏳", 2)
        return
    end
    local cf = roomCFrames[roomName]
    local root = getRoot()
    if cf and root then
        pcall(function()
            root.CFrame = cf
        end)
        tpCooldown = true
        debugLog("Teleport succeeded", roomName)
        notify("📍", "You're there! ✨", 2)
        task.wait(0.5)
        tpCooldown = false
    else
        debugLog("Teleport failed", roomName)
        notify("📍", "Couldn't hop there! 😢", 2)
    end
end

-- free mouse (Z): keep the cursor usable while the menu is up
track(runService.RenderStepped:Connect(function()
    if dead or not state.mouseFree then return end
    if userInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
        userInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end))

-- ==========================================
-- KEYBINDS (for the keyboard warriors)
-- H anomalies · J patients · K items · Z free mouse
-- ==========================================
track(userInputService.InputBegan:Connect(function(input, processed)
    if dead then return end
    if debugEnabled and input.KeyCode ~= Enum.KeyCode.Unknown then
        debugLog("Manual input", input.KeyCode.Name)
    end

    if input.KeyCode == Enum.KeyCode.Space and processed then
        local hum = getHumanoid()
        if not state.thirdPerson then
            unlockJumpKey()
        elseif hum and hum:GetState() ~= Enum.HumanoidStateType.Jumping then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end

    if processed then return end
    if input.KeyCode == Enum.KeyCode.H then
        state.anomaliesESP = not state.anomaliesESP
        if not state.anomaliesESP then clearESPByType("Anomaly") end
    elseif input.KeyCode == Enum.KeyCode.J then
        state.patientsESP = not state.patientsESP
        if not state.patientsESP then clearESPByType("Patient") end
    elseif input.KeyCode == Enum.KeyCode.K then
        state.itemsESP = not state.itemsESP
        if not state.itemsESP then clearESPByType("ObjectItem") end
    elseif input.KeyCode == Enum.KeyCode.Z then
        state.mouseFree = not state.mouseFree
        userInputService.MouseIconEnabled = true
    end
end))

-- ==========================================
-- UI (WindUI, inlined above — offline proof)
-- ==========================================
local window = WindUI:CreateWindow({
    Title = "Súc vật bệnh viện",
    Author = "bản tối ưu",
    Theme = "Dark",
    Size = UDim2.new(0, 500, 0, 500),
    Acrylic = false, -- IMPORTANT: Acrylic blur = GPU drain on mobile
    Icon = "lucide:cross",
})

-- ==========================================
-- TAB 1: ESP
-- ==========================================
local espTab = window:Tab({ Title = "Nhìn xuyên", Icon = "lucide:eye" })

espTab:Button({
    Title = "Số người chơi",
    Desc = "Hiển thị số người đang ở máy chủ",
    Icon = "lucide:users",
    Callback = function()
        notify("Người chơi", tostring(#players:GetPlayers()) .. " người đang ở máy chủ", 2)
    end,
})

espTab:Toggle({
    Title = "ESP quái vật",
    Desc = "Đánh dấu bệnh nhân bất thường màu đỏ",
    Default = false,
    Callback = function(s)
        state.anomaliesESP = s
        if not s then clearESPByType("Anomaly") end
    end,
})

espTab:Toggle({
    Title = "ESP bệnh nhân",
    Desc = "Đánh dấu bệnh nhân bình thường màu xanh",
    Default = false,
    Callback = function(s)
        state.patientsESP = s
        if not s then clearESPByType("Patient") end
    end,
})

espTab:Toggle({
    Title = "ESP vật phẩm",
    Desc = "Đánh dấu vật phẩm có thể nhặt màu vàng",
    Default = false,
    Callback = function(s)
        state.itemsESP = s
        if not s then clearESPByType("ObjectItem") end
    end,
})

espTab:Toggle({
    Title = "ESP người chơi",
    Desc = "Đánh dấu người chơi khác màu xanh lục lam",
    Default = false,
    Callback = function(s)
        state.playerESP = s
        if not s then
            for _, p in ipairs(players:GetPlayers()) do
                removePlayerESP(p)
            end
        end
    end,
})

espTab:Toggle({
    Title = "Bật nhìn xuyên",
    Desc = "Nhìn xuyên tường và vật thể.",
    Default = false,
    Callback = function(s)
        state.wallhackEnabled = s
        if not s then
            clearESPByType("Anomaly")
            clearESPByType("Patient")
            clearESPByType("ObjectItem")
        end
    end,
})

espTab:Toggle({
    Title = "Đường chỉ dẫn ESP",
    Desc = "Vẽ đường từ màn hình đến mục tiêu",
    Default = false,
    Callback = function(s)
        state.drawLines = s
        if not s then clearAllLines() end
    end,
})

espTab:Input({
    Title = "Mức nhìn xuyên",
    Desc = "1 nhẹ, 2 rõ, 3 nổi bật xuyên vật thể/tường",
    Placeholder = "Ví dụ: 2",
    Value = tostring(state.wallhackLevel),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.wallhackLevel = math.clamp(math.floor(value), 1, 3)
            if state.wallhackEnabled then
                notify("ESP", "Mức nhìn xuyên: " .. tostring(state.wallhackLevel), 2)
            end
        end
    end,
})

-- ==========================================
-- TAB 2: PLAYER
-- ==========================================
local playerTab = window:Tab({ Title = "Nhân vật", Icon = "lucide:user" })

playerTab:Input({
    Title = "Tốc độ di chuyển",
    Desc = "Nhập tốc độ mong muốn",
    Placeholder = "Ví dụ: 16 hoặc 40",
    Type = "Input",
    Callback = function(text)
        local n = tonumber(text)
        if n then
            state.speed = n
            notify("🏃", "Speed set to " .. n, 2)
        end
    end,
})

playerTab:Button({
    Title = "Đặt lại tốc độ",
    Desc = "Trở về tốc độ mặc định 16",
    Icon = "lucide:rotate-ccw",
    Callback = function()
        state.speed = 16
        notify("🏃", "Speed reset! ✨", 2)
    end,
})

playerTab:Toggle({
    Title = "Xoá thời gian giữ nút",
    Desc = "Thao tác giữ nút được thực hiện ngay",
    Default = false,
    Callback = function(s)
        state.fasterActions = s
        applyFasterActions()
    end,
})

playerTab:Toggle({
    Title = "Giữ tỉnh táo",
    Desc = "Giữ chỉ số tỉnh táo ở mức hiện tại",
    Default = false,
    Callback = function(s) state.infSanity = s end,
})

playerTab:Toggle({
    Title = "Góc nhìn thứ ba",
    Desc = "Đưa camera ra phía sau nhân vật, giữ chuột trái hoặc kéo màn hình để xoay",
    Default = false,
    Callback = function(s)
        state.thirdPerson = s
        if not s then
            thirdPersonMouseLook = false
        end
        applyThirdPerson()
    end,
})

playerTab:Toggle({
    Title = "Ghost mode",
    Desc = "Thoát hồn: thân đứng yên, camera tách khỏi người và xoay tự do như góc nhìn thứ ba",
    Default = false,
    Callback = function(s)
        if s then
            state.thirdPerson = true
            applyThirdPerson()
        end
        applyGhostMode(s)
    end,
})

playerTab:Input({
    Title = "FOV camera",
    Desc = "Nhập góc nhìn từ 40 đến 120",
    Placeholder = "Ví dụ: 70 hoặc 90",
    Value = tostring(state.fov),
    Type = "Input",
    Callback = function(text)
        local numeric = tonumber(text)
        if numeric and applyFov(numeric) then
            notify("Camera", "FOV đã đặt: " .. tostring(state.fov), 2)
        else
            notify("Camera", "FOV hợp lệ nằm trong khoảng 40-120.", 3)
        end
    end,
})

playerTab:Toggle({
    Title = "Chống đứng yên",
    Desc = "Giữ phiên chơi không bị ngắt do không hoạt động",
    Default = true,
    Callback = function(s) state.antiAfk = s end,
})

playerTab:Toggle({
    Title = "Mở chuột tự do [Z]",
    Desc = "Cho phép di chuyển con trỏ khi mở giao diện",
    Default = false,
    Callback = function(s)
        state.mouseFree = s
        userInputService.MouseIconEnabled = true
    end,
})

playerTab:Toggle({
    Title = "NoClip",
    Desc = "Bật chế độ đi xuyên vật cản và vượt tường",
    Default = false,
    Callback = function(s)
        state.noClip = s
        applyNoClip(s)
    end,
})

playerTab:Toggle({
    Title = "Thu nhỏ nhân vật",
    Desc = "Thu nhỏ ở client; người chơi khác có thể không thấy đúng kích thước",
    Default = false,
    Callback = function(s)
        local ok = applyCharacterScale(s)
        if ok then
            notify("👤", s and "Nhân vật đã thu nhỏ lại." or "Nhân vật đã phục hồi kích thước ban đầu.", 2)
        else
            notify("👤", "Rig hiện tại không cho phép thay đổi kích thước. Đã ghi chi tiết vào Debug log.", 4)
        end
    end,
})

playerTab:Input({
    Title = "Tỷ lệ nhân vật",
    Desc = "Nhập 0.1-2.0; 0.5 là nhỏ một nửa, 1 là bình thường",
    Placeholder = "Ví dụ: 0.5 hoặc 1.2",
    Type = "Input",
    Callback = function(text)
        local numeric = tonumber(text)
        if not numeric then
            notify("👤", "Tỷ lệ phải là số từ 0.1 đến 2.0.", 3)
            return
        end
        state.characterScale = math.clamp(numeric, 0.1, 2)
        if state.shrink then
            local ok = applyCharacterScale(true)
            if not ok then
                notify("👤", "Rig hiện tại không nhận tỷ lệ mới.", 3)
            end
        end
        notify("👤", "Tỷ lệ nhân vật: " .. tostring(state.characterScale), 2)
    end,
})

playerTab:Button({
    Title = "Chọn người chơi gần nhất",
    Desc = "Đặt mục tiêu bám theo người chơi gần nhất hiện tại",
    Icon = "lucide:user-round",
    Callback = function()
        local target = getNearestPlayerTarget()
        if target then
            setFollowTarget(target)
            notify("👥", "Đang theo: " .. target.Name, 2)
        else
            notify("👥", "Không tìm thấy người chơi nào gần đây.", 2)
        end
    end,
})

playerTab:Button({
    Title = "Đổi mục tiêu bám tiếp theo",
    Desc = "Bật theo người chơi tiếp theo trong danh sách",
    Icon = "lucide:arrow-right-left",
    Callback = function()
        local list = {}
        for _, p in ipairs(players:GetPlayers()) do
            if p ~= localPlayer then
                table.insert(list, p)
            end
        end
        if #list == 0 then
            notify("👥", "Chưa có người chơi nào để bám.", 2)
            return
        end
        local index = 1
        if state.followTarget then
            for i, p in ipairs(list) do
                if p == state.followTarget then
                    index = (i % #list) + 1
                    break
                end
            end
        end
        setFollowTarget(list[index])
        notify("👥", "Mục tiêu mới: " .. list[index].Name, 2)
    end,
})

playerTab:Toggle({
    Title = "Bám theo người chơi",
    Desc = "Teleport liên tục theo người được chọn và giữ cách nhau cố định",
    Default = false,
    Callback = function(s)
        state.followPlayer = s
        if s and not state.followTarget then
            setFollowTarget(getNearestPlayerTarget())
        end
        if s then
            notify("👥", "Bám theo người chơi đang bật.", 2)
        else
            notify("👥", "Bám theo người chơi đã tắt.", 2)
        end
    end,
})

playerTab:Input({
    Title = "Khoảng cách bám",
    Desc = "Khoảng cách phía sau mục tiêu, từ 1 đến 50",
    Placeholder = "Ví dụ: 6",
    Value = tostring(state.followDistance),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.followDistance = math.clamp(value, 1, 50)
            notify("👥", "Khoảng cách bám: " .. tostring(state.followDistance), 2)
        end
    end,
})

playerTab:Input({
    Title = "Tốc độ bám",
    Desc = "Số lần cập nhật bám mỗi giây, từ 1 đến 60",
    Placeholder = "Ví dụ: 20",
    Value = tostring(state.followSpeed),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.followSpeed = math.clamp(value, 1, 60)
            notify("👥", "Tốc độ bám: " .. tostring(state.followSpeed), 2)
        end
    end,
})

playerTab:Toggle({
    Title = "Độ sáng ban đêm",
    Desc = "Tăng độ sáng và khôi phục đúng thiết lập cũ khi tắt",
    Default = false,
    Callback = function(s)
        state.fullbright = s
        setFullbright(s)
    end,
})

-- ==========================================
-- TAB 3: AUTO
-- ==========================================
local autoTab = window:Tab({ Title = "Tự động", Icon = "lucide:bot" })

autoTab:Section({
    Title = "⚠️ Beta zone",
    Text = "Auto Tasks & Auto Heal are still beta babies — they work but might hiccup. Skinwalkers beware anyway.",
})

autoTab:Toggle({
    Title = "🎮 Auto play Minigames",
    Desc = "Plays the color game and heartbeat game for you",
    Default = false,
    Callback = function(s)
        state.autoMinigames = s
        debugLog("Auto Minigames", s and "enabled" or "disabled")
        if s then
            minigameQueue = {}
            minigameClicked = {}
            hookColorMinigame()
            minigameLastTrigger = os.clock()
        end
    end,
})

autoTab:Toggle({
    Title = "📋 Auto Tasks (BETA)",
    Desc = "Runs the whole check-in dance for every patient",
    Default = false,
    Callback = function(s)
        state.autoTasks = s
        debugLog("Auto Tasks toggle", s and "enabled" or "disabled")
        autoTaskRunId = autoTaskRunId + 1
        if s then
            task.spawn(autoTasksLoop, autoTaskRunId)
        else
            local hum = getHumanoid()
            if hum then camera.CameraSubject = hum end
        end
    end,
})

autoTab:Toggle({
    Title = "💊 Auto Heal (BETA)",
    Desc = "Runs the whole fix-a-patient circuit by itself",
    Default = false,
    Callback = function(s)
        state.autoHeal = s
        debugLog("Auto Heal toggle", s and "enabled" or "disabled")
        autoHealRunId = autoHealRunId + 1
        if s then
            task.spawn(autoHealLoop, autoHealRunId)
        end
    end,
})

autoTab:Button({
    Title = "Dừng tác vụ tự động",
    Desc = "Dừng Auto Tasks và Auto Heal hiện tại",
    Icon = "lucide:square",
    Callback = function()
        state.autoTasks = false
        state.autoHeal = false
        autoTaskRunId = autoTaskRunId + 1
        autoHealRunId = autoHealRunId + 1
        setAutomationPhase("Idle")
        taskDiagnostic("Đã dừng toàn bộ tác vụ tự động.")
    end,
})

autoTab:Toggle({
    Title = "Debug tổng",
    Desc = "Bật log tổng: quét môi trường, bệnh nhân, prompt, lỗi và mọi sự kiện đều ghi vào log",
    Default = false,
    Callback = function(s)
        debugEnabled = s
        if s then
            logEnvironmentSnapshot("debug toggle on")
            scanWorkspaceNames()
            diagnoseAutomation()
            debugLog("Debug enabled")
            notify("Debug", "Đã bật debug tổng. Tất cả log đang được ghi vào 1 nơi.", 3)
        else
            print("[AH DEBUG] disabled")
        end
    end,
})

autoTab:Button({
    Title = "Sao chép debug log",
    Desc = "Chép tối đa 300 dòng log gần nhất vào clipboard",
    Icon = "lucide:clipboard",
    Callback = copyDebugLog,
})

-- ==========================================
-- TAB 4: ITEMS
-- ==========================================
local itemsTab = window:Tab({ Title = "Đồ vật", Icon = "lucide:package" })

itemsTab:Button({
    Title = "Quét đồ vật có thể dùng",
    Desc = "Liệt kê prompt để biết đồ nào có thể cầm, dùng hoặc đặt",
    Icon = "lucide:scan-search",
    Callback = scanUsableObjects,
})

itemsTab:Section({
    Title = "Kho đồ",
    Text = "Danh sách món đồ đã lấy thành công. Mỗi món là một nút lấy lại nếu cần.",
})

local function refreshInventoryButtons()
    for _, button in ipairs(inventoryButtons) do
        if button and button.Destroy then
            pcall(function() button:Destroy() end)
        end
    end
    inventoryButtons = {}

    if #itemInventory == 0 then
        local placeholder = itemsTab:Button({
            Title = "Kho đồ trống",
            Icon = "lucide:package-open",
            Callback = function()
                notify("Kho đồ", "Chưa có món nào trong kho.", 2)
            end,
        })
        table.insert(inventoryButtons, placeholder)
        return
    end

    for _, itemName in ipairs(itemInventory) do
        local button = itemsTab:Button({
            Title = itemName,
            Icon = "lucide:package",
            Callback = function()
                notify("🧰", "Grabbing " .. itemName .. "...", 2)
                local got = fetchObject(itemName)
                if got then
                    notify("🧰", itemName .. " secured! ✨", 2)
                else
                    notify("🧰", "Couldn't find it! 😢", 3)
                end
            end,
        })
        table.insert(inventoryButtons, button)
    end
end

itemsTab:Button({
    Title = "🥤 Get Run Fast Cola",
    Desc = "A cola lands in your backpack — drink it for 30s of zoom + purple sparkles",
    Icon = "lucide:cup-soda",
    Callback = function()
        local got = getRunFastCola()
        if got then
            notify("🥤", "Cola secured! Check your backpack ✨", 2)
        else
            notify("🥤", "Couldn't grab one! 😢", 3)
        end
    end,
})

itemsTab:Section({
    Title = "Get Object",
    Text = "Tap any item — you blink over, grab it, blink back.",
})

refreshInventoryButtons()

local itemNames = {
    { name = "Herbs",        icon = "lucide:leaf" },
    { name = "Eye Drops",    icon = "lucide:eye" },
    { name = "IV Drops",     icon = "lucide:droplets" },
    { name = "Medkit",       icon = "lucide:briefcase-medical" },
    { name = "Thermo",       icon = "lucide:thermometer" },
    { name = "Ointment",     icon = "lucide:pill" },
    { name = "Bandages",     icon = "lucide:bandage" },
    { name = "Maple Syrup",  icon = "lucide:flask-conical" },
    { name = "Cough Syrup",  icon = "lucide:flask-round" },
    { name = "Medicine",     icon = "lucide:pills" },
}

for _, item in ipairs(itemNames) do
    itemsTab:Button({
        Title = item.name,
        Icon = item.icon,
        Callback = function()
            notify("🧰", "Grabbing " .. item.name .. "...", 2)
            local got = fetchObject(item.name)
            if got then
                notify("🧰", item.name .. " secured! ✨", 2)
            else
                notify("🧰", "Couldn't find it! 😢", 3)
            end
        end,
    })
end

-- ==========================================
-- TAB 5: TELEPORT
-- ==========================================
local tpTab = window:Tab({ Title = "Dịch chuyển", Icon = "lucide:map-pin" })

tpTab:Section({ Title = "General", Text = "" })
for _, name in ipairs({ "checkzone", "entrance", "shop" }) do
    tpTab:Button({
        Title = name,
        Icon = "lucide:door-open",
        Callback = function() teleportTo(name) end,
    })
end

tpTab:Section({ Title = "Patient Rooms", Text = "" })
for _, name in ipairs({ "room 1", "room 2", "room 3", "room 4",
    "room 5", "room 6", "room 7", "room 8" }) do
    tpTab:Button({
        Title = name,
        Icon = "lucide:door-open",
        Callback = function() teleportTo(name) end,
    })
end

tpTab:Section({ Title = "Hallways", Text = "" })
for _, name in ipairs({ "room halfway A (1-5)", "halfway B (6-8)" }) do
    tpTab:Button({
        Title = name,
        Icon = "lucide:door-open",
        Callback = function() teleportTo(name) end,
    })
end

-- ==========================================
-- TAB 6: KHÁC
-- ==========================================
local vehicleTab = window:Tab({ Title = "Xe", Icon = "lucide:car-front" })

vehicleTab:Section({
    Title = "Điều khiển xe",
    Text = "Các mức chỉ áp dụng khi đang ngồi VehicleSeat; phanh giữ bằng phím S.",
})

vehicleTab:Input({
    Title = "Độ bám đường",
    Desc = "Mức 1-10; mức cao bám đường hơn",
    Placeholder = "Ví dụ: 6",
    Value = tostring(state.vehicleGrip),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.vehicleGrip = math.clamp(value, 1, 10)
            notify("Xe", "Độ bám: " .. tostring(state.vehicleGrip), 2)
        end
    end,
})

vehicleTab:Input({
    Title = "Phanh chủ động",
    Desc = "Mức 1-5; giữ S để phanh mạnh hơn, không bó bánh khi nhả ga",
    Placeholder = "Ví dụ: 3",
    Value = tostring(state.vehicleBrake),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.vehicleBrake = math.clamp(value, 1, 5)
            notify("Xe", "Phanh: " .. tostring(state.vehicleBrake), 2)
        end
    end,
})

vehicleTab:Input({
    Title = "Đề / tăng tốc",
    Desc = "Mức 1-5; tăng giới hạn tốc độ và mô-men đề",
    Placeholder = "Ví dụ: 3",
    Value = tostring(state.vehicleLaunch),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.vehicleLaunch = math.clamp(value, 1, 5)
            notify("Xe", "Đề: " .. tostring(state.vehicleLaunch), 2)
        end
    end,
})

vehicleTab:Input({
    Title = "Góc lái",
    Desc = "Mức 1-3; tăng hỗ trợ quay đầu xe",
    Placeholder = "Ví dụ: 2",
    Value = tostring(state.vehicleSteering),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.vehicleSteering = math.clamp(value, 1, 3)
            notify("Xe", "Góc lái: " .. tostring(state.vehicleSteering), 2)
        end
    end,
})

vehicleTab:Input({
    Title = "Kính xe tối",
    Desc = "Mức 0.05-0.9; số cao thì kính trong hơn",
    Placeholder = "Ví dụ: 0.65",
    Value = tostring(state.vehicleGlass),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.vehicleGlass = math.clamp(value, 0.05, 0.9)
            notify("Xe", "Độ trong kính: " .. tostring(state.vehicleGlass), 2)
        end
    end,
})

vehicleTab:Toggle({
    Title = "Bô nẹt lửa",
    Desc = "Tạo lửa local ở các part có tên exhaust, muffler hoặc pipe",
    Default = false,
    Callback = function(s)
        state.vehicleExhaust = s
        if not s then
            for part, effect in pairs(vehicleExhaustParts) do
                if effect and effect.Parent then effect:Destroy() end
                vehicleExhaustParts[part] = nil
            end
        end
        vehicleLastApply = 0
    end,
})

vehicleTab:Toggle({
    Title = "Khói/cát khi drift",
    Desc = "Đã tắt mặc định để không tạo khói drift; còn có thể bật nếu cần",
    Default = false,
    Callback = function(s)
        state.driftEffects = s
        vehicleLastApply = 0
        if not s and vehicleLastModel then
            setDriftEffects(vehicleLastModel, false)
        end
    end,
})

vehicleTab:Input({
    Title = "Lực đẩy người",
    Desc = "Mức 10-200; dùng cho đẩy người gần nhất sau tele sát",
    Placeholder = "Ví dụ: 35",
    Value = tostring(state.playerPushForce),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.playerPushForce = math.clamp(value, 10, 200)
            notify("Đẩy người", "Lực đẩy: " .. tostring(state.playerPushForce), 2)
        end
    end,
})

vehicleTab:Toggle({
    Title = "Đẩy bằng vật (local)",
    Desc = "Nếu cầm vật hoặc tool, nó sẽ ép người gần nhất di chuyển theo hướng local; chỉ có hiệu ứng client.",
    Default = false,
    Callback = function(s)
        state.objectPushEnabled = s
        if s then
            notify("Đẩy vật", "Đẩy vật local đã bật.", 2)
        end
    end,
})

vehicleTab:Input({
    Title = "Tên món đồ làm vật đẩy",
    Desc = "Ví dụ: ToolName hoặc tên vật cầm trên tay. Để trống nếu muốn lấy tool đang cầm.",
    Placeholder = "Ví dụ: Hammer",
    Value = tostring(state.objectPushItemName),
    Type = "Input",
    Callback = function(text)
        state.objectPushItemName = tostring(text or "")
        notify("Đẩy vật", "Món đồ đang chọn: " .. tostring(state.objectPushItemName == "" and "tool đang cầm" or state.objectPushItemName), 2)
    end,
})

vehicleTab:Input({
    Title = "Khoảng cách vật đẩy",
    Desc = "Bán kính đẩy bằng vật, từ 3 đến 25",
    Placeholder = "Ví dụ: 10",
    Value = tostring(state.objectPushDistance),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.objectPushDistance = math.clamp(value, 3, 25)
            notify("Đẩy vật", "Khoảng cách: " .. tostring(state.objectPushDistance), 2)
        end
    end,
})

vehicleTab:Button({
    Title = "Đẩy người gần nhất",
    Desc = "Tele sát người gần nhất rồi dùng vật đẩy ném họ đi theo hướng",
    Icon = "lucide:zap",
    Callback = function()
        pushNearestTargetPlayer(state.playerPushForce)
    end,
})

-- ==========================================
-- TAB 7: KHÁC
-- ==========================================
local miscTab = window:Tab({ Title = "Khác", Icon = "lucide:settings-2" })

miscTab:Dropdown({
    Title = "Ngôn ngữ / Language",
    Desc = "Chọn ngôn ngữ giao diện",
    Values = { "Tiếng Việt", "English" },
    Value = "Tiếng Việt",
    Callback = function(value)
        state.language = value == "English" and "en" or "vi"
        notify("Language", state.language == "en"
            and "English selected. Existing labels require reload to fully translate."
            or "Đã chọn Tiếng Việt. Một số nhãn cần chạy lại script để đổi hoàn toàn.", 4)
    end,
})

miscTab:Toggle({
    Title = "Bay cố định tại chỗ",
    Desc = "Giữ nhân vật ở đúng vị trí hiện tại, không bị trôi; đặt cao độ theo hướng nhìn",
    Default = false,
    Callback = function(s)
        state.fixedFlight = s
        local root = getRoot()
        fixedFlightCFrame = s and (root and root.CFrame or nil) or nil
        if fixedFlightCFrame and root then
            root.CFrame = fixedFlightCFrame
        end
        notify("Bay", s and "Đã khóa vị trí hiện tại." or "Đã thả vị trí.", 2)
    end,
})

miscTab:Input({
    Title = "Độ cao bay theo hướng nhìn",
    Desc = "Nhìn lên = lên, nhìn xuống = xuống. Giá trị từ -15 đến 15",
    Placeholder = "Ví dụ: 3",
    Value = tostring(state.fixedFlightHeight),
    Type = "Input",
    Callback = function(text)
        local value = tonumber(text)
        if value then
            state.fixedFlightHeight = math.clamp(value, -15, 15)
            notify("Bay", "Độ cao bay: " .. tostring(state.fixedFlightHeight), 2)
        end
    end,
})

miscTab:Toggle({
    Title = "Đồ họa tối đa",
    Desc = "Bật chất lượng cao, bóng, Mesh fidelity và quality level nếu máy hỗ trợ",
    Default = false,
    Callback = function(s)
        if s and state.lowGraphics then
            setLowGraphics(false)
        end
        setMaxGraphics(s)
        notify("Đồ họa", s and "Đã bật chất lượng tối đa client." or "Đã khôi phục chất lượng trước đó.", 3)
    end,
})

miscTab:Toggle({
    Title = "Khử răng cưa / cạnh mượt",
    Desc = "Tùy máy: tăng quality level và RenderFidelity; Roblox không có API AA riêng",
    Default = true,
    Callback = function(s)
        state.highQualityEdges = s
        if state.maxGraphics then
            setMaxGraphics(false)
            setMaxGraphics(true)
        end
    end,
})

miscTab:Toggle({
    Title = "Fix lag / Đồ họa đơn giản",
    Desc = "Tắt hiệu ứng, bóng đổ, ESP và giảm quét nền để nhẹ máy hơn",
    Default = false,
    Callback = function(s)
        if s and state.maxGraphics then
            setMaxGraphics(false)
        end
        setLowGraphics(s)
        notify("Đồ họa", s and "Đã bật chế độ tối ưu nhẹ máy." or "Đã khôi phục hiệu ứng ban đầu.", 3)
    end,
})

miscTab:Toggle({
    Title = "Ẩn NPC không tương tác",
    Desc = "Ẩn NPC không có prompt hoặc click detector để giảm model phải render",
    Default = true,
    Callback = function(s)
        state.hideNpcGraphics = s
        if state.lowGraphics then
            setLowGraphics(false)
            setLowGraphics(true)
        end
    end,
})

miscTab:Button({
    Title = "♻️ Unload Script",
    Desc = "Cleanly shuts everything off and closes the menu",
    Icon = "lucide:power",
    Callback = function()
        notify("♻️", "Unloaded! Re-execute anytime 💚", 3)
        if genv.__AHOSP_CLEANUP then
            pcall(genv.__AHOSP_CLEANUP)
        end
    end,
})

-- ==========================================
-- CLEANUP (re-execution safe — never stacks copies,
-- every loop bails, every glow & line disappears)
-- ==========================================
genv.__AHOSP_CLEANUP = function()
    if cleanupDone then return end
    cleanupDone = true
    dead = true
    automationBusy = false
    autoTaskRunId = autoTaskRunId + 1
    autoHealRunId = autoHealRunId + 1
    state.fullbright = false
    setFullbright(false)
    state.maxGraphics = false
    setMaxGraphics(false)
    state.lowGraphics = false
    setLowGraphics(false)
    state.noClip = false
    applyNoClip(false)
    state.thirdPerson = false
    applyThirdPerson()
    if savedCameraFov and workspace.CurrentCamera then
        workspace.CurrentCamera.FieldOfView = savedCameraFov
        savedCameraFov = nil
    end
    state.shrink = false
    applyCharacterScale(false)
    state.followPlayer = false
    state.followTarget = nil
    state.fixedFlight = false
    fixedFlightCFrame = nil
    dragTargetPlayer = nil
    restoreVehicleProperties()
    state.vehicleBrakeHeld = false
    state.fasterActions = false
    applyFasterActions()
    promptDurations = {}
    for k in pairs(state) do
        if type(state[k]) == "boolean" then state[k] = false end
    end
    for _, p in ipairs(helperParts) do
        if p and p.Parent then pcall(function() p:Destroy() end) end
    end
    helperParts = {}
    for _, conn in pairs(sanityConns) do
        pcall(function() conn:Disconnect() end)
    end
    sanityConns = {}
    clearAllLines()
    for target, hl in pairs(highlightCache) do
        if hl and hl.Parent then pcall(function() hl:Destroy() end) end
    end
    highlightCache = {}
    for _, p in ipairs(players:GetPlayers()) do
        removePlayerESP(p)
    end
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}
    for prompt, conn in pairs(manualPromptConnections) do
        pcall(function() conn:Disconnect() end)
        manualPromptConnections[prompt] = nil
    end
    pcall(function()
        if espLineGui and espLineGui.Parent then espLineGui:Destroy() end
    end)
    pcall(function() window:Destroy() end)
    pcall(function()
        local containers = { playerGui }
        if gethui then table.insert(containers, gethui()) end
        for _, container in ipairs(containers) do
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    local n = tostring(child.Name)
                    if n == "\0\1\2\3\4" or n == "\0\1\2\3\5"
                        or n == "\0\1\2\3\6" or n == "\0\1\2\3\7" then
                        child:Destroy()
                    end
                end
            end
        end
    end)
    minigameClicked = {}
    minigameQueue = {}
    cachedCandidates = {}
    cachedPrompts = {}
    itemInventory = {}
    inventoryButtons = {}
    characterModelScaleCache = {}
    promptDurations = {}

    thirdPersonYaw = 0
    thirdPersonPitch = 0
    thirdPersonMouseLook = false
    ghostBodyHeight = nil

    objectPushCooldown = 0
    colaBoostUntil = 0
    tpCooldown = false
    busy = false
    worldScanDirty = true

    automationPhase = "Idle"
    automationBusy = false
    lastTaskDiagnostic = ""
    lastTaskDiagnosticAt = 0
    minigameLastTrigger = os.clock()

    noClipLastUpdate = 0
    playerEspLastUpdate = 0
    followLastUpdate = 0

    remoteActionEvent = nil
    remoteServerDragEnabled = false

    -- Xóa mọi instance lạ còn sót trong Workspace
    pcall(function()
        for _, child in ipairs(workspace:GetChildren()) do
            if child.Name == "RefPart" then child:Destroy() end
        end
    end)

    if genv.__AHOSP_CLEANUP then
        genv.__AHOSP_CLEANUP = nil
    end
end

-- Boot it up (v1.6.65 windows auto-open, just pick the first tab)
window:SelectTab(1)
if isInLobby then
    notify("animal hospital", "Join the actual game first — lobby detected! 🏥", 6)
else
notify("animal hospital", "Loaded! 🏥💚", 4)
end
