--[[
    ============================================================
    BSS WINDY AUTO-WAKE + RED-LINE - Bee Swarm Simulator
    ============================================================
    Alur lengkap:
      A. DETEKSI AWAN WINDY: awan yang muncul di folder yang kamu tentukan
         (CloudFolders + CloudNames) DIVERIFIKASI dulu: hanya awan yang terbukti
         berisi / didampingi Windy (WindyMarkerNames + MarkerMode) yang dikunjungi.
         Awan kosong diabaikan.
      B. AUTO-WAKE: tween ke awan, sentuh beberapa kali (membangunkan Windy),
         lalu berdiri di tanah field tempat awan itu berada.
      C. STANDBY: diam sampai garis merah muncul. Kalau tidak ada garis merah
         dalam StandbyTimeout detik dan awan masih ada, sentuh ulang.
      D. RED-LINE (sama seperti sebelumnya): 4 Part garis merah -> titik tengah
         (LastRedBoxCenter) -> tween masuk -> jeda HitWait -> FORCED RETURN.

    Tidak ada auto click / serangan / anchor. Murni event, tanpa polling scan.

    PENTING: nama objek awan (CloudFolders / CloudNames) adalah TEBAKAN.
    Nyalakan DebugCloud = true untuk melihat nama aslinya di console (F9).

    Kontrol:
      RightControl = ON/OFF
      getgenv().AutoFarm = true/false
    ============================================================
]]

if getgenv().WindyLineCleanup then pcall(getgenv().WindyLineCleanup) end

-- ============================================================
-- [1] SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")
local LocalPlayer      = Players.LocalPlayer

-- ============================================================
-- [2] CONFIG
-- ============================================================
local CONFIG = {
    ToggleKey = Enum.KeyCode.RightControl,   -- UBAH DI SINI: tombol ON/OFF
    Debug = false,                           -- true = print ringkas alur gelombang (F9)

    -- ==========================================================
    -- A. DETEKSI AWAN WINDY BEE  (UBAH DI SINI setelah inspeksi Dex)
    -- ==========================================================
    AutoVisitCloud = true,    -- false = fitur auto-wake dimatikan (hanya red-line)

    -- Folder Workspace tempat awan/Windy muncul. Makin sempit makin ringan.
    -- Kandidat: "Monsters", "NPCs", "Particles". Jangan isi "workspace" kecuali terpaksa (berat).
    CloudFolders = { "Monsters", "NPCs", "Particles" },

    -- Kata kunci nama AWAN (semua awan, yang berisi Windy maupun yang kosong).
    -- Tidak case-sensitive, cocok sebagian. Sertakan "windy" supaya model Windy
    -- yang muncul di dalam awan juga memicu pengecekan ulang awan induknya.
    CloudNames = { "cloud", "windy" },

    -- ---------- PEMBEDA: awan berisi Windy vs awan kosong ----------
    -- Awan HANYA dikunjungi kalau terbukti ada "penanda Windy" (objek yang namanya
    -- mengandung kata di bawah). Awan kosong otomatis diabaikan.
    -- UBAH DI SINI setelah inspeksi Dex (lihat perbedaan isi awan Windy vs awan kosong).
    WindyMarkerNames = { "windy" },

    -- Cara mencari penanda:
    --   "inside" = penanda ada DI DALAM awan (anak/turunan awan)
    --   "near"   = penanda ada di dekat awan (dalam MarkerRadius), mis. model Windy terpisah dari awan
    --   "either" = salah satu di atas (disarankan untuk awal)
    --   "none"   = tanpa pengecekan (SEMUA awan dikunjungi)
    MarkerMode    = "either",
    MarkerRadius  = 25,                                      -- stud, untuk mode "near"
    MarkerFolders = { "Monsters", "NPCs", "Particles" },     -- folder pencarian mode "near" (anak langsung)

    -- Windy kadang muncul sedikit setelah awannya. Script menunggu penanda sampai batas ini.
    MarkerCheckTime     = 4,      -- detik
    MarkerCheckInterval = 0.3,    -- detik

    -- Opsional: kalau awan Windy punya Attribute khusus (cek di Dex, bagian Attributes),
    -- isi namanya di sini, mis. "HasWindy". nil = tidak dipakai.
    WindyAttributeName = nil,

    -- Tipe objek yang dianggap awan. Hapus yang tidak relevan setelah inspeksi Dex.
    CloudClasses = { Model = true, MeshPart = true, Part = true, UnionOperation = true },

    VisitExistingAtStart = true,  -- true = kalau awan sudah ada saat script dijalankan, langsung dikunjungi
    CloudSettleDelay = 0.5,       -- jeda setelah objek muncul (menunggu parent/posisi selesai di-set)

    -- Cegah kunjungan ganda ke awan/Windy yang sama (mis. model Windy muncul setelah bangun)
    RevisitRadius   = 60,         -- stud
    RevisitCooldown = 180,        -- detik

    -- Debug penemuan nama objek: print objek baru yang namanya cocok DebugKeywords
    DebugCloud    = false,        -- NYALAKAN dulu untuk mencari nama asli, lalu matikan
    DebugKeywords = { "windy", "cloud", "bee", "wind" },

    -- ==========================================================
    -- B. SENTUH AWAN (membangunkan Windy)
    -- ==========================================================
    CloudTweenSpeed = 60,     -- kecepatan tween menuju awan (stud/detik)
    TouchPasses     = 3,      -- berapa kali "menyentuh" (masuk ke volume awan dari sisi berbeda)
    TouchOffset     = 2,      -- jarak geser tiap sentuhan (stud)
    TouchPassDelay  = 0.35,   -- jeda antar sentuhan (detik)
    TouchDwell      = 0.5,    -- diam di dalam awan setelah sentuhan terakhir (detik)

    -- true = tambahan firetouchinterest (fungsi executor). Nyalakan HANYA kalau
    -- sentuhan fisik tidak membangunkan Windy. Lebih berisiko terdeteksi.
    UseFireTouch = false,

    -- ==========================================================
    -- C. STANDBY SETELAH MENYENTUH
    -- ==========================================================
    GroundRayLength = 400,    -- jarak raycast ke bawah untuk mencari tanah field
    StandbyTimeout  = 20,     -- tunggu garis merah sebanyak ini (detik) sebelum sentuh ulang
    TouchRetries    = 3,      -- maksimal siklus sentuh -> standby per awan

    -- ==========================================================
    -- D. KRITERIA GARIS MERAH (dari data log kamu)
    -- ==========================================================
    ParticlesFolderName = "Particles",
    PartColor      = Color3.new(0.768627, 0.156863, 0.109804),
    ColorTolerance = 0.04,
    PartMaterial   = Enum.Material.Neon,
    PartTransparency = 0.35,
    TransparencyTolerance = 0.15,
    Thickness      = 0.3,
    ThicknessTolerance = 0.05,
    MinLength      = 5,

    CollectDelay   = 0.2,
    MinParts       = 4,
    ExpectedParts  = 4,
    CollectRetries = 3,
    RetryDelay     = 0.1,

    UseCurrentHeight = true,  -- pakai tinggi karakter saat menapak tanah
    CenterOffsetY    = 3,     -- UBAH DI SINI kalau karakter melayang / tenggelam
    MaxHeightDiff    = 12,

    -- ==========================================================
    -- E. GERAKAN & FORCED RETURN
    -- ==========================================================
    TweenSpeed   = 120,        -- tween masuk kotak & tween kembali (Durasi = Jarak / TweenSpeed)
    MaxTweenTime = 15,        -- batas durasi satu tween (detik), pengaman
    HitWait      = 2,         -- jeda statis di tengah kotak sebelum ditarik balik (detik)
    RespawnWait  = 10,        -- kalau mati, tunggu respawn sampai sekian detik lalu tetap kembali
}

-- ============================================================
-- [3] STATE
-- ============================================================
if getgenv().AutoFarm == nil then getgenv().AutoFarm = true end

local connections  = {}
local runId        = tick()
getgenv().WindyLineRunId = runId
local function isRunning() return getgenv().WindyLineRunId == runId end

local LastRedBoxCenter = nil
local pending       = {}
local collecting    = false
local waveId        = 0        -- gelombang red-line baru membatalkan gelombang lama
local visitId       = 0        -- kunjungan awan baru / gelombang red-line membatalkan kunjungan lama
local currentTween  = nil
local visitedList   = {}       -- { {pos=Vector3, time=number}, ... }

local function dbg(...)
    if CONFIG.Debug then print("[RedLine]", ...) end
end

local function notify(text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",
            { Title = "Windy RedLine", Text = text, Duration = 3 })
    end)
end

-- ============================================================
-- [4] ANTI-AFK
-- ============================================================
connections[#connections + 1] = LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0)) -- hanya reset timer idle
    end)
end)

-- ============================================================
-- [5] HELPER UMUM
-- ============================================================
local function getRoot()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then return hrp, hum end
    return nil
end

local function stopMomentum(root)
    pcall(function()
        root.AssemblyLinearVelocity  = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function cancelTween()
    if currentTween then
        pcall(function() currentTween:Cancel() end)
        currentTween = nil
    end
end

-- Tween mulus (Linear). Durasi = Jarak / speed (default CONFIG.TweenSpeed).
-- resetVelocity = true: nol-kan momentum tiap frame selama tween (forced return).
local function tweenTo(position, resetVelocity, speed)
    local root = getRoot()
    if not root then return false end
    local dist = (root.Position - position).Magnitude
    if dist < 1 then return true end

    cancelTween()
    local duration = math.clamp(dist / (speed or CONFIG.TweenSpeed), 0.05, CONFIG.MaxTweenTime)
    local tween = TweenService:Create(root,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { CFrame = CFrame.new(position) })
    currentTween = tween
    stopMomentum(root)

    local hb
    if resetVelocity then
        hb = RunService.Heartbeat:Connect(function() stopMomentum(root) end)
    end

    local ok, state = pcall(function()
        tween:Play()
        return tween.Completed:Wait()
    end)
    if hb then hb:Disconnect() end

    local done = ok and state == Enum.PlaybackState.Completed
    if done then stopMomentum(root) end
    return done
end

local function nameMatches(name, list)
    local lower = string.lower(name)
    for _, key in ipairs(list) do
        if string.find(lower, string.lower(key), 1, true) then return true end
    end
    return false
end

local function resolveFolders(names)
    local result = {}
    for _, n in ipairs(names) do
        local f = (n == "workspace") and workspace or workspace:FindFirstChild(n)
        if f then result[#result + 1] = f end
    end
    return result
end

local function pathOf(obj)
    local ok, p = pcall(function() return obj:GetFullName() end)
    return ok and p or tostring(obj)
end

-- ============================================================
-- [6] KUNJUNGAN AWAN WINDY (AUTO-WAKE)
-- ============================================================
local function visitStale(myVisit)
    return visitId ~= myVisit or not isRunning() or not getgenv().AutoFarm
end

local function sleepVisit(seconds, myVisit)
    local t0 = tick()
    while tick() - t0 < seconds do
        if visitStale(myVisit) then return false end
        task.wait(0.05)
    end
    return not visitStale(myVisit)
end

-- Posisi tengah objek awan (Model = pusat bounding box, Part = Position)
local function getObjectPosition(obj)
    local ok, pos = pcall(function()
        if obj:IsA("BasePart") then return obj.Position end
        if obj:IsA("Model") then
            local cf = obj:GetBoundingBox()
            return cf.Position
        end
        return nil
    end)
    return ok and pos or nil
end

-- ---------- PEMBEDA AWAN BERISI WINDY vs AWAN KOSONG ----------
local function hasMarkerInside(obj)
    for _, d in ipairs(obj:GetDescendants()) do
        if nameMatches(d.Name, CONFIG.WindyMarkerNames) then return true end
    end
    return false
end

local function hasMarkerNear(obj, pos)
    for _, folder in ipairs(resolveFolders(CONFIG.MarkerFolders)) do
        if folder ~= workspace then
            for _, o in ipairs(folder:GetChildren()) do
                if o ~= obj and nameMatches(o.Name, CONFIG.WindyMarkerNames) then
                    local p = getObjectPosition(o)
                    if p and (p - pos).Magnitude <= CONFIG.MarkerRadius then return true end
                end
            end
        end
    end
    return false
end

-- true kalau awan ini terbukti berisi / didampingi Windy Bee
local function isWindyCloud(obj, pos)
    local mode = CONFIG.MarkerMode
    if mode == "none" then return true end

    if CONFIG.WindyAttributeName then
        local v = obj:GetAttribute(CONFIG.WindyAttributeName)
        if v ~= nil and v ~= false then return true end
    end
    -- Nama awan itu sendiri sudah mengandung "windy"
    if nameMatches(obj.Name, CONFIG.WindyMarkerNames) then return true end

    if (mode == "inside" or mode == "either") and hasMarkerInside(obj) then return true end
    if (mode == "near" or mode == "either") and hasMarkerNear(obj, pos) then return true end
    return false
end

-- Untuk debug: daftar isi awan (maks 15 turunan) supaya kamu bisa lihat bedanya
local function describeContents(obj)
    local names, n = {}, 0
    for _, d in ipairs(obj:GetDescendants()) do
        n += 1
        if n > 15 then names[#names + 1] = "..."; break end
        names[#names + 1] = d.Name .. "(" .. d.ClassName .. ")"
    end
    if #names == 0 then return "(kosong)" end
    return table.concat(names, ", ")
end

-- Cari tanah di bawah awan (untuk berdiri di field). nil kalau tidak ketemu.
local function findGround(pos)
    local ok, result = pcall(function()
        local exclude = {}
        if LocalPlayer.Character then exclude[#exclude + 1] = LocalPlayer.Character end
        for _, f in ipairs(resolveFolders(CONFIG.CloudFolders)) do
            if f ~= workspace then exclude[#exclude + 1] = f end
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclude
        local hit = workspace:Raycast(pos, Vector3.new(0, -CONFIG.GroundRayLength, 0), params)
        if hit then
            return hit.Position + Vector3.new(0, CONFIG.CenterOffsetY, 0)
        end
        return nil
    end)
    return ok and result or nil
end

-- Opsional: firetouchinterest (fungsi executor) ke semua BasePart awan (maks 8)
local function fireTouch(obj)
    if not CONFIG.UseFireTouch then return end
    pcall(function()
        local fti = firetouchinterest
        local root = getRoot()
        if not fti or not root then return end
        local parts = {}
        if obj:IsA("BasePart") then
            parts[1] = obj
        else
            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("BasePart") then
                    parts[#parts + 1] = d
                    if #parts >= 8 then break end
                end
            end
        end
        for _, part in ipairs(parts) do
            fti(root, part, 0)
            task.wait()
            fti(root, part, 1)
        end
    end)
end

local function visitCloud(obj, pos, myVisit)
    local offsets = {
        Vector3.new(CONFIG.TouchOffset, 0, 0),
        Vector3.new(-CONFIG.TouchOffset, 0, 0),
        Vector3.new(0, 0, CONFIG.TouchOffset),
        Vector3.new(0, 0, -CONFIG.TouchOffset),
    }

    for attempt = 1, CONFIG.TouchRetries do
        if visitStale(myVisit) then return end

        -- 1) Tween ke awan lalu sentuh beberapa kali dari sisi berbeda
        dbg("Menuju awan (percobaan " .. attempt .. "):", pos)
        if not tweenTo(pos, false, CONFIG.CloudTweenSpeed) then return end

        for i = 1, CONFIG.TouchPasses do
            if visitStale(myVisit) then return end
            tweenTo(pos + offsets[(i - 1) % #offsets + 1], false, CONFIG.CloudTweenSpeed)
            fireTouch(obj)
            if not sleepVisit(CONFIG.TouchPassDelay, myVisit) then return end
        end
        if not sleepVisit(CONFIG.TouchDwell, myVisit) then return end

        -- 2) Turun ke tanah field, lalu STANDBY sampai garis merah muncul
        --    (gelombang red-line otomatis membatalkan kunjungan ini lewat visitId)
        local standPos = findGround(pos) or pos
        dbg("Standby di:", standPos)
        tweenTo(standPos, false, CONFIG.CloudTweenSpeed)

        local t0 = tick()
        while not visitStale(myVisit) and (tick() - t0) < CONFIG.StandbyTimeout do
            if not getRoot() then return end
            task.wait(0.1)
        end
        if visitStale(myVisit) then return end   -- garis merah muncul / dimatikan -> selesai

        -- 3) Tidak ada garis merah. Sentuh ulang HANYA kalau awan masih ada
        --    dan Windy masih terdeteksi di dalamnya / di dekatnya.
        if not obj.Parent then
            dbg("Awan sudah hilang, berhenti mencoba")
            return
        end
        local okW, stillWindy = pcall(function()
            return isWindyCloud(obj, getObjectPosition(obj) or pos)
        end)
        if okW and not stillWindy then
            dbg("Windy sudah keluar dari awan, berhenti mencoba")
            return
        end
        dbg("Belum ada garis merah, sentuh ulang")
    end
end

local function startVisit(obj, pos)
    visitId += 1
    local myVisit = visitId
    notify("Windy terdeteksi, menuju awan")
    task.spawn(function()
        local ok, err = pcall(visitCloud, obj, pos, myVisit)
        if not ok then warn("[RedLine] Error kunjungan awan:", err) end
    end)
end

-- ---------- Deduplikasi kunjungan ----------
local function recentlyVisited(pos)
    local now = tick()
    for i = #visitedList, 1, -1 do
        local v = visitedList[i]
        if now - v.time > CONFIG.RevisitCooldown then
            table.remove(visitedList, i)
        elseif (v.pos - pos).Magnitude <= CONFIG.RevisitRadius then
            return true
        end
    end
    return false
end

local function markVisited(pos)
    visitedList[#visitedList + 1] = { pos = pos, time = tick() }
end

local function isPlayerObject(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and obj:IsDescendantOf(char) then return true end
    end
    return false
end

-- Naik ke induk teratas yang namanya juga cocok (supaya posisi = pusat awan, bukan anak kecil)
local function topMatch(obj)
    while obj.Parent and (obj.Parent:IsA("Model") or obj.Parent:IsA("BasePart"))
        and nameMatches(obj.Parent.Name, CONFIG.CloudNames) do
        obj = obj.Parent
    end
    return obj
end

local checking = setmetatable({}, { __mode = "k" })   -- awan yang sedang diverifikasi
local rejected = setmetatable({}, { __mode = "k" })   -- awan kosong (waktu penolakan)
local REJECT_TTL = 5                                  -- detik sebelum awan ditolak boleh dicek ulang

local function handleCloudCandidate(obj)
    if not CONFIG.AutoVisitCloud or not getgenv().AutoFarm or not isRunning() then return end
    if not obj.Parent then return end

    obj = topMatch(obj)
    if checking[obj] then return end
    if rejected[obj] and tick() - rejected[obj] < REJECT_TTL then return end
    if isPlayerObject(obj) then return end

    checking[obj] = true
    task.spawn(function()
        -- Tunggu sampai penanda Windy muncul (maks MarkerCheckTime detik)
        local ok, passed, pos = pcall(function()
            
