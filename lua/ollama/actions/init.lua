---@type table<string, Ollama.PromptAction>
local actions = {}

local factory = require("ollama.actions.factory")

actions.display = factory.build({ display = true, show_prompt = true })

actions.insert = factory.build({ display = false, insert = true })

actions.replace = factory.build({ display = false, replace = true })

-- basically a merge of display -> replace actions
-- lots of duplicated code
actions.display_replace = factory.build({
	replace = true,
	show_prompt = true,
})

actions.display_insert = factory.build({ insert = true, show_prompt = true })

-- TODO: remove this as its not used anymore
actions.display_prompt = actions.display

return actions
