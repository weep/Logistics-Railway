require "util"
require "defines"

script.on_event(defines.events.on_built_entity, function(event)
	if event.created_entity.name == "entity-ghost" then
		if event.created_entity.ghost_name == "requester-rail" or event.created_entity.ghost_name == "passive-provider-rail" or event.created_entity.ghost_name == "active-provider-rail" or event.created_entity.ghost_name == "storage-rail" then
			if event.created_entity.direction == defines.direction.northeast or event.created_entity.direction == defines.direction.southeast or event.created_entity.direction == defines.direction.southwest or event.created_entity.direction == defines.direction.northwest then
				event.created_entity.destroy() -- No diagonal ghosts allowed
				return
			end
			orderEntityDeconstruction(event.created_entity.surface, "requester-rail", event.created_entity.position) -- No overlapping Logistics Rails allowed
			orderEntityDeconstruction(event.created_entity.surface, "passive-provider-rail", event.created_entity.position)
			orderEntityDeconstruction(event.created_entity.surface, "active-provider-rail", event.created_entity.position)
			orderEntityDeconstruction(event.created_entity.surface, "storage-rail", event.created_entity.position)
			return
		end
	end
	local player = game.get_player(event.player_index)
	if event.created_entity.name == "requester-rail" or event.created_entity.name == "passive-provider-rail" or event.created_entity.name == "active-provider-rail" or event.created_entity.name == "storage-rail" then
		if event.created_entity.direction == defines.direction.northeast or event.created_entity.direction == defines.direction.southeast or event.created_entity.direction == defines.direction.southwest or event.created_entity.direction == defines.direction.northwest then
			local previous_name = player.cursor_stack.name .. ""	-- All this is to disallow placement of diagonal Logistics Rails, and snap the rotation back to orthogonal if it gets stuck in diagonal
			local previous_count = player.cursor_stack.count + 0
			event.created_entity.destroy()
			player.cursor_stack.set_stack{name="straight-rail", count=1}
			player.rotate_for_build()
			player.cursor_stack.set_stack()
			player.insert{name=previous_name, count=(previous_count) + 1}
			return
		end
		removeDummy(event.created_entity.surface, "requester-rail-dummy-chest", event.created_entity.position) -- Don't want any duplicate dummy chests
		if removeDummy(event.created_entity.surface, "straight-rail", event.created_entity.position) then
			player.insert{name="straight-rail", count=1}
		end
	end
	if event.created_entity.name == "requester-rail" then
		insertDummyItem(event.created_entity.surface, "requester-rail-dummy-chest", event.created_entity.position, event.created_entity.force)
	end
end)

script.on_event(defines.events.on_robot_built_entity, function(event)
	removeDummy(event.created_entity.surface, "requester-rail-dummy-chest", event.created_entity.position) -- Don't want any duplicate dummy chests
	if event.created_entity.name == "requester-rail" or event.created_entity.name == "passive-provider-rail" or event.created_entity.name == "active-provider-rail" or event.created_entity.name == "storage-rail" then
		orderEntityDeconstruction(event.created_entity.surface, "straight-rail", event.created_entity.position) -- While vanilla Straight Rails can coexist on the same tile, Logistics Rails should not
	end
	if event.created_entity.name == "requester-rail" then
		insertDummyItem(event.created_entity.surface, "requester-rail-dummy-chest", event.created_entity.position, event.created_entity.force)
	end
end)

script.on_event(defines.events.on_preplayer_mined_item, function(event)
	if event.entity.name == "requester-rail-dummy-chest" then
		removeDummy(event.entity.surface, "requester-rail", event.entity.position)
		return event.entity.clear_items_inside()
	end
	if event.entity.name == "requester-rail" then
		removeDummy(event.entity.surface, "requester-rail-dummy-chest", event.entity.position)
	end
end)

script.on_event(defines.events.on_robot_pre_mined, function(event) -- The dummy chest can't actually be robo-deconstructed, so we don't have to worry about it
	if event.entity.name == "requester-rail" then
		removeDummy(event.entity.surface, "requester-rail-dummy-chest", event.entity.position)
	end
end)

script.on_event(defines.events.on_entity_died, function(event) -- The dummy chest also can't die (indestructible), so we don't have to worry about it
	if event.entity.name == "requester-rail" then
		removeDummy(event.entity.surface, "requester-rail-dummy-chest", event.entity.position)
	end
end)

script.on_event(defines.events.on_train_changed_state, function(event)
	if event.train.state == defines.trainstate.wait_station and event.train.speed == 0 then -- Wagons only interact with the logistics network when they are waiting at a station in automatic mode
		placeChests(event.train)
	else
		syncChests(event.train)
	end
end)

function copyInventory(from, to)
	local inventory = from.get_inventory(defines.inventory.chest)
	local contents = inventory.get_contents()
	for n, c in pairs(contents) do
		to.insert({name=n, count=c})
	end
end

function placeChests(train)
	for i = 1, #train.cargo_wagons do
		local wagon = train.cargo_wagons[i]
		if wagon.type == "cargo-wagon" then
			local requester = wagon.surface.find_entity("requester-rail", wagon.position)
			local passive_provider = wagon.surface.find_entity("passive-provider-rail", wagon.position)
			local active_provider = wagon.surface.find_entity("active-provider-rail", wagon.position)
			local storage = wagon.surface.find_entity("storage-rail", wagon.position)
			if requester then
				wagon.minable = false -- Don't want any changes to the wagon's inventory while it's been copied over to the proxy chest
				wagon.operable = false
				local chest = wagon.surface.create_entity({name = "requester-chest-from-wagon", position = wagon.position, force = wagon.force})
				local wagon_inventory = wagon.get_inventory(defines.inventory.chest)
				wagon_inventory.setbar(0)
				local chest_inventory = chest.get_inventory(defines.inventory.chest)
				if #chest_inventory > #wagon_inventory then
					chest_inventory.setbar(#wagon_inventory)	-- Limit the chest inventory size to equal the wagon inventory size; proxy chest has a lot of slots to accommodate modded wagons
				end
				copyInventory(wagon, chest) -- Wagon to chest
				wagon.clear_items_inside()
				local dummy_requester = wagon.surface.find_entity("requester-rail-dummy-chest", wagon.position)
				for s = 1, 10 do			-- It seems all requester chests are limited to 10 request slots
					local request = dummy_requester.get_request_slot(s)
					if request then
						chest.set_request_slot(request, s)
					end
				end
			end
			if passive_provider then
				wagon.minable = false
				wagon.operable = false
				local chest = wagon.surface.create_entity({name = "passive-provider-chest-from-wagon", position = wagon.position, force = wagon.force})
				local wagon_inventory = wagon.get_inventory(defines.inventory.chest)
				wagon_inventory.setbar(0)
				copyInventory(wagon, chest) -- Wagon to chest
				wagon.clear_items_inside()
			end
			if active_provider then
				wagon.minable = false
				wagon.operable = false
				local chest = wagon.surface.create_entity({name = "active-provider-chest-from-wagon", position = wagon.position, force = wagon.force})
				local wagon_inventory = wagon.get_inventory(defines.inventory.chest)
				wagon_inventory.setbar(0)
				copyInventory(wagon, chest) -- Wagon to chest
				wagon.clear_items_inside()
			end
			if storage then
				wagon.minable = false
				wagon.operable = false
				local chest = wagon.surface.create_entity({name = "storage-chest-from-wagon", position = wagon.position, force = wagon.force})
				local wagon_inventory = wagon.get_inventory(defines.inventory.chest)
				wagon_inventory.setbar(0)
				local chest_inventory = chest.get_inventory(defines.inventory.chest)
				if #chest_inventory > #wagon_inventory then
					chest_inventory.setbar(#wagon_inventory) -- Limit the chest inventory size to equal the wagon inventory size; proxy chest has a lot of slots to accommodate modded wagons
				end
				copyInventory(wagon, chest) -- Wagon to chest
				wagon.clear_items_inside()
			end
		end
	end
end

function syncChests(train)
	for i = 1, #train.cargo_wagons do
		local wagon = train.cargo_wagons[i]
		if wagon.type == "cargo-wagon" then
			prepareDeparture(wagon, "requester-chest-from-wagon")
			prepareDeparture(wagon, "passive-provider-chest-from-wagon")
			prepareDeparture(wagon, "active-provider-chest-from-wagon")
			prepareDeparture(wagon, "storage-chest-from-wagon")
		end
	end
end

function prepareDeparture(wagon, chestName)
	local chest = wagon.surface.find_entity(chestName, wagon.position)
	if chest then
		local wagon_inventory = wagon.get_inventory(defines.inventory.chest)
		wagon_inventory.setbar()
		copyInventory(chest, wagon) -- Chest to wagon
		chest.destroy()
		wagon.minable = true
		wagon.operable = true
	end
end

function orderEntityDeconstruction(surface, entityName, position)
	local chest = surface.find_entity(entityName, position)
	if chest then
		chest.order_deconstruction(chest.force)
	end
end

function insertDummyItem(surface, chestName, chestPosition, chestForce)
	local dummy = surface.create_entity({name = chestName, position = chestPosition, force = chestForce})
	dummy.insert{name="dummy-item", count=1}
end

function removeDummy(surface, dummyName, position)
	local dummy = surface.find_entity(dummyName, position)
	if dummy then
		dummy.destroy()
		return true
	end
	return false
end
