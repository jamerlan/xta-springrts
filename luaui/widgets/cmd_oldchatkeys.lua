function widget:GetInfo()
	return {
		name = "Old chat keys",
		desc = "Binds alt/shift+enter for ally/spec chat, alt+backspace for fullscreen toggle" ,
		author = "",
		date = "",
		license = "Anyone who uses this widget has to email me a horse",
		layer = 0,
		enabled = false
	}
end

local binds={
	"bind      Alt+backspace  fullscreen",
	"bind          Alt+enter  chatally",
	"bind          Alt+enter  chatswitchally",
	"bind         Ctrl+enter  chatall",
	"bind         Ctrl+enter  chatswitchall",
	"bind        Shift+enter  chatspec",
	"bind        Shift+enter  chatswitchspec",
	"bind 				   o  buildfacing inc",
	--"bind          Any+enter  chat", --default, bound by engine
	--"bind          Any+enter  edit_return", --default, bound by engine
}

local unbinds={
	"bind Alt+enter fullscreen",
}

function widget:Initialize()
	for k,v in ipairs(unbinds) do
		Spring.SendCommands("un"..v)
	end
	for k,v in ipairs(binds) do
		Spring.SendCommands(v)
	end
end

function widget:Shutdown()
	for k,v in ipairs(binds) do
		Spring.SendCommands("un"..v)
	end
	for k,v in ipairs(unbinds) do
		Spring.SendCommands(v)
	end
end