---@type table<string, Ollama.PromptAction>
local actions = {}

actions.display = {
	fn = function(prompt)
		local tokens = {}
		local out_buf = vim.api.nvim_create_buf(false, true)
		-- show a rotating spinner while waiting for the response
		local timer = require("ollama.util").show_spinner(out_buf)

		local out_win = vim.api.nvim_open_win(out_buf, true, {
			relative = "editor",
			width = 160,
			height = 25,
			row = 10,
			col = 10,
			style = "minimal",
			border = "rounded",
			title = prompt.model,
			title_pos = "center",
		})

		-- vim.api.nvim_buf_set_name(out_buf, "OllamaOutput")
		vim.api.nvim_set_option_value("filetype", "markdown", { buf = out_buf })
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = out_buf })
		vim.api.nvim_set_option_value("wrap", true, { win = out_win })

		-- set some keybinds for the buffer
		vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

		---@type Job?
		local job
		vim.api.nvim_buf_attach(out_buf, false, {
			on_detach = function()
				if job ~= nil then
					job:shutdown()
				end
			end,
		})

		---@type Ollama.PromptActionResponseCallback
		return function(body, _job)
			if timer:is_active() then
				timer:stop()
			end
			if job == nil and _job ~= nil then
				job = _job
			end
			table.insert(tokens, body.response)
			vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, vim.split(table.concat(tokens), "\n"))

			if body.done then
				vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })
			end
		end
	end,

	opts = {
		stream = true,
	},
}

actions.insert = {
	fn = function(prompt)
		return function(body) end
	end,

	opts = { stream = false },
}

return actions
