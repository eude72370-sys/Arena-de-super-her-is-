-- SYSTEM MENU | Delta Executor
-- Menu com quadrado por jogador (foto + nick), 3 toques = farm,
-- Auto Ataque/E/R, teleporte para posição salva e as duas bases.

-- ========== DATA DE EXPIRAÇÃO ==========
local ano_expira = 2026
local mes_expira = 12 -- Dezembro
local dia_expira = 3  -- Dia 3
local hora_expira = 18
local min_expira = 0
local fuso_horas = -3 -- seu fuso (Fortaleza = -3)

-- Converte a data para timestamp (já descontando o fuso)
local data_limite = DateTime.fromUniversalTime(
	ano_expira, mes_expira, dia_expira, hora_expira, min_expira, 0
).UnixTimestamp - fuso_horas * 3600

local function expirou()
	return DateTime.now().UnixTimestamp > data_limite
end

if expirou() then
	print("Este script expirou! Entre em contato com o criador.")
	return -- para tudo: nenhum menu aparece
end

--// SERVIÇOS
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer

-- ========== CONFIGURAÇÃO ==========
local VERSAO = "v1.8"
local TITULO = "SYSTEM MENU " .. VERSAO

local CONFIG = {
	SAFE_POS = Vector3.new(-118.3, 456.8, -253.1), -- posição salva (foto)
	OFFSET_Y = -5,       -- altura em relação ao alvo durante o farm
	NEAR_RADIUS = 30,    -- raio do "farma jogador próximo"
	SKILL_DELAY = 0.2,   -- intervalo entre os toques automáticos
	VOID_Y = 390,        -- abaixo disso o jogador está no void (farm nele para)
}

-- ADMs (criadores do script): ninguém farma neles.
-- Só os próprios ADMs podem, ligando o interruptor dentro do menu 👑
local ADMS = {
	["10_mil414"] = true,
	["minato1234005"] = true,
}

-- Base do lobby: criada toda vez que você nasce (invisível). Quem está dentro = lobby
local BASE = {
	pos = Vector3.new(192.0, 444.5, -926.4),
	tamanho = Vector3.new(126.0, 88.0, 364.0), -- L, E, C
	cor = Color3.fromRGB(0, 150, 255),
	transparencia = 1, -- 1 = invisível
}

-- Base de segurança: criada ao sair do lobby, no X/Z de onde você nasceu no mapa
local BASE_SEGURA = {
	altura = 390, -- altura (Y) da base de cima (se ainda travar ao andar, diminua de 1 em 1)
	tamanho = Vector3.new(2048, 5, 2048), -- L, E, C
	camadas = 5, -- bases extras logo abaixo da original (por causa do ragdoll)
	cor = Color3.fromRGB(0, 150, 255),
	transparencia = 1, -- 1 = invisível (use 0.7 para ver)
	pes = 3, -- distância do centro do corpo até os pés
	folga = 1, -- tolerância do toque
	espera = 1.5, -- segundos sem checar o toque depois de voltar
}

local MENU = {
	largura = 175,
	altura = 200,
	posicao = UDim2.new(0, 25, 0, 8), -- X=25 | Y=8
	raio = 12,
	transparencia = 0.05,
}

local BARRA = {altura = 28, transparencia = 0.3}
local CARD = {largura = 76, altura = 84, foto = 56, espaco = 6, borda = 2}
local TOQUES = {quantidade = 3, tempo = 0.6} -- 3 toques em até 0.6s

local COR = {
	fundo = Color3.fromRGB(15, 15, 25),
	card = Color3.fromRGB(25, 25, 40),
	texto = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(150, 150, 180),
	azul = Color3.fromRGB(0, 150, 255),
	laranja = Color3.fromRGB(255, 150, 0),
	verde = Color3.fromRGB(0, 200, 100),
	roxo = Color3.fromRGB(200, 50, 200),
	ouro = Color3.fromRGB(255, 200, 0),
	cinza = Color3.fromRGB(90, 90, 110),
	on = Color3.fromRGB(0, 180, 80),
	onTexto = Color3.fromRGB(0, 110, 50),
	fechar = Color3.fromRGB(200, 50, 50),
	minimizar = Color3.fromRGB(200, 150, 0),
}

-- ========== ESTADO ==========
local vivo = true
local conexoes = {}
local target = nil
local randomOn, nearOn = false, false
local tpAoMatar = false -- teleportar para a posição salva quando o alvo morrer
local ultimaPosAlvo = nil
local auto = {attack = false, e = false, r = false}
local cartoes = {}
local cache = {}
local baseParte = nil   -- base do lobby
local baseSegura = nil  -- {parte, cf, partes, todas}
local ultimoChao = nil  -- {pos} última posição firme do mapa em que você pisou
local esperaBase = 0    -- até quando a base de segurança não checa o toque
local proximaBusca = 0  -- limita a busca de alvo nos modos automáticos
local paginaAtual = "menu"
local admFarmOn = false -- só para ADMs: liga/desliga o farm nos ADMs
local refresh           -- definida mais abaixo

-- ========== FUNÇÕES AUXILIARES ==========
-- Guarda a conexão para poder desligar tudo ao fechar o menu
local function ligar(sinal, fn)
	local c = sinal:Connect(fn)
	table.insert(conexoes, c)
	return c
end

-- Cria uma instância já com propriedades e pai
local function criar(classe, props, pai)
	local obj = Instance.new(classe)
	for k, v in pairs(props) do obj[k] = v end
	obj.Parent = pai
	return obj
end

local function arredondar(obj, raio)
	criar("UICorner", {CornerRadius = UDim.new(0, raio or 8)}, obj)
end

-- Pulinho ao tocar
local function efeitoClique(obj)
	local escala = obj:FindFirstChild("UIScale") or criar("UIScale", {}, obj)
	TweenService:Create(escala, TweenInfo.new(0.08), {Scale = 1.1}):Play()
	task.delay(0.08, function()
		TweenService:Create(escala, TweenInfo.new(0.08), {Scale = 1}):Play()
	end)
end

-- Arrastar o menu pela barra (toque ou mouse)
local function arrastar(handle, alvo)
	local ativo, inicio, posIni = false, nil, nil
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseButton1 then
			ativo, inicio, posIni = true, i.Position, alvo.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then ativo = false end
			end)
		end
	end)
	ligar(UIS.InputChanged, function(i)
		if ativo and (i.UserInputType == Enum.UserInputType.Touch
			or i.UserInputType == Enum.UserInputType.MouseMovement) then
			local d = i.Position - inicio
			alvo.Position = UDim2.new(posIni.X.Scale, posIni.X.Offset + d.X,
				posIni.Y.Scale, posIni.Y.Offset + d.Y)
		end
	end)
end

-- Nome do jogador: se o nick for igual ao nome mostra só um
local function textoNome(plr)
	if plr.DisplayName == plr.Name then return plr.Name end
	return plr.DisplayName .. "\n@" .. plr.Name
end

-- Foto do jogador (carrega em segundo plano)
local function carregarFoto(plr, label)
	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, plr.UserId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and label.Parent then label.Image = img end
	end)
end

-- ADMs
local function ehAdm(plr)
	return ADMS[string.lower(plr.Name)] == true
end

local souAdm = ehAdm(LocalPlayer)

local function admLiberado() -- farm nos ADMs só vale para ADM com o interruptor ligado
	return souAdm and admFarmOn
end

local function getHRP(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- ========== BASES (lobby e segurança) ==========
local BASE_CF = CFrame.new(BASE.pos)

-- Posição dentro da base do lobby?
local function noLobby(pos)
	local p = BASE_CF:PointToObjectSpace(pos)
	local m = BASE.tamanho / 2
	return math.abs(p.X) <= m.X and math.abs(p.Y) <= m.Y and math.abs(p.Z) <= m.Z
end

-- Cria a base do lobby (apaga a anterior). Toda vez que você nasce
local function criarBase()
	if baseParte then baseParte:Destroy() end
	baseParte = criar("Part", {
		Name = "BaseLobby",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Size = BASE.tamanho,
		CFrame = BASE_CF,
		Color = BASE.cor,
		Material = Enum.Material.SmoothPlastic,
		Transparency = BASE.transparencia,
	}, workspace)
end

local function removerBaseSegura()
	if baseSegura then
		for _, parte in ipairs(baseSegura.partes) do parte:Destroy() end
		baseSegura = nil
	end
	ultimoChao = nil
end

-- Cria a base de segurança no X/Z de onde você nasceu no mapa,
-- mais as camadas extras logo abaixo (o ragdoll não deixa atravessar)
local function criarBaseSegura(posMapa)
	removerBaseSegura()
	local cf = CFrame.new(posMapa.X, BASE_SEGURA.altura, posMapa.Z)
	local partes, todas = {}, {}
	for i = 0, BASE_SEGURA.camadas do
		local parte = criar("Part", {
			Name = "BaseSegura",
			Anchored = true,
			CanCollide = true, -- também segura você se cair no void
			CanQuery = true,
			CanTouch = false,
			Size = BASE_SEGURA.tamanho,
			CFrame = cf * CFrame.new(0, -i * BASE_SEGURA.tamanho.Y, 0),
			Color = BASE_SEGURA.cor,
			Material = Enum.Material.SmoothPlastic,
			Transparency = BASE_SEGURA.transparencia,
		}, workspace)
		table.insert(partes, parte)
		todas[parte] = true
	end
	baseSegura = {parte = partes[1], cf = cf, partes = partes, todas = todas}
	ultimoChao = {pos = posMapa} -- ponto inicial de retorno
end

-- Roda todo frame: cria a base de segurança ao sair do lobby,
-- guarda o último chão firme e te devolve a ele quando você toca na base
local raioParams = RaycastParams.new()
raioParams.FilterType = Enum.RaycastFilterType.Exclude

local function atualizarBases(hrp, hum)
	if not baseSegura then
		if not noLobby(hrp.Position) then criarBaseSegura(hrp.Position) end
		return
	end
	if target or noLobby(hrp.Position) then return end -- durante o farm não checa

	-- Guarda o último chão do mapa em que você pisou
	if hum.FloorMaterial ~= Enum.Material.Air then
		raioParams.FilterDescendantsInstances = {LocalPlayer.Character, baseParte}
		local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), raioParams)
		if hit and not baseSegura.todas[hit.Instance] then
			ultimoChao = {pos = hrp.Position}
		end
	end

	-- Tocou na base de segurança? Volta para o último chão
	local topo = BASE_SEGURA.altura + BASE_SEGURA.tamanho.Y / 2
	local pes = hrp.Position.Y - BASE_SEGURA.pes
	if os.clock() > esperaBase and pes <= topo + BASE_SEGURA.folga and ultimoChao then
		hrp.CFrame = CFrame.new(ultimoChao.pos + Vector3.new(0, 3, 0))
		hrp.AssemblyLinearVelocity = Vector3.zero
		esperaBase = os.clock() + BASE_SEGURA.espera
	end
end

-- ========== LÓGICA DO JOGO ==========
local startChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
startChar:WaitForChild("HumanoidRootPart")

-- Motivo pelo qual o jogador NÃO pode ser farmado (nil = pode)
local function motivoInvalido(plr)
	if not plr or plr == LocalPlayer then return "invalido" end
	if ehAdm(plr) and not admLiberado() then return "invalido" end
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP(char)
	if not hum or not hrp then return "saiu" end
	if hum.Health <= 0 then return "morto" end
	if noLobby(hrp.Position) then return "lobby" end
	if hrp.Position.Y < CONFIG.VOID_Y then return "void" end
	return nil
end

local function isValid(plr)
	return motivoInvalido(plr) == nil
end

-- Escolhe um alvo nos modos automáticos
local function escolherAlvo(hrp)
	local lista = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if isValid(p) then table.insert(lista, p) end
	end
	if #lista == 0 then return nil end

	if randomOn then
		return lista[math.random(#lista)]
	end

	-- próximo: o mais perto dentro do raio
	local melhor, dist = nil, CONFIG.NEAR_RADIUS
	for _, p in ipairs(lista) do
		local d = (getHRP(p.Character).Position - hrp.Position).Magnitude
		if d < dist then melhor, dist = p, d end
	end
	return melhor
end

-- Um passo do farm (todo frame)
local function farmar(hrp)
	if noLobby(hrp.Position) then return end

	if target then
		local motivo = motivoInvalido(target)
		if motivo then
			target = nil
			if motivo == "morto" and tpAoMatar then
				hrp.CFrame = CFrame.new(CONFIG.SAFE_POS)
				hrp.AssemblyLinearVelocity = Vector3.zero
			end
			refresh()
			return
		end
		local pos = getHRP(target.Character).Position
		ultimaPosAlvo = pos
		hrp.CFrame = CFrame.new(pos + Vector3.new(0, CONFIG.OFFSET_Y, 0))
		hrp.AssemblyLinearVelocity = Vector3.zero
		return
	end

	if (randomOn or nearOn) and os.clock() >= proximaBusca then
		proximaBusca = os.clock() + 0.25
		target = escolherAlvo(hrp)
		if target then refresh() end
	end
end

-- Liga/desliga o farm manual em um jogador (3 toques no quadrado)
local function alternarFarm(plr)
	if target == plr then
		target = nil
	elseif isValid(plr) then
		target = plr
	end
	refresh()
end

-- Busca dos botões do jogo
local WORDS = {
	attack = {"ataque", "attack", "m1"},
	e = {"e"},
	r = {"r"},
}

local function findGameButton(kind)
	local cached = cache[kind]
	if cached and cached.Parent then return cached end

	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return nil end

	for _, o in ipairs(pg:GetDescendants()) do
		if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Visible then
			local t = string.lower(o.Text):gsub("%s", "")
			for _, w in ipairs(WORDS[kind]) do
				if t == w then
					local host = o:FindFirstAncestorWhichIsA("GuiButton") or o
					cache[kind] = host
					return host
				end
			end
		end
	end
	return nil
end

-- Apertar: só toque de celular
local function press(kind)
	local host = findGameButton(kind)
	if not host then return end

	if firesignal then
		for _, name in ipairs({"MouseButton1Down", "MouseButton1Click", "Activated", "MouseButton1Up"}) do
			pcall(function() firesignal(host[name]) end)
		end
	end

	local inset = GuiService:GetGuiInset()
	local p = host.AbsolutePosition + host.AbsoluteSize / 2 + inset
	VIM:SendTouchEvent(7, 0, p.X, p.Y)
	task.wait(0.03)
	VIM:SendTouchEvent(7, 2, p.X, p.Y)
end

-- Loop dos botões automáticos (Ataque / E / R)
task.spawn(function()
	while vivo and task.wait(CONFIG.SKILL_DELAY) do
		if auto.attack then press("attack") end
		if auto.e then press("e") end
		if auto.r then press("r") end
	end
end)

-- ========== JANELA ==========
local gui = criar("ScreenGui", {Name = "TemaMenu", ResetOnSpawn = false})
if not pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) then
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local main = criar("Frame", {
	Size = UDim2.new(0, MENU.largura, 0, MENU.altura),
	Position = MENU.posicao,
	BackgroundColor3 = COR.fundo,
	BackgroundTransparency = MENU.transparencia,
	BorderSizePixel = 0,
}, gui)
arredondar(main, MENU.raio)
criar("UIStroke", {Color = COR.azul, Thickness = 2}, main)

-- ========== BARRA SUPERIOR ==========
local barra = criar("Frame", {
	Size = UDim2.new(1, 0, 0, BARRA.altura),
	BackgroundColor3 = COR.card,
	BackgroundTransparency = BARRA.transparencia,
	BorderSizePixel = 0,
}, main)
arredondar(barra, MENU.raio)

local titulo = criar("TextLabel", {
	Size = UDim2.new(1, -99, 1, 0),
	Position = UDim2.new(0, 8, 0, 0),
	BackgroundTransparency = 1,
	Text = TITULO,
	TextColor3 = COR.texto,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.SourceSansBold,
}, barra)
criar("UITextSizeConstraint", {MaxTextSize = 14}, titulo)

local function botaoBarra(texto, x, cor)
	local b = criar("TextButton", {
		Size = UDim2.new(0, 20, 0, 20),
		Position = x,
		BackgroundColor3 = cor,
		Text = texto,
		TextColor3 = COR.texto,
		TextSize = 13,
		Font = Enum.Font.SourceSansBold,
	}, barra)
	arredondar(b, 6)
	return b
end

local btnFechar = botaoBarra("X", UDim2.new(1, -23, 0, 4), COR.fechar)
local btnMinimizar = botaoBarra("–", UDim2.new(1, -45, 0, 4), COR.minimizar)
local btnConfig = botaoBarra("⚙", UDim2.new(1, -67, 0, 4), COR.azul)   -- página CONFIGURAÇÕES
local btnTele = botaoBarra("📍", UDim2.new(1, -89, 0, 4), COR.laranja) -- página TELEPORTE

-- Botão 👑: só aparece para os ADMs (abre o MENU ADM)
local btnAdm = nil
if souAdm then
	btnAdm = botaoBarra("👑", UDim2.new(1, -111, 0, 4), COR.cinza)
	titulo.Size = UDim2.new(1, -121, 1, 0)
end

arrastar(barra, main)

-- ========== PÁGINAS ==========
local corpo = criar("Frame", {
	Size = UDim2.new(1, 0, 1, -BARRA.altura),
	Position = UDim2.new(0, 0, 0, BARRA.altura),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, main)

local paginas = {}
local titulos = {menu = TITULO, config = "CONFIGURAÇÕES", tele = "TELEPORTE", adm = "MENU ADM"}

local function criarLista(nome, emGrade)
	local lista = criar("ScrollingFrame", {
		Name = nome,
		Size = UDim2.new(1, -10, 1, -8),
		Position = UDim2.new(0, 5, 0, 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
	}, corpo)
	if emGrade then
		-- folga em cima e embaixo: a borda dos quadrados não fica cortada
		criar("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
		}, lista)
		criar("UIGridLayout", {
			CellSize = UDim2.new(0, CARD.largura, 0, CARD.altura),
			CellPadding = UDim2.new(0, CARD.espaco, 0, CARD.espaco),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, lista)
	else
		criar("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}, lista)
	end
	paginas[nome] = lista
	return lista
end

local grade = criarLista("menu", true)      -- quadradinhos dos jogadores
local listaConfig = criarLista("config")    -- interruptores de função
local listaTele = criarLista("tele")        -- teleporte
local listaAdm = souAdm and criarLista("adm") or nil -- menu ADM (só para ADMs)

-- Cada botão da barra abre a sua página; apertando de novo (←) volta ao menu
local function mostrarPagina(nome)
	paginaAtual = nome
	for n, frame in pairs(paginas) do frame.Visible = (n == nome) end
	titulo.Text = titulos[nome]
	btnConfig.Text = (nome == "config") and "←" or "⚙"
	btnTele.Text = (nome == "tele") and "←" or "📍"
	if btnAdm then btnAdm.Text = (nome == "adm") and "←" or "👑" end
end

btnConfig.MouseButton1Click:Connect(function()
	mostrarPagina(paginaAtual == "config" and "menu" or "config")
end)
btnTele.MouseButton1Click:Connect(function()
	mostrarPagina(paginaAtual == "tele" and "menu" or "tele")
end)
if btnAdm then
	btnAdm.MouseButton1Click:Connect(function()
		mostrarPagina(paginaAtual == "adm" and "menu" or "adm")
	end)
end

-- Botão simples
local function novoBotao(ordem, pai, texto, cor)
	local btn = criar("TextButton", {
		Size = UDim2.new(1, -6, 0, 30),
		LayoutOrder = ordem,
		BackgroundColor3 = COR.card,
		BorderSizePixel = 0,
		Text = texto or "",
		TextColor3 = COR.texto,
		TextScaled = true,
		Font = Enum.Font.SourceSansBold,
		AutoButtonColor = false,
	}, pai)
	arredondar(btn, 6)
	criar("UIStroke", {Color = cor or COR.azul, Thickness = 1.5}, btn)
	criar("UITextSizeConstraint", {MaxTextSize = 12}, btn)
	btn.MouseButton1Click:Connect(function() efeitoClique(btn) end)
	return btn
end

-- Interruptor estilo ON/OFF (pílula verde com bolinha branca / cinza)
local function novoInterruptor(ordem, pai, texto, cor, aoMudar)
	local linha = criar("TextButton", {
		Size = UDim2.new(1, -6, 0, 34),
		LayoutOrder = ordem,
		BackgroundColor3 = COR.card,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, pai)
	arredondar(linha, 6)
	criar("UIStroke", {Color = cor or COR.azul, Thickness = 1.5}, linha)

	criar("TextLabel", {
		Size = UDim2.new(1, -62, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = texto,
		TextColor3 = COR.texto,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.SourceSansBold,
	}, linha)

	local trilho = criar("Frame", {
		Size = UDim2.new(0, 46, 0, 22),
		Position = UDim2.new(1, -52, 0.5, -11),
		BackgroundColor3 = COR.cinza,
		BorderSizePixel = 0,
	}, linha)
	arredondar(trilho, 11)

	local rotulo = criar("TextLabel", {
		Size = UDim2.new(0, 24, 1, 0),
		Position = UDim2.new(1, -27, 0, 0),
		BackgroundTransparency = 1,
		Text = "OFF",
		TextColor3 = COR.sub,
		TextSize = 9,
		Font = Enum.Font.SourceSansBold,
	}, trilho)

	local bola = criar("Frame", {
		Size = UDim2.new(0, 18, 0, 18),
		Position = UDim2.new(0, 2, 0.5, -9),
		BackgroundColor3 = COR.texto,
		BorderSizePixel = 0,
	}, trilho)
	arredondar(bola, 9)

	local ligado = false
	local function set(estado)
		if estado == ligado then return end
		ligado = estado
		local info = TweenInfo.new(0.15)
		TweenService:Create(bola, info, {
			Position = ligado and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		}):Play()
		TweenService:Create(trilho, info, {
			BackgroundColor3 = ligado and COR.on or COR.cinza,
		}):Play()
		rotulo.Text = ligado and "ON" or "OFF"
		rotulo.Position = ligado and UDim2.new(0, 3, 0, 0) or UDim2.new(1, -27, 0, 0)
		rotulo.TextColor3 = ligado and COR.onTexto or COR.sub
	end

	linha.MouseButton1Click:Connect(function()
		set(not ligado)
		if aoMudar then aoMudar(ligado) end
	end)

	return {linha = linha, set = set}
end

-- Texto explicativo pequeno
local function novoTexto(ordem, pai, texto, altura)
	return criar("TextLabel", {
		Size = UDim2.new(1, -6, 0, altura),
		LayoutOrder = ordem,
		BackgroundTransparency = 1,
		Text = texto,
		TextColor3 = COR.sub,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.SourceSans,
	}, pai)
end

-- ========== PÁGINA CONFIGURAÇÕES ==========
local swAtk = novoInterruptor(1, listaConfig, "⚔️ Auto Ataque", COR.azul, function(v)
	auto.attack = v
end)
local swE = novoInterruptor(2, listaConfig, "🅴 Auto E", COR.laranja, function(v)
	auto.e = v
end)
local swR = novoInterruptor(3, listaConfig, "🆁 Auto R", COR.verde, function(v)
	auto.r = v
end)
local swRandom = novoInterruptor(4, listaConfig, "Farm farmar player", COR.roxo, function(v)
	randomOn = v
	if v then nearOn = false end
	refresh()
end)
local swNear = novoInterruptor(5, listaConfig, "Farma jogador próximo", COR.azul, function(v)
	nearOn = v
	if v then randomOn = false end
	refresh()
end)

-- ========== PÁGINA TELEPORTE ==========
local swTpMatar = novoInterruptor(1, listaTele, "Teleportar ao matar", COR.laranja, function(v)
	tpAoMatar = v
end)

novoTexto(2, listaTele,
	"Ativado: quando o jogador que você está farmando morrer, você é teleportado "
	.. "para a posição salva. Desativado: você continua no mapa, no lugar onde ele morreu.", 84)

local tpBtn = novoBotao(3, listaTele, "📍 Teleportar para a posição", COR.laranja)

novoTexto(4, listaTele,
	"Aviso: o anti-void ainda está em desenvolvimento. Você ainda pode morrer ou cair no void.", 56)

-- ========== PÁGINA MENU ADM (só existe para ADMs) ==========
local swAdm, tpAdmBtn = nil, nil
if listaAdm then
	swAdm = novoInterruptor(1, listaAdm, "Farm nos ADMs", COR.ouro, function(v)
		admFarmOn = v
		refresh()
	end)

	novoTexto(2, listaAdm,
		"Ativado: o farm passa a funcionar nos ADMs. "
		.. "Para quem não é ADM o farm nunca funciona neles.", 52)

	tpAdmBtn = novoBotao(3, listaAdm, "📍 Voltar à última parte do mapa", COR.ouro)
end

-- ========== QUADRADOS DOS JOGADORES ==========
local function criarCartao(plr)
	if plr == LocalPlayer or cartoes[plr] then return end
	local adm = ehAdm(plr)

	local quad = criar("TextButton", {
		Name = plr.Name,
		BackgroundColor3 = COR.card,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, grade)
	arredondar(quad, 8)
	local borda = criar("UIStroke", {
		Color = adm and COR.ouro or COR.azul,
		Thickness = CARD.borda,
	}, quad)

	local foto = criar("ImageLabel", {
		Size = UDim2.new(0, CARD.foto, 0, CARD.foto),
		Position = UDim2.new(0.5, -CARD.foto / 2, 0, 4),
		BackgroundColor3 = COR.fundo,
		BorderSizePixel = 0,
		Image = "",
	}, quad)
	arredondar(foto, 8)

	-- Cobertura "LOBBY": aparece quando o jogador está na base do lobby
	local lobby = criar("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Text = "LOBBY",
		TextColor3 = COR.texto,
		TextSize = 11,
		Font = Enum.Font.SourceSansBold,
		Visible = false,
		ZIndex = 2,
	}, foto)
	arredondar(lobby, 8)

	local nome = criar("TextLabel", {
		Size = UDim2.new(1, -4, 0, CARD.altura - CARD.foto - 9),
		Position = UDim2.new(0, 2, 0, CARD.foto + 6),
		BackgroundTransparency = 1,
		Text = textoNome(plr),
		TextColor3 = COR.texto,
		TextScaled = true,
		Font = Enum.Font.SourceSansBold,
	}, quad)
	criar("UITextSizeConstraint", {MaxTextSize = 10}, nome)

	carregarFoto(plr, foto)

	-- 3 toques seguidos no quadrado = liga/desliga o farm nele
	local toques = {}
	quad.Activated:Connect(function()
		local agora = os.clock()
		table.insert(toques, agora)
		while #toques > 0 and agora - toques[1] > TOQUES.tempo do
			table.remove(toques, 1)
		end
		efeitoClique(quad)
		if #toques >= TOQUES.quantidade then
			toques = {}
			alternarFarm(plr)
		end
	end)

	cartoes[plr] = {quad = quad, borda = borda, nome = nome, lobby = lobby, adm = adm}
end

local function removerCartao(plr)
	local c = cartoes[plr]
	if c then
		c.quad:Destroy()
		cartoes[plr] = nil
	end
	if target == plr then target = nil end
end

for _, p in ipairs(Players:GetPlayers()) do criarCartao(p) end
ligar(Players.PlayerAdded, criarCartao)
ligar(Players.PlayerRemoving, removerCartao)

-- ========== VISUAL ON/OFF ==========
refresh = function()
	swRandom.set(randomOn)
	swNear.set(nearOn)
	if swAdm then swAdm.set(admFarmOn) end
	if btnAdm then btnAdm.BackgroundColor3 = admFarmOn and COR.on or COR.cinza end

	for plr, c in pairs(cartoes) do
		local on = (plr == target)
		c.borda.Color = on and COR.on or (c.adm and COR.ouro or COR.azul)
		c.nome.TextColor3 = on and COR.on or COR.texto
	end
end

-- Atualiza a cobertura "LOBBY" dos quadrados
task.spawn(function()
	while vivo and task.wait(0.5) do
		for plr, c in pairs(cartoes) do
			local hrp = getHRP(plr.Character)
			c.lobby.Visible = (hrp ~= nil) and noLobby(hrp.Position)
		end
	end
end)

-- ========== BOTÕES ==========
-- Teleportar para a posição salva
tpBtn.MouseButton1Click:Connect(function()
	local hrp = getHRP(LocalPlayer.Character)
	if hrp then
		target = nil
		hrp.CFrame = CFrame.new(CONFIG.SAFE_POS)
		hrp.AssemblyLinearVelocity = Vector3.zero
		refresh()
	end
end)

-- ADM: voltar ao último chão do mapa
if tpAdmBtn then
	tpAdmBtn.MouseButton1Click:Connect(function()
		local hrp = getHRP(LocalPlayer.Character)
		if hrp and ultimoChao then
			target = nil
			hrp.CFrame = CFrame.new(ultimoChao.pos + Vector3.new(0, 3, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			refresh()
		end
	end)
end

-- Minimizar
local minimizado = false
btnMinimizar.MouseButton1Click:Connect(function()
	minimizado = not minimizado
	corpo.Visible = not minimizado
	main.Size = UDim2.new(0, MENU.largura, 0, minimizado and BARRA.altura or MENU.altura)
	btnMinimizar.Text = minimizado and "+" or "–"
end)

-- Fechar: desliga tudo e apaga as bases
btnFechar.MouseButton1Click:Connect(function()
	vivo = false
	target = nil
	for _, c in ipairs(conexoes) do c:Disconnect() end
	if baseParte then baseParte:Destroy() end
	removerBaseSegura()
	gui:Destroy()
end)

-- ========== LOOP PRINCIPAL E NASCIMENTO ==========
-- Toda vez que você nasce: cria a base do lobby e limpa a base de segurança
criarBase()
ligar(LocalPlayer.CharacterAdded, function()
	criarBase()
	removerBaseSegura() -- será criada de novo ao sair do lobby
end)

-- Todo frame: bases + farm
ligar(RunService.Heartbeat, function()
	if not vivo then return end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = getHRP(char)
	if not hum or not hrp or hum.Health <= 0 then return end
	atualizarBases(hrp, hum)
	farmar(hrp)
end)

mostrarPagina("menu")
refresh()
