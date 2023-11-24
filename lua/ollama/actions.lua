---@type table<string, Ollama.PromptAction>
local actions = {}
actions.display = {
	fn = function(prompt)
		local tokens = {}
		local out_buf = vim.api.nvim_create_buf(false, true)
		require("ollama.util").open_floating_win(out_buf, { title = prompt.model })
		-- show a rotating spinner while waiting for the response
		local timer = require("ollama.util").show_spinner(out_buf)

		-- set some keybinds for the buffer
		vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

		---@type Job?
		local job
		local is_cancelled = false
		vim.api.nvim_buf_attach(out_buf, false, {
			on_detach = function()
				if job ~= nil then
					is_cancelled = true
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
				if is_cancelled then
					job:shutdown()
				end
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
		local bufnr = vim.fn.bufnr("%") or 0
		local cursorLine = vim.fn.line(".") or 1
		vim.notify("Sending request...", vim.log.levels.INFO, { title = "Ollama" })

		return function(body)
			local text = body.response
			if prompt.extract then
				text = text:match(prompt.extract)
			end

			if text == nil then
				vim.api.nvim_notify("No match found", vim.log.levels.INFO, { title = "Ollama" })
				return
			end

			local lines = vim.split(text, "\n")
			vim.api.nvim_buf_set_lines(bufnr, cursorLine, cursorLine, false, lines)
		end
	end,

	opts = { stream = false },
}

actions.replace = {
	fn = function(prompt)
		local bufnr = vim.fn.bufnr("%") or 0
		local sel_pos = require("ollama.util").get_selection_pos()

		if sel_pos == nil then
			vim.api.nvim_notify("No selection found", vim.log.levels.INFO, { title = "Ollama" })
			return false
		end

		vim.api.nvim_notify("Sending request...", vim.log.levels.INFO, { title = "Ollama" })

		return function(body)
			local text = body.response
			if prompt.extract then
				text = text:match(prompt.extract)
			end

			if text == nil then
				vim.api.nvim_notify("No match found", vim.log.levels.INFO, { title = "Ollama" })
				return
			end

			local lines = vim.split(text, "\n")
			local start_line, start_col, end_line, end_col = unpack(sel_pos)
			vim.api.nvim_buf_set_text(bufnr, start_line, start_col, end_line, end_col, lines)
		end
	end,

	opts = { stream = false },
}

-- basically a merge of display -> replace actions
-- lots of duplicated code
actions.display_replace = {
	fn = function(prompt)
		local bufnr = vim.fn.bufnr("%") or 0
		local sel_pos = require("ollama.util").get_selection_pos()

		if sel_pos == nil then
			vim.api.nvim_notify("No selection found", vim.log.levels.INFO, { title = "Ollama" })
			return false
		end

		local tokens = {}
		local out_buf = vim.api.nvim_create_buf(false, true)
		local out_win = require("ollama.util").open_floating_win(out_buf, { title = prompt.model })
		-- show a rotating spinner while waiting for the response
		local timer = require("ollama.util").show_spinner(out_buf)

		-- set some keybinds for the buffer
		vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

		---@type Job?
		local job
		local is_cancelled = false
		vim.api.nvim_buf_attach(out_buf, false, {
			on_detach = function()
				if job ~= nil then
					is_cancelled = true
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
				if is_cancelled then
					job:shutdown()
				end
			end
			table.insert(tokens, body.response)
			local lines = vim.split(table.concat(tokens), "\n")
			vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, lines)

			if body.done then
				local text = table.concat(lines, "\n")
				if prompt.extract then
					text = text:match(prompt.extract)
				end

				if text == nil then
					vim.api.nvim_notify("No match found", vim.log.levels.INFO, { title = "Ollama" })
					return
				end

				lines = vim.split(text, "\n")
				local start_line, start_col, end_line, end_col = unpack(sel_pos)
				vim.api.nvim_buf_set_text(bufnr, start_line, start_col, end_line, end_col, lines)

				-- close the floating window
				if vim.api.nvim_win_is_valid(out_win) then
					vim.api.nvim_win_close(out_win, true)
				end
			end
		end
	end,

	opts = { stream = true },
}

actions.display_insert = {
	fn = function(prompt)
		local bufnr = vim.fn.bufnr("%") or 0
		local cursorLine = vim.fn.line(".") or 1

		local tokens = {}
		local out_buf = vim.api.nvim_create_buf(false, true)
		local out_win = require("ollama.util").open_floating_win(out_buf, { title = prompt.model })
		-- show a rotating spinner while waiting for the response
		local timer = require("ollama.util").show_spinner(out_buf)

		-- set some keybinds for the buffer
		vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

		---@type Job?
		local job
		local is_cancelled = false
		vim.api.nvim_buf_attach(out_buf, false, {
			on_detach = function()
				if job ~= nil then
					is_cancelled = true
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
				if is_cancelled then
					job:shutdown()
				end
			end
			table.insert(tokens, body.response)
			local lines = vim.split(table.concat(tokens), "\n")
			vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, lines)

			if body.done then
				local text = table.concat(lines, "\n")
				if prompt.extract then
					text = text:match(prompt.extract)
				end

				if text == nil then
					vim.api.nvim_notify("No match found", vim.log.levels.INFO, { title = "Ollama" })
					return
				end

				lines = vim.split(text, "\n")
				vim.api.nvim_buf_set_lines(bufnr, cursorLine, cursorLine, false, lines)

				-- close the floating window
				if vim.api.nvim_win_is_valid(out_win) then
					vim.api.nvim_win_close(out_win, true)
				end
			end
		end
	end,

	opts = { stream = true },
}

actions.display_prompt = {
	fn = function(prompt)
		local input_label = prompt.input_label or "> "
		local display_prompt = input_label .. " " .. prompt.parsed_prompt .. "\n\n"
		local tokens = { display_prompt .. "\n\n" }
		local out_buf = vim.api.nvim_create_buf(false, true)
		require("ollama.util").open_floating_win(out_buf, { title = prompt.model })
		-- show a rotating spinner while waiting for the response
		local timer = require("ollama.util").show_spinner(out_buf, display_prompt)

		-- set some keybinds for the buffer
		vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

		---@type Job?
		local job
		local is_cancelled = false
		vim.api.nvim_buf_attach(out_buf, false, {
			on_detach = function()
				if job ~= nil then
					is_cancelled = true
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
				if is_cancelled then
					job:shutdown()
				end
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

return actions
