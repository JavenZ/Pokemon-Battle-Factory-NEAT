---@diagnostic disable: trailing-space

-- global pointer offsets
local ACTIVE_ENEMY_OFFSET = 0x54658 -- BLOCK_B
local ACTIVE_ALLY_OFFSET = 0x54598 -- BLOCK_B
local FUTURE_ENEMY_OFFSET = 0x3CDCC -- BLOCK_A
local ALLY_OFFSET = 0x3D10C  -- Encrypted
local ENEMY_OFFSET = 0x3D6BC -- Encrypted
local MODE_OFFSET = 0x54600
local TRADEMENU_OFFSET = 0x62BEC
local BATTLESTATE_OFFSET = -0x514F4
local BATTLE_MENU_OFFSET = 0xFE618
local BATTLE_PARTY_OFFSET = 0x62BEC
local MOVE_FAIL_OFFSET = 0xFE69A
local PARTY_SELECTED_OFFSET = 0xFE5AA

-- game state & game mode consts
local STATE_INIT = 0
local STATE_BATTLE = 1
local STATE_TRADE = 2
local STATE_NA = 3
local MODE_TRADE = 0x140
local MODE_TRADEMENU = 0x0000
local MODE_OUTSIDE = 0x57BC
local MODE_BATTLEROOM = 0x290
local MODE_NA = 0x0000
local MODE_BATTLE_TURN = 0x1
local MODE_BATTLE_PMENU = 0x97
local MODE_MOVE_FAIL = 0xFFFF
local MODE_SWITCH_FAIL = 0x0000
local MODE_BATTLE_MENU = 0x12C0
-- local MODE_BATTLE_MOVES = 0x1E80
local MODE_BATTLE_PARTY = 0x1AAA
local MODE_PARTY_SELECTED = 0x8000

-- neural network consts
local ACTIONS = {'Move1', 'Move2', 'Move3', 'Move4', 'Poke1', 'Poke2', 'Poke3', 'Poke4', 'Poke5', 'Poke6'}

-- global vars for game loop
local ttl
local ally_deaths
local enemy_deaths
local gp
local battle_number
local round_number
local fitness
local has_battled
local input_state
local turn
local turn_failure

-- game loop options
local FORCE_MOVES = false  -- forces move actions
local LOAD_SLOT = 2  -- the emulator save slot to load
local PUNISH_ACTION_FAILURES = true  -- ends run after an action failure
local DISABLE_GRAPHICS = true
local ADD_RNG = false

-- orderings of shuffled pokemon data blocks from shift-values
local SHUFFLE_ORDER = {
	["0"] = {A = 1, B = 2, C = 3, D = 4};
	["1"] = {A = 1, B = 2, C = 4, D = 3};
	["2"] = {A = 1, B = 3, C = 2, D = 4};
	["3"] = {A = 1, B = 4, C = 2, D = 3};
	["4"] = {A = 1, B = 3, C = 4, D = 2};
	["5"] = {A = 1, B = 4, C = 3, D = 2};
	["6"] = {A = 2, B = 1, C = 3, D = 4};
	["7"] = {A = 2, B = 1, C = 4, D = 3};
	["8"] = {A = 3, B = 1, C = 2, D = 4};
	["9"] = {A = 4, B = 1, C = 2, D = 3};
	["10"] = {A = 3, B = 1, C = 4, D = 2};
	["11"] = {A = 4, B = 1, C = 3, D = 2};
	["12"] = {A = 2, B = 3, C = 1, D = 4};
	["13"] = {A = 2, B = 4, C = 1, D = 3};
	["14"] = {A = 3, B = 2, C = 1, D = 4};
	["15"] = {A = 4, B = 2, C = 1, D = 3};
	["16"] = {A = 3, B = 4, C = 1, D = 2};
	["17"] = {A = 4, B = 3, C = 1, D = 2};
	["18"] = {A = 2, B = 3, C = 4, D = 1};
	["19"] = {A = 2, B = 4, C = 3, D = 1};
	["20"] = {A = 3, B = 2, C = 4, D = 1};
	["21"] = {A = 4, B = 2, C = 3, D = 1};
	["22"] = {A = 3, B = 4, C = 2, D = 1};
	["23"] = {A = 4, B = 3, C = 2, D = 1};
}

-- pokemon data structure
local POKEMON_STRUCT = {
	ID = 0x0,
	-- PID = 0x0,
	HeldItem = 0x0,
	Ability = 0x0,
	Active = 0x0,
	Moves = {
		["1"] = {ID = 0x0, PP = 0x0},
		["2"] = {ID = 0x0, PP = 0x0},
		["3"] = {ID = 0x0, PP = 0x0},
		["4"] = {ID = 0x0, PP = 0x0},
	},
	-- IVs = {
	-- 	HP = 0x0, ATK = 0x0, DEF = 0x0,
	--	SPEED = 0x0, SPA = 0x0, SPD = 0x0,
	--},
	-- EVs = {
	--	HP = 0x0, ATK = 0x0, DEF = 0x0,
	--	SPEED = 0x0, SPA = 0x0, SPD = 0x0,
	--},
	Stats = {
	    -- Level = 0x0, EXP = 0x0,
		Status = 0x0,
		HP = 0x0,
		MaxHP = 0x0,
		ATK = 0x0,
		DEF = 0x0,
		SPEED = 0x0,
		SPA = 0x0,
		SPD = 0x0,
		ATK_Boost = 0x0, -- 0x6
		DEF_Boost = 0x0,
		SPA_Boost = 0x0,
		SPD_Boost = 0x0,
		EVA_Boost = 0x0,
		SPEED_Boost = 0x0,
		Confused = 0x0,
	}
}

-- unencrypted pokemon memory block offsets
local BLOCK_A = {  -- 56 bytes
    SIZE = 0x38,
    ID = 0x0,
    HELD_ITEM = 0x2,
    MOVE1_ID = 0x4,
    MOVE2_ID = 0x6,
    MOVE3_ID = 0x8,
    MOVE4_ID = 0xA,
    ABILITY = 0x20,
}
local BLOCK_B = {  -- 192 bytes
    SIZE = 0xC0,
    ID = 0x0,
    HP = 0x4C,
    MAXHP = 0x50,
    MOVE1_PP = 0x2C,
    MOVE2_PP = 0x2D,
    MOVE3_PP = 0x2E,
    MOVE4_PP = 0x2F,
    ATK_BOOST = 0x19,
    DEF_BOOST = 0x1A,
    SPEED_BOOST = 0x1B,
    SPA_BOOST = 0x1C,
    SPD_BOOST = 0x1D,
    UNK1_BOOST = 0x1E,
    EVA_BOOST = 0x1F,
    STATUS = 0x6C,
    CONFUSED = 0x70,
}

local function log(msg)
    comm.socketServerSend("LOG:"..tostring(msg))
end

-- copy table data structures
function table.shallow_copy(t)
	local t2 = {}
	for k,v in pairs(t) do
	    if type(v) == "table" then
	        -- resursive table copy
            t2[k] = table.shallow_copy(v)
        else
		    t2[k] = v
		end
	end
	return t2
end

-- input layer data structure
local INPUTSTATE_STRUCT = {
    State = STATE_INIT,
    AllyParty = {
        ["1"] = table.shallow_copy(POKEMON_STRUCT),
        ["2"] = table.shallow_copy(POKEMON_STRUCT),
        ["3"] = table.shallow_copy(POKEMON_STRUCT),
        ["4"] = table.shallow_copy(POKEMON_STRUCT),
        ["5"] = table.shallow_copy(POKEMON_STRUCT),
        ["6"] = table.shallow_copy(POKEMON_STRUCT),
    },
    EnemyParty = {
        ["1"] = table.shallow_copy(POKEMON_STRUCT),
        ["2"] = table.shallow_copy(POKEMON_STRUCT),
        ["3"] = table.shallow_copy(POKEMON_STRUCT),
    }
}

-- multiply 4-byte values
local function mult32(a, b)
	local c = a >> 16
	local d = a % 0x10000
	local e = b >> 16
	local f = b % 0x10000
	local g = (c * f + d * e) % 0x10000
	local h = d * f
	local i = g * 0x10000 + h
	return i
end

-- decrypt pokemon bytes
local function decrypt(seed, addr, words)
	local X = { seed }
	local D = {}
	for n = 1, words+1, 1 do
		X[n+1] = mult32(X[n], 0x41C64E6D) + 0x6073
		D[n] = memory.read_u16_le(addr + ((n - 1) * 0x02))
		D[n] = D[n] ~ (X[n+1] >> 16)
		-- log(n, string.format("%X", D[n]))
	end
	return D
end

-- read encrypted pokemon data
local function read_pokemon(ptr, party_idx)
	-- offset pokemon pointer for party index
	ptr = ptr + (0xEC * party_idx)

	-- pokemon decryption vars
	local pid = memory.read_u32_le(ptr + 0x0)
	local checksum = memory.read_u16_le(ptr + 0x06)
	local shift = tostring(((pid & 0x3E000) >> 0xD) % 24)
	-- log("PID:", pid)
	-- log("Checksum:", checksum)
	-- log("Shift:", shift)

	-- decrypt pokemon bytes
	local D = decrypt(checksum, ptr + 0x08, 64) -- data
	local B = decrypt(pid, ptr + 0x88, 50) -- battle stats

	local function fetch_Dv(block_offset, var_offset)
		return D[((block_offset + var_offset) / 2) + 1]
	end

	local function fetch_Bv(var_offset)
		return B[((var_offset - 0x88) / 2) + 1]
	end

	-- calculate shuffled block offsets
	local a_offset = (SHUFFLE_ORDER[shift]["A"] - 1) * 0x20
	local b_offset = (SHUFFLE_ORDER[shift]["B"] - 1) * 0x20
	-- local c_offset = (SHUFFLE_ORDER[shift]["C"] - 1) * 0x20
	-- local d_offset = (SHUFFLE_ORDER[shift]["D"] - 1) * 0x20

	-- instantiate new pokemon obj and populate vars
	local pokemon = table.shallow_copy(POKEMON_STRUCT)
	pokemon.ID = fetch_Dv(a_offset, 0x08 - 0x08) & 0x0FFF
	pokemon.HeldItem = fetch_Dv(a_offset, 0x0A - 0x08) & 0x0FFF
	pokemon.Ability = (fetch_Dv(a_offset, 0x14 - 0x08) & 0xFF00) >> 8
	pokemon.Moves = {
		["1"] = {
			ID = fetch_Dv(b_offset, 0x28 - 0x28) & 0xFFFF,
			PP = fetch_Dv(b_offset, 0x30 - 0x28) & 0x00FF,
		};
		["2"] = {
			ID = fetch_Dv(b_offset, 0x2A - 0x28) & 0xFFFF,
			PP = (fetch_Dv(b_offset, 0x30 - 0x28) & 0xFF00) >> 8,
		};
		["3"] = {
			ID = fetch_Dv(b_offset, 0x2C - 0x28) & 0xFFFF,
			PP = fetch_Dv(b_offset, 0x32 - 0x28) & 0x00FF,
		};
		["4"] = {
			ID = fetch_Dv(b_offset, 0x2E - 0x28) & 0xFFFF,
			PP = (fetch_Dv(b_offset, 0x32 - 0x28) & 0xFF00) >> 8,
		};
	}
	-- pokemon.IVs = {  -- TODO
	--	HP = 0x0,
	--	ATK = 0x0,
	--	DEF = 0x0,
	--	SPEED = 0x0,
	--	SPA = 0x0,
	--	SPD = 0x0,
	--}
	-- pokemon.EVs = {
	--	HP = fetch_Dv(a_offset, 0x18 - 0x08) & 0x00FF,
	--	ATK = (fetch_Dv(a_offset, 0x18 - 0x08) & 0xFF00) >> 8,
	--	DEF = fetch_Dv(a_offset, 0x1A - 0x08) & 0x00FF,
	--	SPEED = (fetch_Dv(a_offset, 0x1A - 0x08) & 0xFF00) >> 8,
	--	SPA = fetch_Dv(a_offset, 0x1C - 0x08) & 0x00FF,
	--	SPD = (fetch_Dv(a_offset, 0x1C - 0x08) & 0xFF00) >> 8,
	-- }
	pokemon.Stats = {
		Status = fetch_Bv(0x88) & 0x00FF, -- TODO test
		Confused = 0x0,
		-- Level = fetch_Bv(0x8C) & 0x00FF,
		HP = fetch_Bv(0x8E) & 0xFFFF,
		MaxHP = fetch_Bv(0x90) & 0xFFFF,
		ATK = fetch_Bv(0x92) & 0xFFFF,
		DEF = fetch_Bv(0x94) & 0xFFFF,
		SPEED = fetch_Bv(0x96) & 0xFFFF,
		SPA = fetch_Bv(0x98) & 0xFFFF,
		SPD = fetch_Bv(0x9A) & 0xFFFF,
		ATK_Boost = 0x6,
		DEF_Boost = 0x6,
		SPA_Boost = 0x6,
		SPD_Boost = 0x6,
		SPEED_Boost = 0x6,
		EVA_Boost = 0x6,
	}
	return pokemon
end

-- reads unencrypted pokemon data from memory
local function read_unencrypted_pokemon(ptr, offsets, party_idx, pk)
    party_idx = party_idx or 0
	ptr = ptr + (offsets.SIZE * party_idx) -- offset pokemon pointer for party index
    pk = pk or table.shallow_copy(POKEMON_STRUCT) -- use existing pokemon or create new one

    pk.ID = memory.read_u16_le(ptr + offsets.ID)
    if offsets == BLOCK_A then
        pk.HeldItem = memory.read_u16_le(ptr + offsets.HELD_ITEM)
    	pk.Ability = memory.read_u8(ptr + offsets.ABILITY)
    	pk.Moves["1"].ID = memory.read_u16_le(ptr + offsets.MOVE1_ID)
    	pk.Moves["2"].ID = memory.read_u16_le(ptr + offsets.MOVE2_ID)
    	pk.Moves["3"].ID = memory.read_u16_le(ptr + offsets.MOVE3_ID)
    	pk.Moves["4"].ID = memory.read_u16_le(ptr + offsets.MOVE4_ID)
    end
    if offsets == BLOCK_B then
    	pk.Stats.HP = memory.read_u16_le(ptr + offsets.HP)
    	pk.Stats.MaxHP = memory.read_u16_le(ptr + offsets.MAXHP)
    	pk.Stats.Status = memory.read_u8(ptr + offsets.STATUS)
    	pk.Stats.Confused = memory.read_u8(ptr + offsets.CONFUSED)
    	pk.Stats.ATK_Boost = memory.read_u8(ptr + offsets.ATK_BOOST)
    	pk.Stats.DEF_Boost = memory.read_u8(ptr + offsets.DEF_BOOST)
    	pk.Stats.SPA_Boost = memory.read_u8(ptr + offsets.SPA_BOOST)
    	pk.Stats.SPD_Boost = memory.read_u8(ptr + offsets.SPD_BOOST)
    	pk.Stats.SPEED_Boost = memory.read_u8(ptr + offsets.SPEED_BOOST)
    	pk.Stats.EVA_Boost = memory.read_u8(ptr + offsets.EVA_BOOST)
    	-- TODO pk.HeldItem
    	pk.Moves["1"].PP = memory.read_u8(ptr + offsets.MOVE1_PP)
    	pk.Moves["2"].PP = memory.read_u8(ptr + offsets.MOVE2_PP)
    	pk.Moves["3"].PP = memory.read_u8(ptr + offsets.MOVE3_PP)
    	pk.Moves["4"].PP = memory.read_u8(ptr + offsets.MOVE4_PP)
    end
    return pk
end

local function refresh_gui()
    if DISABLE_GRAPHICS then
    	return
    end
    gui.cleartext()
	gui.drawText(150, 0, "Ally Deaths: "..ally_deaths, "#ED4C40", "#000000", 10)
	gui.drawText(150, 10, "Enemy Deaths: "..enemy_deaths, "#ED4C40", "#000000", 10)
	gui.drawText(150, 20, "TTL: "..ttl, "#ED4C40", "#000000", 10)
	gui.drawText(150, 30, "Battle #: "..battle_number, "#ED4C40", "#000000", 10)
	gui.drawText(150, 40, "Round #: "..round_number, "#ED4C40", "#000000", 10)
	gui.drawText(150, 50, "Fitness: "..fitness, "#ED4C40", "#000000", 10)
end

local function advance_frames(instruct, cnt)
    cnt = cnt or 1
    instruct = instruct or {}
    for i=0, cnt, 1 do
        emu.frameadvance()
        joypad.set(instruct)
        ttl = ttl - 1
        refresh_gui()
    end
end

local function serialize_table(tabl, indent, nl)
    nl = nl or string.char(10) -- newline
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

local function reset_ttl()
    ttl = 50000
end

local function is_battle_turn()
    local battle_state = memory.read_u8(gp + BATTLESTATE_OFFSET)
    return battle_state == MODE_BATTLE_TURN or battle_state == MODE_BATTLE_PMENU
end

local function in_battle_room()
    return memory.read_u16_le(gp + MODE_OFFSET) == MODE_BATTLEROOM
end

local function in_transition()
    return memory.read_u16_le(gp + MODE_OFFSET) == MODE_NA
end

local function in_trade_menu()
    return memory.read_u16_le(gp + TRADEMENU_OFFSET) == MODE_TRADEMENU
end

local function is_outside()
    return memory.read_u16_le(gp + MODE_OFFSET) == MODE_OUTSIDE
end

local function is_trading()
    return memory.read_u16_le(gp + MODE_OFFSET) == MODE_TRADE
end

local function forfeit_check()
    return is_outside() and enemy_deaths < (3 * battle_number) and has_battled == 1
end

local function in_move_failure()
    return memory.read_u16_le(gp + MOVE_FAIL_OFFSET) == MODE_MOVE_FAIL
end

local function in_switch_failure()
    return memory.read_u16_le(gp + PARTY_SELECTED_OFFSET) == MODE_SWITCH_FAIL
end

local function in_battle_menu()
    return memory.read_u16_le(gp + BATTLE_MENU_OFFSET) == MODE_BATTLE_MENU
end

--local function in_move_menu()
--    return memory.read_u16_le(gp + BATTLE_MENU_OFFSET) == MODE_BATTLE_MOVES
--end

local function in_party_menu()
    return memory.read_u16_le(gp + BATTLE_MENU_OFFSET) == MODE_BATTLE_PARTY
end

local function in_party_selected()
    return memory.read_u16_le(gp + PARTY_SELECTED_OFFSET) == MODE_PARTY_SELECTED
end

local function get_active_ally_hp()
    return memory.read_u16_le(gp + ACTIVE_ALLY_OFFSET + BLOCK_B.HP)
end

local function get_active_enemy_hp()
    return memory.read_u16_le(gp + ACTIVE_ENEMY_OFFSET + BLOCK_B.HP)
end

local function game_state()
    if in_transition() then
    	return STATE_NA
	elseif in_trade_menu() and has_battled == 0 then
		return STATE_INIT
	elseif ((not is_outside()) and (not is_trading())) or in_battle_room() then
	    return STATE_BATTLE
	elseif is_trading() and in_trade_menu() then
	    return STATE_TRADE
	else
	    return STATE_NA
	end
end

-- updates the cached inputstate from current game state memory
local function read_inputstate()
    input_state.State = game_state()
    -- determine state pointers
    if input_state.State == STATE_INIT then
        -- init state
        local allyparty_ptr = gp + ALLY_OFFSET -- encrypted party of 6
        input_state.AllyParty = {
            ["1"] = read_pokemon(allyparty_ptr, 0),
            ["2"] = read_pokemon(allyparty_ptr, 1),
            ["3"] = read_pokemon(allyparty_ptr, 2),
            ["4"] = read_pokemon(allyparty_ptr, 3),
            ["5"] = read_pokemon(allyparty_ptr, 4),
            ["6"] = read_pokemon(allyparty_ptr, 5),
        }
        local enemyparty_ptr = gp + FUTURE_ENEMY_OFFSET -- BLOCK_A party of 3
        input_state.EnemyParty = {
            ["1"] = read_unencrypted_pokemon(enemyparty_ptr, BLOCK_A, 0),
            ["2"] = read_unencrypted_pokemon(enemyparty_ptr, BLOCK_A, 1),
            ["3"] = read_unencrypted_pokemon(enemyparty_ptr, BLOCK_A, 2),
        }
    elseif input_state.State == STATE_BATTLE then
        -- TODO read battle conditions - weather effects, switch preventions, taunt, etc.
        -- battle state
        local active_ally_ptr = gp + ACTIVE_ALLY_OFFSET
        local active_enemy_ptr = gp + ACTIVE_ENEMY_OFFSET
        local allyparty_ptr = gp + ALLY_OFFSET -- encrypted party of 3
        local enemyparty_ptr = gp + ENEMY_OFFSET -- encrypted party of 3
        -- init battle pokemon states
        if in_battle_room() then
        	input_state.AllyParty = {
                ["1"] = read_pokemon(allyparty_ptr, 0),
                ["2"] = read_pokemon(allyparty_ptr, 1),
                ["3"] = read_pokemon(allyparty_ptr, 2),
                ["4"] = table.shallow_copy(POKEMON_STRUCT),
                ["5"] = table.shallow_copy(POKEMON_STRUCT),
                ["6"] = table.shallow_copy(POKEMON_STRUCT),
            }
            input_state.EnemyParty = {
                ["1"] = read_pokemon(enemyparty_ptr, 0),
                ["2"] = read_pokemon(enemyparty_ptr, 1),
                ["3"] = read_pokemon(enemyparty_ptr, 2),
            }
        end
        -- update active party member state
        local active_ally_id = memory.read_u16_le(active_ally_ptr) -- ID only
        local active_enemy_id = memory.read_u16_le(active_enemy_ptr) -- ID only
        -- active ally
        for k,v in pairs(input_state.AllyParty) do
        	if v.ID == active_ally_id then
        		read_unencrypted_pokemon(active_ally_ptr, BLOCK_B, 0, v)
                v.Active = 1
        	else
        	    v.Active = 0
        	end
        end
        -- active enemy
        for k,v in pairs(input_state.EnemyParty) do
        	if v.ID == active_enemy_id then
        		read_unencrypted_pokemon(active_enemy_ptr, BLOCK_B, 0, v)
                v.Active = 1
                -- buffer if active enemy is dying to prevent double counting enemy deaths
                if v.Stats.HP <= 0 then
                    log("Active enemy is dead! "..v.ID)
                    while not (is_battle_turn() or in_battle_room()) do
                        -- check active ally again
                        if get_active_ally_hp() <= 0 then
                        	for _,a in pairs(input_state.AllyParty) do
                                if a.ID == active_ally_id then
                                    read_unencrypted_pokemon(active_ally_ptr, BLOCK_B, 0, a)
                                end
                            end
                        	break -- TODO test if this break is needed or not
                        end
                    	advance_frames({A = "True"}, 1)
                        advance_frames({}, 5)
                    end
                end
        	else
        	    v.Active = 0
        	end
        end

    elseif input_state.State == STATE_TRADE then
        -- trade state
        local allyparty_ptr = gp + ALLY_OFFSET -- encrypted party of 3
        local tradeparty_ptr = gp + ENEMY_OFFSET -- encrypted party of 3
        input_state.AllyParty = {
            ["1"] = read_pokemon(allyparty_ptr, 0),
            ["2"] = read_pokemon(allyparty_ptr, 1),
            ["3"] = read_pokemon(allyparty_ptr, 2),
            ["4"] = read_pokemon(tradeparty_ptr, 0),
            ["5"] = read_pokemon(tradeparty_ptr, 1),
            ["6"] = read_pokemon(tradeparty_ptr, 2),
        }
        local enemyparty_ptr = gp + FUTURE_ENEMY_OFFSET -- BLOCK_A party of 3
        input_state.EnemyParty = {
            ["1"] = read_unencrypted_pokemon(enemyparty_ptr, BLOCK_A, 0),
            ["2"] = read_unencrypted_pokemon(enemyparty_ptr, BLOCK_A, 1),
            ["3"] = read_unencrypted_pokemon(enemyparty_ptr, BLOCK_A, 2),
        }
    else
        -- state N/A
        return input_state
    end

    return input_state
end

local function death_check()
    -- game mode check
    if game_state() ~= STATE_BATTLE then
    	return
    end
    -- check active battle pokemon for deaths
    read_inputstate()
    enemy_deaths = (battle_number - 1) * 3
    ally_deaths = 0
    for k,v in pairs(input_state.EnemyParty) do
    	if v.Stats.HP <= 0 then enemy_deaths = enemy_deaths + 1 end
    end
    for k,v in pairs(input_state.AllyParty) do
    	if v.ID ~= 0 and v.Stats.HP <= 0 then ally_deaths = ally_deaths + 1 end
    end
    refresh_gui()
end

local function calculate_fitness()
    fitness = (enemy_deaths * enemy_deaths) + ((battle_number - 1) * 2.5) + ((round_number - 1) * 5.0)
    refresh_gui()
end

local function str_to_table(str)
    local t = {}
    for v in string.gmatch( str, "([%w%d%.]+)") do
       t[#t+1] = v
    end
    return t
end

local function sort_by_values(tbl, sort_function)
    local keys = {}
    for key in pairs(tbl) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return sort_function(tbl[a], tbl[b]) end
    )
    return keys
end

local function sort_actions(weights)
    return sort_by_values(weights, function(a, b) return a > b end)
end

-- sends input state to server for evaluation
local function eval_state()
    read_inputstate()
    comm.socketServerSend("BF_STATE"..serialize_table(input_state))  -- send state to eval server
    return str_to_table(comm.socketServerResponse())
end

-- selects initial pokemon in trade menu
local function init_pokemon(indices)
    local menu_index = 1
    -- rent each pokemon by index
    for k,idx in pairs(indices) do
        local dist = idx - menu_index
        log("Selecting init pokemon #"..idx)
        -- advance to next index
        if dist ~= 0 then
            local dir
            if dist < 0 then
                dir = "Left"
            else
                dir = "Right"
                -- dist = dist - 1
            end
            -- 6 frames L/R, 1 null frame per index
            for i=0,math.abs(dist)-1,1 do
                advance_frames({[dir] = "True"}, 6)
                advance_frames({}, 1)
            end
            menu_index = idx
        end
        -- select pokemon
        advance_frames({A = "True"}, 5)
        advance_frames({}, 1)
        advance_frames({["Down"] = "True"}, 6)
        advance_frames({}, 1)
        advance_frames({A = "True"}, 8)
        advance_frames({}, 1)
    end
end

local function trade_pokemon(ally_idx, enemy_idx)
    log("Trading ally_idx="..ally_idx.." for enemy_idx="..enemy_idx)
    -- first select ally pokemon
    local dist = ally_idx - 1
    for i=0,math.abs(dist)-1,1 do
        advance_frames({["Right"] = "True"}, 6)
        advance_frames({}, 1)
    end
    advance_frames({A = "True"}, 5)
    advance_frames({}, 1)
    advance_frames({["Down"] = "True"}, 6)
    advance_frames({}, 1)
    advance_frames({A = "True"}, 8)
    -- then buffer and select enemy pokemon
    advance_frames({}, 300)
    dist = enemy_idx - 1
    for i=0,math.abs(dist)-1,1 do
        advance_frames({["Right"] = "True"}, 6)
        advance_frames({}, 1)
    end
    advance_frames({A = "True"}, 5)
    advance_frames({}, 1)
    advance_frames({A = "True"}, 20)
end

-- switch active battle pokemon to given party index, if possible
local function switch_active(party_idx)
    party_idx = tostring(party_idx)
    -- is the party index in range?
    if input_state.AllyParty[party_idx] == nil then
    	log("Failed to switch: party_idx="..party_idx.." is out of range!")
    	return false
    end
    -- is the given party member dead?
    if input_state.AllyParty[party_idx].Stats.HP <= 0 then
        log("Failed to switch: party_idx="..party_idx.." is already dead!")
    	return false
    end

    -- is the given party member already active?
    if input_state.AllyParty[party_idx].Active == 1 then
        log("Failed to switch: party_idx="..party_idx.." is already active!")
    	return false
    end

    -- first move to party selection menu
    if in_battle_menu() then
        log("Moving to party selection menu...")
        while not in_party_menu() do
            joypad.setanalog({
                ["Touch X"] = 200,
                ["Touch Y"] = 160,
            })
            advance_frames({["Touch"] = "True"}, 15)
            advance_frames({}, 1)
        end
    end

    -- find target pokemon menu index
    local target_id = input_state.AllyParty[party_idx].ID
    local menu_idx = 0
    for i=0,2,1 do
    	local test_id = memory.read_u16_le(gp + BATTLE_PARTY_OFFSET + (0x50 * i))
    	if test_id == target_id then
    		menu_idx = i + 1
    	end
    end

    -- reposition menu selection
    if menu_idx == 1 then
    	log("Failed to switch: party_idx="..party_idx.." is already active! (menu_idx=1)")
        return false
    elseif menu_idx == 2 then
        while not in_party_selected() do
        	joypad.setanalog({
                ["Touch X"] = 180,
                ["Touch Y"] = 30,
            })
            advance_frames({["Touch"] = "True"}, 15)
            advance_frames({}, 1)
        end

    elseif menu_idx == 3 then
        while not in_party_selected() do
            joypad.setanalog({
                ["Touch X"] = 120,
                ["Touch Y"] = 60,
            })
            advance_frames({["Touch"] = "True"}, 15)
            advance_frames({}, 1)
        end

    else
        log("Failed to switch: could not find menu_idx for party_idx="..party_idx)
        return false
    end
    -- confirm menu selection
    log("Selecting menu_idx="..menu_idx.." for party_idx="..party_idx)
    while in_party_menu() do
        joypad.setanalog({
            ["Touch X"] = 120,
            ["Touch Y"] = 75,
        })
        advance_frames({["Touch"] = "True"}, 15)
        advance_frames({}, 1)
        -- are we prevented from switching?
        if in_switch_failure() then
        	log("Failed to switch: some status prevented switching!")
        	while not in_battle_menu() do
                advance_frames({B = "True"}, 20)
                advance_frames({}, 1)
            end
        	return false
        end
    end

    return true
end

local function perform_move(move_idx)
    -- advance into move menu
    if in_battle_menu() then
        log("Moving to move selection menu...")
    	while in_battle_menu() do
    		joypad.setanalog({
                ["Touch X"] = 120,
                ["Touch Y"] = 80,
            })
            advance_frames({["Touch"] = "True"}, 15)
            advance_frames({}, 1)
    	end
    end

    -- select chosen move using analog controls
    if move_idx == 1 then
    	joypad.setanalog({
            ["Touch X"] = 60,
            ["Touch Y"] = 60,
        })
        advance_frames({["Touch"] = "True"}, 15)
    elseif move_idx == 2 then
    	joypad.setanalog({
            ["Touch X"] = 200,
            ["Touch Y"] = 60,
        })
        advance_frames({["Touch"] = "True"}, 15)
    elseif move_idx == 3 then
        joypad.setanalog({
            ["Touch X"] = 60,
            ["Touch Y"] = 120,
        })
        advance_frames({["Touch"] = "True"}, 15)
    elseif move_idx == 4 then
        joypad.setanalog({
            ["Touch X"] = 200,
            ["Touch Y"] = 120,
        })
        advance_frames({["Touch"] = "True"}, 15)
    end

    -- did the move fail?
    if in_move_failure() then
        log("Move failed...")
        while not in_battle_menu() do
        	advance_frames({B = "True"}, 20)
            advance_frames({}, 1)
        end
    	return false
    end
    log("Performing move...")
    return true
end

-- check if evaluation is finished
local function finished_check()
    -- did the last battle turn fail?
    if turn_failure then
    	log("Battle turn failure occurred: turn="..turn)
    	return true
    end
    -- battle lost?
    if ttl <= 0 or ally_deaths >= 3 then
        log("Battle was lost: ttl="..ttl..", ally_deaths="..ally_deaths)
        return true
    end
    -- battle forfeit?
    if forfeit_check() then
        log("Battle was forfeit.")
        return true
    end
    -- battle won?
    if enemy_deaths >= (3 * battle_number) then
        log("Battle won! "..battle_number)
        -- round also won?
        if battle_number % 7 == 0 then
            log("Round won! "..round_number)
            round_number = round_number + 1
            has_battled = 0
            input_state = table.shallow_copy(INPUTSTATE_STRUCT)
        end

        -- buffer while battle finishes
        while not in_battle_room() do
            advance_frames({A = "True"}, 1)
            advance_frames({}, 5)
        end
        battle_number = battle_number + 1
        ally_deaths = 0
        turn = 1
        reset_ttl()
        refresh_gui()
    end
    return false
end

local function randomize_seed()
    if ADD_RNG and is_outside() then
    	-- math.randomseed(os.time())
    	-- local rng = math.random(1, 250)
    	comm.socketServerSend("SEED")
        local rng = comm.socketServerResponse()
    	log("Randomizing seed: waiting "..rng.." frames...")
        advance_frames({}, rng)
    end
end

-- manually move out of trivial states
local function trivial_state_check()
    if is_outside() or is_trading() then
        while not (in_trade_menu() or in_battle_room()) do
            advance_frames({A = "True"}, 1)
            advance_frames({}, 5)
        end
    end
end

-- select pokemon from trade menu
local function trade_menu_check()
    if is_trading() and in_trade_menu() then
        local output = eval_state()
        local team_weights = sort_actions({table.unpack(output, 5, #output)})  -- sort 6 team selection weights
        advance_frames({}, 200) -- buffer while menu loads
        if game_state() == STATE_INIT then
            -- select init pokemon
            log("Selecting initial pokemon...")
            init_pokemon({ team_weights[1], team_weights[2], team_weights[3] })  -- select top 3 pokemon choices
        else
            log("Trading team members: "..serialize_table(team_weights, "", ""))
            -- are any enemy pokemon weighted higher than any ally?
            local enemy_idx = math.huge
            local ally_idx = -math.huge
            for k,v in ipairs(team_weights) do
            	if v <= 3 then
                    ally_idx = math.max(k, ally_idx)  -- worst ally
            	else
            	    enemy_idx = math.min(k, enemy_idx) -- best enemy
            	end
            end
            log("enemy_idx="..enemy_idx..", ally_idx="..ally_idx)
            if enemy_idx < ally_idx then
                -- trade worst ally with best enemy
            	enemy_idx = team_weights[enemy_idx] - 3
                ally_idx = team_weights[ally_idx]
                trade_pokemon(ally_idx, enemy_idx)
            else
                -- cancel trade
                log("No trade was made.")
                advance_frames({["Down"] = "True"}, 5)
                advance_frames({}, 1)
                advance_frames({A = "True"}, 5)
                advance_frames({}, 1)
                advance_frames({A = "True"}, 5)
                advance_frames({}, 1)
            end
        end
        -- exit trade menu
        -- while in_trade_menu() do
        while not in_battle_room() do
            advance_frames({A = "True"}, 1)
            advance_frames({}, 5)
        end
    end
end

-- advance from battle-room to battle
local function battle_room_check()
    if in_battle_room() then
        read_inputstate() -- encrypted enemy team now available in memory
        while in_battle_room() do
            advance_frames({A = "True"}, 1)
            advance_frames({}, 5)
        end
    end
end

-- performs battle action if it is my turn
local function battle_turn_check()
    if is_battle_turn() then
        has_battled = 1 -- has battled this round
        -- buffer while battle menu loads
        log("Battle turn #: "..turn)
        while not (in_battle_menu() or in_party_menu()) do
        	advance_frames({B = "True"}, 1) -- get out of analog mode
            advance_frames({}, 1)
            if not is_battle_turn() then
                -- log("No longer my battle turn?")
                return false
            end
        end

        -- evaluate action weights
        local output = eval_state()
        local action_weights = sort_actions({table.unpack(output, 1, 7)}) -- sort all relevant action weights
        log("Action Priorities: "..serialize_table(action_weights, "", ""))
        -- attempt to perform next best action
        local attempt_idx = 1
        local turn_success = false
        while not turn_success do
            log("Attempt_idx="..attempt_idx)
            -- first check if active pokemon is dead
            if get_active_ally_hp() <= 0 then
                local party_idx
                if PUNISH_ACTION_FAILURES then
                	party_idx = action_weights[attempt_idx] - 4
                else
                    local team_weights = sort_actions({table.unpack(output, 5, 7)}) -- sort team member weights
                    party_idx = team_weights[attempt_idx]
                end
                log("Active pokemon is dead! Attempting switch to party_idx="..party_idx)
                turn_success = switch_active(party_idx)
            elseif FORCE_MOVES then
                local move_weights = sort_actions({table.unpack(output, 1, 4)}) -- sort move weights
                log("Forcing move_idx="..move_weights[attempt_idx])
                turn_success = perform_move(move_weights[attempt_idx])
            else
                -- attempt moves in chosen priority
                local action_idx = action_weights[attempt_idx]
                log("Action_idx="..action_idx)
                if action_idx <= 4 then
                    -- move decision
                    log("Performing move_idx="..action_idx)
                    turn_success = perform_move(action_idx)
                else
                    -- switch decision
                    log("Switching to party_idx="..action_idx - 4)
                    turn_success = switch_active(action_idx - 4)
                end
            end

            -- end game loop if punishing turn failures
            if PUNISH_ACTION_FAILURES and not turn_success then
            	log("Failed to perform turn action! Punishing...")
            	break
            end

            -- try next best action
            attempt_idx = attempt_idx + 1
            if attempt_idx > 7 then
                log("Failed to perform any turn action!")
                break
            end
        end

        -- return if turn failure occurred
        if turn_success then
        	turn = turn + 1
        end
        return not turn_success
    end
    -- not my turn
    return false
end


-- ####################################
-- ####         GAME LOOP          ####
-- ####################################
function GameLoop()
    log("Beginning game loop...")

    -- initialize global vars
    reset_ttl()
    ally_deaths = 0
    enemy_deaths = 0
    battle_number = 1
    round_number = 1
    fitness = 0.0
    turn = 1
    turn_failure = false
    has_battled = 0  -- reset each round
    input_state = table.shallow_copy(INPUTSTATE_STRUCT)

    -- load save state
    log("Loading save slot "..LOAD_SLOT.."...")
    savestate.loadslot(LOAD_SLOT)
    gp = memory.read_u32_le(0x02101D2C)
    -- client.invisibleemulation(true)
    refresh_gui()

    -- register death check callbacks
    -- event.on_bus_write(death_check, gp + ACTIVE_ENEMY_OFFSET + BLOCK_B.HP)
    -- event.on_bus_write(death_check, gp + ACTIVE_ALLY_OFFSET + BLOCK_B.HP)

    -- loop until a round is lost or TTL runs out
    while true do
        -- check game state
        death_check()
        calculate_fitness()
        -- is evaluation over?
        if finished_check() then
            break
        end
        -- state advancement
        randomize_seed()
        trivial_state_check()
        trade_menu_check()
        battle_room_check()
        turn_failure = battle_turn_check()
        -- advance single frame
        advance_frames({}, 1)
    end

    -- end game loop
    log("Finished game loop.")
    comm.socketServerSend("FITNESS:"..fitness)
    advance_frames({}, 250) -- buffer while server prepares
    return fitness
end

-- repeat game loop until evaluation server finishes
print("Is client connected to socket server?")
print(comm.socketServerIsConnected())
print(comm.socketServerGetInfo())
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