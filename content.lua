-- includes
local http = require("resty.http") -- https://github.com/liseen/lua-resty-http
local cjson = require("cjson")
local bslib = require("bitset") -- https://github.com/bsm/bitset.lua

-- basic configuration
local block_size = 256*1024 -- Block size 256k
local backend = "http://127.0.0.1:8080/" -- backend
local fcttl = 30 -- Time to cache HEAD requests
local wait_lock = 0.01 -- Time to wait lock for concurrency access

local manage_stats = 0 -- 1 to compute Hit/Miss stats, 0 to disable

local bypass_headers = { 
	["expires"] = "Expires",
	["content-type"] = "Content-Type",
	["last-modified"] = "Last-Modified",
	["expires"] = "Expires",
	["cache-control"] = "Cache-Control",
	["server"] = "Server",
	["content-length"] = "Content-Length",
	["p3p"] = "P3P",
	["accept-ranges"] = "Accept-Ranges"
}

local httpc = http.new()

local cache_dict = nil
local file_dict = ngx.shared.file_dict 
local chunk_dict = nil
if manage_stats == 1 then
	cache_dict = ngx.shared.cache_dict
	chunk_dict = ngx.shared.chunk_dict
end

local sub = string.sub
local tonumber = tonumber
local ceil = math.ceil
local floor = math.floor
local error = error
local null = ngx.null
local match = ngx.re.match

local start = 0
local stop = -1

-- ngx.status = 206 -- Default HTTP status
local status = 206

-- register on_abort callback, reguires lua_check_client_abort
local ok, err = ngx.on_abort(function () 
	ngx.exit(499)
end)
if not ok then
	-- ngx.log(ngx.ERR, "Can't register on_abort function.", err)
	-- ngx.exit(500)
end

-- try reading values from dict, if not issue a HEAD request and save the value
local updating, flags = file_dict:get(ngx.var.uri .. "-update")
while updating do
	updating, flags = file_dict:get(ngx.var.uri .. "-update")
	ngx.sleep(wait_lock)
end

local origin_headers = {}
local origin_info = file_dict:get(ngx.var.uri .. "-info")
if not origin_info then
	file_dict:set(ngx.var.uri .. "-update", true, 5)
	local ok, code, headers, status, body = httpc:request { 
		url = backend .. ngx.var.uri, 
		method = 'HEAD' 
	}
        if code == 404 then
		file_dict:delete(ngx.var.uri .. "-update")
		ngx.status = code
		ngx.eof()
		return ngx.exit(code)
        end
 
	for key, value in pairs(bypass_headers) do
		origin_headers[value] = headers[key]
	end
	origin_info = cjson.encode(origin_headers)
	file_dict:set(ngx.var.uri .. "-info", origin_info, fcttl)
	file_dict:delete(ngx.var.uri .. "-update")
end

origin_headers = cjson.decode(origin_info)

local is_get = ngx.req.get_method()
if string.match(is_get, "HEAD") then
	for key, value in pairs(origin_headers) do
        	ngx.header[key] = value
        end
	-- should 
        ngx.status = 200
	ngx.send_headers()
        ngx.eof()
        return ngx.exit(ngx.status)
else
	if not string.match(is_get, "GET") then
		ngx.status = 500
		ngx.eof()
		return ngx.exit(ngx.status)
	end
end

ngx.status = status

-- parse range header
local range_header = ngx.req.get_headers()["Range"] or "bytes=0-"
local matches, err = match(range_header, "^bytes=(\\d+)?-([^\\\\]\\d+)?", "joi")
if matches then
	if matches[1] == nil and matches[2] then
		stop = (origin_headers["Content-Length"] - 1)
		start = (stop - matches[2]) + 1
	else
		start = matches[1] or 0
		stop = matches[2] or (origin_headers["Content-Length"] - 1)
	end
else
	stop = (origin_headers["Content-Length"] - 1)
end

for header, value in pairs(origin_headers) do
	ngx.header[header] = value
end

local cl = origin_headers["Content-Length"]
ngx.header["Content-Length"] = (stop - (start - 1))
ngx.header["Content-Range"] = "bytes " .. start .. "-" .. stop .. "/" .. cl

block_stop = (ceil(stop / block_size) * block_size)
block_start = (floor(start / block_size) * block_size)


local chunk_info, flags = nil, nil
local chunk_map = nil
if manage_stats == 1 then
	-- hits / miss info
	chunk_info, flags = chunk_dict:get(ngx.var.uri)
	chunk_map = bslib:new()
	if chunk_info then
		chunk_map.nums = cjson.decode(chunk_info)
	end
end

local bytes_miss, bytes_hit = 0, 0

for block_range_start = block_start, stop, block_size do
	local block_range_stop = (block_range_start + block_size) - 1
	local block_id = (floor(block_range_start / block_size))
	local content_start = 0
	local content_stop = block_size

	local block_status = nil
	if manage_stats == 1 then
		block_status = chunk_map:get(block_id)
		if block_status then
			bytes_hit = bytes_hit + (content_stop - content_start)
		else
			bytes_miss = bytes_miss + (content_stop - content_start)
		end
	end

	if block_range_start == block_start then
		content_start = (start - block_range_start)
	end

	if (block_range_stop + 1) == block_stop then
		content_stop = (stop - block_range_start) + 1
	end

end


if manage_stats == 1 then
	if bytes_miss > 0 then
		ngx.var.ranger_cache_status = "MISS"
		ngx.header["X-Cache"] = "MISS"
	else
		ngx.var.ranger_cache_status = "HIT"
		ngx.header["X-Cache"] = "HIT"
	end
	ngx.header["X-Bytes-Hit"] = bytes_hit
	ngx.header["X-Bytes-Miss"] = bytes_miss
end

ngx.send_headers()

-- fetch the content from the backend
for block_range_start = block_start, stop, block_size do
	local block_range_stop = (block_range_start + block_size) - 1
	local block_id = (floor(block_range_start / block_size))
	local content_start = 0
	local content_stop = -1

	ngx.log(ngx.ERR, "block ", block_range_start, " => ",  ngx.now())

	local req_params = {
		url = backend .. ngx.var.uri,
		method = 'GET',
		headers = {
			Range = "bytes=" .. block_range_start .. "-" .. block_range_stop,
		}
	}

	req_params["body_callback"] =	function(data, chunked_header, ...)
						if chunked_header then return end
							ngx.print(data)
							ngx.flush(true)
					end

	if block_range_start == block_start then
		req_params["body_callback"] = nil
		content_start = (start - block_range_start)
	end

	if (block_range_stop + 1) == block_stop then
		req_params["body_callback"] = nil
		content_stop = (stop - block_range_start) + 1
	end

	local ok, code, headers, status, body  = httpc:request(req_params)
	if body then
		ngx.print(sub(body, (content_start + 1), content_stop)) -- lua count from 1
	end

	if manage_stats == 1 then
		if headers and match(headers["x-cache"],"HIT") then
			chunk_map:set(block_id)
			cache_dict:incr("cache_hit", 1)
		else
			chunk_map:clear(block_id)
			cache_dict:incr("cache_miss", 1)
		end
	end
end
if manage_stats == 1 then
	ngx.log(ngx.ERR, "before csjon ", ngx.now())
	chunk_dict:set(ngx.var.uri,cjson.encode(chunk_map.nums))
	ngx.log(ngx.ERR, "after cjson ", ngx.now())
end
ngx.eof()
return ngx.exit(status)
