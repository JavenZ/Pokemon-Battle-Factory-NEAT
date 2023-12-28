---@diagnostic disable: trailing-space

-- input layer data structure
local state_struct = {
    Mode = 0,  -- init=0, battle=1, trade=2
    Ally1 = {},
    Ally2 = {},
    Ally3 = {},
    Ally4 = {},
    Ally5 = {},
    Ally6 = {},
    Enemy1 = {},
    Enemy2 = {},
    Enemy3 = {},
}

-- read pokemon data
local function read_pokemon(mode)
    local pk = { ID=0, HeldItem=0, Ability=0, Moves={}, Stats={} }
    pk.ID = 0x123
    pk.HeldItem = 0x123
    pk.Ability = 0x123
    pk.Moves = {
        Move1 = {
            ID = 0x1,
            PP = 0xF
        };
        Move2 = {
            ID = 0x2,
            PP = 0xF
        };
        Move3 = {
            ID = 0x3,
            PP = 0xF
        };
        Move4 = {
            ID = 0x4,
            PP = 0xF
        };
    }
    pk.Stats = {
        HP = 0x10,
        MAXHP = 0x10,
        ATK = 0xF,
        DEF = 0xF,
        SPEED = 0xF,
        SPA = 0xF,
        SPD = 0xF,
    }
    return pk
end

local function serialize_table(tabl, indent)
    local nl = string.char(10) -- newline
    indent = indent and (indent.."  ") or ""
    local str = ''
    str = str .. indent.."{"
    for key, value in pairs (tabl) do
        local pr = (type(key)=="string") and ('"'..key..'":') or ""
        if type (value) == "table" then
            str = str..nl..pr..serialize_table(value, indent)..','
        elseif type (value) == "string" then
            str = str..nl..indent..pr..'"'..tostring(value)..'",'
        else
            str = str..nl..indent..pr..tostring(value)..','
        end
    end
    str = str:sub(1, #str-1) -- remove last symbol
    str = str..nl..indent.."}"
    return str
end


-- ### GAME LOOP ###
print("Is client connected to socket server?")
print(comm.socketServerIsConnected())
print(comm.socketServerGetInfo())

-- # GLOBAL VARS #
local ttl
local ally_deaths
local enemy_deaths
local last_dead_ally
local last_dead_enemy
local gp
local battle_number
local round_number
local fitness
local has_battled

-- pointer offsets
local active_enemy = 0x54658
local active_enemy_hp = active_enemy + 0x4C
local active_ally = 0x54598
local active_ally_hp = active_ally + 0x4C
local team_enemy = 0x3CDCC -- +0x38
local trade_ally = 0x3BE9E -- +0x70
local init_ally = 0x3CC5C -- +0x38
local game_mode = 0x54600
local trade_menu = 0x62BEC

local function refresh_gui()
    gui.cleartext()
	gui.drawText(150, 0, "Ally Deaths: "..ally_deaths, "#ED4C40", "#000000", 10)
	gui.drawText(150, 10, "Enemy Deaths: "..enemy_deaths, "#ED4C40", "#000000", 10)
	gui.drawText(150, 20, "TTL: "..ttl, "#ED4C40", "#000000", 10)
	gui.drawText(150, 30, "Battle #: "..battle_number, "#ED4C40", "#000000", 10)
	gui.drawText(150, 40, "Round #: "..round_number, "#ED4C40", "#000000", 10)
	gui.drawText(150, 50, "Fitness: "..fitness, "#ED4C40", "#000000", 10)
end

local function death_check()
    local reset_ttl = false

    -- game mode check | 0x140=trading, 0x57BC=done, 0x290=battle-room,
    local mode = memory.read_u16_le(gp + game_mode)
    if mode == 0x0 or mode == 0x140 or mode == 0x57BC or mode == 0x290 then
    	return
    end

    -- checking active battle pokemon for deaths
    if has_battled == 0 then
    	reset_ttl = true
    end
    has_battled = 1

    -- enemy death check
    local enemy_id = memory.read_u16_le(gp + active_enemy)
    local enemy_hp = memory.read_u16_le(gp + active_enemy_hp)
    if enemy_id ~= 0x0 and enemy_id ~= last_dead_enemy and enemy_hp <= 0x0 then
    	enemy_deaths = enemy_deaths + 1
    	last_dead_enemy = enemy_id
    	reset_ttl = true
    	print("Enemy died! "..enemy_deaths)
    end

    -- ally death check
    local ally_id = memory.read_u16_le(gp + active_ally)
    local ally_hp = memory.read_u16_le(gp + active_ally_hp)
    if ally_id ~= 0x0 and ally_id ~= last_dead_ally and ally_hp <= 0x0 then
    	ally_deaths = ally_deaths + 1
    	last_dead_ally = ally_id
    	reset_ttl = true
    	print("Ally Died! "..ally_deaths)
    end

    -- reset TTL?
    if reset_ttl then
    	ttl = ttl + 5000
    	print("Refreshed TTL: "..ttl)
    end
end

local function in_battle_room()
    return memory.read_u16_le(gp + game_mode) == 0x290
end

local function in_trade_menu()
    return memory.read_u16_le(gp + trade_menu) == 0x0000
end

local function is_outside()
    return memory.read_u16_le(gp + game_mode) == 0x57BC
end

local function is_trading()
    return memory.read_u16_le(gp + game_mode) == 0x140
end

local function forfeit_check()
    return is_outside() and enemy_deaths < (3 * battle_number) and has_battled == 1
end

local function calculate_fitness()
    fitness = (enemy_deaths * enemy_deaths) + ((battle_number - 1) * 5) + (has_battled * round_number)
end

local function advance_frames(instruct, cnt)
    cnt = cnt or 1
    instruct = instruct or {}
    for i=0, cnt, 1 do
        emu.frameadvance()
        joypad.set(instruct)
        -- ttl = ttl - 1
    end
end

function GameLoop()
    print("Beginning game loop...")

    -- initialize global vars
    local input_keys = {}
    ttl = 2500 -- 5000 -- 20000
    ally_deaths = 0
    enemy_deaths = 0
    last_dead_ally = nil
    last_dead_enemy = nil
    battle_number = 1
    round_number = 1
    fitness = 0
    has_battled = 0

    -- load save state
    print("Loading save slot 1...")
    savestate.loadslot(1)
    gp = memory.read_u32_le(0x02101D2C)
    refresh_gui()

    -- loop until a round is lost or TTL runs out
    while true do
        -- check game state
        if emu.framecount() % 5 == 0 then
            death_check()
            calculate_fitness()
            refresh_gui()
            -- battle lost?
            if ttl <= 0 or ally_deaths >= 3 then
                print("Battle lost.")
                break
            end
            -- battle forfeit?
            if forfeit_check() then
            	print("Battle forfeit.")
            	break
            end
            -- battle won?
            if enemy_deaths >= (3 * battle_number) then
                print("Battle won! "..battle_number)
                if battle_number % 7 == 0 then
                	print("Round won! "..round_number)
                	round_number = round_number + 1
                	has_battled = 0
                end
                battle_number = battle_number + 1
            	ally_deaths = 0
            	refresh_gui()
            end
        end

        -- manually move out of trivial states
        if is_outside() or is_trading() then
            while not (in_trade_menu() or in_battle_room()) do
            	advance_frames({A = "True"}, 1)
                advance_frames({}, 5)
                -- refresh_gui()
            end
        end

        -- forward-feed next decision
        if emu.framecount() % 55 == 0 then
            local decision = comm.socketServerScreenShotResponse()
            input_keys = {}
            input_keys[decision] = "True"
        end

        -- advance single frame
        advance_frames(input_keys)
        ttl = ttl - 1
    end

    -- end game loop
    print("Finished game loop.")
    print("Fitness: "..fitness)
    comm.socketServerSend("FITNESS:"..fitness)
    return fitness
end

-- repeat game loop until evaluation server finishes
while true do
    comm.socketServerSend("READY")
    local server_state = comm.socketServerResponse()
    print("Server State: "..server_state)
    if server_state == "READY" then
        -- start game loop
    	GameLoop()
    elseif server_state == "FINISHED" then
        -- Close emulator
        client.exit()
    end
end