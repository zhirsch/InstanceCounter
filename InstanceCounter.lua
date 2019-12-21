﻿InstanceCounter = CreateFrame('Frame', 'InstanceCounter')
InstanceCounter:SetScript('OnEvent', function (addon, event, ...) addon[event](addon, ...) end)
InstanceCounter:SetScript('OnUpdate', function (addon, ...) addon["OnUpdate"](addon, ...) end)
InstanceCounter:RegisterEvent('ADDON_LOADED')
InstanceCounter.ADDONNAME = 'InstanceCounter'
InstanceCounter.ADDONVERSION = GetAddOnMetadata(InstanceCounter.ADDONNAME, 'Version');
InstanceCounter.ADDONAUTHOR = GetAddOnMetadata(InstanceCounter.ADDONNAME, 'Author');

local self = InstanceCounter;
local L = InstanceCounterLocals
local C = {
	BLUE	= '|cff00ccff';
	GREEN	= '|cff66ff33';
	RED		= '|cffff3300';
	YELLOW	= '|cffffff00';
	WHITE	= '|cffffffff';
}
local db = {};
local prefix = C.GREEN .. L['NAME'] .. C.WHITE .. ': '

local ADDON_MESSAGE_PREFIX = 'INSTANCE_COUNTER'
local ADDON_MESSAGE_RESET_SPECIFIC = 'INSTANCE RESET\t'


function InstanceCounter:ADDON_LOADED(frame)
	if frame ~= InstanceCounter.ADDONNAME then return end
	
	self:UnregisterEvent('ADDON_LOADED');
	self.ADDON_LOADED = nil;
	
	-- Init DB
	if InstanceCounterDB == nil then InstanceCounterDB = {} end
	if InstanceCounterDB.List == nil then InstanceCounterDB.List = {} end
	db = InstanceCounterDB;
	
	-- Register Events
	self.ClearOldInstances();
	self:RegisterEvent('PLAYER_ENTERING_WORLD');
	self:RegisterEvent('CHAT_MSG_ADDON');
	
	if # db.List >= 1 then
		self:RegisterEvent('CHAT_MSG_SYSTEM');
	end	

	successfulRequest = C_ChatInfo.RegisterAddonMessagePrefix(ADDON_MESSAGE_PREFIX)
	if not successfulRequest then
		print(prefix .. C.RED .. L['TOO_MANY_PREFIXES'])
	end
end

function InstanceCounter:PLAYER_ENTERING_WORLD()
	self.ClearOldInstances();
	
	if IsInInstance() then 
		self.AddCurrentInstance()
	end		
end

function InstanceCounter:CHAT_MSG_SYSTEM(msg)
	if msg == TRANSFER_ABORT_TOO_MANY_INSTANCES then
		self.ClearOldInstances()
		self.PrintTimeUntilReset()
	end
	
	if msg == ERR_LEFT_GROUP_YOU then
		self.ResetInstancesForCharacter(UnitName('player'))
	end

	name = string.match(msg, '(.*) has been reset')
	if name ~= nil then
		self.ResetInstanceByName(name)
		if IsInGroup() then
			self.Broadcast(name)
		end
	end
end

function InstanceCounter:CHAT_MSG_ADDON(prefix, msg, channel, sender)
	if prefix ~= ADDON_MESSAGE_PREFIX or channel ~= 'PARTY' then 
		return 
	end

	name = string.match(msg, ADDON_MESSAGE_RESET_SPECIFIC .. '(.+)')
	if name ~= nil then
		self.ResetInstanceByName(name)
	end
end


function InstanceCounter:OnUpdate(sinceLastUpdate)
	self.sinceLastUpdate = (self.sinceLastUpdate or 0) + sinceLastUpdate;
	if self.sinceLastUpdate >= 5 then
		self.sinceLastUpdate = 0;

		self.ClearOldAndPrint()
		
		if IsInInstance() then
			self.UpdateTimeInInstance()
		end
	end
end

function InstanceCounter.Broadcast(name)
	success = C_ChatInfo.SendAddonMessage(ADDON_MESSAGE_PREFIX, ADDON_MESSAGE_RESET_SPECIFIC .. name, 'PARTY')
	if not success then
		print(prefix .. C.RED .. L['MESSAGE_NOT_SENT'])
	end
end

function InstanceCounter.UpdateTimeInInstance()
	local name, instanceType, difficultyID = GetInstanceInfo();
	if instanceType ~= "party" and instanceType ~= "raid" then
		return
	end

	local character = UnitName('player')

	for i = 1, # db.List do
		if db.List[i].reset == false and 
			db.List[i].name == name and 
			db.List[i].instanceType == instanceType and 
			db.List[i].difficultyID == difficultyID and 
			db.List[i].character == character then
			db.List[i].lastSeen = time();
		end
	end	
end

function InstanceCounter.AddCurrentInstance()
	local name, instanceType, difficultyID = GetInstanceInfo();
	if instanceType ~= "party" and instanceType ~= "raid" then return end
	
	self.AddInstance(name, instanceType, difficultyID);

	if # db.List >= 5 then
		self.PrintTimeUntilReset()
	end
end

function InstanceCounter.AddInstance(name, instanceType, difficultyID)
	if self.IsInstanceInList(name, instanceType, difficultyID) then return end

	local instance = {
		name		= name;
		instanceType= instanceType;
		difficultyID= difficultyID;
		character	= UnitName('player');
		reset		= false;
		saved		= self.IsPlayerSavedToInstance(name, instanceType, difficultyID);
		entered		= time();
		lastSeen	= time();
		resetTime	= nil;
	}
	
	table.insert(db.List, instance);
	self.SortInstances();

	self:RegisterEvent('CHAT_MSG_SYSTEM');
end


function InstanceCounter.ClearInstances()
	db.List = {};
	self:UnregisterEvent('CHAT_MSG_SYSTEM');
end

function InstanceCounter.ClearOldInstances()
	local t = time()
	local removed = false
	
	for i = # db.List, 1, -1 do
		if t - db.List[i].lastSeen > 3600 then
			table.remove(db.List, i)
			removed = true
		end
	end

	self.SortInstances();

	if # db.List == 0 then
		self:UnregisterEvent('CHAT_MSG_SYSTEM');
	end
	return removed
end

function InstanceCounter.IsInstanceInList(name, instanceType, difficultyID)
	for i = 1, # db.List do
		if name == db.List[i].name and 
		   instanceType == db.List[i].instanceType and 
		   difficultyID == db.List[i].difficultyID and 
		   UnitName('player') == db.List[i].character and
		   (db.List[i].saved or not db.List[i].reset) then
			return true
		end
	end
	
	return false
end

function InstanceCounter.IsPlayerSavedToInstance(name, instanceType, difficultyID)
	if instanceType == 'party' and difficultyID == 1 then return false end

	for i = 1, GetNumSavedInstances() do
		local i_name,_,_, i_difficultyID, i_locked = GetSavedInstanceInfo(i);
		
		if i_name == name and 
		   i_difficultyID == difficultyID and 
		   i_locked then
			return true
		end
	end
	
	return false;
end

function InstanceCounter.ResetInstancesForParty()
	self.ResetInstancesForCharacter(UnitName('player'))

	for groupindex = 1,MAX_PARTY_MEMBERS do
		local playername = UnitName('party' .. groupindex)
		if playername ~= nil then
			self.ResetInstancesForCharacter(playername)
		end
	end		
end

function InstanceCounter.ResetInstancesForCharacter(playername)
	for i = 1, # db.List do
		if db.List[i].instanceType == 'party' and 
		   db.List[i].character == playername and 
		   not db.List[i].reset then				
			db.List[i].resetTime = time();
			db.List[i].reset = true;
		end
	end
end

function InstanceCounter.ResetInstanceByName(instance)
	for i = 1, # db.List do
		if db.List[i].name == instance and not db.List[i].reset then			
			db.List[i].reset = true;	
			db.List[i].resetTime = time();
		end
	end
end

function InstanceCounter.OnResetInstances()
	if IsInInstance() then return end

	if not IsInGroup() or UnitIsGroupLeader('player') then
		self.ResetInstancesForParty()
	end		
end


function InstanceCounter.SortInstances()
	table.sort(db.List, function(a, b) return a.entered < b.entered end);
end

function InstanceCounter.TimeRemaining(t)
	local t = 3600 - (time() - t);
	local neg = '';

	if t < 0 then 
		t = -t
		neg = '-'
	end

	return neg .. string.format("%.2d:%.2d", floor(t/60), t%60)
end



------ PRINT ------

function InstanceCounter.ClearOldAndPrint()
	if self.ClearOldInstances() and # db.List == 4 then
		print(prefix .. C.YELLOW .. L['OPEN_INSTANCES']);
	end
end

function InstanceCounter.PrintTimeUntilReset()
	if # db.List > 0 then
		if # db.List >= 5 then
			print(prefix .. C.YELLOW .. L['TIME_REMAINING'] .. self.TimeRemaining(db.List[1].lastSeen));
		else
			print(prefix .. C.YELLOW .. L['ONLY_ENTERED'] .. C.GREEN .. # db.List .. L['THIS_HOUR']);
		end
	else
		print(prefix .. C.YELLOW .. L['NO_INSTANCES']);
	end
end

function InstanceCounter.PrintInstances()
	self.ClearOldInstances();
	
	if # db.List > 0 then
		print(prefix .. C.YELLOW .. L['LIST_HEADERS']);
		for i = 1, # db.List do
			local i_color;
						
			if db.List[i].reset then
				i_color = C.RED
			else
				i_color = C.WHITE
			end
			print(C.WHITE .. db.List[i].character .. ' ' .. i_color .. db.List[i].name  .. C.WHITE .. ' ' .. self.TimeRemaining(db.List[i].lastSeen));
		end
	else
		print(prefix .. C.YELLOW .. L['NO_INSTANCES']);
	end
end


function InstanceCounter.PrintInstancesToChat(chat, channel)
	self.ClearOldInstances();
	
	if # db.List > 0 then
		SendChatMessage(L['LIST_HEADERS'], chat ,"Common", channel);
		for i = 1, # db.List do
			SendChatMessage(db.List[i].character .. ' - ' .. db.List[i].name  .. ' - ' .. self.TimeRemaining(db.List[i].lastSeen), chat ,"Common", channel);
		end
	else
		SendChatMessage(L['NO_INSTANCES'], chat ,"Common", channel);
	end
end

function InstanceCounter.PrintOptions()
	print(prefix .. L['CMD_LONG'] .. C.RED .. L['CMD_CMD'] .. C.WHITE .. ' ' .. L['OR']  .. ' ' .. L['CMD_SHORT'] .. C.RED .. L['CMD_CMD']);
	print(prefix .. C.RED .. L['CMD']['PRINT']['CMD'] .. C.WHITE .. L['CMD']['PRINT']['DESCRIPTION']);
	print(prefix .. C.RED .. L['CMD']['RESET']['CMD'] .. C.WHITE .. L['CMD']['RESET']['DESCRIPTION']);
	print(prefix .. C.RED .. L['CMD']['TIME']['CMD'] .. C.WHITE .. L['CMD']['TIME']['DESCRIPTION']);
end

------


hooksecurefunc('ResetInstances', function(...)
	self.OnResetInstances();
end)

SlashCmdList['InstanceCounter'] = function(txt)
	local txt, arg1, arg2 = strsplit(" ", txt, 3)
	if txt == L['CMD']['CLEAR']['CMD'] then
		InstanceCounter.ClearInstances()
		print(prefix .. C.YELLOW .. L['LIST_CLEARED']);
	elseif txt == L['CMD']['PRINT']['CMD'] then
		InstanceCounter.PrintInstances()
	elseif txt == L['CMD']['RESET']['CMD'] then
		InstanceCounter.ResetInstancesForParty()
		print(prefix .. C.YELLOW .. L['MANUAL_RESET']);
	elseif txt == L['CMD']['TIME']['CMD'] then
		InstanceCounter.PrintTimeUntilReset()
	elseif txt == 'chat' then
		InstanceCounter.PrintInstancesToChat(arg1, arg2)
	else
		InstanceCounter.PrintOptions()
	end
end