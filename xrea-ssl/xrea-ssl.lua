require("socket")
local https = require("ssl.https")
local json = require("json")

io.write("Content-Type: text/plain\nPragma: no-cache\n\n")

cookies_table = {}

function print_r (t)  
	local print_r_cache={}
	local function sub_print_r(t,indent)
		if (print_r_cache[tostring(t)]) then
			print(indent.."*"..tostring(t))
		else
			print_r_cache[tostring(t)]=true
			if (type(t)=="table") then
				for pos,val in pairs(t) do
					if (type(val)=="table") then
						print(indent.."["..pos.."] => "..tostring(t).." {")
						sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
						print(indent..string.rep(" ",string.len(pos)+6).."}")
					elseif (type(val)=="string") then
						print(indent.."["..pos..'] => "'..val..'"')
					else
						print(indent.."["..pos.."] => "..tostring(val))
					end
				end
			else
				print(indent..tostring(t))
			end
		end
	end
	if (type(t)=="table") then
		print(tostring(t).." {")
		sub_print_r(t,"  ")
		print("}")
	else
		sub_print_r(t,"  ")
	end
	print()
end


function split(s, delimiter)
	result = {}
	for match in (s..delimiter:gsub("%%", "")):gmatch("(.-)"..delimiter) do
		table.insert(result, match)
	end
	return result
end

function trim(s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end

function url_encode(str)
   if str then
	  -- str = str:gsub("\n", "\r\n")
	  str = str:gsub("([^%w %-%_%.%~])", function(c)
		 return ("%%%02X"):format(string.byte(c))
	  end)
	  str = str:gsub(" ", "+")
   end
   return str
end

function update_cookies(str)
	local segments = split(str, ";")
	for i, v in pairs(segments) do
		if v:find(",") then
			for i, w in pairs(split(v, ",")) do
				if w:find("=") then
					local kv = split(w, "=")
					local ck = trim(kv[1])
					local cv = trim(kv[2])
					if ck:lower() ~= "path" and ck:lower() ~= "expires" and ck:lower() ~= "max-age" then
						cookies_table[ck] = cv
					end
				end
			end
		else
			if v:find("=") then
				local kv = split(v, "=")
				local ck = trim(kv[1])
				local cv = trim(kv[2])
				if ck:lower() ~= "path" and ck:lower() ~= "expires" and ck:lower() ~= "max-age" then
					cookies_table[ck] = cv
				end
			end
		end
	end
end

function cookies_string()
	local r = {}
	for i, v in pairs(cookies_table) do
		table.insert(r, i .. "=" .. v)
	end
	return table.concat(r, ";")
end

function https_get(link)
	local res = {}
	local req = {
		url = link,
		protocol = "tlsv1_2",
		verify = "none",
		sink = ltn12.sink.table(res),
		headers = {
			["Cookie"] = cookies_string()
		}
	}
	-- print_r(req)
	local ok, code, header, http = https.request(req)
	for i, v in pairs(header) do
		if i:lower() == "set-cookie" then
			update_cookies(v)
		end
	end
	-- print_r(header)
	return table.concat(res)
end

function https_post(link, data)
	local res = {}
	local req = {
		method = "POST",
		url = link,
		protocol = "tlsv1_2",
		verify = "none",
		source = ltn12.source.string(data),
		sink = ltn12.sink.table(res),
		headers = {
			["Content-Length"] = string.len(data),
			["Content-Type"] = "application/x-www-form-urlencoded",
			["Cookie"] = cookies_string()
		}
	}
	-- print_r(req)
	local ok, code, header, http = https.request(req);
	for i, v in pairs(header) do
		if i:lower() == "set-cookie" then
			update_cookies(v)
		end
	end
	print_r(header)
	return table.concat(res)
end

function make_query_string(t)
	local r = {}
	for i, v in pairs(t) do
		table.insert(r, url_encode(i) .. "=" .. url_encode(v))
	end
	return table.concat(r, "&")
end

function curl(url, post)
	return io.popen('curl -k --data "' .. post .. '"' .. " " .. url):read("*a")
end

local _GET = {}

for k, v in pairs(split(os.getenv("QUERY_STRING"), "&")) do
	local kv = split(v, "=")
	_GET[kv[1]] = kv[2]
end

local my_username = _GET["username"]
local my_password = _GET["password"]
local my_server = _GET["server"]
local my_site = _GET["site"]
local my_server_no = split(my_server, "%.")[1]
local login_html = https_get("https://cp.xrea.com/account/login/")
local login_token = login_html:match('"fuel_csrf_token"%s*value="(%S*)"')
local login_form = {
	account = my_username,
	password = my_password,
	server = my_server,
	fuel_csrf_token = login_token
}
https_post("https://cp.xrea.com/account/login/", make_query_string(login_form))
local dashboard_html = https_get("https://cp.xrea.com/site/detail/" .. my_site .. "/")
local my_auth_key = dashboard_html:match("auth_key%s*=%s*['\"](%S*)['\"]")
local my_save_hash = dashboard_html:match("save_hash[^\n]*value%s*=%s*['\"](%S*)['\"]")
local my_data_no = dashboard_html:match("data%-no%s*=%s*['\"](%S*)['\"]")
local my_ip = dashboard_html:match("data%-ip%s*=%s*['\"](%S*)['\"]")
local my_phpver = dashboard_html:match("data%-phpver%s*=%s*['\"](%S*)['\"]")
local my_key_txt = io.open(my_site .. ".privkey.pem"):read("*a")
local my_cert_txt = io.open(my_site .. ".cert.pem"):read("*a")
local my_cact_txt = io.open(my_site .. ".chain.pem"):read("*a")

local edit_form = {
	account = my_username,
	auth_key = my_auth_key,
	reset_flg = "0",
	save_hash = my_save_hash,
	["param[0][no]"] = my_data_no,
	["param[0][domain]"] = my_site,
	["param[0][ip]"] = my_ip,
	["param[0][phpver]"] = my_phpver,
	["param[0][force]"] = "0",
	["param[0][ssl_status]"] = "2",
	["param[0][ssl_info][key_txt]"] = my_key_txt,
	["param[0][ssl_info][cert_txt]"] = my_cert_txt,
	["param[0][ssl_info][cact_txt]"] = my_cact_txt
}
print_r(edit_form)
print_r(curl("https://api-" .. my_server_no .. ".xrea.com/domain/edit/", make_query_string(edit_form)))