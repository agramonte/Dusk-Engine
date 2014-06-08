--------------------------------------------------------------------------------
--[[
Dusk Engine Component: Tile Layer

Builds a tile layer from data.
--]]
--------------------------------------------------------------------------------

local tilelayer = {}

--------------------------------------------------------------------------------
-- Localize
--------------------------------------------------------------------------------
local require = require

local verby = require("Dusk.dusk_core.external.verby")
local screen = require("Dusk.dusk_core.misc.screen")
local lib_settings = require("Dusk.dusk_core.misc.settings")
local lib_functions = require("Dusk.dusk_core.misc.functions")

local display_remove = display.remove
local display_newSprite = display.newSprite
local display_newGroup = display.newGroup
local math_abs = math.abs
local math_max = math.max
local math_ceil = math.ceil
local table_maxn = table.maxn
local table_insert = table.insert
local string_len = string.len
local tonumber = tonumber
local pairs = pairs
local unpack = unpack
local type = type
local getSetting = lib_settings.get
local setVariable = lib_settings.setEvalVariable
local removeVariable = lib_settings.removeEvalVariable
local verby_error = verby.error
local verby_assert = verby.assert
local spliceTable = lib_functions.spliceTable
local getProperties = lib_functions.getProperties
local addProperties = lib_functions.addProperties
local getXY = lib_functions.getXY
local hasBit = lib_functions.hasBit
local setBit = lib_functions.setBit
local clearBit = lib_functions.clearBit
local physicsKeys = {radius = true, isSensor = true, bounce = true, friction = true, density = true, shape = true}
local physics_addBody; if physics and type(physics) == "table" and physics.addBody then physics_addBody = physics.addBody else physics_addBody = function() verby_error("Physics library was not found on Dusk Engine startup") end end

local flipX = tonumber("80000000", 16)
local flipY = tonumber("40000000", 16)
local flipD = tonumber("20000000", 16)

--------------------------------------------------------------------------------
-- Create Layer
--------------------------------------------------------------------------------
function tilelayer.createLayer(mapData, data, dataIndex, tileIndex, imageSheets, imageSheetConfig, tileProperties)
	local props = getProperties(data.properties or {}, "tiles", true)

	local layer = display_newGroup()

	layer.props = {}
	local layerTiles = {}
	local locked = {}

	function layer.tile(x, y) if layerTiles[x] ~= nil and layerTiles[x][y] ~= nil then return layerTiles[x][y] else return nil end end

	------------------------------------------------------------------------------
	-- Draw a Single Tile to the Screen
	------------------------------------------------------------------------------
	function layer._drawTile(x, y)
		if locked[x] and locked[x][y] == "e" then return false end

		if layer.tile(x, y) == nil then
			local id = ((y - 1) * mapData.width) + x
			local gid = data.data[id]

			if gid == 0 then return true end -- Don't draw if the GID is 0 (signifying an empty tile)

			--------------------------------------------------------------------------
			-- Create Tile
			--------------------------------------------------------------------------
			local flippedX = false
			local flippedY = false
			local rotated = false
			if hasBit(gid, flipX) then flippedX = true gid = clearBit(gid, flipX) end
			if hasBit(gid, flipY) then flippedY = true gid = clearBit(gid, flipY) end
			if hasBit(gid, flipD) then rotated = true gid = clearBit(gid, flipD) end

			if not (gid <= mapData.highestGID and gid >= 0) then verby_error("Invalid GID at position [" .. x .. "," .. y .."] (index #" .. id ..") - expected [0 <= GID <= " .. mapData.highestGID .. "] but got " .. gid .. " instead.") end

			local tileData = tileIndex[gid]
			local sheetIndex = tileData.tilesetIndex
			local tileGID = tileData.gid

			local tile = display_newSprite(imageSheets[sheetIndex], imageSheetConfig[sheetIndex])
				tile:setFrame(tileGID)
				tile.x, tile.y = mapData.stats.tileWidth * (x - 0.5), mapData.stats.tileHeight * (y - 0.5)
				tile.xScale, tile.yScale = screen.zoomX, screen.zoomY
				
				tile.GID = gid
				tile.tilesetGID = tileGID
				tile.tileset = sheetIndex
				tile.layerIndex = dataIndex

				if flippedX then tile.xScale = -tile.xScale end
				if flippedY then tile.yScale = -tile.yScale end

			local tileProps

			if tileProperties[sheetIndex][tileGID] then
				tileProps = tileProperties[sheetIndex][tileGID]
			else
				tileProps = {options={nodot={},usedot={}},physics={},object={},props={}}
			end

			--------------------------------------------------------------------------
			-- Add Physics to Tile
			--------------------------------------------------------------------------
			if (tileProps.options.physicsExistent ~= nil and tileProps.options.physicsExistent) or props.options.physicsExistent then
				local physicsParameters = {}
				local physicsBodyCount = props.options.physicsBodyCount
				local tpPhysicsBodyCount = (tileProps.options.physicsBodyCount ~= nil and tileProps.options.physicsBodyCount) or physicsBodyCount

				physicsBodyCount = math_max(physicsBodyCount, tpPhysicsBodyCount)

				for i = 1, physicsBodyCount do
					physicsParameters[i] = spliceTable(physicsKeys, tileProps.physics[i] or {}, props.physics[i] or {})
				end

				if physicsBodyCount == 1 then -- Weed out any extra slowdown due to unpack()
					physics_addBody(tile, physicsParameters[1])
				else
					physics_addBody(tile, unpack(physicsParameters))
				end
			end

			--------------------------------------------------------------------------
			-- Add Properties and Add Tile to Layer
			--------------------------------------------------------------------------
			tile.props = {}
		
			addProperties(props, "object", tile)
			addProperties(tileProps, "object", tile)
			addProperties(tileProps, "props", tile.props)

			tile.tileX, tile.tileY = x, y
			if not layerTiles[x] then layerTiles[x] = {} end
			layerTiles[x][y] = tile
			layer:insert(tile)
			tile:toBack()
		elseif getSetting("redrawOnTileExistent") then
			layer._eraseTile(x, y)
			layer._drawTile(x, y)
		end
	end

	------------------------------------------------------------------------------
	-- Erase a Single Tile from the Screen
	------------------------------------------------------------------------------
	function layer._eraseTile(x, y)
		if locked[x] and locked[x][y] == "d" then return false end

		if layerTiles[x] and layerTiles[x][y] then
			display_remove(layerTiles[x][y])
			layerTiles[x][y] = nil

			if table_maxn(layerTiles[x]) == 0 then
				layerTiles[x] = nil -- Clear row if no tiles in the row
			end
		end
	end

	------------------------------------------------------------------------------
	-- Redraw a Tile
	------------------------------------------------------------------------------
	function layer._redrawTile(x, y)
		layer._eraseTile(x, y)
		layer._drawTile(x, y)
	end

	------------------------------------------------------------------------------
	-- Lock/Unlock a Tile
	------------------------------------------------------------------------------
	function layer._lockTileDrawn(x, y) if not locked[x] then locked[x] = {} end locked[x][y] = "d" layer._drawTile(x, y) end
	function layer._lockTileErased(x, y) if not locked[x] then locked[x] = {} end locked[x][y] = "e" layer._eraseTile(x, y) end
	function layer._unlockTile(x, y) if locked[x] and locked[x][y] then locked[x][y] = nil if table_maxn(locked[x]) == 0 then locked[x] = nil end end end

	------------------------------------------------------------------------------
	-- Edit Section
	------------------------------------------------------------------------------
	function layer._edit(x1, x2, y1, y2, mode)
		local mode = mode or "d"
		local x1 = x1 or 0
		local x2 = x2 or x1
		local y1 = y1 or 0
		local y2 = y2 or y1

		-- "Shortcuts" for cutting down time
		if x1 > x2 then x1, x2 = x2, x1 end; if y1 > y2 then y1, y2 = y2, y1 end
		if x2 < 1 or x1 > mapData.stats.mapWidth then return true end; if y2 < 1 or y1 > mapData.stats.mapHeight then return true end
		if x1 < 1 then x1 = 1 end; if y1 < 1 then y1 = 1 end
		if x2 > mapData.stats.mapWidth then x2 = mapData.stats.mapWidth end; if y2 > mapData.stats.mapHeight then y2 = mapData.stats.mapHeight end

		-- Function associated with edit mode
		local layerFunc = "_eraseTile"
		if mode == "d" then layerFunc = "_drawTile" elseif mode == "ld" then layerFunc = "_lockTileDrawn" elseif mode == "le" then layerFunc = "_lockTileErased" elseif mode == "u" then layerFunc = "_unlockTile" end

		for x = x1, x2 do
			for y = y1, y2 do
				layer[layerFunc](x, y)
			end
		end -- for x = x1, x2
	end

	------------------------------------------------------------------------------
	-- Draw Section (shortcut)
	------------------------------------------------------------------------------
	function layer.draw(x1, x2, y1, y2)
		return layer._edit(x1, x2, y1, y2, "d")
	end

	------------------------------------------------------------------------------
	-- Erase Section (shortcut)
	------------------------------------------------------------------------------
	function layer.erase(x1, x2, y1, y2)
		return layer._edit(x1, x2, y1, y2, "e")
	end

	------------------------------------------------------------------------------
	-- Lock Section (shortcut)
	------------------------------------------------------------------------------
	function layer.lock(x1, y1, x2, y2, mode)
		if mode == "draw" or mode == "d" then
			return layer._edit(x1, x2, y1, y2, "ld")
		elseif mode == "erase" or mode == "e" then
			return layer._edit(x1, x2, y1, y2, "le")
		elseif mode == "unlock" or mode == "u" then
			return layer._edit(x1, x2, y1, y2, "u")
		end
	end

	------------------------------------------------------------------------------
	-- Tiles to Pixels Conversion
	------------------------------------------------------------------------------
	function layer.tilesToPixels(x, y)
		local x, y = getXY(x, y)

		if not ((x ~= nil) and (y ~= nil)) then verby_error("Missing argument(s).") end

		x, y = x - 0.5, y - 0.5
		x, y = (x * mapData.stats.tileWidth), (y * mapData.stats.tileHeight)

		return x, y
	end

	------------------------------------------------------------------------------
	-- Pixels to Tiles Conversion
	------------------------------------------------------------------------------
	function layer.pixelsToTiles(x, y)
		local x, y = getXY(x, y)

		if not ((x ~= nil) and (y ~= nil)) then verby_error("Missing argument(s).") end
		
		return math_ceil(x / mapData.stats.tileWidth), math_ceil(y / mapData.stats.tileHeight)
	end

	------------------------------------------------------------------------------
	-- Tile by Pixels
	------------------------------------------------------------------------------
	function layer.tileByPixels(x, y)
		local x, y = layer.pixelsToTiles(x, y)
		return layer.tile(x, y)
	end

	------------------------------------------------------------------------------
	-- Get Tiles in Range
	------------------------------------------------------------------------------
	function layer._getTilesInRange(x, y, w, h)
		local t = {}
		for xPos = x, x + w do
			for yPos = y, y + h do
				local tile = layer.tile(xPos, yPos)
				if tile then
					table_insert(t, tile)
				end
			end
		end

		return t
	end

	------------------------------------------------------------------------------
	-- Tile Iterators
	------------------------------------------------------------------------------
	function layer.tilesInRange(x, y, w, h)
		if not ((x ~= nil) and (y ~= nil) and (w ~= nil) and (h ~= nil)) then verby_error("Missing argument(s).") end

		local tiles = layer._getTilesInRange(x, y, w, h)
		
		local i = 0
		return function()
			i = i + 1
			if tiles[i] then return tiles[i] else return nil end
		end
	end

	function layer.tilesInRect(x, y, w, h)
		if not ((x ~= nil) and (y ~= nil) and (w ~= nil) and (h ~= nil)) then verby_error("Missing argument(s).") end

		local tiles = layer._getTilesInRange(x - w, y - h, w * 2, h * 2)

		local i = 0
		return function()
			i = i + 1
			if tiles[i] then return tiles[i] else return nil end
		end
	end

	------------------------------------------------------------------------------
	-- Destroy Layer
	------------------------------------------------------------------------------
	function layer.destroy()
		display.remove(layer)
		layer = nil
	end

	------------------------------------------------------------------------------
	-- Finish Up
	------------------------------------------------------------------------------
	addProperties(props, "props", layer.props)
	addProperties(props, "layer", layer)

	return layer
end

return tilelayer