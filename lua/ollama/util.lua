local util = {}

---@param cb fun(body: table)
function util.handle_stream(cb)
	return function(_, chunk)
		vim.schedule(function()
			local _, body = pcall(function()
				return vim.json.decode(chunk)
			end)
			if type(body) ~= "table" or body.response == nil then
				return
			end
			cb(body)
		end)
	end
end

return util
