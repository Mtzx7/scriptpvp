-- LocalScript para Xeno Executor
-- ESP Normal + Hitbox ESP + ShiftLock + Piso ao Pular + Speed Boost Configurável + AimLock
-- REMOVIDO: função de deixar base transparente
-- Coloque em StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
if not localPlayer then
    print("[lznx7] Aguardando jogador local...")
    wait(1)
    localPlayer = Players.LocalPlayer
    if not localPlayer then return end
end

-- Configurações
local ESP_ENABLED = false
local INFINITE_JUMP = false
local JUMP_IMPULSE_Y = 70
local GOD_MODE = true
local GOD_MAX_HEALTH = 1000000
local ANTI_RAGDOLL = true
local HITBOX_ESP = false  -- Nova opção para Hitbox ESP
local JUMP_PLATFORM = true  -- Nova opção: criar piso ao pular
local PLATFORM_DURATION = 4  -- Duração do piso em segundos
local SPEED_BOOST = false  -- Nova opção: Speed Boost
local SPEED_BOOST_MULTIPLIER = 3  -- Multiplicador de velocidade (3x mais rápido)
local AIMLOCK_ENABLED = false  -- Nova opção: AimLock
local AIMLOCK_KEY = Enum.KeyCode.Q  -- Tecla para ativar AimLock
local AIMLOCK_SMOOTHNESS = 0.15  -- Suavidade do AimLock (0-1, menor = mais suave)
local AIMLOCK_USE_CAMERA = true  -- Usar câmera em vez de mouse
local aimLockConn = nil
local aimLockTarget = nil
local aimLockTargetPart = "Head"  -- Parte do corpo para mirar
local speedBoostConn = nil
local speedBoostActive = false

-- Shift Lock (trava "Shift" / trava sprint na tela)
local SHIFT_LOCK = false
local SHIFT_WALK_SPEED = 24 -- velocidade enquanto shift estiver travado
local DEFAULT_WALK_SPEED = 16
local shiftLockConn = nil
local shiftLockCharacterConn = nil
local shiftLockOrigSpeed = {}

-- Armazenamento
local playerGui = localPlayer:WaitForChild("PlayerGui")
local espStore = playerGui:FindFirstChild("Lznx7ESPStore")
if not espStore then
    espStore = Instance.new("Folder")
    espStore.Name = "Lznx7ESPStore"
    espStore.Parent = playerGui
end

-- Variáveis globais
local godConns = {}
local antiRagdollConns = {}
local infiniteJumpConnection
local espData = {} -- Armazenar dados do ESP por jogador
local jumpPlatformConnection
local platformParts = {} -- Armazenar pisos criados
local lastJumpTime = 0
local JUMP_COOLDOWN = 0.2 -- Cooldown entre criação de pisos
local originalWalkSpeed = 16
local originalJumpPower = 50
local speedConfigGui = nil  -- GUI para configuração de velocidade
local speedBoostMultiplier = 3  -- Valor atual do multiplicador
local mainHubGui = nil  -- Referência para o menu principal
local aimConfigGui = nil  -- GUI para configuração do AimLock
local aimLockTargets = {}  -- Alvos disponíveis para AimLock
local aimLockFOV = 500  -- Campo de visão do AimLock
local aimLockPriority = "Nearest"  -- Prioridade: Nearest, LowestHealth, HighestHealth
local camera = Workspace.CurrentCamera

-- Funções utilitárias
local function safeCreate(className, properties)
    local success, obj = pcall(function()
        local instance = Instance.new(className)
        for prop, value in pairs(properties) do
            instance[prop] = value
        end
        return instance
    end)
    return success and obj or nil
end

local function safeDestroy(obj)
    if obj and obj.Parent then
        pcall(function() obj:Destroy() end)
    end
end

-- Função para encontrar o melhor alvo para AimLock
local function findAimLockTarget()
    if not localPlayer.Character then return nil end
    local myPosition = localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myPosition then return nil end
    myPosition = myPosition.Position
    
    local bestTarget = nil
    local bestDistance = math.huge
    local bestHealth = math.huge
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character and player.Character:FindFirstChild("Humanoid") then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local targetPart = player.Character:FindFirstChild("HumanoidRootPart") or 
                                  player.Character:FindFirstChild("Head") or
                                  player.Character:FindFirstChild("UpperTorso")
                
                if targetPart then
                    -- Verificar se está dentro do FOV
                    local screenPoint = camera:WorldToViewportPoint(targetPart.Position)
                    local viewportSize = camera.ViewportSize
                    local distanceFromCenter = (Vector2.new(screenPoint.X, screenPoint.Y) - viewportSize / 2).Magnitude
                    
                    if screenPoint.Z > 0 and distanceFromCenter < aimLockFOV then
                        local distance = (myPosition - targetPart.Position).Magnitude
                        local health = humanoid.Health
                        
                        if aimLockPriority == "Nearest" then
                            if distance < bestDistance then
                                bestDistance = distance
                                bestTarget = player
                            end
                        elseif aimLockPriority == "LowestHealth" then
                            if health < bestHealth then
                                bestHealth = health
                                bestTarget = player
                            end
                        elseif aimLockPriority == "HighestHealth" then
                            if health > bestHealth then
                                bestHealth = health
                                bestTarget = player
                            end
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget
end

-- Função para aplicar AimLock
local function applyAimLock()
    if not AIMLOCK_ENABLED then return end
    if not aimLockTarget or not aimLockTarget.Character then return end
    
    local targetPart = aimLockTarget.Character:FindFirstChild(aimLockTargetPart) or
                      aimLockTarget.Character:FindFirstChild("HumanoidRootPart") or
                      aimLockTarget.Character:FindFirstChild("Head") or
                      aimLockTarget.Character:FindFirstChild("UpperTorso")
    
    if not targetPart then return end
    if not localPlayer.Character then return end
    
    local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Calcular direção para o alvo
    local targetPosition = targetPart.Position
    local myPosition = localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myPosition then return end
    myPosition = myPosition.Position
    
    local direction = (targetPosition - myPosition).Unit
    
    if AIMLOCK_USE_CAMERA then
        -- Usar câmera para mirar
        local currentCF = camera.CFrame
        local lookVector = currentCF.LookVector
        
        -- Interpolar suavemente para a direção do alvo
        local newLookVector = lookVector:Lerp(direction, AIMLOCK_SMOOTHNESS)
        local newCF = CFrame.new(currentCF.Position, currentCF.Position + newLookVector)
        camera.CFrame = newCF
    else
        -- Usar mouse para mirar (para jogos que usam mouse)
        local mouse = localPlayer:GetMouse()
        if mouse then
            -- Converter direção para posição na tela
            local screenPoint = camera:WorldToScreenPoint(targetPosition)
            if screenPoint.Z > 0 then
                mousemoverel(screenPoint.X - mouse.X, screenPoint.Y - mouse.Y)
            end
        end
    end
end

-- Função para criar indicador visual do AimLock
local function createAimLockIndicator(target)
    if not target or not target.Character then return nil end
    
    local indicator = safeCreate("BillboardGui", {
        Name = "AimLockIndicator",
        Size = UDim2.new(0, 100, 0, 100),
        StudsOffset = Vector3.new(0, 3, 0),
        AlwaysOnTop = true,
        MaxDistance = 1000,
        Parent = playerGui
    })
    
    local frame = safeCreate("Frame", {
        Name = "IndicatorFrame",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = indicator
    })
    
    -- Círculo vermelho
    local circle = safeCreate("ImageLabel", {
        Name = "Circle",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Image = "rbxassetid://3570695787",
        ImageColor3 = Color3.fromRGB(255, 50, 50),
        ScaleType = Enum.ScaleType.Fit,
        Parent = frame
    })
    
    -- Texto com nome do alvo
    local nameLabel = safeCreate("TextLabel", {
        Name = "NameLabel",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 1.1, 0),
        BackgroundTransparency = 1,
        Text = target.Name,
        TextColor3 = Color3.fromRGB(255, 100, 100),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = frame
    })
    
    -- Atualizar posição
    local updateConnection = RunService.RenderStepped:Connect(function()
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            indicator.Adornee = target.Character.HumanoidRootPart
            
            -- Verificar saúde
            local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local healthPercent = humanoid.Health / humanoid.MaxHealth
                if healthPercent < 0.3 then
                    circle.ImageColor3 = Color3.fromRGB(255, 0, 0)  -- Vermelho para baixa vida
                elseif healthPercent < 0.6 then
                    circle.ImageColor3 = Color3.fromRGB(255, 165, 0)  -- Laranja
                else
                    circle.ImageColor3 = Color3.fromRGB(255, 50, 50)  -- Vermelho claro
                end
                
                nameLabel.Text = string.format("%s (%d/%d HP)", target.Name, math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
            end
        else
            updateConnection:Disconnect()
            safeDestroy(indicator)
        end
    end)
    
    return indicator
end

-- Ativar/Desativar AimLock
local function toggleAimLock(enabled)
    AIMLOCK_ENABLED = enabled
    
    if enabled then
        -- Encontrar alvo inicial
        aimLockTarget = findAimLockTarget()
        
        if aimLockTarget then
            -- Criar indicador visual
            local indicator = createAimLockIndicator(aimLockTarget)
            
            -- Iniciar loop do AimLock
            aimLockConn = RunService.RenderStepped:Connect(function()
                if AIMLOCK_ENABLED and aimLockTarget and aimLockTarget.Character then
                    -- Verificar se o alvo ainda é válido
                    local humanoid = aimLockTarget.Character:FindFirstChildOfClass("Humanoid")
                    if not humanoid or humanoid.Health <= 0 then
                        -- Encontrar novo alvo
                        aimLockTarget = findAimLockTarget()
                        if aimLockTarget then
                            safeDestroy(indicator)
                            indicator = createAimLockIndicator(aimLockTarget)
                        end
                    else
                        applyAimLock()
                    end
                else
                    -- Tentar encontrar novo alvo
                    aimLockTarget = findAimLockTarget()
                    if aimLockTarget and not indicator then
                        indicator = createAimLockIndicator(aimLockTarget)
                    end
                end
            end)
            
            print("[AimLock] Alvo travado: " .. aimLockTarget.Name)
        else
            print("[AimLock] Nenhum alvo encontrado no FOV")
        end
    else
        if aimLockConn then
            aimLockConn:Disconnect()
            aimLockConn = nil
        end
        
        aimLockTarget = nil
        
        -- Remover todos os indicadores
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui.Name == "AimLockIndicator" then
                safeDestroy(gui)
            end
        end
        
        print("[AimLock] Desativado")
    end
end

-- Função para criar interface de configuração do AimLock
local function createAimConfigGui()
    if aimConfigGui then
        safeDestroy(aimConfigGui)
    end
    
    local screenGui = safeCreate("ScreenGui", {
        Name = "AimConfig_GUI",
        ResetOnSpawn = false,
        DisplayOrder = 10001,
        Parent = playerGui
    })
    
    local mainFrame = safeCreate("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0, 320, 0, 300),
        Position = UDim2.new(0.5, -160, 0.5, -150),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(25, 25, 35),
        BorderSizePixel = 0,
        Parent = screenGui
    })
    
    local corner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = mainFrame
    })
    
    -- Barra de título
    local titleBar = safeCreate("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local titleBarCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12, 0, 0),
        Parent = titleBar
    })
    
    -- Botão de fechar
    local closeBtn = safeCreate("TextButton", {
        Name = "CloseBtn",
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, -35, 0, 5),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "X",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 16,
        Parent = titleBar
    })
    
    local closeCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 15),
        Parent = closeBtn
    })
    
    -- Título
    local title = safeCreate("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = "CONFIGURAR AIMLOCK",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar
    })
    
    -- Configurações
    local settingsY = 50
    
    -- Suavidade
    local smoothLabel = safeCreate("TextLabel", {
        Name = "SmoothLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY),
        BackgroundTransparency = 1,
        Text = "Suavidade: " .. string.format("%.2f", AIMLOCK_SMOOTHNESS),
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local smoothSlider = safeCreate("Frame", {
        Name = "SmoothSlider",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0, 10, 0, settingsY + 25),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local smoothCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = smoothSlider
    })
    
    local smoothFill = safeCreate("Frame", {
        Name = "SmoothFill",
        Size = UDim2.new(AIMLOCK_SMOOTHNESS, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        BorderSizePixel = 0,
        Parent = smoothSlider
    })
    
    local smoothCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = smoothFill
    })
    
    -- FOV
    local fovLabel = safeCreate("TextLabel", {
        Name = "FOVLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY + 55),
        BackgroundTransparency = 1,
        Text = "Campo de Visão: " .. aimLockFOV .. "px",
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local fovSlider = safeCreate("Frame", {
        Name = "FOVSlider",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0, 10, 0, settingsY + 80),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local fovCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = fovSlider
    })
    
    local fovFill = safeCreate("Frame", {
        Name = "FOVFill",
        Size = UDim2.new((aimLockFOV - 100) / 900, 0, 1, 0),  -- 100 a 1000
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        BorderSizePixel = 0,
        Parent = fovSlider
    })
    
    local fovCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = fovFill
    })
    
    -- Parte do corpo
    local partLabel = safeCreate("TextLabel", {
        Name = "PartLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY + 110),
        BackgroundTransparency = 1,
        Text = "Parte do Corpo: " .. aimLockTargetPart,
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local partButtons = {
        {text = "Cabeça", value = "Head", x = 10},
        {text = "Torso", value = "UpperTorso", x = 90},
        {text = "Raiz", value = "HumanoidRootPart", x = 170}
    }
    
    for _, btn in ipairs(partButtons) do
        local partBtn = safeCreate("TextButton", {
            Name = "PartBtn_" .. btn.value,
            Size = UDim2.new(0, 70, 0, 30),
            Position = UDim2.new(0, btn.x, 0, settingsY + 135),
            BackgroundColor3 = aimLockTargetPart == btn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80),
            Text = btn.text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSans,
            TextSize = 12,
            Parent = mainFrame
        })
        
        local partBtnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = partBtn
        })
        
        partBtn.MouseButton1Click:Connect(function()
            aimLockTargetPart = btn.value
            partLabel.Text = "Parte do Corpo: " .. aimLockTargetPart
            
            -- Atualizar cores dos botões
            for _, otherBtn in ipairs(partButtons) do
                local otherPartBtn = mainFrame:FindFirstChild("PartBtn_" .. otherBtn.value)
                if otherPartBtn then
                    otherPartBtn.BackgroundColor3 = aimLockTargetPart == otherBtn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80)
                end
            end
        end)
    end
    
    -- Prioridade
    local priorityLabel = safeCreate("TextLabel", {
        Name = "PriorityLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY + 175),
        BackgroundTransparency = 1,
        Text = "Prioridade: " .. aimLockPriority,
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local priorityButtons = {
        {text = "Mais Próximo", value = "Nearest", x = 10},
        {text = "Menos Vida", value = "LowestHealth", x = 110},
        {text = "Mais Vida", value = "HighestHealth", x = 210}
    }
    
    for _, btn in ipairs(priorityButtons) do
        local priorityBtn = safeCreate("TextButton", {
            Name = "PriorityBtn_" .. btn.value,
            Size = UDim2.new(0, 90, 0, 30),
            Position = UDim2.new(0, btn.x, 0, settingsY + 200),
            BackgroundColor3 = aimLockPriority == btn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80),
            Text = btn.text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSans,
            TextSize = 12,
            Parent = mainFrame
        })
        
        local priorityBtnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = priorityBtn
        })
        
        priorityBtn.MouseButton1Click:Connect(function()
            aimLockPriority = btn.value
            priorityLabel.Text = "Prioridade: " .. aimLockPriority
            
            -- Atualizar cores dos botões
            for _, otherBtn in ipairs(priorityButtons) do
                local otherPriorityBtn = mainFrame:FindFirstChild("PriorityBtn_" .. otherBtn.value)
                if otherPriorityBtn then
                    otherPriorityBtn.BackgroundColor3 = aimLockPriority == otherBtn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80)
                end
            end
        end)
    end
    
    -- Botões de controle
    local controlFrame = safeCreate("Frame", {
        Name = "ControlFrame",
        Size = UDim2.new(1, -20, 0, 40),
        Position = UDim2.new(0, 10, 1, -50),
        BackgroundTransparency = 1,
        Parent = mainFrame
    })
    
    -- Botão Aplicar
    local applyBtn = safeCreate("TextButton", {
        Name = "ApplyBtn",
        Size = UDim2.new(0.48, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(60, 150, 255),
        Text = "APLICAR",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = controlFrame
    })
    
    local applyCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = applyBtn
    })
    
    -- Botão Testar
    local testBtn = safeCreate("TextButton", {
        Name = "TestBtn",
        Size = UDim2.new(0.48, 0, 1, 0),
        Position = UDim2.new(0.52, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(255, 150, 0),
        Text = "TESTAR",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = controlFrame
    })
    
    local testCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = testBtn
    })
    
    -- Funções de interação com sliders
    local function updateSmoothSlider(value)
        AIMLOCK_SMOOTHNESS = math.clamp(value, 0.01, 1.0)
        smoothLabel.Text = "Suavidade: " .. string.format("%.2f", AIMLOCK_SMOOTHNESS)
        smoothFill.Size = UDim2.new(AIMLOCK_SMOOTHNESS, 0, 1, 0)
    end
    
    local function updateFOVSlider(value)
        aimLockFOV = math.clamp(value, 100, 1000)
        fovLabel.Text = "Campo de Visão: " .. aimLockFOV .. "px"
        fovFill.Size = UDim2.new((aimLockFOV - 100) / 900, 0, 1, 0)
    end
    
    -- Configurar arrasto dos sliders
    local function setupSlider(slider, fill, label, updateFunc, min, max)
        local dragging = false
        
        slider.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
            end
        end)
        
        slider.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local mousePos = input.Position
                local sliderPos = slider.AbsolutePosition
                local sliderSize = slider.AbsoluteSize
                
                local relativeX = (mousePos.X - sliderPos.X) / sliderSize.X
                relativeX = math.clamp(relativeX, 0, 1)
                
                local value = min + (relativeX * (max - min))
                updateFunc(value)
            end
        end)
    end
    
    setupSlider(smoothSlider, smoothFill, smoothLabel, updateSmoothSlider, 0.01, 1.0)
    setupSlider(fovSlider, fovFill, fovLabel, updateFOVSlider, 100, 1000)
    
    -- Botões de incremento/decremento
    local function createControlButtons(slider, updateFunc, step, min, max)
        local minusBtn = safeCreate("TextButton", {
            Name = "MinusBtn",
            Size = UDim2.new(0, 25, 0, 25),
            Position = UDim2.new(1, 5, 0.5, -12.5),
            BackgroundColor3 = Color3.fromRGB(200, 60, 60),
            Text = "-",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 18,
            Parent = slider
        })
        
        local plusBtn = safeCreate("TextButton", {
            Name = "PlusBtn",
            Size = UDim2.new(0, 25, 0, 25),
            Position = UDim2.new(1, 35, 0.5, -12.5),
            BackgroundColor3 = Color3.fromRGB(60, 200, 60),
            Text = "+",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 18,
            Parent = slider
        })
        
        local btnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 12),
            Parent = minusBtn
        })
        
        local btnCorner2 = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 12),
            Parent = plusBtn
        })
        
        minusBtn.MouseButton1Click:Connect(function()
            local currentValue = slider == smoothSlider and AIMLOCK_SMOOTHNESS or aimLockFOV
            local newValue = currentValue - step
            if newValue >= min then
                updateFunc(newValue)
            end
        end)
        
        plusBtn.MouseButton1Click:Connect(function()
            local currentValue = slider == smoothSlider and AIMLOCK_SMOOTHNESS or aimLockFOV
            local newValue = currentValue + step
            if newValue <= max then
                updateFunc(newValue)
            end
        end)
    end
    
    createControlButtons(smoothSlider, updateSmoothSlider, 0.05, 0.01, 1.0)
    createControlButtons(fovSlider, updateFOVSlider, 50, 100, 1000)
    
    -- Funções dos botões principais
    closeBtn.MouseButton1Click:Connect(function()
        safeDestroy(screenGui)
        aimConfigGui = nil
        
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    applyBtn.MouseButton1Click:Connect(function()
        -- Reaplicar AimLock se estiver ativo
        if AIMLOCK_ENABLED then
            toggleAimLock(false)
            wait(0.1)
            toggleAimLock(true)
        end
        
        safeDestroy(screenGui)
        aimConfigGui = nil
        
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    testBtn.MouseButton1Click:Connect(function()
        -- Testar o AimLock
        if not AIMLOCK_ENABLED then
            local wasEnabled = AIMLOCK_ENABLED
            toggleAimLock(true)
            wait(2)
            if not wasEnabled then
                toggleAimLock(false)
            end
        end
    end)
    
    aimConfigGui = screenGui
    return screenGui
end

-- Função para criar interface de configuração de velocidade
local function createSpeedConfigGui()
    if speedConfigGui then
        safeDestroy(speedConfigGui)
    end
    
    local screenGui = safeCreate("ScreenGui", {
        Name = "SpeedConfig_GUI",
        ResetOnSpawn = false,
        DisplayOrder = 10000,
        Parent = playerGui
    })
    
    local mainFrame = safeCreate("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0, 320, 0, 220),
        Position = UDim2.new(0.5, -160, 0.5, -110),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(25, 25, 35),
        BorderSizePixel = 0,
        Parent = screenGui
    })
    
    local corner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = mainFrame
    })
    
    -- Barra de título com botão fechar
    local titleBar = safeCreate("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(45, 45, 60),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local titleBarCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12, 0, 0),
        Parent = titleBar
    })
    
    -- Botão de fechar
    local closeBtn = safeCreate("TextButton", {
        Name = "CloseBtn",
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, -35, 0, 5),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "X",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 16,
        Parent = titleBar
    })
    
    local closeCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 15),
        Parent = closeBtn
    })
    
    -- Título
    local title = safeCreate("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = "CONFIGURAR SPEED BOOST",
        TextColor3 = Color3.fromRGB(255, 150, 0),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar
    })
    
    -- Velocidade
    local speedLabel = safeCreate("TextLabel", {
        Name = "SpeedLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, 50),
        BackgroundTransparency = 1,
        Text = "Multiplicador de Velocidade:",
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local speedValue = safeCreate("TextLabel", {
        Name = "SpeedValue",
        Size = UDim2.new(0, 60, 0, 30),
        Position = UDim2.new(1, -70, 0, 48),
        BackgroundColor3 = Color3.fromRGB(40, 40, 60),
        Text = tostring(speedBoostMultiplier) .. "x",
        TextColor3 = Color3.fromRGB(255, 200, 100),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        Parent = mainFrame
    })
    
    local speedCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = speedValue
    })
    
    -- Slider para velocidade
    local sliderFrame = safeCreate("Frame", {
        Name = "SliderFrame",
        Size = UDim2.new(0, 260, 0, 30),
        Position = UDim2.new(0.5, -130, 0, 85),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local sliderCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = sliderFrame
    })
    
    local sliderFill = safeCreate("Frame", {
        Name = "SliderFill",
        Size = UDim2.new((speedBoostMultiplier - 1) / 9, 0, 1, 0),  -- 1x a 10x
        BackgroundColor3 = Color3.fromRGB(255, 150, 0),
        BorderSizePixel = 0,
        Parent = sliderFrame
    })
    
    local sliderCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = sliderFill
    })
    
    -- Botões de ajuste rápido
    local quickButtons = {
        {text = "2x", value = 2, color = Color3.fromRGB(100, 200, 100)},
        {text = "5x", value = 5, color = Color3.fromRGB(255, 150, 0)},
        {text = "10x", value = 10, color = Color3.fromRGB(255, 100, 100)},
        {text = "15x", value = 15, color = Color3.fromRGB(200, 100, 255)}
    }
    
    local buttonFrame = safeCreate("Frame", {
        Name = "ButtonFrame",
        Size = UDim2.new(1, -20, 0, 40),
        Position = UDim2.new(0, 10, 0, 120),
        BackgroundTransparency = 1,
        Parent = mainFrame
    })
    
    for i, btn in ipairs(quickButtons) do
        local quickBtn = safeCreate("TextButton", {
            Name = "QuickBtn_" .. btn.text,
            Size = UDim2.new(0.23, 0, 1, 0),
            Position = UDim2.new(0.25 * (i-1), 0, 0, 0),
            BackgroundColor3 = btn.color,
            Text = btn.text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 14,
            Parent = buttonFrame
        })
        
        local btnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = quickBtn
        })
        
        quickBtn.MouseButton1Click:Connect(function()
            speedBoostMultiplier = btn.value
            speedValue.Text = tostring(speedBoostMultiplier) .. "x"
            sliderFill.Size = UDim2.new((speedBoostMultiplier - 1) / 14, 0, 1, 0)
        end)
    end
    
    -- Botões de controle do slider
    local minusBtn = safeCreate("TextButton", {
        Name = "MinusBtn",
        Size = UDim2.new(0, 35, 0, 35),
        Position = UDim2.new(0, -40, 0, 83),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "−",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 22,
        Parent = mainFrame
    })
    
    local plusBtn = safeCreate("TextButton", {
        Name = "PlusBtn",
        Size = UDim2.new(0, 35, 0, 35),
        Position = UDim2.new(1, 5, 0, 83),
        BackgroundColor3 = Color3.fromRGB(60, 200, 60),
        Text = "+",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 22,
        Parent = mainFrame
    })
    
    local btnCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 17),
        Parent = minusBtn
    })
    
    local btnCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 17),
        Parent = plusBtn
    })
    
    -- Status info
    local statusInfo = safeCreate("TextLabel", {
        Name = "StatusInfo",
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 0, 165),
        BackgroundTransparency = 1,
        Text = "Velocidade atual: " .. tostring(speedBoostMultiplier) .. "x",
        TextColor3 = Color3.fromRGB(150, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    -- Funções dos botões
    local function updateSlider()
        speedValue.Text = tostring(speedBoostMultiplier) .. "x"
        sliderFill.Size = UDim2.new((speedBoostMultiplier - 1) / 14, 0, 1, 0)
        statusInfo.Text = "Velocidade atual: " .. tostring(speedBoostMultiplier) .. "x"
    end
    
    minusBtn.MouseButton1Click:Connect(function()
        if speedBoostMultiplier > 1 then
            speedBoostMultiplier = speedBoostMultiplier - 0.5
            if speedBoostMultiplier < 1 then speedBoostMultiplier = 1 end
            updateSlider()
        end
    end)
    
    plusBtn.MouseButton1Click:Connect(function()
        if speedBoostMultiplier < 15 then
            speedBoostMultiplier = speedBoostMultiplier + 0.5
            if speedBoostMultiplier > 15 then speedBoostMultiplier = 15 end
            updateSlider()
        end
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        safeDestroy(screenGui)
        speedConfigGui = nil
        
        -- Reabrir o menu principal
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    -- Permitir arrastar o slider
    local dragging = false
    
    sliderFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    
    sliderFrame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInput.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = input.Position
            local sliderPos = sliderFrame.AbsolutePosition
            local sliderSize = sliderFrame.AbsoluteSize
            
            local relativeX = (mousePos.X - sliderPos.X) / sliderSize.X
            relativeX = math.clamp(relativeX, 0, 1)
            
            speedBoostMultiplier = 1 + (relativeX * 14)  -- 1 a 15
            speedBoostMultiplier = math.floor(speedBoostMultiplier * 2) / 2  -- Arredondar para múltiplos de 0.5
            
            updateSlider()
        end
    end)
    
    -- Botão Aplicar
    local applyBtn = safeCreate("TextButton", {
        Name = "ApplyBtn",
        Size = UDim2.new(0.85, 0, 0, 40),
        Position = UDim2.new(0.5, -127, 0, 190),
        BackgroundColor3 = Color3.fromRGB(60, 150, 255),
        Text = "APLICAR CONFIGURAÇÃO",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = mainFrame
    })
    
    local applyCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = applyBtn
    })
    
    applyBtn.MouseButton1Click:Connect(function()
        -- Aplicar configuração
        if SPEED_BOOST then
            toggleSpeedBoost(false)
            wait(0.1)
            toggleSpeedBoost(true)
        end
        
        -- Atualizar botão no menu principal se existir
        if mainHubGui then
            local configBtn = mainHubGui:FindFirstChild("ConfigSpeedBtn", true)
            if configBtn then
                configBtn.Text = "CONFIGURAR SPEED BOOST (" .. speedBoostMultiplier .. "x)"
            end
        end
        
        safeDestroy(screenGui)
        speedConfigGui = nil
        
        -- Reabrir o menu principal
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    -- Fechar com ESC também
    local escConnection
    escConnection = UserInput.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Escape then
            safeDestroy(screenGui)
            speedConfigGui = nil
            if escConnection then
                escConnection:Disconnect()
            end
            
            -- Reabrir o menu principal
            if mainHubGui then
                mainHubGui.Enabled = true
            end
        end
    end)
    
    speedConfigGui = screenGui
    return screenGui
end

-- Função Speed Boost (atualizada para usar multiplicador personalizado)
local function applySpeedBoost(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Salvar velocidade original se não salvar ainda
    if originalWalkSpeed == 16 then
        originalWalkSpeed = humanoid.WalkSpeed
        originalJumpPower = humanoid.JumpPower or 50
    end
    
    -- Aplicar boost com multiplicador personalizado
    humanoid.WalkSpeed = originalWalkSpeed * speedBoostMultiplier
    humanoid.JumpPower = originalJumpPower * (1 + (speedBoostMultiplier - 1) * 0.3)
    
    -- Efeito visual baseado na velocidade
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        -- Remover efeitos antigos
        local oldParticles = rootPart:FindFirstChild("SpeedBoostParticles")
        if oldParticles then
            oldParticles:Destroy()
        end
        
        local oldLight = rootPart:FindFirstChild("SpeedBoostLight")
        if oldLight then
            oldLight:Destroy()
        end
        
        -- Criar partículas de velocidade
        local particles = Instance.new("ParticleEmitter")
        particles.Name = "SpeedBoostParticles"
        particles.Parent = rootPart
        particles.Color = ColorSequence.new(Color3.fromRGB(0, 255, 255))
        particles.Lifetime = NumberRange.new(0.5)
        particles.Rate = 30 * (speedBoostMultiplier / 3)
        particles.Rotation = NumberRange.new(0, 360)
        particles.RotSpeed = NumberRange.new(-100, 100)
        particles.Speed = NumberRange.new(2 * (speedBoostMultiplier / 3))
        particles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5 * (speedBoostMultiplier / 3)),
            NumberSequenceKeypoint.new(1, 0)
        })
        particles.Texture = "rbxassetid://242842396"
        particles.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        })
        particles.VelocityInheritance = 0.8
        particles.ZOffset = 2
        
        -- Criar luz
        local light = Instance.new("PointLight")
        light.Name = "SpeedBoostLight"
        light.Parent = rootPart
        light.Color = Color3.fromRGB(0, 200, 255)
        light.Brightness = 1.5 * (speedBoostMultiplier / 3)
        light.Range = 10 * (speedBoostMultiplier / 3)
        light.Shadows = false
    end
end

local function removeSpeedBoost(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Restaurar velocidade original
    humanoid.WalkSpeed = originalWalkSpeed
    humanoid.JumpPower = originalJumpPower
    
    -- Remover efeitos visuais
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local particles = rootPart:FindFirstChild("SpeedBoostParticles")
        if particles then
            particles:Destroy()
        end
        
        local light = rootPart:FindFirstChild("SpeedBoostLight")
        if light then
            light:Destroy()
        end
    end
end

local function toggleSpeedBoost(enabled)
    SPEED_BOOST = enabled
    
    if enabled then
        -- Aplicar ao personagem atual
        local character = localPlayer.Character
        if character then
            applySpeedBoost(character)
        end
        
        -- Conectar para personagens futuros
        if speedBoostConn then
            speedBoostConn:Disconnect()
        end
        
        speedBoostConn = localPlayer.CharacterAdded:Connect(function(char)
            wait(0.2)
            if SPEED_BOOST then
                applySpeedBoost(char)
            end
        end)
        
        -- Verificar periodicamente
        RunService.Heartbeat:Connect(function()
            if SPEED_BOOST then
                local character = localPlayer.Character
                if character then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.WalkSpeed ~= originalWalkSpeed * speedBoostMultiplier then
                        applySpeedBoost(character)
                    end
                end
            end
        end)
    else
        -- Remover do personagem atual
        local character = localPlayer.Character
        if character then
            removeSpeedBoost(character)
        end
        
        if speedBoostConn then
            speedBoostConn:Disconnect()
            speedBoostConn = nil
        end
    end
end

-- Criar piso abaixo do jogador ao pular
local function createJumpPlatform()
    if not JUMP_PLATFORM then return end
    
    local character = localPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Verificar cooldown
    local currentTime = tick()
    if currentTime - lastJumpTime < JUMP_COOLDOWN then
        return
    end
    lastJumpTime = currentTime
    
    -- Calcular posição do piso (5 unidades abaixo do personagem)
    local platformPosition = hrp.Position - Vector3.new(0, 5, 0)
    
    -- Criar piso
    local platform = Instance.new("Part")
    platform.Name = "JumpPlatform_" .. tick()
    platform.Size = Vector3.new(10, 1, 10)
    platform.Position = platformPosition
    platform.Anchored = true
    platform.CanCollide = true
    platform.Transparency = 0.3
    platform.Material = Enum.Material.Neon
    platform.Color = Color3.fromRGB(0, 255, 255)
    
    -- Adicionar brilho
    local glow = Instance.new("SurfaceLight")
    glow.Name = "PlatformGlow"
    glow.Brightness = 2
    glow.Range = 10
    glow.Color = Color3.fromRGB(0, 200, 255)
    glow.Parent = platform
    
    -- Adicionar outline
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Name = "PlatformOutline"
    selectionBox.Adornee = platform
    selectionBox.Color3 = Color3.fromRGB(255, 255, 255)
    selectionBox.LineThickness = 0.05
    selectionBox.Transparency = 0.5
    selectionBox.Parent = platform
    
    platform.Parent = Workspace
    
    -- Armazenar para limpeza posterior
    table.insert(platformParts, {
        part = platform,
        creationTime = tick()
    })
    
    -- Efeito de surgimento (animação)
    local originalSize = platform.Size
    platform.Size = Vector3.new(0.1, 0.1, 0.1)
    
    local tweenInfo = TweenInfo.new(
        0.3,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tween = TweenService:Create(platform, tweenInfo, {Size = originalSize})
    tween:Play()
    
    -- Efeito de piscar
    local blinkTween = TweenService:Create(platform, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Transparency = 0.7
    })
    blinkTween:Play()
    
    -- Configurar para destruir após 4 segundos
    delay(PLATFORM_DURATION, function()
        if platform and platform.Parent then
            -- Efeito de desaparecimento
            local disappearTween = TweenService:Create(platform, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
                Size = Vector3.new(0.1, 0.1, 0.1)
            })
            disappearTween:Play()
            
            wait(0.5)
            safeDestroy(platform)
            
            -- Remover da tabela
            for i, platData in ipairs(platformParts) do
                if platData.part == platform then
                    table.remove(platformParts, i)
                    break
                end
            end
        end
    end)
    
    return platform
end

-- Limpar todos os pisos criados
local function clearAllPlatforms()
    for _, platData in ipairs(platformParts) do
        if platData.part and platData.part.Parent then
            safeDestroy(platData.part)
        end
    end
    platformParts = {}
end

-- Ativar/desativar função de piso ao pular
local function toggleJumpPlatform(enabled)
    JUMP_PLATFORM = enabled
    
    if enabled then
        -- Conectar aos eventos de pulo
        jumpPlatformConnection = UserInput.JumpRequest:Connect(function()
            createJumpPlatform()
        end)
        
        -- Também conectar ao InputBegan para tecla Espaço
        if not infiniteJumpConnection then
            UserInput.InputBegan:Connect(function(input)
                if input.KeyCode == Enum.KeyCode.Space and JUMP_PLATFORM then
                    createJumpPlatform()
                end
            end)
        end
    else
        if jumpPlatformConnection then
            jumpPlatformConnection:Disconnect()
            jumpPlatformConnection = nil
        end
    end
end

-- ShiftLock helpers
local function applyShiftLockToCharacter(char)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if not shiftLockOrigSpeed[char] then
        shiftLockOrigSpeed[char] = humanoid.WalkSpeed or DEFAULT_WALK_SPEED
    end

    humanoid.WalkSpeed = SHIFT_WALK_SPEED
end

local function removeShiftLockFromCharacter(char)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if shiftLockOrigSpeed[char] then
        humanoid.WalkSpeed = shiftLockOrigSpeed[char]
        shiftLockOrigSpeed[char] = nil
    else
        humanoid.WalkSpeed = DEFAULT_WALK_SPEED
    end
end

local function toggleShiftLock(enabled)
    SHIFT_LOCK = enabled

    if shiftLockConn then
        shiftLockConn:Disconnect()
        shiftLockConn = nil
    end
    if shiftLockCharacterConn then
        shiftLockCharacterConn:Disconnect()
        shiftLockCharacterConn = nil
    end

    if enabled then
        if localPlayer.Character then
            applyShiftLockToCharacter(localPlayer.Character)
        end

        shiftLockConn = RunService.Heartbeat:Connect(function()
            local char = localPlayer.Character
            if char and SHIFT_LOCK then
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.WalkSpeed ~= SHIFT_WALK_SPEED then
                    humanoid.WalkSpeed = SHIFT_WALK_SPEED
                end
            end
        end)

        shiftLockCharacterConn = localPlayer.CharacterAdded:Connect(function(char)
            wait(0.1)
            if SHIFT_LOCK then
                applyShiftLockToCharacter(char)
            end
        end)
    else
        if localPlayer.Character then
            removeShiftLockFromCharacter(localPlayer.Character)
        end
    end
end

-- Criar Hitbox ESP (caixas ao redor do personagem)
local function createHitboxESP(player, character)
    if not character or not character.Parent then return end
    if player == localPlayer then return end

    local hitboxFolder = Instance.new("Folder")
    hitboxFolder.Name = "HitboxESP_" .. player.UserId
    hitboxFolder.Parent = Workspace

    -- Criar caixas para partes principais do corpo
    local bodyParts = {
        {name = "Head", size = Vector3.new(2, 2, 2), color = Color3.fromRGB(255, 0, 0)},
        {name = "UpperTorso", size = Vector3.new(2, 1.5, 1), color = Color3.fromRGB(0, 255, 0)},
        {name = "LowerTorso", size = Vector3.new(2, 1, 1), color = Color3.fromRGB(0, 200, 200)},
        {name = "HumanoidRootPart", size = Vector3.new(2, 2, 2), color = Color3.fromRGB(255, 255, 0)}
    }

    local hitboxes = {}

    for _, partInfo in pairs(bodyParts) do
        local bodyPart = character:FindFirstChild(partInfo.name)
        if bodyPart then
            local hitbox = safeCreate("BoxHandleAdornment", {
                Name = "Hitbox_" .. partInfo.name,
                Adornee = bodyPart,
                Size = partInfo.size,
                Color3 = partInfo.color,
                Transparency = 0.3,
                ZIndex = 10,
                AlwaysOnTop = true,
                Visible = true,
                Parent = hitboxFolder
            })

            table.insert(hitboxes, {part = bodyPart, hitbox = hitbox})
        end
    end

    -- Criar caixa de bounding box ao redor de todo o personagem
    local boundingBox = safeCreate("BoxHandleAdornment", {
        Name = "BoundingBox",
        Adornee = character,
        Size = Vector3.new(4, 6, 4),
        Color3 = Color3.fromRGB(255, 100, 255),
        Transparency = 0.7,
        ZIndex = 5,
        AlwaysOnTop = true,
        Visible = true,
        Parent = hitboxFolder
    })

    -- Atualizar posições das hitboxes
    local updateConnection = RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then
            updateConnection:Disconnect()
            safeDestroy(hitboxFolder)
            return
        end

        -- Atualizar bounding box para envolver todo o personagem
        if boundingBox then
            pcall(function()
                boundingBox.Adornee = character
            end)
        end

        -- Atualizar hitboxes individuais
        for _, hitboxData in pairs(hitboxes) do
            if hitboxData.hitbox and hitboxData.part then
                pcall(function()
                    hitboxData.hitbox.Adornee = hitboxData.part
                end)
            end
        end
    end)

    -- Armazenar dados
    espData[player.UserId] = espData[player.UserId] or {}
    espData[player.UserId].hitboxFolder = hitboxFolder
    espData[player.UserId].hitboxUpdate = updateConnection

    return hitboxFolder
end

-- Criar ESP normal (Highlight + Billboard)
local function createESPForCharacter(player, character)
    if not character or not character.Parent then return end
    if player == localPlayer then return end

    local userId = player.UserId

    -- Limpar ESP antigo
    if espData[userId] then
        if espData[userId].highlight then safeDestroy(espData[userId].highlight) end
        if espData[userId].billboard then safeDestroy(espData[userId].billboard) end
        if espData[userId].updateConnection then espData[userId].updateConnection:Disconnect() end
    end

    -- Criar Highlight
    local highlight = safeCreate("Highlight", {
        Name = "ESP_Highlight_" .. userId,
        Adornee = character,
        Enabled = true,
        FillColor = Color3.fromRGB(255, 50, 50),
        FillTransparency = 0.5,
        OutlineColor = Color3.fromRGB(255, 0, 0),
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Parent = Workspace
    })

    -- Criar Billboard
    local hrp = character:FindFirstChild("HumanoidRootPart") or
                character:FindFirstChild("UpperTorso") or
                character:FindFirstChild("Torso") or
                character:FindFirstChild("Head")

    local billboard = nil
    if hrp then
        billboard = safeCreate("BillboardGui", {
            Name = "ESP_Billboard_" .. userId,
            Adornee = hrp,
            Size = UDim2.new(0, 200, 0, 50),
            StudsOffset = Vector3.new(0, 3, 0),
            AlwaysOnTop = true,
            MaxDistance = 1000,
            Parent = playerGui
        })

        if billboard then
            -- Nome do jogador
            local nameLabel = safeCreate("TextLabel", {
                Name = "NameLabel",
                Size = UDim2.new(1, -10, 0.4, 0),
                Position = UDim2.new(0, 5, 0, 0),
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(255, 255, 255),
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.SourceSansBold,
                TextSize = 16,
                Text = player.Name,
                Parent = billboard
            })

            -- Distância e vida
            local infoLabel = safeCreate("TextLabel", {
                Name = "InfoLabel",
                Size = UDim2.new(1, -10, 0.3, 0),
                Position = UDim2.new(0, 5, 0.4, 0),
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(200, 200, 255),
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.SourceSans,
                TextSize = 14,
                Text = "0m | 100 HP",
                Parent = billboard
            })

            -- Tool (arma que está segurando)
            local toolLabel = safeCreate("TextLabel", {
                Name = "ToolLabel",
                Size = UDim2.new(1, -10, 0.3, 0),
                Position = UDim2.new(0, 5, 0.7, 0),
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(255, 200, 100),
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.SourceSans,
                TextSize = 12,
                Text = "Arma: Nenhuma",
                Parent = billboard
            })

            -- Atualizar informações
            local updateConnection = RunService.Heartbeat:Connect(function()
                if not character or not character.Parent then
                    updateConnection:Disconnect()
                    return
                end

                pcall(function()
                    if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local myPos = localPlayer.Character.HumanoidRootPart.Position
                        local theirPos = character:FindFirstChild("HumanoidRootPart") and
                                        character.HumanoidRootPart.Position or character.PrimaryPart.Position
                        local dist = (myPos - theirPos).Magnitude

                        local humanoid = character:FindFirstChildOfClass("Humanoid")
                        local health = humanoid and math.floor(humanoid.Health) or 100
                        local maxHealth = humanoid and math.floor(humanoid.MaxHealth) or 100

                        infoLabel.Text = string.format("[%.0fm] | %d/%d HP", dist, health, maxHealth)

                        local toolText = "Arma: Nenhuma"
                        for _, item in pairs(character:GetChildren()) do
                            if item:IsA("Tool") then
                                toolText = "Arma: " .. item.Name
                                break
                            end
                        end
                        toolLabel.Text = toolText

                        if humanoid then
                            local healthPercent = humanoid.Health / humanoid.MaxHealth
                            if healthPercent < 0.3 then
                                highlight.FillColor = Color3.fromRGB(255, 0, 0)
                            elseif healthPercent < 0.6 then
                                highlight.FillColor = Color3.fromRGB(255, 165, 0)
                            else
                                highlight.FillColor = Color3.fromRGB(0, 255, 0)
                            end
                        end
                    end
                end)
            end)

            espData[userId] = espData[userId] or {}
            espData[userId].updateConnection = updateConnection
        end
    end

    if HITBOX_ESP then
        createHitboxESP(player, character)
    end

    espData[userId] = espData[userId] or {}
    espData[userId].highlight = highlight
    espData[userId].billboard = billboard
    espData[userId].player = player
    espData[userId].character = character

    character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            if espData[userId] then
                if espData[userId].highlight then safeDestroy(espData[userId].highlight) end
                if espData[userId].billboard then safeDestroy(espData[userId].billboard) end
                if espData[userId].hitboxFolder then safeDestroy(espData[userId].hitboxFolder) end
                if espData[userId].updateConnection then espData[userId].updateConnection:Disconnect() end
                if espData[userId].hitboxUpdate then espData[userId].hitboxUpdate:Disconnect() end
                espData[userId] = nil
            end
        end
    end)
end

-- Remover ESP do jogador
local function removeESPForPlayer(player)
    local userId = player.UserId
    if espData[userId] then
        if espData[userId].highlight then safeDestroy(espData[userId].highlight) end
        if espData[userId].billboard then safeDestroy(espData[userId].billboard) end
        if espData[userId].hitboxFolder then safeDestroy(espData[userId].hitboxFolder) end
        if espData[userId].updateConnection then espData[userId].updateConnection:Disconnect() end
        if espData[userId].hitboxUpdate then espData[userId].hitboxUpdate:Disconnect() end
        espData[userId] = nil
    end
end

-- Ativar/Desativar Hitbox ESP para todos
local function toggleHitboxESP(enabled)
    HITBOX_ESP = enabled

    if enabled then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                createHitboxESP(player, player.Character)
            end
        end
    else
        for userId, data in pairs(espData) do
            if data.hitboxFolder then
                safeDestroy(data.hitboxFolder)
                data.hitboxFolder = nil
            end
            if data.hitboxUpdate then
                data.hitboxUpdate:Disconnect()
                data.hitboxUpdate = nil
            end
        end
    end
end

-- Reconstruir todos ESPs
local function rebuildAllESP()
    for userId, data in pairs(espData) do
        if data.highlight then safeDestroy(data.highlight) end
        if data.billboard then safeDestroy(data.billboard) end
        if data.hitboxFolder then safeDestroy(data.hitboxFolder) end
        if data.updateConnection then data.updateConnection:Disconnect() end
        if data.hitboxUpdate then data.hitboxUpdate:Disconnect() end
    end
    espData = {}

    if ESP_ENABLED then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                createESPForCharacter(player, player.Character)
            end
        end
    end
end

-- Configurar jogador para ESP
local function setupPlayer(player)
    if player == localPlayer then return end

    if player.Character and ESP_ENABLED then
        createESPForCharacter(player, player.Character)
    end

    player.CharacterAdded:Connect(function(char)
        wait(0.3)
        if ESP_ENABLED then
            createESPForCharacter(player, char)
        end
    end)

    player.CharacterRemoving:Connect(function()
        removeESPForPlayer(player)
    end)
end

-- Inicializar ESP
for _, player in pairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
    removeESPForPlayer(player)
end)

-- PULO INFINITO
local function doInfiniteJump()
    if not INFINITE_JUMP then return end

    local character = localPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    pcall(function()
        humanoid.Jump = true

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.Velocity = Vector3.new(hrp.Velocity.X, JUMP_IMPULSE_Y, hrp.Velocity.Z)
        end
        
        -- Criar piso se a opção estiver ativada
        if JUMP_PLATFORM then
            createJumpPlatform()
        end
    end)
end

local function toggleInfiniteJump(enabled)
    INFINITE_JUMP = enabled

    if enabled then
        -- Conexão para pulo contínuo
        infiniteJumpConnection = RunService.Heartbeat:Connect(function()
            if not INFINITE_JUMP then return end

            if UserInput:IsKeyDown(Enum.KeyCode.Space) then
                doInfiniteJump()
            end
        end)

        -- Conexões adicionais
        UserInput.JumpRequest:Connect(function()
            if INFINITE_JUMP then doInfiniteJump() end
        end)

        UserInput.InputBegan:Connect(function(input)
            if INFINITE_JUMP and input.KeyCode == Enum.KeyCode.Space then
                doInfiniteJump()
            end
        end)
    else
        if infiniteJumpConnection then
            infiniteJumpConnection:Disconnect()
            infiniteJumpConnection = nil
        end
    end
end

-- Ativar Infinite Jump se configurado
if INFINITE_JUMP then
    toggleInfiniteJump(true)
end

-- GOD MODE
local function enableGodForCharacter(character)
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    pcall(function()
        humanoid.MaxHealth = GOD_MAX_HEALTH
        humanoid.Health = GOD_MAX_HEALTH
    end)

    local conn1 = humanoid.HealthChanged:Connect(function(newHealth)
        pcall(function()
            if humanoid and newHealth < GOD_MAX_HEALTH then
                humanoid.Health = GOD_MAX_HEALTH
            end
        end)
    end)

    local conn2 = RunService.Heartbeat:Connect(function()
        pcall(function()
            if humanoid and humanoid.Health < GOD_MAX_HEALTH then
                humanoid.Health = GOD_MAX_HEALTH
            end
        end)
    end)

    godConns[character] = {conn1, conn2}
end

local function disableGodForCharacter(character)
    local conns = godConns[character]
    if conns then
        for _, conn in pairs(conns) do
            if conn then pcall(function() conn:Disconnect() end) end
        end
        godConns[character] = nil
    end
end

-- ANTI-RAGDOLL
local function enableAntiRagdollForCharacter(character)
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local conn1 = RunService.Heartbeat:Connect(function()
        pcall(function()
            if humanoid then
                if humanoid:GetState() == Enum.HumanoidStateType.Ragdoll or
                   humanoid:GetState() == Enum.HumanoidStateType.FallingDown then
                    humanoid:ChangeState(Enum.HumanoidStateType.Running)
                end

                if humanoid.PlatformStand then
                    humanoid.PlatformStand = false
                end

                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, hrp.Orientation.Y, 0)
                    hrp.Velocity = Vector3.new(hrp.Velocity.X, math.min(hrp.Velocity.Y, 50), hrp.Velocity.Z)
                end
            end
        end)
    end)

    antiRagdollConns[character] = {conn1}
end

local function disableAntiRagdollForCharacter(character)
    local conns = antiRagdollConns[character]
    if conns then
        for _, conn in pairs(conns) do
            if conn then pcall(function() conn:Disconnect() end) end
        end
        antiRagdollConns[character] = nil
    end
end

-- Configurar personagem local
local function setupLocalCharacter(char)
    wait(0.2)

    if GOD_MODE then enableGodForCharacter(char) end
    if ANTI_RAGDOLL then enableAntiRagdollForCharacter(char) end

    if SHIFT_LOCK then
        wait(0.1)
        applyShiftLockToCharacter(char)
    end
    
    if JUMP_PLATFORM then
        toggleJumpPlatform(true)
    end
    
    if SPEED_BOOST then
        applySpeedBoost(char)
    end

    char.AncestryChanged:Connect(function(_, parent)
        if not parent then
            disableGodForCharacter(char)
            disableAntiRagdollForCharacter(char)
            removeSpeedBoost(char)
        end
    end)
end

if localPlayer.Character then
    setupLocalCharacter(localPlayer.Character)
end

localPlayer.CharacterAdded:Connect(function(char)
    setupLocalCharacter(char)
end)

-- INTERFACE GRÁFICA
local function createHub()
    local existing = playerGui:FindFirstChild("Lznx7_Hub")
    if existing then safeDestroy(existing) end

    local screenGui = safeCreate("ScreenGui", {
        Name = "Lznx7_Hub",
        ResetOnSpawn = false,
        DisplayOrder = 9999,
        Parent = playerGui
    })
    
    mainHubGui = screenGui

    local mainFrame = safeCreate("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0, 320, 0, 340),  -- Aumentado para caber AimLock
        Position = UDim2.new(0.5, -160, 0.5, -170),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25),
        BorderSizePixel = 0,
        Parent = screenGui
    })

    local corner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = mainFrame
    })

    -- Título
    local title = safeCreate("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(40, 40, 50),
        BorderSizePixel = 0,
        Text = "lznx7 Hub - AimLock + Speed",
        TextColor3 = Color3.fromRGB(255, 100, 100),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        Parent = mainFrame
    })

    local titleCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12, 0, 0),
        Parent = title
    })

    -- Status
    local status = safeCreate("TextLabel", {
        Name = "Status",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, 45),
        BackgroundTransparency = 1,
        Text = "Pressione F para abrir/fechar",
        TextColor3 = Color3.fromRGB(180, 180, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })

    -- Botões em 5 linhas
    local buttons = {
        {name = "ESP", x = 0.03, y = 75, default = ESP_ENABLED, color = Color3.fromRGB(255, 100, 100)},
        {name = "InfJump", x = 0.53, y = 75, default = INFINITE_JUMP, color = Color3.fromRGB(100, 255, 100)},
        {name = "HitboxESP", x = 0.03, y = 115, default = HITBOX_ESP, color = Color3.fromRGB(100, 100, 255)},
        {name = "AntiRagdoll", x = 0.53, y = 115, default = ANTI_RAGDOLL, color = Color3.fromRGB(255, 255, 100)},
        {name = "GodMode", x = 0.03, y = 155, default = GOD_MODE, color = Color3.fromRGB(255, 100, 255)},
        {name = "ShiftLock", x = 0.53, y = 155, default = SHIFT_LOCK, color = Color3.fromRGB(150, 200, 255)},
        {name = "PisoPulo", x = 0.03, y = 195, default = JUMP_PLATFORM, color = Color3.fromRGB(0, 255, 255)},
        {name = "SpeedBoost", x = 0.53, y = 195, default = SPEED_BOOST, color = Color3.fromRGB(255, 150, 0)},
        {name = "AimLock", x = 0.03, y = 235, default = AIMLOCK_ENABLED, color = Color3.fromRGB(200, 50, 50)}  -- Novo botão AimLock
    }

    local buttonInstances = {}

    for _, btnInfo in pairs(buttons) do
        local btn = safeCreate("TextButton", {
            Name = btnInfo.name .. "_Btn",
            Size = UDim2.new(0.44, 0, 0, 35),
            Position = UDim2.new(btnInfo.x, 0, 0, btnInfo.y),
            BackgroundColor3 = btnInfo.default and btnInfo.color or Color3.fromRGB(60, 60, 70),
            Text = btnInfo.name .. ": " .. (btnInfo.default and "ON" or "OFF"),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 13,
            Parent = mainFrame
        })

        local btnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 8),
            Parent = btn
        })

        buttonInstances[btnInfo.name] = btn
    end
    
    -- Botão de Configuração do Speed Boost
    local configSpeedBtn = safeCreate("TextButton", {
        Name = "ConfigSpeedBtn",
        Size = UDim2.new(0.44, 0, 0, 32),
        Position = UDim2.new(0.03, 0, 0, 275),
        BackgroundColor3 = Color3.fromRGB(100, 100, 200),
        Text = "CONFIG SPEED",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 12,
        Parent = mainFrame
    })
    
    local configSpeedCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = configSpeedBtn
    })
    
    -- Botão de Configuração do AimLock
    local configAimBtn = safeCreate("TextButton", {
        Name = "ConfigAimBtn",
        Size = UDim2.new(0.44, 0, 0, 32),
        Position = UDim2.new(0.53, 0, 0, 275),
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        Text = "CONFIG AIMLOCK",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 12,
        Parent = mainFrame
    })
    
    local configAimCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = configAimBtn
    })

    -- Botão Fechar
    local closeBtn = safeCreate("TextButton", {
        Name = "Close_Btn",
        Size = UDim2.new(0.94, 0, 0, 32),
        Position = UDim2.new(0.03, 0, 0, 315),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "FECHAR MENU",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = mainFrame
    })

    local closeCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = closeBtn
    })

    -- Funções dos botões
    buttonInstances.ESP.MouseButton1Click:Connect(function()
        ESP_ENABLED = not ESP_ENABLED
        if ESP_ENABLED then
            buttonInstances.ESP.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            buttonInstances.ESP.Text = "ESP: ON"
            rebuildAllESP()
            status.Text = "ESP Normal ATIVADO"
        else
            buttonInstances.ESP.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.ESP.Text = "ESP: OFF"
            for userId, data in pairs(espData) do
                if data.highlight then safeDestroy(data.highlight) end
                if data.billboard then safeDestroy(data.billboard) end
                if data.updateConnection then data.updateConnection:Disconnect() end
            end
            espData = {}
            status.Text = "ESP Desativado"
        end
    end)

    buttonInstances.InfJump.MouseButton1Click:Connect(function()
        INFINITE_JUMP = not INFINITE_JUMP
        if INFINITE_JUMP then
            buttonInstances.InfJump.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
            buttonInstances.InfJump.Text = "InfJump: ON"
            toggleInfiniteJump(true)
            status.Text = "Pulo Infinito ATIVADO - Mantenha Espaço"
        else
            buttonInstances.InfJump.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.InfJump.Text = "InfJump: OFF"
            toggleInfiniteJump(false)
            status.Text = "Pulo Infinito Desativado"
        end
    end)

    buttonInstances.HitboxESP.MouseButton1Click:Connect(function()
        HITBOX_ESP = not HITBOX_ESP
        if HITBOX_ESP then
            buttonInstances.HitboxESP.BackgroundColor3 = Color3.fromRGB(100, 100, 255)
            buttonInstances.HitboxESP.Text = "HitboxESP: ON"
            status.Text = "Hitbox ESP ATIVADO - Caixas coloridas"
            toggleHitboxESP(true)
        else
            buttonInstances.HitboxESP.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.HitboxESP.Text = "HitboxESP: OFF"
            status.Text = "Hitbox ESP Desativado"
            toggleHitboxESP(false)
        end
    end)

    buttonInstances.AntiRagdoll.MouseButton1Click:Connect(function()
        ANTI_RAGDOLL = not ANTI_RAGDOLL
        if ANTI_RAGDOLL then
            buttonInstances.AntiRagdoll.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
            buttonInstances.AntiRagdoll.Text = "AntiRagdoll: ON"
            status.Text = "Anti-Ragdoll ATIVADO"
            if localPlayer.Character then enableAntiRagdollForCharacter(localPlayer.Character) end
        else
            buttonInstances.AntiRagdoll.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.AntiRagdoll.Text = "AntiRagdoll: OFF"
            status.Text = "Anti-Ragdoll Desativado"
            if localPlayer.Character then disableAntiRagdollForCharacter(localPlayer.Character) end
        end
    end)

    buttonInstances.GodMode.MouseButton1Click:Connect(function()
        GOD_MODE = not GOD_MODE
        if GOD_MODE then
            buttonInstances.GodMode.BackgroundColor3 = Color3.fromRGB(255, 100, 255)
            buttonInstances.GodMode.Text = "GodMode: ON"
            status.Text = "God Mode ATIVADO"
            if localPlayer.Character then enableGodForCharacter(localPlayer.Character) end
        else
            buttonInstances.GodMode.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.GodMode.Text = "GodMode: OFF"
            status.Text = "God Mode Desativado"
            if localPlayer.Character then disableGodForCharacter(localPlayer.Character) end
        end
    end)

    buttonInstances.ShiftLock.MouseButton1Click:Connect(function()
        SHIFT_LOCK = not SHIFT_LOCK
        if SHIFT_LOCK then
            buttonInstances.ShiftLock.BackgroundColor3 = Color3.fromRGB(150, 200, 255)
            buttonInstances.ShiftLock.Text = "ShiftLock: ON"
            status.Text = "Shift Lock ATIVADO - Sprint travado"
            toggleShiftLock(true)
        else
            buttonInstances.ShiftLock.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.ShiftLock.Text = "ShiftLock: OFF"
            status.Text = "Shift Lock Desativado"
            toggleShiftLock(false)
        end
    end)

    buttonInstances.PisoPulo.MouseButton1Click:Connect(function()
        JUMP_PLATFORM = not JUMP_PLATFORM
        if JUMP_PLATFORM then
            buttonInstances.PisoPulo.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
            buttonInstances.PisoPulo.Text = "PisoPulo: ON"
            status.Text = "Piso ao Pular ATIVADO - 4 segundos"
            toggleJumpPlatform(true)
        else
            buttonInstances.PisoPulo.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.PisoPulo.Text = "PisoPulo: OFF"
            status.Text = "Piso ao Pular Desativado"
            toggleJumpPlatform(false)
        end
    end)

    buttonInstances.SpeedBoost.MouseButton1Click:Connect(function()
        SPEED_BOOST = not SPEED_BOOST
        if SPEED_BOOST then
            buttonInstances.SpeedBoost.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
            buttonInstances.SpeedBoost.Text = "SpeedBoost: ON"
            status.Text = "Speed Boost ATIVADO - " .. speedBoostMultiplier .. "x"
            toggleSpeedBoost(true)
        else
            buttonInstances.SpeedBoost.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.SpeedBoost.Text = "SpeedBoost: OFF"
            status.Text = "Speed Boost Desativado"
            toggleSpeedBoost(false)
        end
    end)

    buttonInstances.AimLock.MouseButton1Click:Connect(function()
        AIMLOCK_ENABLED = not AIMLOCK_ENABLED
        if AIMLOCK_ENABLED then
            buttonInstances.AimLock.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            buttonInstances.AimLock.Text = "AimLock: ON"
            status.Text = "AimLock ATIVADO - Pressione " .. tostring(AIMLOCK_KEY)
            toggleAimLock(true)
        else
            buttonInstances.AimLock.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.AimLock.Text = "AimLock: OFF"
            status.Text = "AimLock Desativado"
            toggleAimLock(false)
        end
    end)
    
    -- Botão de Configuração Speed
    configSpeedBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
        wait(0.1)
        createSpeedConfigGui()
    end)
    
    -- Botão de Configuração AimLock
    configAimBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
        wait(0.1)
        createAimConfigGui()
    end)

    closeBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
    end)

    -- Tecla F para abrir/fechar
    UserInput.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.F then
            screenGui.Enabled = not screenGui.Enabled
            
            -- Fechar painéis abertos
            if speedConfigGui then
                safeDestroy(speedConfigGui)
                speedConfigGui = nil
            end
            
            if aimConfigGui then
                safeDestroy(aimConfigGui)
                aimConfigGui = nil
            end
        end
        
        -- Tecla para ativar AimLock (mantenha pressionada)
        if input.KeyCode == AIMLOCK_KEY then
            if not AIMLOCK_ENABLED then
                local wasEnabled = AIMLOCK_ENABLED
                toggleAimLock(true)
                
                -- Manter ativo enquanto a tecla estiver pressionada
                local connection
                connection = UserInput.InputEnded:Connect(function(endInput)
                    if endInput.KeyCode == AIMLOCK_KEY then
                        if not wasEnabled then
                            toggleAimLock(false)
                        end
                        if connection then
                            connection:Disconnect()
                        end
                    end
                end)
            end
        end
    end)

    return screenGui
end

-- Criar GUI
wait(1)
local success, gui = pcall(createHub)
if success and gui then
    print("[lznx7] Hub criado com sucesso!")
    print("[lznx7] Pressione F para abrir/fechar o menu")
    print("[lznx7] AimLock: Pressione " .. tostring(AIMLOCK_KEY) .. " para mirar automaticamente")
else
    warn("[lznx7] Erro ao criar GUI")
end

-- Notificação
local function showNotification(message)
    pcall(function()
        local notif = Instance.new("ScreenGui")
        notif.Name = "Notification"
        notif.Parent = playerGui

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 350, 0, 80)
        frame.Position = UDim2.new(0.5, -175, 0.8, 0)
        frame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        frame.BorderSizePixel = 0
        frame.Parent = notif

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 1, -20)
        label.Position = UDim2.new(0, 10, 0, 10)
        label.BackgroundTransparency = 1
        label.Text = message
        label.TextColor3 = Color3.fromRGB(255, 255, 100)
        label.Font = Enum.Font.SourceSansBold
        label.TextSize = 16
        label.TextWrapped = true
        label.Parent = frame

        wait(4)
        notif:Destroy()
    end)
end

showNotification("lznx7 Hub - AimLock + Speed\n• Pressione F para menu\n• AimLock: " .. tostring(AIMLOCK_KEY) .. " para mira automática\n• Configure opções nos botões CONFIG")

print("[lznx7] Sistema completo carregado!")
print("[lznx7] Features: ESP, Hitbox ESP, Infinite Jump, Anti-Ragdoll, God Mode")
print("[lznx7] ShiftLock, Piso ao Pular (4s), Speed Boost (1-15x), AimLock")

-- Conectar ao evento de pulo inicialmente
if JUMP_PLATFORM then
    toggleJumpPlatform(true)
end

-- Ativar Speed Boost se configurado
if SPEED_BOOST then
    toggleSpeedBoost(true)
end

-- Ativar AimLock se configurado
if AIMLOCK_ENABLED then
    toggleAimLock(true)
end

-- Loop para limpeza periódica
RunService.Heartbeat:Connect(function()
    -- Limpar pisos muito antigos
    for i = #platformParts, 1, -1 do
        local platData = platformParts[i]
        if platData and platData.part then
            if tick() - platData.creationTime > PLATFORM_DURATION + 6 then
                safeDestroy(platData.part)
                table.remove(platformParts, i)
            end
        end
    end
end)

-- Controle com tecla ESC
UserInput.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Escape then
        -- Fechar painel de configuração de velocidade
        if speedConfigGui then
            safeDestroy(speedConfigGui)
            speedConfigGui = nil
            
            if mainHubGui then
                mainHubGui.Enabled = true
            end
        -- Fechar painel de configuração do AimLock
        elseif aimConfigGui then
            safeDestroy(aimConfigGui)
            aimConfigGui = nil
            
            if mainHubGui then
                mainHubGui.Enabled = true
            end
        -- Fechar menu principal
        elseif mainHubGui and mainHubGui.Enabled then
            mainHubGui.Enabled = false
        end
    end
end)


-- LocalScript para Xeno Executor
-- ESP Normal + Hitbox ESP + ShiftLock + Piso ao Pular + Speed Boost Configurável + AimLock
-- REMOVIDO: função de deixar base transparente
-- Coloque em StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
if not localPlayer then
    print("[lznx7] Aguardando jogador local...")
    wait(1)
    localPlayer = Players.LocalPlayer
    if not localPlayer then return end
end

-- Configurações
local ESP_ENABLED = false
local INFINITE_JUMP = false
local JUMP_IMPULSE_Y = 70
local GOD_MODE = true
local GOD_MAX_HEALTH = 1000000
local ANTI_RAGDOLL = true
local HITBOX_ESP = false  -- Nova opção para Hitbox ESP
local JUMP_PLATFORM = true  -- Nova opção: criar piso ao pular
local PLATFORM_DURATION = 4  -- Duração do piso em segundos
local SPEED_BOOST = false  -- Nova opção: Speed Boost
local SPEED_BOOST_MULTIPLIER = 3  -- Multiplicador de velocidade (3x mais rápido)
local AIMLOCK_ENABLED = false  -- Nova opção: AimLock
local AIMLOCK_KEY = Enum.KeyCode.Q  -- Tecla para ativar AimLock
local AIMLOCK_SMOOTHNESS = 0.15  -- Suavidade do AimLock (0-1, menor = mais suave)
local AIMLOCK_USE_CAMERA = true  -- Usar câmera em vez de mouse
local aimLockConn = nil
local aimLockTarget = nil
local aimLockTargetPart = "Head"  -- Parte do corpo para mirar
local speedBoostConn = nil
local speedBoostActive = false

-- Shift Lock (trava "Shift" / trava sprint na tela)
local SHIFT_LOCK = false
local SHIFT_WALK_SPEED = 24 -- velocidade enquanto shift estiver travado
local DEFAULT_WALK_SPEED = 16
local shiftLockConn = nil
local shiftLockCharacterConn = nil
local shiftLockOrigSpeed = {}

-- Armazenamento
local playerGui = localPlayer:WaitForChild("PlayerGui")
local espStore = playerGui:FindFirstChild("Lznx7ESPStore")
if not espStore then
    espStore = Instance.new("Folder")
    espStore.Name = "Lznx7ESPStore"
    espStore.Parent = playerGui
end

-- Variáveis globais
local godConns = {}
local antiRagdollConns = {}
local infiniteJumpConnection
local espData = {} -- Armazenar dados do ESP por jogador
local jumpPlatformConnection
local platformParts = {} -- Armazenar pisos criados
local lastJumpTime = 0
local JUMP_COOLDOWN = 0.2 -- Cooldown entre criação de pisos
local originalWalkSpeed = 16
local originalJumpPower = 50
local speedConfigGui = nil  -- GUI para configuração de velocidade
local speedBoostMultiplier = 3  -- Valor atual do multiplicador
local mainHubGui = nil  -- Referência para o menu principal
local aimConfigGui = nil  -- GUI para configuração do AimLock
local aimLockTargets = {}  -- Alvos disponíveis para AimLock
local aimLockFOV = 500  -- Campo de visão do AimLock
local aimLockPriority = "Nearest"  -- Prioridade: Nearest, LowestHealth, HighestHealth
local camera = Workspace.CurrentCamera

-- Funções utilitárias
local function safeCreate(className, properties)
    local success, obj = pcall(function()
        local instance = Instance.new(className)
        for prop, value in pairs(properties) do
            instance[prop] = value
        end
        return instance
    end)
    return success and obj or nil
end

local function safeDestroy(obj)
    if obj and obj.Parent then
        pcall(function() obj:Destroy() end)
    end
end

-- Função para encontrar o melhor alvo para AimLock
local function findAimLockTarget()
    if not localPlayer.Character then return nil end
    local myPosition = localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myPosition then return nil end
    myPosition = myPosition.Position
    
    local bestTarget = nil
    local bestDistance = math.huge
    local bestHealth = math.huge
    
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character and player.Character:FindFirstChild("Humanoid") then
            local humanoid = player.Character:FindFirstChild("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local targetPart = player.Character:FindFirstChild("HumanoidRootPart") or 
                                  player.Character:FindFirstChild("Head") or
                                  player.Character:FindFirstChild("UpperTorso")
                
                if targetPart then
                    -- Verificar se está dentro do FOV
                    local screenPoint = camera:WorldToViewportPoint(targetPart.Position)
                    local viewportSize = camera.ViewportSize
                    local distanceFromCenter = (Vector2.new(screenPoint.X, screenPoint.Y) - viewportSize / 2).Magnitude
                    
                    if screenPoint.Z > 0 and distanceFromCenter < aimLockFOV then
                        local distance = (myPosition - targetPart.Position).Magnitude
                        local health = humanoid.Health
                        
                        if aimLockPriority == "Nearest" then
                            if distance < bestDistance then
                                bestDistance = distance
                                bestTarget = player
                            end
                        elseif aimLockPriority == "LowestHealth" then
                            if health < bestHealth then
                                bestHealth = health
                                bestTarget = player
                            end
                        elseif aimLockPriority == "HighestHealth" then
                            if health > bestHealth then
                                bestHealth = health
                                bestTarget = player
                            end
                        end
                    end
                end
            end
        end
    end
    
    return bestTarget
end

-- Função para aplicar AimLock
local function applyAimLock()
    if not AIMLOCK_ENABLED then return end
    if not aimLockTarget or not aimLockTarget.Character then return end
    
    local targetPart = aimLockTarget.Character:FindFirstChild(aimLockTargetPart) or
                      aimLockTarget.Character:FindFirstChild("HumanoidRootPart") or
                      aimLockTarget.Character:FindFirstChild("Head") or
                      aimLockTarget.Character:FindFirstChild("UpperTorso")
    
    if not targetPart then return end
    if not localPlayer.Character then return end
    
    local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Calcular direção para o alvo
    local targetPosition = targetPart.Position
    local myPosition = localPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myPosition then return end
    myPosition = myPosition.Position
    
    local direction = (targetPosition - myPosition).Unit
    
    if AIMLOCK_USE_CAMERA then
        -- Usar câmera para mirar
        local currentCF = camera.CFrame
        local lookVector = currentCF.LookVector
        
        -- Interpolar suavemente para a direção do alvo
        local newLookVector = lookVector:Lerp(direction, AIMLOCK_SMOOTHNESS)
        local newCF = CFrame.new(currentCF.Position, currentCF.Position + newLookVector)
        camera.CFrame = newCF
    else
        -- Usar mouse para mirar (para jogos que usam mouse)
        local mouse = localPlayer:GetMouse()
        if mouse then
            -- Converter direção para posição na tela
            local screenPoint = camera:WorldToScreenPoint(targetPosition)
            if screenPoint.Z > 0 then
                mousemoverel(screenPoint.X - mouse.X, screenPoint.Y - mouse.Y)
            end
        end
    end
end

-- Função para criar indicador visual do AimLock
local function createAimLockIndicator(target)
    if not target or not target.Character then return nil end
    
    local indicator = safeCreate("BillboardGui", {
        Name = "AimLockIndicator",
        Size = UDim2.new(0, 100, 0, 100),
        StudsOffset = Vector3.new(0, 3, 0),
        AlwaysOnTop = true,
        MaxDistance = 1000,
        Parent = playerGui
    })
    
    local frame = safeCreate("Frame", {
        Name = "IndicatorFrame",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Parent = indicator
    })
    
    -- Círculo vermelho
    local circle = safeCreate("ImageLabel", {
        Name = "Circle",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Image = "rbxassetid://3570695787",
        ImageColor3 = Color3.fromRGB(255, 50, 50),
        ScaleType = Enum.ScaleType.Fit,
        Parent = frame
    })
    
    -- Texto com nome do alvo
    local nameLabel = safeCreate("TextLabel", {
        Name = "NameLabel",
        Size = UDim2.new(1, 0, 0, 20),
        Position = UDim2.new(0, 0, 1.1, 0),
        BackgroundTransparency = 1,
        Text = target.Name,
        TextColor3 = Color3.fromRGB(255, 100, 100),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = frame
    })
    
    -- Atualizar posição
    local updateConnection = RunService.RenderStepped:Connect(function()
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            indicator.Adornee = target.Character.HumanoidRootPart
            
            -- Verificar saúde
            local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local healthPercent = humanoid.Health / humanoid.MaxHealth
                if healthPercent < 0.3 then
                    circle.ImageColor3 = Color3.fromRGB(255, 0, 0)  -- Vermelho para baixa vida
                elseif healthPercent < 0.6 then
                    circle.ImageColor3 = Color3.fromRGB(255, 165, 0)  -- Laranja
                else
                    circle.ImageColor3 = Color3.fromRGB(255, 50, 50)  -- Vermelho claro
                end
                
                nameLabel.Text = string.format("%s (%d/%d HP)", target.Name, math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
            end
        else
            updateConnection:Disconnect()
            safeDestroy(indicator)
        end
    end)
    
    return indicator
end

-- Ativar/Desativar AimLock
local function toggleAimLock(enabled)
    AIMLOCK_ENABLED = enabled
    
    if enabled then
        -- Encontrar alvo inicial
        aimLockTarget = findAimLockTarget()
        
        if aimLockTarget then
            -- Criar indicador visual
            local indicator = createAimLockIndicator(aimLockTarget)
            
            -- Iniciar loop do AimLock
            aimLockConn = RunService.RenderStepped:Connect(function()
                if AIMLOCK_ENABLED and aimLockTarget and aimLockTarget.Character then
                    -- Verificar se o alvo ainda é válido
                    local humanoid = aimLockTarget.Character:FindFirstChildOfClass("Humanoid")
                    if not humanoid or humanoid.Health <= 0 then
                        -- Encontrar novo alvo
                        aimLockTarget = findAimLockTarget()
                        if aimLockTarget then
                            safeDestroy(indicator)
                            indicator = createAimLockIndicator(aimLockTarget)
                        end
                    else
                        applyAimLock()
                    end
                else
                    -- Tentar encontrar novo alvo
                    aimLockTarget = findAimLockTarget()
                    if aimLockTarget and not indicator then
                        indicator = createAimLockIndicator(aimLockTarget)
                    end
                end
            end)
            
            print("[AimLock] Alvo travado: " .. aimLockTarget.Name)
        else
            print("[AimLock] Nenhum alvo encontrado no FOV")
        end
    else
        if aimLockConn then
            aimLockConn:Disconnect()
            aimLockConn = nil
        end
        
        aimLockTarget = nil
        
        -- Remover todos os indicadores
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui.Name == "AimLockIndicator" then
                safeDestroy(gui)
            end
        end
        
        print("[AimLock] Desativado")
    end
end

-- Função para criar interface de configuração do AimLock
local function createAimConfigGui()
    if aimConfigGui then
        safeDestroy(aimConfigGui)
    end
    
    local screenGui = safeCreate("ScreenGui", {
        Name = "AimConfig_GUI",
        ResetOnSpawn = false,
        DisplayOrder = 10001,
        Parent = playerGui
    })
    
    local mainFrame = safeCreate("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0, 320, 0, 300),
        Position = UDim2.new(0.5, -160, 0.5, -150),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(25, 25, 35),
        BorderSizePixel = 0,
        Parent = screenGui
    })
    
    local corner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = mainFrame
    })
    
    -- Barra de título
    local titleBar = safeCreate("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local titleBarCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12, 0, 0),
        Parent = titleBar
    })
    
    -- Botão de fechar
    local closeBtn = safeCreate("TextButton", {
        Name = "CloseBtn",
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, -35, 0, 5),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "X",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 16,
        Parent = titleBar
    })
    
    local closeCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 15),
        Parent = closeBtn
    })
    
    -- Título
    local title = safeCreate("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = "CONFIGURAR AIMLOCK",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar
    })
    
    -- Configurações
    local settingsY = 50
    
    -- Suavidade
    local smoothLabel = safeCreate("TextLabel", {
        Name = "SmoothLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY),
        BackgroundTransparency = 1,
        Text = "Suavidade: " .. string.format("%.2f", AIMLOCK_SMOOTHNESS),
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local smoothSlider = safeCreate("Frame", {
        Name = "SmoothSlider",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0, 10, 0, settingsY + 25),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local smoothCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = smoothSlider
    })
    
    local smoothFill = safeCreate("Frame", {
        Name = "SmoothFill",
        Size = UDim2.new(AIMLOCK_SMOOTHNESS, 0, 1, 0),
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        BorderSizePixel = 0,
        Parent = smoothSlider
    })
    
    local smoothCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = smoothFill
    })
    
    -- FOV
    local fovLabel = safeCreate("TextLabel", {
        Name = "FOVLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY + 55),
        BackgroundTransparency = 1,
        Text = "Campo de Visão: " .. aimLockFOV .. "px",
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local fovSlider = safeCreate("Frame", {
        Name = "FOVSlider",
        Size = UDim2.new(0, 200, 0, 20),
        Position = UDim2.new(0, 10, 0, settingsY + 80),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local fovCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = fovSlider
    })
    
    local fovFill = safeCreate("Frame", {
        Name = "FOVFill",
        Size = UDim2.new((aimLockFOV - 100) / 900, 0, 1, 0),  -- 100 a 1000
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        BorderSizePixel = 0,
        Parent = fovSlider
    })
    
    local fovCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 4),
        Parent = fovFill
    })
    
    -- Parte do corpo
    local partLabel = safeCreate("TextLabel", {
        Name = "PartLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY + 110),
        BackgroundTransparency = 1,
        Text = "Parte do Corpo: " .. aimLockTargetPart,
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local partButtons = {
        {text = "Cabeça", value = "Head", x = 10},
        {text = "Torso", value = "UpperTorso", x = 90},
        {text = "Raiz", value = "HumanoidRootPart", x = 170}
    }
    
    for _, btn in ipairs(partButtons) do
        local partBtn = safeCreate("TextButton", {
            Name = "PartBtn_" .. btn.value,
            Size = UDim2.new(0, 70, 0, 30),
            Position = UDim2.new(0, btn.x, 0, settingsY + 135),
            BackgroundColor3 = aimLockTargetPart == btn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80),
            Text = btn.text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSans,
            TextSize = 12,
            Parent = mainFrame
        })
        
        local partBtnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = partBtn
        })
        
        partBtn.MouseButton1Click:Connect(function()
            aimLockTargetPart = btn.value
            partLabel.Text = "Parte do Corpo: " .. aimLockTargetPart
            
            -- Atualizar cores dos botões
            for _, otherBtn in ipairs(partButtons) do
                local otherPartBtn = mainFrame:FindFirstChild("PartBtn_" .. otherBtn.value)
                if otherPartBtn then
                    otherPartBtn.BackgroundColor3 = aimLockTargetPart == otherBtn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80)
                end
            end
        end)
    end
    
    -- Prioridade
    local priorityLabel = safeCreate("TextLabel", {
        Name = "PriorityLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, settingsY + 175),
        BackgroundTransparency = 1,
        Text = "Prioridade: " .. aimLockPriority,
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local priorityButtons = {
        {text = "Mais Próximo", value = "Nearest", x = 10},
        {text = "Menos Vida", value = "LowestHealth", x = 110},
        {text = "Mais Vida", value = "HighestHealth", x = 210}
    }
    
    for _, btn in ipairs(priorityButtons) do
        local priorityBtn = safeCreate("TextButton", {
            Name = "PriorityBtn_" .. btn.value,
            Size = UDim2.new(0, 90, 0, 30),
            Position = UDim2.new(0, btn.x, 0, settingsY + 200),
            BackgroundColor3 = aimLockPriority == btn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80),
            Text = btn.text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSans,
            TextSize = 12,
            Parent = mainFrame
        })
        
        local priorityBtnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = priorityBtn
        })
        
        priorityBtn.MouseButton1Click:Connect(function()
            aimLockPriority = btn.value
            priorityLabel.Text = "Prioridade: " .. aimLockPriority
            
            -- Atualizar cores dos botões
            for _, otherBtn in ipairs(priorityButtons) do
                local otherPriorityBtn = mainFrame:FindFirstChild("PriorityBtn_" .. otherBtn.value)
                if otherPriorityBtn then
                    otherPriorityBtn.BackgroundColor3 = aimLockPriority == otherBtn.value and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(60, 60, 80)
                end
            end
        end)
    end
    
    -- Botões de controle
    local controlFrame = safeCreate("Frame", {
        Name = "ControlFrame",
        Size = UDim2.new(1, -20, 0, 40),
        Position = UDim2.new(0, 10, 1, -50),
        BackgroundTransparency = 1,
        Parent = mainFrame
    })
    
    -- Botão Aplicar
    local applyBtn = safeCreate("TextButton", {
        Name = "ApplyBtn",
        Size = UDim2.new(0.48, 0, 1, 0),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(60, 150, 255),
        Text = "APLICAR",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = controlFrame
    })
    
    local applyCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = applyBtn
    })
    
    -- Botão Testar
    local testBtn = safeCreate("TextButton", {
        Name = "TestBtn",
        Size = UDim2.new(0.48, 0, 1, 0),
        Position = UDim2.new(0.52, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(255, 150, 0),
        Text = "TESTAR",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = controlFrame
    })
    
    local testCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = testBtn
    })
    
    -- Funções de interação com sliders
    local function updateSmoothSlider(value)
        AIMLOCK_SMOOTHNESS = math.clamp(value, 0.01, 1.0)
        smoothLabel.Text = "Suavidade: " .. string.format("%.2f", AIMLOCK_SMOOTHNESS)
        smoothFill.Size = UDim2.new(AIMLOCK_SMOOTHNESS, 0, 1, 0)
    end
    
    local function updateFOVSlider(value)
        aimLockFOV = math.clamp(value, 100, 1000)
        fovLabel.Text = "Campo de Visão: " .. aimLockFOV .. "px"
        fovFill.Size = UDim2.new((aimLockFOV - 100) / 900, 0, 1, 0)
    end
    
    -- Configurar arrasto dos sliders
    local function setupSlider(slider, fill, label, updateFunc, min, max)
        local dragging = false
        
        slider.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
            end
        end)
        
        slider.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        
        UserInput.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local mousePos = input.Position
                local sliderPos = slider.AbsolutePosition
                local sliderSize = slider.AbsoluteSize
                
                local relativeX = (mousePos.X - sliderPos.X) / sliderSize.X
                relativeX = math.clamp(relativeX, 0, 1)
                
                local value = min + (relativeX * (max - min))
                updateFunc(value)
            end
        end)
    end
    
    setupSlider(smoothSlider, smoothFill, smoothLabel, updateSmoothSlider, 0.01, 1.0)
    setupSlider(fovSlider, fovFill, fovLabel, updateFOVSlider, 100, 1000)
    
    -- Botões de incremento/decremento
    local function createControlButtons(slider, updateFunc, step, min, max)
        local minusBtn = safeCreate("TextButton", {
            Name = "MinusBtn",
            Size = UDim2.new(0, 25, 0, 25),
            Position = UDim2.new(1, 5, 0.5, -12.5),
            BackgroundColor3 = Color3.fromRGB(200, 60, 60),
            Text = "-",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 18,
            Parent = slider
        })
        
        local plusBtn = safeCreate("TextButton", {
            Name = "PlusBtn",
            Size = UDim2.new(0, 25, 0, 25),
            Position = UDim2.new(1, 35, 0.5, -12.5),
            BackgroundColor3 = Color3.fromRGB(60, 200, 60),
            Text = "+",
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 18,
            Parent = slider
        })
        
        local btnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 12),
            Parent = minusBtn
        })
        
        local btnCorner2 = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 12),
            Parent = plusBtn
        })
        
        minusBtn.MouseButton1Click:Connect(function()
            local currentValue = slider == smoothSlider and AIMLOCK_SMOOTHNESS or aimLockFOV
            local newValue = currentValue - step
            if newValue >= min then
                updateFunc(newValue)
            end
        end)
        
        plusBtn.MouseButton1Click:Connect(function()
            local currentValue = slider == smoothSlider and AIMLOCK_SMOOTHNESS or aimLockFOV
            local newValue = currentValue + step
            if newValue <= max then
                updateFunc(newValue)
            end
        end)
    end
    
    createControlButtons(smoothSlider, updateSmoothSlider, 0.05, 0.01, 1.0)
    createControlButtons(fovSlider, updateFOVSlider, 50, 100, 1000)
    
    -- Funções dos botões principais
    closeBtn.MouseButton1Click:Connect(function()
        safeDestroy(screenGui)
        aimConfigGui = nil
        
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    applyBtn.MouseButton1Click:Connect(function()
        -- Reaplicar AimLock se estiver ativo
        if AIMLOCK_ENABLED then
            toggleAimLock(false)
            wait(0.1)
            toggleAimLock(true)
        end
        
        safeDestroy(screenGui)
        aimConfigGui = nil
        
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    testBtn.MouseButton1Click:Connect(function()
        -- Testar o AimLock
        if not AIMLOCK_ENABLED then
            local wasEnabled = AIMLOCK_ENABLED
            toggleAimLock(true)
            wait(2)
            if not wasEnabled then
                toggleAimLock(false)
            end
        end
    end)
    
    aimConfigGui = screenGui
    return screenGui
end

-- Função para criar interface de configuração de velocidade
local function createSpeedConfigGui()
    if speedConfigGui then
        safeDestroy(speedConfigGui)
    end
    
    local screenGui = safeCreate("ScreenGui", {
        Name = "SpeedConfig_GUI",
        ResetOnSpawn = false,
        DisplayOrder = 10000,
        Parent = playerGui
    })
    
    local mainFrame = safeCreate("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0, 320, 0, 220),
        Position = UDim2.new(0.5, -160, 0.5, -110),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(25, 25, 35),
        BorderSizePixel = 0,
        Parent = screenGui
    })
    
    local corner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = mainFrame
    })
    
    -- Barra de título com botão fechar
    local titleBar = safeCreate("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(45, 45, 60),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local titleBarCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12, 0, 0),
        Parent = titleBar
    })
    
    -- Botão de fechar
    local closeBtn = safeCreate("TextButton", {
        Name = "CloseBtn",
        Size = UDim2.new(0, 30, 0, 30),
        Position = UDim2.new(1, -35, 0, 5),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "X",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 16,
        Parent = titleBar
    })
    
    local closeCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 15),
        Parent = closeBtn
    })
    
    -- Título
    local title = safeCreate("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, -40, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1,
        Text = "CONFIGURAR SPEED BOOST",
        TextColor3 = Color3.fromRGB(255, 150, 0),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar
    })
    
    -- Velocidade
    local speedLabel = safeCreate("TextLabel", {
        Name = "SpeedLabel",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, 50),
        BackgroundTransparency = 1,
        Text = "Multiplicador de Velocidade:",
        TextColor3 = Color3.fromRGB(200, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    local speedValue = safeCreate("TextLabel", {
        Name = "SpeedValue",
        Size = UDim2.new(0, 60, 0, 30),
        Position = UDim2.new(1, -70, 0, 48),
        BackgroundColor3 = Color3.fromRGB(40, 40, 60),
        Text = tostring(speedBoostMultiplier) .. "x",
        TextColor3 = Color3.fromRGB(255, 200, 100),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        Parent = mainFrame
    })
    
    local speedCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = speedValue
    })
    
    -- Slider para velocidade
    local sliderFrame = safeCreate("Frame", {
        Name = "SliderFrame",
        Size = UDim2.new(0, 260, 0, 30),
        Position = UDim2.new(0.5, -130, 0, 85),
        BackgroundColor3 = Color3.fromRGB(50, 50, 70),
        BorderSizePixel = 0,
        Parent = mainFrame
    })
    
    local sliderCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = sliderFrame
    })
    
    local sliderFill = safeCreate("Frame", {
        Name = "SliderFill",
        Size = UDim2.new((speedBoostMultiplier - 1) / 9, 0, 1, 0),  -- 1x a 10x
        BackgroundColor3 = Color3.fromRGB(255, 150, 0),
        BorderSizePixel = 0,
        Parent = sliderFrame
    })
    
    local sliderCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 6),
        Parent = sliderFill
    })
    
    -- Botões de ajuste rápido
    local quickButtons = {
        {text = "2x", value = 2, color = Color3.fromRGB(100, 200, 100)},
        {text = "5x", value = 5, color = Color3.fromRGB(255, 150, 0)},
        {text = "10x", value = 10, color = Color3.fromRGB(255, 100, 100)},
        {text = "15x", value = 15, color = Color3.fromRGB(200, 100, 255)}
    }
    
    local buttonFrame = safeCreate("Frame", {
        Name = "ButtonFrame",
        Size = UDim2.new(1, -20, 0, 40),
        Position = UDim2.new(0, 10, 0, 120),
        BackgroundTransparency = 1,
        Parent = mainFrame
    })
    
    for i, btn in ipairs(quickButtons) do
        local quickBtn = safeCreate("TextButton", {
            Name = "QuickBtn_" .. btn.text,
            Size = UDim2.new(0.23, 0, 1, 0),
            Position = UDim2.new(0.25 * (i-1), 0, 0, 0),
            BackgroundColor3 = btn.color,
            Text = btn.text,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 14,
            Parent = buttonFrame
        })
        
        local btnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 6),
            Parent = quickBtn
        })
        
        quickBtn.MouseButton1Click:Connect(function()
            speedBoostMultiplier = btn.value
            speedValue.Text = tostring(speedBoostMultiplier) .. "x"
            sliderFill.Size = UDim2.new((speedBoostMultiplier - 1) / 14, 0, 1, 0)
        end)
    end
    
    -- Botões de controle do slider
    local minusBtn = safeCreate("TextButton", {
        Name = "MinusBtn",
        Size = UDim2.new(0, 35, 0, 35),
        Position = UDim2.new(0, -40, 0, 83),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "−",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 22,
        Parent = mainFrame
    })
    
    local plusBtn = safeCreate("TextButton", {
        Name = "PlusBtn",
        Size = UDim2.new(0, 35, 0, 35),
        Position = UDim2.new(1, 5, 0, 83),
        BackgroundColor3 = Color3.fromRGB(60, 200, 60),
        Text = "+",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 22,
        Parent = mainFrame
    })
    
    local btnCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 17),
        Parent = minusBtn
    })
    
    local btnCorner2 = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 17),
        Parent = plusBtn
    })
    
    -- Status info
    local statusInfo = safeCreate("TextLabel", {
        Name = "StatusInfo",
        Size = UDim2.new(1, -20, 0, 20),
        Position = UDim2.new(0, 10, 0, 165),
        BackgroundTransparency = 1,
        Text = "Velocidade atual: " .. tostring(speedBoostMultiplier) .. "x",
        TextColor3 = Color3.fromRGB(150, 200, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })
    
    -- Funções dos botões
    local function updateSlider()
        speedValue.Text = tostring(speedBoostMultiplier) .. "x"
        sliderFill.Size = UDim2.new((speedBoostMultiplier - 1) / 14, 0, 1, 0)
        statusInfo.Text = "Velocidade atual: " .. tostring(speedBoostMultiplier) .. "x"
    end
    
    minusBtn.MouseButton1Click:Connect(function()
        if speedBoostMultiplier > 1 then
            speedBoostMultiplier = speedBoostMultiplier - 0.5
            if speedBoostMultiplier < 1 then speedBoostMultiplier = 1 end
            updateSlider()
        end
    end)
    
    plusBtn.MouseButton1Click:Connect(function()
        if speedBoostMultiplier < 15 then
            speedBoostMultiplier = speedBoostMultiplier + 0.5
            if speedBoostMultiplier > 15 then speedBoostMultiplier = 15 end
            updateSlider()
        end
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        safeDestroy(screenGui)
        speedConfigGui = nil
        
        -- Reabrir o menu principal
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    -- Permitir arrastar o slider
    local dragging = false
    
    sliderFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
        end
    end)
    
    sliderFrame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInput.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = input.Position
            local sliderPos = sliderFrame.AbsolutePosition
            local sliderSize = sliderFrame.AbsoluteSize
            
            local relativeX = (mousePos.X - sliderPos.X) / sliderSize.X
            relativeX = math.clamp(relativeX, 0, 1)
            
            speedBoostMultiplier = 1 + (relativeX * 14)  -- 1 a 15
            speedBoostMultiplier = math.floor(speedBoostMultiplier * 2) / 2  -- Arredondar para múltiplos de 0.5
            
            updateSlider()
        end
    end)
    
    -- Botão Aplicar
    local applyBtn = safeCreate("TextButton", {
        Name = "ApplyBtn",
        Size = UDim2.new(0.85, 0, 0, 40),
        Position = UDim2.new(0.5, -127, 0, 190),
        BackgroundColor3 = Color3.fromRGB(60, 150, 255),
        Text = "APLICAR CONFIGURAÇÃO",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = mainFrame
    })
    
    local applyCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = applyBtn
    })
    
    applyBtn.MouseButton1Click:Connect(function()
        -- Aplicar configuração
        if SPEED_BOOST then
            toggleSpeedBoost(false)
            wait(0.1)
            toggleSpeedBoost(true)
        end
        
        -- Atualizar botão no menu principal se existir
        if mainHubGui then
            local configBtn = mainHubGui:FindFirstChild("ConfigSpeedBtn", true)
            if configBtn then
                configBtn.Text = "CONFIGURAR SPEED BOOST (" .. speedBoostMultiplier .. "x)"
            end
        end
        
        safeDestroy(screenGui)
        speedConfigGui = nil
        
        -- Reabrir o menu principal
        if mainHubGui then
            mainHubGui.Enabled = true
        end
    end)
    
    -- Fechar com ESC também
    local escConnection
    escConnection = UserInput.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Escape then
            safeDestroy(screenGui)
            speedConfigGui = nil
            if escConnection then
                escConnection:Disconnect()
            end
            
            -- Reabrir o menu principal
            if mainHubGui then
                mainHubGui.Enabled = true
            end
        end
    end)
    
    speedConfigGui = screenGui
    return screenGui
end

-- Função Speed Boost (atualizada para usar multiplicador personalizado)
local function applySpeedBoost(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Salvar velocidade original se não salvar ainda
    if originalWalkSpeed == 16 then
        originalWalkSpeed = humanoid.WalkSpeed
        originalJumpPower = humanoid.JumpPower or 50
    end
    
    -- Aplicar boost com multiplicador personalizado
    humanoid.WalkSpeed = originalWalkSpeed * speedBoostMultiplier
    humanoid.JumpPower = originalJumpPower * (1 + (speedBoostMultiplier - 1) * 0.3)
    
    -- Efeito visual baseado na velocidade
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        -- Remover efeitos antigos
        local oldParticles = rootPart:FindFirstChild("SpeedBoostParticles")
        if oldParticles then
            oldParticles:Destroy()
        end
        
        local oldLight = rootPart:FindFirstChild("SpeedBoostLight")
        if oldLight then
            oldLight:Destroy()
        end
        
        -- Criar partículas de velocidade
        local particles = Instance.new("ParticleEmitter")
        particles.Name = "SpeedBoostParticles"
        particles.Parent = rootPart
        particles.Color = ColorSequence.new(Color3.fromRGB(0, 255, 255))
        particles.Lifetime = NumberRange.new(0.5)
        particles.Rate = 30 * (speedBoostMultiplier / 3)
        particles.Rotation = NumberRange.new(0, 360)
        particles.RotSpeed = NumberRange.new(-100, 100)
        particles.Speed = NumberRange.new(2 * (speedBoostMultiplier / 3))
        particles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5 * (speedBoostMultiplier / 3)),
            NumberSequenceKeypoint.new(1, 0)
        })
        particles.Texture = "rbxassetid://242842396"
        particles.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        })
        particles.VelocityInheritance = 0.8
        particles.ZOffset = 2
        
        -- Criar luz
        local light = Instance.new("PointLight")
        light.Name = "SpeedBoostLight"
        light.Parent = rootPart
        light.Color = Color3.fromRGB(0, 200, 255)
        light.Brightness = 1.5 * (speedBoostMultiplier / 3)
        light.Range = 10 * (speedBoostMultiplier / 3)
        light.Shadows = false
    end
end

local function removeSpeedBoost(character)
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    
    -- Restaurar velocidade original
    humanoid.WalkSpeed = originalWalkSpeed
    humanoid.JumpPower = originalJumpPower
    
    -- Remover efeitos visuais
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart then
        local particles = rootPart:FindFirstChild("SpeedBoostParticles")
        if particles then
            particles:Destroy()
        end
        
        local light = rootPart:FindFirstChild("SpeedBoostLight")
        if light then
            light:Destroy()
        end
    end
end

local function toggleSpeedBoost(enabled)
    SPEED_BOOST = enabled
    
    if enabled then
        -- Aplicar ao personagem atual
        local character = localPlayer.Character
        if character then
            applySpeedBoost(character)
        end
        
        -- Conectar para personagens futuros
        if speedBoostConn then
            speedBoostConn:Disconnect()
        end
        
        speedBoostConn = localPlayer.CharacterAdded:Connect(function(char)
            wait(0.2)
            if SPEED_BOOST then
                applySpeedBoost(char)
            end
        end)
        
        -- Verificar periodicamente
        RunService.Heartbeat:Connect(function()
            if SPEED_BOOST then
                local character = localPlayer.Character
                if character then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.WalkSpeed ~= originalWalkSpeed * speedBoostMultiplier then
                        applySpeedBoost(character)
                    end
                end
            end
        end)
    else
        -- Remover do personagem atual
        local character = localPlayer.Character
        if character then
            removeSpeedBoost(character)
        end
        
        if speedBoostConn then
            speedBoostConn:Disconnect()
            speedBoostConn = nil
        end
    end
end

-- Criar piso abaixo do jogador ao pular
local function createJumpPlatform()
    if not JUMP_PLATFORM then return end
    
    local character = localPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Verificar cooldown
    local currentTime = tick()
    if currentTime - lastJumpTime < JUMP_COOLDOWN then
        return
    end
    lastJumpTime = currentTime
    
    -- Calcular posição do piso (5 unidades abaixo do personagem)
    local platformPosition = hrp.Position - Vector3.new(0, 5, 0)
    
    -- Criar piso
    local platform = Instance.new("Part")
    platform.Name = "JumpPlatform_" .. tick()
    platform.Size = Vector3.new(10, 1, 10)
    platform.Position = platformPosition
    platform.Anchored = true
    platform.CanCollide = true
    platform.Transparency = 0.3
    platform.Material = Enum.Material.Neon
    platform.Color = Color3.fromRGB(0, 255, 255)
    
    -- Adicionar brilho
    local glow = Instance.new("SurfaceLight")
    glow.Name = "PlatformGlow"
    glow.Brightness = 2
    glow.Range = 10
    glow.Color = Color3.fromRGB(0, 200, 255)
    glow.Parent = platform
    
    -- Adicionar outline
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Name = "PlatformOutline"
    selectionBox.Adornee = platform
    selectionBox.Color3 = Color3.fromRGB(255, 255, 255)
    selectionBox.LineThickness = 0.05
    selectionBox.Transparency = 0.5
    selectionBox.Parent = platform
    
    platform.Parent = Workspace
    
    -- Armazenar para limpeza posterior
    table.insert(platformParts, {
        part = platform,
        creationTime = tick()
    })
    
    -- Efeito de surgimento (animação)
    local originalSize = platform.Size
    platform.Size = Vector3.new(0.1, 0.1, 0.1)
    
    local tweenInfo = TweenInfo.new(
        0.3,
        Enum.EasingStyle.Quad,
        Enum.EasingDirection.Out
    )
    
    local tween = TweenService:Create(platform, tweenInfo, {Size = originalSize})
    tween:Play()
    
    -- Efeito de piscar
    local blinkTween = TweenService:Create(platform, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
        Transparency = 0.7
    })
    blinkTween:Play()
    
    -- Configurar para destruir após 4 segundos
    delay(PLATFORM_DURATION, function()
        if platform and platform.Parent then
            -- Efeito de desaparecimento
            local disappearTween = TweenService:Create(platform, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 1,
                Size = Vector3.new(0.1, 0.1, 0.1)
            })
            disappearTween:Play()
            
            wait(0.5)
            safeDestroy(platform)
            
            -- Remover da tabela
            for i, platData in ipairs(platformParts) do
                if platData.part == platform then
                    table.remove(platformParts, i)
                    break
                end
            end
        end
    end)
    
    return platform
end

-- Limpar todos os pisos criados
local function clearAllPlatforms()
    for _, platData in ipairs(platformParts) do
        if platData.part and platData.part.Parent then
            safeDestroy(platData.part)
        end
    end
    platformParts = {}
end

-- Ativar/desativar função de piso ao pular
local function toggleJumpPlatform(enabled)
    JUMP_PLATFORM = enabled
    
    if enabled then
        -- Conectar aos eventos de pulo
        jumpPlatformConnection = UserInput.JumpRequest:Connect(function()
            createJumpPlatform()
        end)
        
        -- Também conectar ao InputBegan para tecla Espaço
        if not infiniteJumpConnection then
            UserInput.InputBegan:Connect(function(input)
                if input.KeyCode == Enum.KeyCode.Space and JUMP_PLATFORM then
                    createJumpPlatform()
                end
            end)
        end
    else
        if jumpPlatformConnection then
            jumpPlatformConnection:Disconnect()
            jumpPlatformConnection = nil
        end
    end
end

-- ShiftLock helpers
local function applyShiftLockToCharacter(char)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if not shiftLockOrigSpeed[char] then
        shiftLockOrigSpeed[char] = humanoid.WalkSpeed or DEFAULT_WALK_SPEED
    end

    humanoid.WalkSpeed = SHIFT_WALK_SPEED
end

local function removeShiftLockFromCharacter(char)
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if shiftLockOrigSpeed[char] then
        humanoid.WalkSpeed = shiftLockOrigSpeed[char]
        shiftLockOrigSpeed[char] = nil
    else
        humanoid.WalkSpeed = DEFAULT_WALK_SPEED
    end
end

local function toggleShiftLock(enabled)
    SHIFT_LOCK = enabled

    if shiftLockConn then
        shiftLockConn:Disconnect()
        shiftLockConn = nil
    end
    if shiftLockCharacterConn then
        shiftLockCharacterConn:Disconnect()
        shiftLockCharacterConn = nil
    end

    if enabled then
        if localPlayer.Character then
            applyShiftLockToCharacter(localPlayer.Character)
        end

        shiftLockConn = RunService.Heartbeat:Connect(function()
            local char = localPlayer.Character
            if char and SHIFT_LOCK then
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.WalkSpeed ~= SHIFT_WALK_SPEED then
                    humanoid.WalkSpeed = SHIFT_WALK_SPEED
                end
            end
        end)

        shiftLockCharacterConn = localPlayer.CharacterAdded:Connect(function(char)
            wait(0.1)
            if SHIFT_LOCK then
                applyShiftLockToCharacter(char)
            end
        end)
    else
        if localPlayer.Character then
            removeShiftLockFromCharacter(localPlayer.Character)
        end
    end
end

-- Criar Hitbox ESP (caixas ao redor do personagem)
local function createHitboxESP(player, character)
    if not character or not character.Parent then return end
    if player == localPlayer then return end

    local hitboxFolder = Instance.new("Folder")
    hitboxFolder.Name = "HitboxESP_" .. player.UserId
    hitboxFolder.Parent = Workspace

    -- Criar caixas para partes principais do corpo
    local bodyParts = {
        {name = "Head", size = Vector3.new(2, 2, 2), color = Color3.fromRGB(255, 0, 0)},
        {name = "UpperTorso", size = Vector3.new(2, 1.5, 1), color = Color3.fromRGB(0, 255, 0)},
        {name = "LowerTorso", size = Vector3.new(2, 1, 1), color = Color3.fromRGB(0, 200, 200)},
        {name = "HumanoidRootPart", size = Vector3.new(2, 2, 2), color = Color3.fromRGB(255, 255, 0)}
    }

    local hitboxes = {}

    for _, partInfo in pairs(bodyParts) do
        local bodyPart = character:FindFirstChild(partInfo.name)
        if bodyPart then
            local hitbox = safeCreate("BoxHandleAdornment", {
                Name = "Hitbox_" .. partInfo.name,
                Adornee = bodyPart,
                Size = partInfo.size,
                Color3 = partInfo.color,
                Transparency = 0.3,
                ZIndex = 10,
                AlwaysOnTop = true,
                Visible = true,
                Parent = hitboxFolder
            })

            table.insert(hitboxes, {part = bodyPart, hitbox = hitbox})
        end
    end

    -- Criar caixa de bounding box ao redor de todo o personagem
    local boundingBox = safeCreate("BoxHandleAdornment", {
        Name = "BoundingBox",
        Adornee = character,
        Size = Vector3.new(4, 6, 4),
        Color3 = Color3.fromRGB(255, 100, 255),
        Transparency = 0.7,
        ZIndex = 5,
        AlwaysOnTop = true,
        Visible = true,
        Parent = hitboxFolder
    })

    -- Atualizar posições das hitboxes
    local updateConnection = RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then
            updateConnection:Disconnect()
            safeDestroy(hitboxFolder)
            return
        end

        -- Atualizar bounding box para envolver todo o personagem
        if boundingBox then
            pcall(function()
                boundingBox.Adornee = character
            end)
        end

        -- Atualizar hitboxes individuais
        for _, hitboxData in pairs(hitboxes) do
            if hitboxData.hitbox and hitboxData.part then
                pcall(function()
                    hitboxData.hitbox.Adornee = hitboxData.part
                end)
            end
        end
    end)

    -- Armazenar dados
    espData[player.UserId] = espData[player.UserId] or {}
    espData[player.UserId].hitboxFolder = hitboxFolder
    espData[player.UserId].hitboxUpdate = updateConnection

    return hitboxFolder
end

-- Criar ESP normal (Highlight + Billboard)
local function createESPForCharacter(player, character)
    if not character or not character.Parent then return end
    if player == localPlayer then return end

    local userId = player.UserId

    -- Limpar ESP antigo
    if espData[userId] then
        if espData[userId].highlight then safeDestroy(espData[userId].highlight) end
        if espData[userId].billboard then safeDestroy(espData[userId].billboard) end
        if espData[userId].updateConnection then espData[userId].updateConnection:Disconnect() end
    end

    -- Criar Highlight
    local highlight = safeCreate("Highlight", {
        Name = "ESP_Highlight_" .. userId,
        Adornee = character,
        Enabled = true,
        FillColor = Color3.fromRGB(255, 50, 50),
        FillTransparency = 0.5,
        OutlineColor = Color3.fromRGB(255, 0, 0),
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
        Parent = Workspace
    })

    -- Criar Billboard
    local hrp = character:FindFirstChild("HumanoidRootPart") or
                character:FindFirstChild("UpperTorso") or
                character:FindFirstChild("Torso") or
                character:FindFirstChild("Head")

    local billboard = nil
    if hrp then
        billboard = safeCreate("BillboardGui", {
            Name = "ESP_Billboard_" .. userId,
            Adornee = hrp,
            Size = UDim2.new(0, 200, 0, 50),
            StudsOffset = Vector3.new(0, 3, 0),
            AlwaysOnTop = true,
            MaxDistance = 1000,
            Parent = playerGui
        })

        if billboard then
            -- Nome do jogador
            local nameLabel = safeCreate("TextLabel", {
                Name = "NameLabel",
                Size = UDim2.new(1, -10, 0.4, 0),
                Position = UDim2.new(0, 5, 0, 0),
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(255, 255, 255),
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.SourceSansBold,
                TextSize = 16,
                Text = player.Name,
                Parent = billboard
            })

            -- Distância e vida
            local infoLabel = safeCreate("TextLabel", {
                Name = "InfoLabel",
                Size = UDim2.new(1, -10, 0.3, 0),
                Position = UDim2.new(0, 5, 0.4, 0),
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(200, 200, 255),
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.SourceSans,
                TextSize = 14,
                Text = "0m | 100 HP",
                Parent = billboard
            })

            -- Tool (arma que está segurando)
            local toolLabel = safeCreate("TextLabel", {
                Name = "ToolLabel",
                Size = UDim2.new(1, -10, 0.3, 0),
                Position = UDim2.new(0, 5, 0.7, 0),
                BackgroundTransparency = 1,
                TextColor3 = Color3.fromRGB(255, 200, 100),
                TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
                TextStrokeTransparency = 0.3,
                Font = Enum.Font.SourceSans,
                TextSize = 12,
                Text = "Arma: Nenhuma",
                Parent = billboard
            })

            -- Atualizar informações
            local updateConnection = RunService.Heartbeat:Connect(function()
                if not character or not character.Parent then
                    updateConnection:Disconnect()
                    return
                end

                pcall(function()
                    if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        local myPos = localPlayer.Character.HumanoidRootPart.Position
                        local theirPos = character:FindFirstChild("HumanoidRootPart") and
                                        character.HumanoidRootPart.Position or character.PrimaryPart.Position
                        local dist = (myPos - theirPos).Magnitude

                        local humanoid = character:FindFirstChildOfClass("Humanoid")
                        local health = humanoid and math.floor(humanoid.Health) or 100
                        local maxHealth = humanoid and math.floor(humanoid.MaxHealth) or 100

                        infoLabel.Text = string.format("[%.0fm] | %d/%d HP", dist, health, maxHealth)

                        local toolText = "Arma: Nenhuma"
                        for _, item in pairs(character:GetChildren()) do
                            if item:IsA("Tool") then
                                toolText = "Arma: " .. item.Name
                                break
                            end
                        end
                        toolLabel.Text = toolText

                        if humanoid then
                            local healthPercent = humanoid.Health / humanoid.MaxHealth
                            if healthPercent < 0.3 then
                                highlight.FillColor = Color3.fromRGB(255, 0, 0)
                            elseif healthPercent < 0.6 then
                                highlight.FillColor = Color3.fromRGB(255, 165, 0)
                            else
                                highlight.FillColor = Color3.fromRGB(0, 255, 0)
                            end
                        end
                    end
                end)
            end)

            espData[userId] = espData[userId] or {}
            espData[userId].updateConnection = updateConnection
        end
    end

    if HITBOX_ESP then
        createHitboxESP(player, character)
    end

    espData[userId] = espData[userId] or {}
    espData[userId].highlight = highlight
    espData[userId].billboard = billboard
    espData[userId].player = player
    espData[userId].character = character

    character.AncestryChanged:Connect(function(_, parent)
        if not parent then
            if espData[userId] then
                if espData[userId].highlight then safeDestroy(espData[userId].highlight) end
                if espData[userId].billboard then safeDestroy(espData[userId].billboard) end
                if espData[userId].hitboxFolder then safeDestroy(espData[userId].hitboxFolder) end
                if espData[userId].updateConnection then espData[userId].updateConnection:Disconnect() end
                if espData[userId].hitboxUpdate then espData[userId].hitboxUpdate:Disconnect() end
                espData[userId] = nil
            end
        end
    end)
end

-- Remover ESP do jogador
local function removeESPForPlayer(player)
    local userId = player.UserId
    if espData[userId] then
        if espData[userId].highlight then safeDestroy(espData[userId].highlight) end
        if espData[userId].billboard then safeDestroy(espData[userId].billboard) end
        if espData[userId].hitboxFolder then safeDestroy(espData[userId].hitboxFolder) end
        if espData[userId].updateConnection then espData[userId].updateConnection:Disconnect() end
        if espData[userId].hitboxUpdate then espData[userId].hitboxUpdate:Disconnect() end
        espData[userId] = nil
    end
end

-- Ativar/Desativar Hitbox ESP para todos
local function toggleHitboxESP(enabled)
    HITBOX_ESP = enabled

    if enabled then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                createHitboxESP(player, player.Character)
            end
        end
    else
        for userId, data in pairs(espData) do
            if data.hitboxFolder then
                safeDestroy(data.hitboxFolder)
                data.hitboxFolder = nil
            end
            if data.hitboxUpdate then
                data.hitboxUpdate:Disconnect()
                data.hitboxUpdate = nil
            end
        end
    end
end

-- Reconstruir todos ESPs
local function rebuildAllESP()
    for userId, data in pairs(espData) do
        if data.highlight then safeDestroy(data.highlight) end
        if data.billboard then safeDestroy(data.billboard) end
        if data.hitboxFolder then safeDestroy(data.hitboxFolder) end
        if data.updateConnection then data.updateConnection:Disconnect() end
        if data.hitboxUpdate then data.hitboxUpdate:Disconnect() end
    end
    espData = {}

    if ESP_ENABLED then
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                createESPForCharacter(player, player.Character)
            end
        end
    end
end

-- Configurar jogador para ESP
local function setupPlayer(player)
    if player == localPlayer then return end

    if player.Character and ESP_ENABLED then
        createESPForCharacter(player, player.Character)
    end

    player.CharacterAdded:Connect(function(char)
        wait(0.3)
        if ESP_ENABLED then
            createESPForCharacter(player, char)
        end
    end)

    player.CharacterRemoving:Connect(function()
        removeESPForPlayer(player)
    end)
end

-- Inicializar ESP
for _, player in pairs(Players:GetPlayers()) do
    setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
    removeESPForPlayer(player)
end)

-- PULO INFINITO
local function doInfiniteJump()
    if not INFINITE_JUMP then return end

    local character = localPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    pcall(function()
        humanoid.Jump = true

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.Velocity = Vector3.new(hrp.Velocity.X, JUMP_IMPULSE_Y, hrp.Velocity.Z)
        end
        
        -- Criar piso se a opção estiver ativada
        if JUMP_PLATFORM then
            createJumpPlatform()
        end
    end)
end

local function toggleInfiniteJump(enabled)
    INFINITE_JUMP = enabled

    if enabled then
        -- Conexão para pulo contínuo
        infiniteJumpConnection = RunService.Heartbeat:Connect(function()
            if not INFINITE_JUMP then return end

            if UserInput:IsKeyDown(Enum.KeyCode.Space) then
                doInfiniteJump()
            end
        end)

        -- Conexões adicionais
        UserInput.JumpRequest:Connect(function()
            if INFINITE_JUMP then doInfiniteJump() end
        end)

        UserInput.InputBegan:Connect(function(input)
            if INFINITE_JUMP and input.KeyCode == Enum.KeyCode.Space then
                doInfiniteJump()
            end
        end)
    else
        if infiniteJumpConnection then
            infiniteJumpConnection:Disconnect()
            infiniteJumpConnection = nil
        end
    end
end

-- Ativar Infinite Jump se configurado
if INFINITE_JUMP then
    toggleInfiniteJump(true)
end

-- GOD MODE
local function enableGodForCharacter(character)
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    pcall(function()
        humanoid.MaxHealth = GOD_MAX_HEALTH
        humanoid.Health = GOD_MAX_HEALTH
    end)

    local conn1 = humanoid.HealthChanged:Connect(function(newHealth)
        pcall(function()
            if humanoid and newHealth < GOD_MAX_HEALTH then
                humanoid.Health = GOD_MAX_HEALTH
            end
        end)
    end)

    local conn2 = RunService.Heartbeat:Connect(function()
        pcall(function()
            if humanoid and humanoid.Health < GOD_MAX_HEALTH then
                humanoid.Health = GOD_MAX_HEALTH
            end
        end)
    end)

    godConns[character] = {conn1, conn2}
end

local function disableGodForCharacter(character)
    local conns = godConns[character]
    if conns then
        for _, conn in pairs(conns) do
            if conn then pcall(function() conn:Disconnect() end) end
        end
        godConns[character] = nil
    end
end

-- ANTI-RAGDOLL
local function enableAntiRagdollForCharacter(character)
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local conn1 = RunService.Heartbeat:Connect(function()
        pcall(function()
            if humanoid then
                if humanoid:GetState() == Enum.HumanoidStateType.Ragdoll or
                   humanoid:GetState() == Enum.HumanoidStateType.FallingDown then
                    humanoid:ChangeState(Enum.HumanoidStateType.Running)
                end

                if humanoid.PlatformStand then
                    humanoid.PlatformStand = false
                end

                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, hrp.Orientation.Y, 0)
                    hrp.Velocity = Vector3.new(hrp.Velocity.X, math.min(hrp.Velocity.Y, 50), hrp.Velocity.Z)
                end
            end
        end)
    end)

    antiRagdollConns[character] = {conn1}
end

local function disableAntiRagdollForCharacter(character)
    local conns = antiRagdollConns[character]
    if conns then
        for _, conn in pairs(conns) do
            if conn then pcall(function() conn:Disconnect() end) end
        end
        antiRagdollConns[character] = nil
    end
end

-- Configurar personagem local
local function setupLocalCharacter(char)
    wait(0.2)

    if GOD_MODE then enableGodForCharacter(char) end
    if ANTI_RAGDOLL then enableAntiRagdollForCharacter(char) end

    if SHIFT_LOCK then
        wait(0.1)
        applyShiftLockToCharacter(char)
    end
    
    if JUMP_PLATFORM then
        toggleJumpPlatform(true)
    end
    
    if SPEED_BOOST then
        applySpeedBoost(char)
    end

    char.AncestryChanged:Connect(function(_, parent)
        if not parent then
            disableGodForCharacter(char)
            disableAntiRagdollForCharacter(char)
            removeSpeedBoost(char)
        end
    end)
end

if localPlayer.Character then
    setupLocalCharacter(localPlayer.Character)
end

localPlayer.CharacterAdded:Connect(function(char)
    setupLocalCharacter(char)
end)

-- INTERFACE GRÁFICA
local function createHub()
    local existing = playerGui:FindFirstChild("Lznx7_Hub")
    if existing then safeDestroy(existing) end

    local screenGui = safeCreate("ScreenGui", {
        Name = "Lznx7_Hub",
        ResetOnSpawn = false,
        DisplayOrder = 9999,
        Parent = playerGui
    })
    
    mainHubGui = screenGui

    local mainFrame = safeCreate("Frame", {
        Name = "MainFrame",
        Size = UDim2.new(0, 320, 0, 340),  -- Aumentado para caber AimLock
        Position = UDim2.new(0.5, -160, 0.5, -170),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(20, 20, 25),
        BorderSizePixel = 0,
        Parent = screenGui
    })

    local corner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12),
        Parent = mainFrame
    })

    -- Título
    local title = safeCreate("TextLabel", {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(40, 40, 50),
        BorderSizePixel = 0,
        Text = "lznx7 Hub - AimLock + Speed",
        TextColor3 = Color3.fromRGB(255, 100, 100),
        Font = Enum.Font.SourceSansBold,
        TextSize = 18,
        Parent = mainFrame
    })

    local titleCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 12, 0, 0),
        Parent = title
    })

    -- Status
    local status = safeCreate("TextLabel", {
        Name = "Status",
        Size = UDim2.new(1, -20, 0, 25),
        Position = UDim2.new(0, 10, 0, 45),
        BackgroundTransparency = 1,
        Text = "Pressione F para abrir/fechar",
        TextColor3 = Color3.fromRGB(180, 180, 255),
        Font = Enum.Font.SourceSans,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = mainFrame
    })

    -- Botões em 5 linhas
    local buttons = {
        {name = "ESP", x = 0.03, y = 75, default = ESP_ENABLED, color = Color3.fromRGB(255, 100, 100)},
        {name = "InfJump", x = 0.53, y = 75, default = INFINITE_JUMP, color = Color3.fromRGB(100, 255, 100)},
        {name = "HitboxESP", x = 0.03, y = 115, default = HITBOX_ESP, color = Color3.fromRGB(100, 100, 255)},
        {name = "AntiRagdoll", x = 0.53, y = 115, default = ANTI_RAGDOLL, color = Color3.fromRGB(255, 255, 100)},
        {name = "GodMode", x = 0.03, y = 155, default = GOD_MODE, color = Color3.fromRGB(255, 100, 255)},
        {name = "ShiftLock", x = 0.53, y = 155, default = SHIFT_LOCK, color = Color3.fromRGB(150, 200, 255)},
        {name = "PisoPulo", x = 0.03, y = 195, default = JUMP_PLATFORM, color = Color3.fromRGB(0, 255, 255)},
        {name = "SpeedBoost", x = 0.53, y = 195, default = SPEED_BOOST, color = Color3.fromRGB(255, 150, 0)},
        {name = "AimLock", x = 0.03, y = 235, default = AIMLOCK_ENABLED, color = Color3.fromRGB(200, 50, 50)}  -- Novo botão AimLock
    }

    local buttonInstances = {}

    for _, btnInfo in pairs(buttons) do
        local btn = safeCreate("TextButton", {
            Name = btnInfo.name .. "_Btn",
            Size = UDim2.new(0.44, 0, 0, 35),
            Position = UDim2.new(btnInfo.x, 0, 0, btnInfo.y),
            BackgroundColor3 = btnInfo.default and btnInfo.color or Color3.fromRGB(60, 60, 70),
            Text = btnInfo.name .. ": " .. (btnInfo.default and "ON" or "OFF"),
            TextColor3 = Color3.fromRGB(255, 255, 255),
            Font = Enum.Font.SourceSansBold,
            TextSize = 13,
            Parent = mainFrame
        })

        local btnCorner = safeCreate("UICorner", {
            CornerRadius = UDim.new(0, 8),
            Parent = btn
        })

        buttonInstances[btnInfo.name] = btn
    end
    
    -- Botão de Configuração do Speed Boost
    local configSpeedBtn = safeCreate("TextButton", {
        Name = "ConfigSpeedBtn",
        Size = UDim2.new(0.44, 0, 0, 32),
        Position = UDim2.new(0.03, 0, 0, 275),
        BackgroundColor3 = Color3.fromRGB(100, 100, 200),
        Text = "CONFIG SPEED",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 12,
        Parent = mainFrame
    })
    
    local configSpeedCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = configSpeedBtn
    })
    
    -- Botão de Configuração do AimLock
    local configAimBtn = safeCreate("TextButton", {
        Name = "ConfigAimBtn",
        Size = UDim2.new(0.44, 0, 0, 32),
        Position = UDim2.new(0.53, 0, 0, 275),
        BackgroundColor3 = Color3.fromRGB(200, 50, 50),
        Text = "CONFIG AIMLOCK",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 12,
        Parent = mainFrame
    })
    
    local configAimCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = configAimBtn
    })

    -- Botão Fechar
    local closeBtn = safeCreate("TextButton", {
        Name = "Close_Btn",
        Size = UDim2.new(0.94, 0, 0, 32),
        Position = UDim2.new(0.03, 0, 0, 315),
        BackgroundColor3 = Color3.fromRGB(200, 60, 60),
        Text = "FECHAR MENU",
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.SourceSansBold,
        TextSize = 14,
        Parent = mainFrame
    })

    local closeCorner = safeCreate("UICorner", {
        CornerRadius = UDim.new(0, 8),
        Parent = closeBtn
    })

    -- Funções dos botões
    buttonInstances.ESP.MouseButton1Click:Connect(function()
        ESP_ENABLED = not ESP_ENABLED
        if ESP_ENABLED then
            buttonInstances.ESP.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            buttonInstances.ESP.Text = "ESP: ON"
            rebuildAllESP()
            status.Text = "ESP Normal ATIVADO"
        else
            buttonInstances.ESP.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.ESP.Text = "ESP: OFF"
            for userId, data in pairs(espData) do
                if data.highlight then safeDestroy(data.highlight) end
                if data.billboard then safeDestroy(data.billboard) end
                if data.updateConnection then data.updateConnection:Disconnect() end
            end
            espData = {}
            status.Text = "ESP Desativado"
        end
    end)

    buttonInstances.InfJump.MouseButton1Click:Connect(function()
        INFINITE_JUMP = not INFINITE_JUMP
        if INFINITE_JUMP then
            buttonInstances.InfJump.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
            buttonInstances.InfJump.Text = "InfJump: ON"
            toggleInfiniteJump(true)
            status.Text = "Pulo Infinito ATIVADO - Mantenha Espaço"
        else
            buttonInstances.InfJump.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.InfJump.Text = "InfJump: OFF"
            toggleInfiniteJump(false)
            status.Text = "Pulo Infinito Desativado"
        end
    end)

    buttonInstances.HitboxESP.MouseButton1Click:Connect(function()
        HITBOX_ESP = not HITBOX_ESP
        if HITBOX_ESP then
            buttonInstances.HitboxESP.BackgroundColor3 = Color3.fromRGB(100, 100, 255)
            buttonInstances.HitboxESP.Text = "HitboxESP: ON"
            status.Text = "Hitbox ESP ATIVADO - Caixas coloridas"
            toggleHitboxESP(true)
        else
            buttonInstances.HitboxESP.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.HitboxESP.Text = "HitboxESP: OFF"
            status.Text = "Hitbox ESP Desativado"
            toggleHitboxESP(false)
        end
    end)

    buttonInstances.AntiRagdoll.MouseButton1Click:Connect(function()
        ANTI_RAGDOLL = not ANTI_RAGDOLL
        if ANTI_RAGDOLL then
            buttonInstances.AntiRagdoll.BackgroundColor3 = Color3.fromRGB(255, 255, 100)
            buttonInstances.AntiRagdoll.Text = "AntiRagdoll: ON"
            status.Text = "Anti-Ragdoll ATIVADO"
            if localPlayer.Character then enableAntiRagdollForCharacter(localPlayer.Character) end
        else
            buttonInstances.AntiRagdoll.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.AntiRagdoll.Text = "AntiRagdoll: OFF"
            status.Text = "Anti-Ragdoll Desativado"
            if localPlayer.Character then disableAntiRagdollForCharacter(localPlayer.Character) end
        end
    end)

    buttonInstances.GodMode.MouseButton1Click:Connect(function()
        GOD_MODE = not GOD_MODE
        if GOD_MODE then
            buttonInstances.GodMode.BackgroundColor3 = Color3.fromRGB(255, 100, 255)
            buttonInstances.GodMode.Text = "GodMode: ON"
            status.Text = "God Mode ATIVADO"
            if localPlayer.Character then enableGodForCharacter(localPlayer.Character) end
        else
            buttonInstances.GodMode.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.GodMode.Text = "GodMode: OFF"
            status.Text = "God Mode Desativado"
            if localPlayer.Character then disableGodForCharacter(localPlayer.Character) end
        end
    end)

    buttonInstances.ShiftLock.MouseButton1Click:Connect(function()
        SHIFT_LOCK = not SHIFT_LOCK
        if SHIFT_LOCK then
            buttonInstances.ShiftLock.BackgroundColor3 = Color3.fromRGB(150, 200, 255)
            buttonInstances.ShiftLock.Text = "ShiftLock: ON"
            status.Text = "Shift Lock ATIVADO - Sprint travado"
            toggleShiftLock(true)
        else
            buttonInstances.ShiftLock.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.ShiftLock.Text = "ShiftLock: OFF"
            status.Text = "Shift Lock Desativado"
            toggleShiftLock(false)
        end
    end)

    buttonInstances.PisoPulo.MouseButton1Click:Connect(function()
        JUMP_PLATFORM = not JUMP_PLATFORM
        if JUMP_PLATFORM then
            buttonInstances.PisoPulo.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
            buttonInstances.PisoPulo.Text = "PisoPulo: ON"
            status.Text = "Piso ao Pular ATIVADO - 4 segundos"
            toggleJumpPlatform(true)
        else
            buttonInstances.PisoPulo.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.PisoPulo.Text = "PisoPulo: OFF"
            status.Text = "Piso ao Pular Desativado"
            toggleJumpPlatform(false)
        end
    end)

    buttonInstances.SpeedBoost.MouseButton1Click:Connect(function()
        SPEED_BOOST = not SPEED_BOOST
        if SPEED_BOOST then
            buttonInstances.SpeedBoost.BackgroundColor3 = Color3.fromRGB(255, 150, 0)
            buttonInstances.SpeedBoost.Text = "SpeedBoost: ON"
            status.Text = "Speed Boost ATIVADO - " .. speedBoostMultiplier .. "x"
            toggleSpeedBoost(true)
        else
            buttonInstances.SpeedBoost.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.SpeedBoost.Text = "SpeedBoost: OFF"
            status.Text = "Speed Boost Desativado"
            toggleSpeedBoost(false)
        end
    end)

    buttonInstances.AimLock.MouseButton1Click:Connect(function()
        AIMLOCK_ENABLED = not AIMLOCK_ENABLED
        if AIMLOCK_ENABLED then
            buttonInstances.AimLock.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            buttonInstances.AimLock.Text = "AimLock: ON"
            status.Text = "AimLock ATIVADO - Pressione " .. tostring(AIMLOCK_KEY)
            toggleAimLock(true)
        else
            buttonInstances.AimLock.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            buttonInstances.AimLock.Text = "AimLock: OFF"
            status.Text = "AimLock Desativado"
            toggleAimLock(false)
        end
    end)
    
    -- Botão de Configuração Speed
    configSpeedBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
        wait(0.1)
        createSpeedConfigGui()
    end)
    
    -- Botão de Configuração AimLock
    configAimBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
        wait(0.1)
        createAimConfigGui()
    end)

    closeBtn.MouseButton1Click:Connect(function()
        screenGui.Enabled = false
    end)

    -- Tecla F para abrir/fechar
    UserInput.InputBegan:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.F then
            screenGui.Enabled = not screenGui.Enabled
            
            -- Fechar painéis abertos
            if speedConfigGui then
                safeDestroy(speedConfigGui)
                speedConfigGui = nil
            end
            
            if aimConfigGui then
                safeDestroy(aimConfigGui)
                aimConfigGui = nil
            end
        end
        
        -- Tecla para ativar AimLock (mantenha pressionada)
        if input.KeyCode == AIMLOCK_KEY then
            if not AIMLOCK_ENABLED then
                local wasEnabled = AIMLOCK_ENABLED
                toggleAimLock(true)
                
                -- Manter ativo enquanto a tecla estiver pressionada
                local connection
                connection = UserInput.InputEnded:Connect(function(endInput)
                    if endInput.KeyCode == AIMLOCK_KEY then
                        if not wasEnabled then
                            toggleAimLock(false)
                        end
                        if connection then
                            connection:Disconnect()
                        end
                    end
                end)
            end
        end
    end)

    return screenGui
end

-- Criar GUI
wait(1)
local success, gui = pcall(createHub)
if success and gui then
    print("[lznx7] Hub criado com sucesso!")
    print("[lznx7] Pressione F para abrir/fechar o menu")
    print("[lznx7] AimLock: Pressione " .. tostring(AIMLOCK_KEY) .. " para mirar automaticamente")
else
    warn("[lznx7] Erro ao criar GUI")
end

-- Notificação
local function showNotification(message)
    pcall(function()
        local notif = Instance.new("ScreenGui")
        notif.Name = "Notification"
        notif.Parent = playerGui

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 350, 0, 80)
        frame.Position = UDim2.new(0.5, -175, 0.8, 0)
        frame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        frame.BorderSizePixel = 0
        frame.Parent = notif

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 1, -20)
        label.Position = UDim2.new(0, 10, 0, 10)
        label.BackgroundTransparency = 1
        label.Text = message
        label.TextColor3 = Color3.fromRGB(255, 255, 100)
        label.Font = Enum.Font.SourceSansBold
        label.TextSize = 16
        label.TextWrapped = true
        label.Parent = frame

        wait(4)
        notif:Destroy()
    end)
end

showNotification("lznx7 Hub - AimLock + Speed\n• Pressione F para menu\n• AimLock: " .. tostring(AIMLOCK_KEY) .. " para mira automática\n• Configure opções nos botões CONFIG")

print("[lznx7] Sistema completo carregado!")
print("[lznx7] Features: ESP, Hitbox ESP, Infinite Jump, Anti-Ragdoll, God Mode")
print("[lznx7] ShiftLock, Piso ao Pular (4s), Speed Boost (1-15x), AimLock")

-- Conectar ao evento de pulo inicialmente
if JUMP_PLATFORM then
    toggleJumpPlatform(true)
end

-- Ativar Speed Boost se configurado
if SPEED_BOOST then
    toggleSpeedBoost(true)
end

-- Ativar AimLock se configurado
if AIMLOCK_ENABLED then
    toggleAimLock(true)
end

-- Loop para limpeza periódica
RunService.Heartbeat:Connect(function()
    -- Limpar pisos muito antigos
    for i = #platformParts, 1, -1 do
        local platData = platformParts[i]
        if platData and platData.part then
            if tick() - platData.creationTime > PLATFORM_DURATION + 6 then
                safeDestroy(platData.part)
                table.remove(platformParts, i)
            end
        end
    end
end)

-- Controle com tecla ESC
UserInput.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Escape then
        -- Fechar painel de configuração de velocidade
        if speedConfigGui then
            safeDestroy(speedConfigGui)
            speedConfigGui = nil
            
            if mainHubGui then
                mainHubGui.Enabled = true
            end
        -- Fechar painel de configuração do AimLock
        elseif aimConfigGui then
            safeDestroy(aimConfigGui)
            aimConfigGui = nil
            
            if mainHubGui then
                mainHubGui.Enabled = true
            end
        -- Fechar menu principal
        elseif mainHubGui and mainHubGui.Enabled then
            mainHubGui.Enabled = false
        end
    end
end)

Feito por lucas7motasouza
