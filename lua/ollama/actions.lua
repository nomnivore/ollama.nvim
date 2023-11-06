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

actions.replace = {
	fn = function(prompt)
		local sel_start = vim.fn.getpos("'<")
		local sel_end = vim.fn.getpos("'>")
		local bufnr = vim.fn.bufnr("%") or 0
		local mode = vim.fn.visualmode()

		vim.notify("Sending request...", vim.log.levels.INFO, { title = "Ollama" })

		return function(body)
			vim.api.nvim_notify("Received response:\n" .. body.response, vim.log.levels.INFO, { title = "Ollama" })
			local text = body.response:match(prompt.extract)

			if text == nil then
				vim.api.nvim_notify("No match found", vim.log.levels.INFO, { title = "Ollama" })
				return
			end

			local lines = vim.split(text, "\n")
			local start_line, start_col, end_line, end_col

			-- assign positions based on visual or visual-line mode
			if mode == "v" then
				start_line = sel_start[2]
				start_col = sel_start[3]
				end_line = sel_end[2]
				end_col = sel_end[3]
			elseif mode == "V" then
				start_line = sel_start[2]
				start_col = 1
				end_line = sel_end[2]
				end_col = #vim.fn.getline(sel_end[2]) + 1
			end

			-- validate and adjust positions
			if start_line > end_line or (start_line == end_line and start_col > end_col) then
				start_line, end_line = end_line, start_line
				start_col, end_col = end_col, start_col
			end

			-- adjust for 0-based indexing
			start_line = start_line - 1
			start_col = start_col - 1
			end_line = end_line - 1
			end_col = end_col - 1

			vim.api.nvim_buf_set_text(bufnr, start_line, start_col, end_line, end_col, lines)
		end
	end,

	opts = { stream = false },
}

return actions
