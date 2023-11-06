local util = {}

---@param cb fun(body: table, job: Job?)
function util.handle_stream(cb)
	---@param job Job?
	return function(_, chunk, job)
		vim.schedule(function()
			local _, body = pcall(function()
				return vim.json.decode(chunk)
			end)
			if type(body) ~= "table" or body.response == nil then
				return
			end
			cb(body, job)
		end)
	end
end

-- Show a spinner in the given buffer (overwrites existing lines)
---@param bufnr number The buffer to show the spinner in
function util.show_spinner(bufnr)
	local spinner_chars = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local curr_char = 1
	local timer = vim.loop.new_timer()
	timer:start(
		100,
		100,
		vim.schedule_wrap(function()
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Generating... " .. spinner_chars[curr_char], "" })
			curr_char = curr_char % #spinner_chars + 1
		end)
	)

	return timer
end

return util
