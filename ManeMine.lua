-- ============================================================
-- ManeMine - Bot Hit + Lunge Spear + Aim Assist + 2D ESP
-- ============================================================

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ================= LOAD GAME MODULES =================
local MC = LP.PlayerScripts:WaitForChild("MC")
local Net = require(MC:WaitForChild("Net"))
local Hands = require(MC:WaitForChild("Hands"))
local Controller = require(MC:WaitForChild("Controller"))
local World = require(MC:WaitForChild("World"))

-- ================= ALLOWED WEAPONS =================
local AllowedWeapons = {
    ["netherite_sword"] = true,
    ["netherite_axe"] = true,
    ["mace"] = true
}

-- ================= SETTINGS =================
local CONFIG = {
    -- Bot Hit Settings
    BotHit_Enabled = false,
    BotHit_Range = 3.5,
    BotHit_Angle = 15,
    BotHit_Delay = 0.1,
    RequireStrength = true,

    -- Lunge Spear Settings
    LungeSpear_Enabled = false,

    -- Aim Assist Settings
    AimAssist_Enabled = false,
    AimAssist_Hold = true,
    AimAssist_FOV = 120,
    AimAssist_Range = 6.0,
    AimAssist_Smoothness = 12,
    AimAssist_ShowFOV = false,

    -- 2D ESP Settings
    ESP_Enabled = false,
    ESP_ShowName = true,
    ESP_ShowCharacter = true,
    ESP_ShowHearts = true,
    ESP_TextColor = Color3.fromRGB(255, 255, 255)
}

local lastAttack = 0
local ESP_Drawings = {}

-- ================= HELPER FUNCTIONS =================
local function isHoldingAllowedWeapon()
    local char = LP.Character
    if not char then return false end

    local tool = char:FindFirstChildOfClass("Tool")
    if tool and AllowedWeapons[string.lower(tool.Name)] then
        return true
    end

    local heldAttr = char:GetAttribute("HeldItem") or char:GetAttribute("Weapon") or char:GetAttribute("Item") or LP:GetAttribute("HeldItem")
    if type(heldAttr) == "string" and AllowedWeapons[string.lower(heldAttr)] then
        return true
    end

    if type(Hands) == "table" then
        local item = Hands.item or Hands.held or Hands.current
        if type(item) == "string" and AllowedWeapons[string.lower(item)] then
            return true
        elseif type(item) == "table" and type(item.name) == "string" and AllowedWeapons[string.lower(item.name)] then
            return true
        elseif type(Hands.getHeld) == "function" then
            local ok, res = pcall(Hands.getHeld)
            if ok then
                if type(res) == "string" and AllowedWeapons[string.lower(res)] then
                    return true
                elseif type(res) == "table" and type(res.name) == "string" and AllowedWeapons[string.lower(res.name)] then
                    return true
                end
            end
        end
    end

    return false
end

local function getAimedTarget(maxRange, maxAngleDeg)
    local eye = Controller.eye()
    if not eye then return nil end
    local ok, targets = pcall(World.targets)
    if not ok or type(targets) ~= "table" then return nil end

    local lookVec = Camera.CFrame.LookVector
    local best = nil
    local bestAngle = maxAngleDeg

    for _, target in ipairs(targets) do
        local height = target.height or 1.8
        local centre = target.feet + Vector3.new(0, height * 0.5, 0)
        local offset = centre - eye
        local distance = offset.Magnitude

        if distance <= maxRange and distance > 0.001 then
            local dir = offset.Unit
            local dot = math.clamp(lookVec:Dot(dir), -1, 1)
            local angle = math.deg(math.acos(dot))

            if angle <= bestAngle then
                best = target
                bestAngle = angle
            end
        end
    end

    return best, eye
end

-- ================= BOT HIT LOGIC =================
local function doBotHit()
    if not CONFIG.BotHit_Enabled then return end
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
    if now - lastAttack < CONFIG.BotHit_Delay then return end

    local target, eye = getAimedTarget(CONFIG.BotHit_Range, CONFIG.BotHit_Angle)
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

-- ================= LUNGE SPEAR LOGIC =================
local function equipItem(itemName)
    local char = LP.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end

    local lowerTarget = string.lower(itemName)

    -- Check if already equipped
    local equipped = char:FindFirstChildOfClass("Tool")
    if equipped and string.lower(equipped.Name) == lowerTarget then
        return equipped
    end

    -- Search Backpack for matching tool
    local backpack = LP:FindFirstChild("Backpack")
    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") and string.lower(item.Name) == lowerTarget then
                hum:EquipTool(item)
                return item
            end
        end
    end

    -- Fallback: try custom Hands module equip/select methods if available
    if type(Hands) == "table" then
        if type(Hands.equip) == "function" then
            pcall(Hands.equip, itemName)
        elseif type(Hands.setHeld) == "function" then
            pcall(Hands.setHeld, itemName)
        end
    end

    return nil
end

local function doLungeSpear()
    if not CONFIG.LungeSpear_Enabled then return end
    if Controller.locked then return end

    local character = LP.Character
    if not character or character:GetAttribute("Alive") ~= true then return end

    -- 1. Equip wind_charge
    equipItem("wind_charge")

    -- 2. Same tick: equip netherite_spear and swing/activate directly (no target lookup)
    local spear = equipItem("netherite_spear")
    if spear then
        pcall(function() spear:Activate() end)
    end
    if type(Hands) == "table" then
        if type(Hands.use) == "function" then
            pcall(Hands.use)
        elseif type(Hands.primary) == "function" then
            pcall(Hands.primary)
        end
        Hands.swing = os.clock()
    end
    pcall(Net.send, { a = "swing" })

    -- 3. Same tick: re-equip wind_charge
    equipItem("wind_charge")
end

-- ================= FLOATING LS BUTTON =================
local LS_Gui = Instance.new("ScreenGui")
LS_Gui.Name = "ManeMine_LungeSpear_GUI"
LS_Gui.ResetOnSpawn = false
LS_Gui.IgnoreGuiInset = true
LS_Gui.Parent = (gethui and gethui()) or CoreGui

local LS_Button = Instance.new("TextButton")
LS_Button.Name = "LS_Button"
LS_Button.Size = UDim2.new(0, 56, 0, 56)
LS_Button.Position = UDim2.new(0.82, 0, 0.55, 0)
LS_Button.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
LS_Button.BackgroundTransparency = 0.15
LS_Button.Text = "LS"
LS_Button.TextColor3 = Color3.fromRGB(255, 255, 255)
LS_Button.Font = Enum.Font.GothamBold
LS_Button.TextSize = 18
LS_Button.Visible = false
LS_Button.AutoButtonColor = true
LS_Button.Parent = LS_Gui

local LS_Corner = Instance.new("UICorner")
LS_Corner.CornerRadius = UDim.new(1, 0)
LS_Corner.Parent = LS_Button

local LS_Stroke = Instance.new("UIStroke")
LS_Stroke.Thickness = 2
LS_Stroke.Color = Color3.fromRGB(0, 145, 255)
LS_Stroke.Parent = LS_Button

-- Draggable support for LS button
local lsDragging = false
local lsDragMoved = false
local lsDragStart, lsStartPos

LS_Button.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        lsDragging = true
        lsDragMoved = false
        lsDragStart = input.Position
        lsStartPos = LS_Button.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if lsDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - lsDragStart
        if delta.Magnitude > 6 then
            lsDragMoved = true
        end
        LS_Button.Position = UDim2.new(
            lsStartPos.X.Scale,
            lsStartPos.X.Offset + delta.X,
            lsStartPos.Y.Scale,
            lsStartPos.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if lsDragging then
            lsDragging = false
            if not lsDragMoved then
                pcall(doLungeSpear)
            end
        end
    end
end)

-- ================= AIM ASSIST LOGIC =================
local FOV_Gui = Instance.new("ScreenGui")
FOV_Gui.Name = "ManeMine_FOV_GUI"
FOV_Gui.ResetOnSpawn = false
FOV_Gui.IgnoreGuiInset = true
FOV_Gui.Parent = (gethui and gethui()) or CoreGui

local FOV_Circle = Instance.new("Frame")
FOV_Circle.Name = "FOVCircle"
FOV_Circle.AnchorPoint = Vector2.new(0.5, 0.5)
FOV_Circle.Position = UDim2.new(0.5, 0, 0.5, 0)
FOV_Circle.Size = UDim2.new(0, CONFIG.AimAssist_FOV * 2, 0, CONFIG.AimAssist_FOV * 2)
FOV_Circle.BackgroundTransparency = 1
FOV_Circle.Visible = false
FOV_Circle.Parent = FOV_Gui

local FOV_Corner = Instance.new("UICorner")
FOV_Corner.CornerRadius = UDim.new(1, 0)
FOV_Corner.Parent = FOV_Circle

local FOV_Stroke = Instance.new("UIStroke")
FOV_Stroke.Thickness = 1.5
FOV_Stroke.Color = Color3.fromRGB(255, 255, 255)
FOV_Stroke.Transparency = 0.35
FOV_Stroke.Parent = FOV_Circle

local function isAimKeyDown()
    if not CONFIG.AimAssist_Hold then
        return true
    end
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or #UserInputService:GetTouchInputs() > 0
end

local function getClosestAimTarget()
    local localChar = LP.Character
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
    if not localRoot then return nil end

    local viewportCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local closestPart = nil
    local shortestFOV = CONFIG.AimAssist_FOV

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and player.Character then
            local char = player.Character
            local hum = char:FindFirstChildOfClass("Humanoid")
            local targetPart = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")

            if hum and hum.Health > 0 and targetPart and char:GetAttribute("Alive") ~= false then
                local dist3D = (targetPart.Position - localRoot.Position).Magnitude
                if dist3D <= CONFIG.AimAssist_Range then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen and screenPos.Z > 0 then
                        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - viewportCenter).Magnitude
                        if dist2D <= shortestFOV then
                            shortestFOV = dist2D
                            closestPart = targetPart
                        end
                    end
                end
            end
        end
    end

    return closestPart
end

local function updateAimAssist()
    FOV_Circle.Visible = CONFIG.AimAssist_Enabled and CONFIG.AimAssist_ShowFOV
    FOV_Circle.Size = UDim2.new(0, CONFIG.AimAssist_FOV * 2, 0, CONFIG.AimAssist_FOV * 2)

    if not CONFIG.AimAssist_Enabled or not isAimKeyDown() then return end

    local targetPart = getClosestAimTarget()
    if not targetPart then return end

    local camPos = Camera.CFrame.Position
    local goalCFrame = CFrame.new(camPos, targetPart.Position)
    local alpha = math.clamp(1 / CONFIG.AimAssist_Smoothness, 0.02, 1)
    Camera.CFrame = Camera.CFrame:Lerp(goalCFrame, alpha)
end

-- ================= 2D ESP FUNCTIONS =================
local ESP_Gui = Instance.new("ScreenGui")
ESP_Gui.Name = "ManeMine_2D_ESP"
ESP_Gui.ResetOnSpawn = false
ESP_Gui.IgnoreGuiInset = true
ESP_Gui.Parent = (gethui and gethui()) or CoreGui

local function RemovePlayerESP(player)
    if ESP_Drawings[player] then
        if ESP_Drawings[player].Container then
            ESP_Drawings[player].Container:Destroy()
        end
        ESP_Drawings[player] = nil
    end
end

local function ClearESP()
    for player, _ in pairs(ESP_Drawings) do
        RemovePlayerESP(player)
    end
end

local function GetPlayerCharacterName(player, char)
    local attr = char:GetAttribute("Character")
        or char:GetAttribute("Kit")
        or char:GetAttribute("Class")
        or char:GetAttribute("Role")
        or player:GetAttribute("Character")
        or player:GetAttribute("Kit")
        or player:GetAttribute("Class")

    if attr and tostring(attr) ~= "" then
        return tostring(attr)
    end

    for _, folderName in ipairs({"leaderstats", "Data", "Stats", "Info"}) do
        local folder = player:FindFirstChild(folderName)
        if folder then
            for _, valName in ipairs({"Character", "Kit", "Class", "Role"}) do
                local valObj = folder:FindFirstChild(valName)
                if valObj and valObj:IsA("ValueBase") and tostring(valObj.Value) ~= "" then
                    return tostring(valObj.Value)
                end
            end
        end
    end

    return player.DisplayName
end

local function GetLiveHealthAndHearts(player, char, hum, worldTargets)
    local hp = nil
    local maxHp = nil

    if type(worldTargets) == "table" then
        for _, t in ipairs(worldTargets) do
            if t.player == player or t.character == char or t.model == char or t.name == player.Name or tostring(t.id) == tostring(player.UserId) then
                if type(t.health) == "number" then
                    hp = t.health
                    maxHp = type(t.maxHealth) == "number" and t.maxHealth or nil
                    break
                elseif type(t.hp) == "number" then
                    hp = t.hp
                    maxHp = type(t.maxHp) == "number" and t.maxHp or nil
                    break
                end
            end
        end
    end

    if hp == nil then
        local attrHp = char:GetAttribute("Health") or char:GetAttribute("HP") or char:GetAttribute("CurrentHealth")
            or player:GetAttribute("Health") or player:GetAttribute("HP")
        if type(attrHp) == "number" then
            hp = attrHp
            maxHp = char:GetAttribute("MaxHealth") or char:GetAttribute("MaxHP")
                or player:GetAttribute("MaxHealth") or player:GetAttribute("MaxHP")
        end
    end

    if hp == nil then
        for _, folderName in ipairs({"Data", "Stats", "Status", "Info", "leaderstats"}) do
            local folder = char:FindFirstChild(folderName) or player:FindFirstChild(folderName)
            if folder then
                local hpObj = folder:FindFirstChild("Health") or folder:FindFirstChild("HP")
                if hpObj and hpObj:IsA("NumberValue") or (hpObj and hpObj:IsA("IntValue")) then
                    hp = hpObj.Value
                    local maxObj = folder:FindFirstChild("MaxHealth") or folder:FindFirstChild("MaxHP")
                    if maxObj and (maxObj:IsA("NumberValue") or maxObj:IsA("IntValue")) then
                        maxHp = maxObj.Value
                    end
                    break
                end
            end
        end
    end

    if hp == nil and hum then
        hp = hum.Health
        maxHp = hum.MaxHealth
    end

    hp = math.max(0, hp or 0)
    maxHp = (maxHp and maxHp > 0) and maxHp or (hp > 20 and 100 or 20)

    local hearts = 0
    local maxHearts = 10
    if maxHp <= 20 then
        hearts = hp / 2
        maxHearts = maxHp / 2
    else
        hearts = (hp / maxHp) * 10
        maxHearts = 10
    end

    return math.floor(hearts * 10 + 0.5) / 10, math.floor(maxHearts * 10 + 0.5) / 10
end

local function CreatePlayerESP(player)
    if player == LP or ESP_Drawings[player] then return end

    local container = Instance.new("Frame")
    container.Name = player.Name .. "_2DESP"
    container.Size = UDim2.new(0, 220, 0, 60)
    container.AnchorPoint = Vector2.new(0.5, 1)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = ESP_Gui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, 1)
    layout.Parent = container

    local function makeLabel(order, size, color)
        local lbl = Instance.new("TextLabel")
        lbl.LayoutOrder = order
        lbl.Size = UDim2.new(1, 0, 0, size + 2)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0
        lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = size
        lbl.Text = ""
        lbl.Parent = container
        return lbl
    end

    ESP_Drawings[player] = {
        Container = container,
        NameLabel = makeLabel(1, 14, CONFIG.ESP_TextColor),
        CharLabel = makeLabel(2, 12, Color3.fromRGB(180, 220, 255)),
        HeartsLabel = makeLabel(3, 13, Color3.fromRGB(255, 85, 85))
    }
end

local function Update2DESP()
    if not CONFIG.ESP_Enabled then
        for _, data in pairs(ESP_Drawings) do
            data.Container.Visible = false
        end
        return
    end

    local okTargets, worldTargets = pcall(World.targets)
    if not okTargets or type(worldTargets) ~= "table" then
        worldTargets = nil
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP then
            if not ESP_Drawings[player] then
                CreatePlayerESP(player)
            end

            local data = ESP_Drawings[player]
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))

            if char and root and (not hum or hum.Health > 0) then
                local headPos = root.Position + Vector3.new(0, 1.5, 0)
                local screenPos, onScreen = Camera:WorldToViewportPoint(headPos)

                if onScreen and screenPos.Z > 0 then
                    data.Container.Visible = true
                    data.Container.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)

                    data.NameLabel.Visible = CONFIG.ESP_ShowName
                    if CONFIG.ESP_ShowName then
                        data.NameLabel.Text = player.Name
                        data.NameLabel.TextColor3 = CONFIG.ESP_TextColor
                    end

                    data.CharLabel.Visible = CONFIG.ESP_ShowCharacter
                    if CONFIG.ESP_ShowCharacter then
                        data.CharLabel.Text = "[" .. GetPlayerCharacterName(player, char) .. "]"
                    end

                    data.HeartsLabel.Visible = CONFIG.ESP_ShowHearts
                    if CONFIG.ESP_ShowHearts then
                        local hearts, maxHearts = GetLiveHealthAndHearts(player, char, hum, worldTargets)
                        data.HeartsLabel.Text = tostring(hearts) .. " / " .. tostring(maxHearts) .. " Hearts"
                    end
                else
                    data.Container.Visible = false
                end
            else
                data.Container.Visible = false
            end
        end
    end
end

Players.PlayerAdded:Connect(function(player)
    CreatePlayerESP(player)
end)

Players.PlayerRemoving:Connect(function(player)
    RemovePlayerESP(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LP then
        CreatePlayerESP(player)
    end
end

-- ================= INTERFACE (MENU) =================
local Window = WindUI:CreateWindow({
    Title = "ManeMine",
    Author = "Unstable SMP",
    Size = UDim2.fromOffset(440, 460),
    Theme = "Dark",
    User = { Enabled = true, Anonymous = true }
})

-- COMBAT TAB
local TabCombat = Window:Tab({ Title = "Combat" })

TabCombat:Toggle({
    Title = "Bot Hit",
    Desc = "Automatically hits aimed players when holding netherite_sword, netherite_axe, or mace",
    Value = false,
    Callback = function(state)
        CONFIG.BotHit_Enabled = state
        if state then
            WindUI:Notify({ Title = "Bot Hit Enabled", Content = "Equip netherite_sword, netherite_axe, or mace and aim at a player", Duration = 3 })
        else
            WindUI:Notify({ Title = "Bot Hit Disabled", Duration = 3 })
        end
    end
})

TabCombat:Slider({
    Title = "Bot Hit Range",
    Value = { Min = 2, Max = 8, Default = 3.5 },
    Step = 0.1,
    Callback = function(v) CONFIG.BotHit_Range = v end
})

TabCombat:Slider({
    Title = "Bot Hit Aim Angle (deg)",
    Value = { Min = 3, Max = 45, Default = 15 },
    Step = 1,
    Callback = function(v) CONFIG.BotHit_Angle = v end
})

TabCombat:Slider({
    Title = "Attack Delay (s)",
    Value = { Min = 0.05, Max = 1, Default = 0.1 },
    Step = 0.05,
    Callback = function(v) CONFIG.BotHit_Delay = v end
})

TabCombat:Toggle({
    Title = "Require Minimum Strength",
    Desc = "Only attacks if weapon strength is >= 0.95",
    Value = true,
    Callback = function(state) CONFIG.RequireStrength = state end
})

TabCombat:Divider()

TabCombat:Toggle({
    Title = "Lunge Spear (LS Button)",
    Desc = "Shows floating LS button: equips wind_charge, swaps to netherite_spear, swings, and re-equips wind_charge",
    Value = false,
    Callback = function(state)
        CONFIG.LungeSpear_Enabled = state
        LS_Button.Visible = state
        if state then
            WindUI:Notify({ Title = "Lunge Spear Enabled", Content = "Floating LS button is now visible", Duration = 3 })
        else
            WindUI:Notify({ Title = "Lunge Spear Disabled", Duration = 3 })
        end
    end
})

TabCombat:Divider()

TabCombat:Toggle({
    Title = "Aim Assist",
    Desc = "Smoothly guides your camera toward close-range enemies",
    Value = false,
    Callback = function(state)
        CONFIG.AimAssist_Enabled = state
        if state then
            WindUI:Notify({ Title = "Aim Assist Enabled", Duration = 3 })
        else
            WindUI:Notify({ Title = "Aim Assist Disabled", Duration = 3 })
        end
    end
})

TabCombat:Toggle({
    Title = "Hold to Aim (Right Click / Touch)",
    Desc = "Only assists while holding Right Click or touching screen",
    Value = true,
    Callback = function(state) CONFIG.AimAssist_Hold = state end
})

TabCombat:Toggle({
    Title = "Show Aim FOV Circle",
    Desc = "Displays the aim assist radius on screen",
    Value = false,
    Callback = function(state) CONFIG.AimAssist_ShowFOV = state end
})

TabCombat:Slider({
    Title = "Aim Range",
    Value = { Min = 2, Max = 15, Default = 6.0 },
    Step = 0.5,
    Callback = function(v) CONFIG.AimAssist_Range = v end
})

TabCombat:Slider({
    Title = "Aim FOV Radius",
    Value = { Min = 30, Max = 400, Default = 120 },
    Step = 5,
    Callback = function(v) CONFIG.AimAssist_FOV = v end
})

TabCombat:Slider({
    Title = "Aim Smoothness",
    Value = { Min = 1, Max = 25, Default = 12 },
    Step = 1,
    Callback = function(v) CONFIG.AimAssist_Smoothness = v end
})

-- VISUAL TAB (2D ESP)
local TabVisual = Window:Tab({ Title = "Visual" })

TabVisual:Toggle({
    Title = "Enable 2D ESP",
    Desc = "Shows 2D player info that follows your camera without changing player colors",
    Value = false,
    Callback = function(state)
        CONFIG.ESP_Enabled = state
        if state then
            WindUI:Notify({ Title = "2D ESP Enabled", Duration = 3 })
        else
            WindUI:Notify({ Title = "2D ESP Disabled", Duration = 3 })
        end
    end
})

TabVisual:Toggle({
    Title = "Show Name",
    Desc = "Displays the player's username",
    Value = true,
    Callback = function(state) CONFIG.ESP_ShowName = state end
})

TabVisual:Toggle({
    Title = "Show Character",
    Desc = "Displays the character or kit the player is using",
    Value = true,
    Callback = function(state) CONFIG.ESP_ShowCharacter = state end
})

TabVisual:Toggle({
    Title = "Show Hearts",
    Desc = "Displays live remaining hearts",
    Value = true,
    Callback = function(state) CONFIG.ESP_ShowHearts = state end
})

TabVisual:Button({
    Title = "Refresh 2D ESP",
    Callback = function()
        ClearESP()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP then
                CreatePlayerESP(player)
            end
        end
        WindUI:Notify({ Title = "2D ESP Refreshed", Duration = 2 })
    end
})

-- ================= LOOPS =================
RunService.Heartbeat:Connect(function()
    pcall(doBotHit)
end)

RunService.RenderStepped:Connect(function()
    pcall(updateAimAssist)
    pcall(Update2DESP)
end)
