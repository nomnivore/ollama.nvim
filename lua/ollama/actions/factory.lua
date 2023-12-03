local factory = {}

---@class Ollama.ActionFactoryBuildOpts
---@field display boolean? whether to display the response (default: true)
---@field insert boolean? whether to insert the response at the cursor (default: false)
---@field replace boolean? whether to replace the selection with the response. Precedes `insert` (default: false)
---@field show_prompt boolean? whether to prepend the display buffer with the parsed prompt (default: false)
---@field window "float" | "split" | "vsplit" | nil type of window to display the response in (default: "float") (NOT YET IMPLEMENTED)

---@type Ollama.ActionFactoryBuildOpts
local default_opts = {
	display = true,
	insert = false,
	replace = false,
	show_prompt = false,
	window = "float",
}

---@param opts Ollama.ActionFactoryBuildOpts
function factory.create_action(opts)
	-- prepare for the ugliest most deeply nested if statements you've ever seen
	-- I'm so sorry

	opts = vim.tbl_extend("force", default_opts, opts or {})
	---@type Ollama.PromptAction
	local action = {
		fn = function(prompt)
			local tokens = {}

			-- stuff for display
			local out_buf
			local out_win
			local timer
			local pre_lines

			-- stuff for insert
			local bufnr
			local cursorLine
			if opts.insert then
				bufnr = vim.fn.bufnr("%") or 0
				cursorLine = vim.fn.line(".") or 1
			end

			-- stuff for replace
			local sel_pos
			if opts.replace then
				bufnr = vim.fn.bufnr("%") or 0
				sel_pos = require("ollama.util").get_selection_pos()
				if sel_pos == nil then
					vim.api.nvim_notify("No selection found", vim.log.levels.INFO, { title = "Ollama" })
					return false
				end
			end

			---@type Job?
			local job
			local is_cancelled = false

			if opts.display then
				out_buf = vim.api.nvim_create_buf(false, true)
				local input_label = prompt.input_label or "> "
				local display_prompt = input_label .. " " .. prompt.parsed_prompt .. "\n\n"
				pre_lines = vim.split(display_prompt, "\n")
				vim.api.nvim_buf_set_lines(out_buf, 0, -1, false, pre_lines)

				if opts.window == "float" then
					out_win = require("ollama.util").open_floating_win(out_buf, { title = prompt.model })
				elseif opts.window == "split" then
					vim.cmd("split")
					out_win = vim.api.nvim_get_current_win()
					require("ollama.util").set_output_options(out_buf, out_win)
					vim.api.nvim_win_set_buf(out_win, out_buf)
				elseif opts.window == "vsplit" then
					vim.cmd("vsplit")
					out_win = vim.api.nvim_get_current_win()
					require("ollama.util").set_output_options(out_buf, out_win)
					vim.api.nvim_win_set_buf(out_win, out_buf)
				end

				timer = require("ollama.util").show_spinner(out_buf, { start_ln = #pre_lines, end_ln = #pre_lines + 1 }) -- the +1 makes sure the old spinner is replaced

				-- empty lines as padding so that the response lands in the right place
				vim.api.nvim_buf_set_lines(out_buf, -1, -1, false, { "", "" })

				-- set some keybinds for the buffer
				vim.api.nvim_buf_set_keymap(out_buf, "n", "q", "<cmd>q<cr>", { noremap = true })

				vim.api.nvim_buf_attach(out_buf, false, {
					on_detach = function()
						if job ~= nil then
							is_cancelled = true
							job:shutdown()
						end
					end,
				})
			end

			---@type Ollama.PromptActionResponseCallback
			return function(body, _job)
				-- TODO: implement
				if job == nil and _job ~= nil then
					job = _job
					if is_cancelled and timer then
						timer:stop()
						job:shutdown()
					end
				end
				table.insert(tokens, body.response)
				local lines = vim.split(table.concat(tokens), "\n")

				if opts.display then
					vim.api.nvim_buf_set_lines(out_buf, #pre_lines + 2, -1, false, lines)
				end

				if body.done then
					if timer then
						timer:stop()
					end

					if opts.display then
						vim.api.nvim_buf_set_lines(out_buf, #pre_lines, #pre_lines + 1, false, {
							("> %s in %ss."):format(
								prompt.model,
								require("ollama.util").nano_to_seconds(body.total_duration)
							),
						})
						vim.api.nvim_set_option_value("modifiable", false, { buf = out_buf })
					end

					if opts.insert or opts.replace then
						local text = table.concat(lines, "\n")
						if prompt.extract then
							text = text:match(prompt.extract)
						end

						if text == nil then
							vim.api.nvim_notify("No match found", vim.log.levels.INFO, { title = "Ollama" })
							return
						end

						lines = vim.split(text, "\n")

						if opts.replace then
							local start_line, start_col, end_line, end_col = unpack(sel_pos)
							vim.api.nvim_buf_set_text(bufnr, start_line, start_col, end_line, end_col, lines)
						elseif opts.insert then
							vim.api.nvim_buf_set_lines(bufnr, cursorLine, cursorLine, false, lines)
						end

						-- close floating window when done insert/replacing
						if out_win and vim.api.nvim_win_is_valid(out_win) then
							vim.api.nvim_win_close(out_win, true)
						end
					end
				end
			end
		end,
	}

	action.opts = { stream = true }

	return action
end

return factory
