-- ============================================================
-- ManeMine - Bot Hit + Aim Assist + 2D ESP
-- ============================================================

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LP = Players.LocalPlayer

-- ================= LOAD GAME MODULES =================
local MC = LP.PlayerScripts:WaitForChild("MC")
local Net = require(MC:WaitForChild("Net"))
local Hands = require(MC:WaitForChild("Hands"))
local Controller = require(MC:WaitForChild("Controller"))
local World = require(MC:WaitForChild("World"))

-- ================= SETTINGS =================
local CONFIG = {
    -- Bot Hit Settings
    BotHitEnabled = false,
    BotHitRange = 4.5,
    BotHitAngle = 15, -- Max degrees from crosshair to trigger hit
    BotHitDelay = 0.1,
    RequireStrength = true,
    AllowedWeapons = {
        ["Netherite_Sword"] = true,
        ["Netherite_Axe"] = true,
        ["Mace"] = true,
    },

    -- Aim Assist Settings
    AimAssistEnabled = false,
    AimHoldToActivate = true,
    AimFOV = 150,
    AimMaxDistance = 50,
    AimSmoothness = 0.2,
    AimShowFOV = false,

    -- 2D ESP Settings
    ESP_Enabled = false,
    ESP_ShowName = true,
    ESP_ShowCharacter = true,
    ESP_ShowHearts = true,
    ESP_Color = Color3.fromRGB(255, 255, 255),
}

local lastAttack = 0
local isAiming = false
local ESP_Labels = {}

-- ================= WEAPON CHECK =================
local function isHoldingAllowedWeapon()
    local char = LP.Character
    if not char then return false end

    -- 1. Check equipped Tool inside Character
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and CONFIG.AllowedWeapons[child.Name] then
            return true
        end
    end

    -- 2. Check Character attributes (e.g., HeldItem, Weapon, Item)
    for _, attrName in ipairs({"HeldItem", "Weapon", "Item", "Equipped", "Tool"}) do
        local val = char:GetAttribute(attrName)
        if type(val) == "string" and CONFIG.AllowedWeapons[val] then
            return true
        end
    end

    -- 3. Check MC.Hands module state/properties
    if type(Hands) == "table" then
        for _, key in ipairs({"item", "held", "heldItem", "weapon", "currentItem"}) do
            local val = Hands[key]
            if type(val) == "string" and CONFIG.AllowedWeapons[val] then
                return true
            elseif type(val) == "table" and type(val.name) == "string" and CONFIG.AllowedWeapons[val.name] then
                return true
            end
        end
        if type(Hands.getHeldItem) == "function" then
            local ok, res = pcall(Hands.getHeldItem)
            if ok then
                if type(res) == "string" and CONFIG.AllowedWeapons[res] then
                    return true
                elseif type(res) == "table" and type(res.name) == "string" and CONFIG.AllowedWeapons[res.name] then
                    return true
                end
            end
        end
    end

    return false
end

-- ================= BOT HIT FUNCTIONS =================
local function getCrosshairTarget()
    local eye = Controller.eye()
    if not eye then return nil end

    local ok, targets = pcall(World.targets)
    if not ok or type(targets) ~= "table" then return nil end

    local lookVec = Camera.CFrame.LookVector
    local maxRad = math.rad(CONFIG.BotHitAngle)

    local bestTarget = nil
    local bestAngle = maxRad

    for _, target in ipairs(targets) do
        local height = target.height or 1.8
        local centre = target.feet + Vector3.new(0, height * 0.5, 0)
        local toTarget = centre - eye
        local dist = toTarget.Magnitude

        if dist > 0.001 and dist <= CONFIG.BotHitRange then
            local dot = math.clamp(lookVec:Dot(toTarget.Unit), -1, 1)
            local angle = math.acos(dot)
            if angle <= bestAngle then
                bestTarget = target
                bestAngle = angle
            end
        end
    end

    return bestTarget, eye
end

local function doBotHit()
    if not CONFIG.BotHitEnabled then return end
    if Controller.locked then return end
    if workspace:GetAttribute("JugHold") == true then return end

    local character = LP.Character
    if not character or character:GetAttribute("Alive") ~= true then return end

    local okMode, mode = pcall(Hands.gamemode)
    if okMode and mode == "spectator" then return end

    if not isHoldingAllowedWeapon() then return end

    if CONFIG.RequireStrength then
        local okStrength, strength = pcall(Hands.strength)
        if not okStrength or strength < 0.95 then return end
    end

    local now = os.clock()
    if now - lastAttack < CONFIG.BotHitDelay then return end

    local target, eye = getCrosshairTarget()
    if not target then return end

    local height = target.height or 1.8
    local aim = target.feet + Vector3.new(0, height * 0.6, 0) - eye
    if aim.Magnitude < 0.0001 then return end

    local state = {
        fall = Controller.state and Controller.state.fallDistance or 0,
        ground = Controller.state and Controller.state.onGround == true,
        sprint = Controller.state and Controller.state.sprinting == true,
        water = Controller.state and Controller.state.inWater == true,
        gliding = Controller.state and Controller.state.gliding == true,
        vel = Controller.state and Controller.state.vel or Vector3.new(0, 0, 0),
        look = aim.Unit,
        swap = false,
        pos = Controller.state and Controller.state.pos,
        predicted = true
    }

    local ok = pcall(Net.send, { a = "attack", target = target.id, st = state })
    if ok then
        Hands.attackReset = Controller.tickCount
        Hands.swing = os.clock()
        lastAttack = now
    end
end

-- ================= AIM ASSIST FUNCTIONS =================
local AimGui = Instance.new("ScreenGui")
AimGui.Name = "ManeMine_AimFOV"
AimGui.ResetOnSpawn = false
AimGui.IgnoreGuiInset = true
AimGui.Parent = LP:WaitForChild("PlayerGui")

local FOVCircle = Instance.new("Frame")
FOVCircle.Name = "FOVCircle"
FOVCircle.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
FOVCircle.Size = UDim2.fromOffset(CONFIG.AimFOV * 2, CONFIG.AimFOV * 2)
FOVCircle.BackgroundTransparency = 1
FOVCircle.Visible = false
FOVCircle.Parent = AimGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircle

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Color = Color3.fromRGB(255, 255, 255)
FOVStroke.Thickness = 1.5
FOVStroke.Transparency = 0.35
FOVStroke.Parent = FOVCircle

local function getClosestAimTarget()
    local screenCenter = Vector2.new(Camera.ViewportSize.X * 0.5, Camera.ViewportSize.Y * 0.5)
    local closestPart = nil
    local shortestDist = CONFIG.AimFOV

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and player.Character then
            local char = player.Character
            if char:GetAttribute("Alive") == false then continue end

            local targetPart = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
            if targetPart then
                local worldDist = (targetPart.Position - Camera.CFrame.Position).Magnitude
                if worldDist <= CONFIG.AimMaxDistance then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        local fovDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if fovDist < shortestDist then
                            shortestDist = fovDist
                            closestPart = targetPart
                        end
                    end
                end
            end
        end
    end

    return closestPart
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then
        isAiming = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then
        isAiming = false
    end
end)

-- ================= 2D CAMERA ESP FUNCTIONS =================
local ESPGui = Instance.new("ScreenGui")
ESPGui.Name = "ManeMine_2DESP"
ESPGui.ResetOnSpawn = false
ESPGui.IgnoreGuiInset = true
ESPGui.Parent = LP:WaitForChild("PlayerGui")

local function GetPlayerCharacterName(player, char)
    for _, attr in ipairs({"Character", "Kit", "Class", "Role", "SelectedCharacter", "Hero"}) do
        local val = char:GetAttribute(attr) or player:GetAttribute(attr)
        if type(val) == "string" and val ~= "" then
            return val
        end
    end
    for _, folderName in ipairs({"Data", "Stats", "PlayerData", "leaderstats"}) do
        local folder = player:FindFirstChild(folderName)
        if folder then
            for _, valName in ipairs({"Character", "Kit", "Class", "Role"}) do
                local obj = folder:FindFirstChild(valName)
                if obj and obj:IsA("StringValue") and obj.Value ~= "" then
                    return obj.Value
                end
            end
        end
    end
    return player.DisplayName
end

local function GetPlayerHealthData(player, char)
    -- 1. Check World.targets() custom MC entity health if available
    local ok, targets = pcall(World.targets)
    if ok and type(targets) == "table" then
        for _, target in ipairs(targets) do
            local matchesPlayer = (target.player == player)
                or (target.model == char)
                or (target.character == char)
                or (target.name == player.Name)
                or (tostring(target.id) == tostring(player.UserId))
                or (tostring(target.id) == player.Name)

            if not matchesPlayer and target.feet and char:FindFirstChild("HumanoidRootPart") then
                local dist = (target.feet - char.HumanoidRootPart.Position).Magnitude
                if dist < 4.5 then
                    matchesPlayer = true
                end
            end

            if matchesPlayer then
                local hp = target.health or target.hp or target.Health or target.HP
                local maxHp = target.maxHealth or target.maxHp or target.MaxHealth or target.MaxHP or 20
                if type(hp) == "number" then
                    return hp, maxHp
                end
            end
        end
    end

    -- 2. Check custom health Attributes on Character or Player (Unstable SMP uses MC health attributes)
    for _, attr in ipairs({"Health", "HP", "health", "hp", "CurrentHealth"}) do
        local hpAttr = char:GetAttribute(attr) or player:GetAttribute(attr)
        if type(hpAttr) == "number" then
            local maxAttr = char:GetAttribute("Max" .. attr)
                or char:GetAttribute("MaxHealth")
                or char:GetAttribute("MaxHP")
                or player:GetAttribute("MaxHealth")
                or 20
            return hpAttr, (type(maxAttr) == "number" and maxAttr > 0) and maxAttr or 20
        end
    end

    -- 3. Check NumberValue / IntValue objects inside Character or Player folders
    for _, container in ipairs({char, player, player:FindFirstChild("Data"), player:FindFirstChild("Stats")}) do
        if container then
            for _, valName in ipairs({"Health", "HP", "CurrentHealth"}) do
                local valObj = container:FindFirstChild(valName)
                if valObj and (valObj:IsA("NumberValue") or valObj:IsA("IntValue")) then
                    local maxObj = container:FindFirstChild("MaxHealth") or container:FindFirstChild("MaxHP")
                    local maxVal = (maxObj and (maxObj:IsA("NumberValue") or maxObj:IsA("IntValue")) and maxObj.Value > 0)
                        and maxObj.Value or 20
                    return valObj.Value, maxVal
                end
            end
        end
    end

    -- 4. Fallback to Roblox Humanoid
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.Health, hum.MaxHealth
    end

    return nil, nil
end

local function FormatHearts(hp, maxHp)
    if not hp or not maxHp or maxHp <= 0 then
        return "? Hearts"
    end
    -- Minecraft standard is 20 HP = 10 Hearts (1 Heart = 2 HP).
    -- If maxHp is 100 (Roblox default), scale proportionally to 10 Hearts.
    local hearts = (maxHp <= 40) and (hp / 2) or ((hp / maxHp) * 10)
    local maxHearts = (maxHp <= 40) and (maxHp / 2) or 10
    local roundedHearts = math.max(0, math.floor(hearts * 2 + 0.5) / 2)
    local roundedMax = math.floor(maxHearts * 2 + 0.5) / 2
    return string.format("%.1f / %.0f Hearts", roundedHearts, roundedMax)
end

local function RemoveESPLabel(player)
    if ESP_Labels[player] then
        ESP_Labels[player]:Destroy()
        ESP_Labels[player] = nil
    end
end

local function GetOrCreateESPLabel(player)
    if ESP_Labels[player] then
        return ESP_Labels[player]
    end

    local label = Instance.new("TextLabel")
    label.Name = "ESP_" .. player.Name
    label.Size = UDim2.new(0, 220, 0, 60)
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = CONFIG.ESP_Color
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextYAlignment = Enum.TextYAlignment.Bottom
    label.Visible = false
    label.Parent = ESPGui

    ESP_Labels[player] = label
    return label
end

Players.PlayerRemoving:Connect(function(player)
    RemoveESPLabel(player)
end)

-- ================= INTERFACE (MENU) =================
local Window = WindUI:CreateWindow({
    Title = "ManeMine",
    Icon = "rbxassetid://10734898355",
    Author = "Unstable SMP",
    Size = UDim2.fromOffset(440, 420),
    Theme = "Dark",
    User = { Enabled = true, Anonymous = true }
})

-- COMBAT TAB
local TabCombat = Window:Tab({ Title = "Combat", Icon = "rbxassetid://10734898355" })

TabCombat:Section({ Title = "Bot Hit" })

TabCombat:Toggle({
    Title = "Enable Bot Hit",
    Desc = "Auto-hits when aiming at a player with Netherite Sword, Netherite Axe, or Mace",
    Value = false,
    Callback = function(state)
        CONFIG.BotHitEnabled = state
        WindUI:Notify({
            Title = state and "Bot Hit Enabled" or "Bot Hit Disabled",
            Content = state and "Aim at a player with an allowed weapon" or "Bot Hit turned off",
            Duration = 2
        })
    end
})

TabCombat:Slider({
    Title = "Bot Hit Range",
    Value = { Min = 2, Max = 8, Default = 4.5 },
    Callback = function(v) CONFIG.BotHitRange = v end
})

TabCombat:Slider({
    Title = "Aim Angle Cone (Degrees)",
    Value = { Min = 3, Max = 45, Default = 15 },
    Callback = function(v) CONFIG.BotHitAngle = v end
})

TabCombat:Slider({
    Title = "Attack Delay (s)",
    Value = { Min = 0.05, Max = 1, Default = 0.1 },
    Callback = function(v) CONFIG.BotHitDelay = v end
})

TabCombat:Toggle({
    Title = "Require Full Weapon Charge",
    Desc = "Only hits when weapon strength >= 0.95",
    Value = true,
    Callback = function(state) CONFIG.RequireStrength = state end
})

TabCombat:Section({ Title = "Aim Assist" })

TabCombat:Toggle({
    Title = "Enable Aim Assist",
    Desc = "Smoothly guides camera toward players inside FOV",
    Value = false,
    Callback = function(state)
        CONFIG.AimAssistEnabled = state
        FOVCircle.Visible = state and CONFIG.AimShowFOV
    end
})

TabCombat:Toggle({
    Title = "Hold Right-Click / Touch to Aim",
    Desc = "Only assists while holding aim input",
    Value = true,
    Callback = function(state) CONFIG.AimHoldToActivate = state end
})

TabCombat:Toggle({
    Title = "Show FOV Circle",
    Desc = "Draws the Aim Assist FOV circle on screen",
    Value = false,
    Callback = function(state)
        CONFIG.AimShowFOV = state
        FOVCircle.Visible = CONFIG.AimAssistEnabled and state
    end
})

TabCombat:Slider({
    Title = "Aim FOV Radius",
    Value = { Min = 30, Max = 400, Default = 150 },
    Callback = function(v)
        CONFIG.AimFOV = v
        FOVCircle.Size = UDim2.fromOffset(v * 2, v * 2)
    end
})

TabCombat:Slider({
    Title = "Aim Max Distance",
    Value = { Min = 5, Max = 100, Default = 50 },
    Callback = function(v) CONFIG.AimMaxDistance = v end
})

TabCombat:Slider({
    Title = "Aim Smoothness",
    Value = { Min = 0.05, Max = 0.95, Default = 0.2 },
    Callback = function(v) CONFIG.AimSmoothness = v end
})

-- VISUAL TAB (2D ESP)
local TabVisual = Window:Tab({ Title = "Visual", Icon = "rbxassetid://10734924912" })

TabVisual:Toggle({
    Title = "Enable 2D ESP",
    Desc = "Tracks players on screen without changing character colors",
    Value = false,
    Callback = function(state)
        CONFIG.ESP_Enabled = state
        if not state then
            for _, label in pairs(ESP_Labels) do
                label.Visible = false
            end
        end
    end
})

TabVisual:Toggle({
    Title = "Show Name",
    Value = true,
    Callback = function(state) CONFIG.ESP_ShowName = state end
})

TabVisual:Toggle({
    Title = "Show Character",
    Value = true,
    Callback = function(state) CONFIG.ESP_ShowCharacter = state end
})

TabVisual:Toggle({
    Title = "Show Hearts",
    Value = true,
    Callback = function(state) CONFIG.ESP_ShowHearts = state end
})

-- ================= LOOPS =================
-- Bot Hit Loop
RunService.Heartbeat:Connect(function()
    pcall(doBotHit)
end)

-- Aim Assist & 2D ESP Render Loop
RunService.RenderStepped:Connect(function()
    -- Aim Assist
    if CONFIG.AimAssistEnabled then
        if not CONFIG.AimHoldToActivate or isAiming then
            local targetPart = getClosestAimTarget()
            if targetPart then
                local currentCFrame = Camera.CFrame
                local targetCFrame = CFrame.new(currentCFrame.Position, targetPart.Position)
                Camera.CFrame = currentCFrame:Lerp(targetCFrame, CONFIG.AimSmoothness)
            end
        end
    end

    -- 2D Camera ESP
    if not CONFIG.ESP_Enabled then return end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP then
            local char = player.Character
            local label = GetOrCreateESPLabel(player)

            if char and char:GetAttribute("Alive") ~= false then
                local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")

                if head then
                    local worldPos = head.Position + Vector3.new(0, 1.5, 0)
                    local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)

                    if onScreen and screenPos.Z > 0 then
                        local lines = {}
                        if CONFIG.ESP_ShowName then
                            table.insert(lines, player.Name)
                        end
                        if CONFIG.ESP_ShowCharacter then
                            table.insert(lines, "[" .. GetPlayerCharacterName(player, char) .. "]")
                        end
                        if CONFIG.ESP_ShowHearts then
                            local hp, maxHp = GetPlayerHealthData(player, char)
                            table.insert(lines, FormatHearts(hp, maxHp))
                        end

                        label.Text = table.concat(lines, "\n")
                        label.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
                        label.Visible = #lines > 0
                    else
                        label.Visible = false
                    end
                else
                    label.Visible = false
                end
            else
                label.Visible = false
            end
        end
    end
end)
