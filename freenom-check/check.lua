local http_request = require("http.request")
local http_cookie = require("http.cookie")
local http_util = require("http.util")

local username = os.getenv("FREENOM_USERNAME")
local password = os.getenv("FREENOM_PASSWORD")
local proxy = os.getenv("FREENOM_PROXY")

local TIMEOUT = 30
local FREENOM_API = {
    LOGIN = "https://my.freenom.com/dologin.php",
    RENEWAL = "https://my.freenom.com/domains.php?a=renewals",
    RENEW_DOMAIN = function(id) return "https://my.freenom.com/domains.php?a=renewdomain&domain=" .. id end,
    RENEW_DOMAIN_FORM = "https://my.freenom.com/domains.php?submitrenewals=true"
}

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

if username == nil or password == nil then
    print("Missing username or password.")
    os.exit(1)
end

local cookie_store = http_cookie.new_store()

local common_headers = {
    ["user-agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:77.0) Gecko/20100101 Firefox/77.0",
    ["accept-language"] = "en",
    ["accept"] = "text/html"
}

local function http_get(url, headers)
    local req = http_request.new_from_uri(url)
    if proxy ~= nil then
        req.proxy = proxy
    end
    req.cookie_store = cookie_store
    if common_headers ~= nil then
        for header, value in pairs(common_headers) do
            req.headers:upsert(header, value)
        end
    end
    if headers ~= nil then
        for header, value in pairs(headers) do
            req.headers:upsert(header, value)
        end
    end
    local headers, stream = req:go(TIMEOUT)
    return stream:get_body_as_string(), headers
end

local function http_post(url, data, headers)
    local req = http_request.new_from_uri(url)
    if proxy ~= nil then
        req.proxy = proxy
    end
    req.cookie_store = cookie_store
    req.headers:upsert(":method", "POST")
    if common_headers ~= nil then
        for header, value in pairs(common_headers) do
            req.headers:upsert(header, value)
        end
    end
    if headers ~= nil then
        for header, value in pairs(headers) do
            req.headers:upsert(header, value)
        end
    end
    req.headers:append("content-type", "application/x-www-form-urlencoded")
    req:set_body(http_util.dict_to_query(data))
    local headers, stream = req:go(TIMEOUT)
    return stream:get_body_as_string(), headers
end

local function login(username, password)
    local form = http_get("https://my.freenom.com/clientarea.php")
    local token = form:match("dologin%.php.-token.-value=\"(.-)\"")
    local res = http_post(FREENOM_API.LOGIN, {
        username = username,
        password = password,
        token = token
    }, {
        ["referer"] = FREENOM_API.LOGIN
    })
end

local function fetch_renewal_list()
    local renewals = {}
    local list = http_get(FREENOM_API.RENEWAL)
    for domain, status, days, able, id in list:gmatch("<tr><td>(.-)</td><td>(.-)</td>.-<span[^>]->(%d+).-</span>.-<span[^>]->(.-)</span>.-<a.-href=\".-(%d+)\">") do
        table.insert(renewals, {
            id = id,
            domain = domain,
            days = days,
            status = able
        })
    end
    return renewals
end

local function renew(id)
    local form = http_get(FREENOM_API.RENEW_DOMAIN(id))
    local token = form:match("action=\"domains.php.-token.-value=\"(.-)\"")
    local res = http_post(FREENOM_API.RENEW_DOMAIN_FORM, {
        renewalid = id,
        ["renewalperiod[" .. id .. "]"] = "12M",
        paymentmethod = "credit",
        token = token
    }, {
        ["referer"] = FREENOM_API.RENEW_DOMAIN(id)
    })
end

if proxy ~= nil then
    print("Using proxy " .. proxy)
end

print("Logging in Freenom...")
login(username, password)

print("Fetching renewal list...")

local renewals = fetch_renewal_list()

print("================")
for _, r in ipairs(renewals) do
    print(string.format("%-32s%s days", r.domain, r.days))
end
print("================")

local update_flag_bucket = {}
local has_available_renewals = false

for _, r in ipairs(renewals) do
    if r.status == "Renewable" or tonumber(r.days) < 15 then
        print("Try renewing " .. r.domain)
        has_available_renewals = true
        renew(r.id)
        update_flag_bucket[r.domain] = true
    end
end

if has_available_renewals then
    local renewals_now = fetch_renewal_list()

    for _, r in ipairs(renewals_now) do
        if update_flag_bucket[r.domain] then
            print("Checking " .. r.domain)
            if r.status == "Renewable" or tonumber(r.days) < 15 then
                print("Failed to update domain " .. r.domain)
            else
                print("Successfully update domain " .. r.domain)
            end
        end
    end
else
    print("No domains available to renew.")
end