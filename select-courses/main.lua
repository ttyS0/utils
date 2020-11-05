#!/usr/bin/lua

local http_req = require("http.request")
local http_util = require("http.util")

local json = require("json")
local socket = require("socket")

--local cookies = io.open("cookies.config"):read("*a")
local cookies

local function hust_get(url)
    local req = http_req.new_from_uri(url)
    req.headers:upsert("cookie", cookies)
    local headers, stream = req:go()
    return stream:get_body_as_string()
end

local function hust_post(url, data)
    local req = http_req.new_from_uri(url)
    req.headers:upsert(":method", "POST")
    req.headers:upsert("cookie", cookies)
    req.headers:upsert("content-type", "application/x-www-form-urlencoded")
    req:set_body(http_util.dict_to_query(data))
    print(http_util.dict_to_query(data))
    local headers, stream = req:go()
    return stream:get_body_as_string()
end

local function API_COURSE_LIST(page) return "http://wsxk.hust.edu.cn/zxqstudentcourse/zxqcourses.action?page=" .. page end
local function API_CLASS_LIST(course_id) return "http://wsxk.hust.edu.cn/zxqstudentcourse/zxqclassroom.action?kcbh=" .. course_id end
local function API_CLASS_DETAIL(class_id, term_id) return "http://wsxk.hust.edu.cn/common/addNotice!findteachroomForZxq.action?ktbh=" .. class_id .. "&xqh=" .. term_id end
local function API_CHOOSE() return "http://wsxk.hust.edu.cn/zxqstudentcourse/zxqcoursesresult.action" end
local function API_CHOOSE_DATA(course_id, points, class_id, total, occupied, name)
    return {
        kcbh = course_id,
        kczxf = points,
        ktbh = class_id,
        ktrl = total,
        ktrs = occupied,
        kcmc = name
    }
end

print("Enter your cookies:")
cookies = io.read("*l")

local course_page = hust_get(API_COURSE_LIST(1)):match([[makeXkxtPaging%('%d*','%d*','(%d+)'%)]])

local all_courses
if io.open("cache.json") ~= nil then
    print("Reading cache.json ...")
    all_courses = json.decode(io.open("cache.json"):read("*a"))
else
    print("Generating cache.json ...")
    all_courses = {}
    for i = 1, course_page do
        io.write("Page " .. i .. "...")
        local course_list_page = hust_get(API_COURSE_LIST(i))
	print(course_list_page)
        for category, name, points, school, course_id in course_list_page:gmatch("<tr class=\"tablelist\"%s*>%s*<td>%s*(.-)%s*</td>%s*<td>%s*<a[^>]+>%s*(.-)%s*</a>%s*</td>%s*<td>%s*(.-)%s*</td>%s*<td>%s*(.-)%s*</td>[%s%S]-selectKT%(this.id,'(.-)'%)") do
            local class_list = hust_get(API_CLASS_LIST(course_id))
            local post_point = class_list:match([[id="kczxf"%s-value="(.-)"]])
            local post_name = class_list:match([[id="kcmc"%s-value="(.-)"]])
            local classes = {}
            for teacher, class_id, term_id in class_list:gmatch("<a[^>]+>%s*(.-)%s*</a>[%s%S]-ClassWhenWhereForZxq%('(.-)','(.-)'%)") do
                local class_detail = hust_get(API_CLASS_DETAIL(class_id, term_id))
                local details = {}
                for place, week_start, week_end, schedule in class_detail:gmatch("<tr class=\"tablelist\"%s*>%s*<td>(.-)</td>%s*<td>(.-)</td>%s*<td>(.-)</td>%s*<td>%s*([%s%S]-)%s*</td>") do
                    schedule = schedule:gsub("%s+", " ")
                    table.insert(details, {
                        place = place,
                        week_start = week_start,
                        week_end = week_end,
                        schedule = schedule
                    })
                end
                table.insert(classes, {
                    teacher = teacher,
                    class_id = class_id,
                    term_id = term_id,
                    details = details
                })
            end
            table.insert(all_courses, {
                category = category,
                name = name,
                points = points,
                school = school,
                course_id = course_id,
                classes = classes
            })
        end
    end
    print()
    io.open("cache.json", "w+"):write(json.encode(all_courses))
end


for i, course in ipairs(all_courses) do
    print("\27[1;4m" .. i .. " " .. course.name .. " " .. course.points .. "\27[0m")
    for j, class in ipairs(course.classes) do
        io.write("\27[90m" .. j .. " " .. class.teacher)
        for _, detail in ipairs(class.details) do
            io.write(detail.place .. " " .. detail.week_start .. "~" .. detail.week_end .. " " .. detail.schedule .. ";")
        end
        print("\27[0m")
    end
end


local subscribed
local subscribed_classes = {}
if io.open("subscribed.config") ~= nil then
    subscribed = io.open("subscribed.config"):read("*a")
else
    print("Subscribe course[.class] (e.g. 1.2,6.3,4,8,5-12,[科学]): ")
    subscribed = io.read("*l")
    --io.open("subscribed.config", "w+"):write(subscribed)
end

for filter in (subscribed .. ","):gmatch("([%S%s]-),") do
    if filter:match("(%d+)%-(%d+)") then
        local s_start, s_end = filter:match("(%d+)%-(%d+)")
        for s_course in ipairs(all_courses) do
            if tonumber(s_start) <= s_course and s_course <= tonumber(s_end) then
                for s_class in ipairs(all_courses[s_course].classes) do
                    print("\27[94mSubscribing " .. all_courses[s_course].name .. " from teacher " .. all_courses[s_course].classes[s_class].teacher .. ".\27[0m")
                    local concat_schedule = ""
                    for _, d in ipairs(all_courses[s_course].classes[s_class].details) do
                        concat_schedule = concat_schedule .. d.schedule
                    end
                    table.insert(subscribed_classes, {
                        course_id = all_courses[s_course].course_id,
                        class_id = all_courses[s_course].classes[s_class].class_id,
                        name = all_courses[s_course].name,
                        points = all_courses[s_course].points,
                        sum_schedule = concat_schedule
                    })
                end
            end
        end
    elseif filter:match("(%d+)%.(%d+)") then
        local s_course, s_class = filter:match("(%d+)%.(%d+)")
        s_course = tonumber(s_course)
        s_class = tonumber(s_class)
        print("\27[94mSubscribing " .. all_courses[s_course].name .. " from teacher " .. all_courses[s_course].classes[s_class].teacher .. ".\27[0m")
        local concat_schedule = ""
        for _, d in ipairs(all_courses[s_course].classes[s_class].details) do
            concat_schedule = concat_schedule .. d.schedule
        end
        table.insert(subscribed_classes, {
            course_id = all_courses[s_course].course_id,
            class_id = all_courses[s_course].classes[s_class].class_id,
            name = all_courses[s_course].name,
            points = all_courses[s_course].points,
            sum_schedule = concat_schedule
        })
    elseif filter:match("%/.-%/") then
        local keyword = filter:match("%/(.-)%/")
        for s_course in ipairs(all_courses) do
            if all_courses[s_course].name:match(keyword) then
                for s_class in ipairs(all_courses[s_course].classes) do
                    print("\27[94mSubscribing " .. all_courses[s_course].name .. " from teacher " .. all_courses[s_course].classes[s_class].teacher .. ".\27[0m")
                    local concat_schedule = ""
                    for _, d in ipairs(all_courses[s_course].classes[s_class].details) do
                        concat_schedule = concat_schedule .. d.schedule
                    end
                    table.insert(subscribed_classes, {
                        course_id = all_courses[s_course].course_id,
                        class_id = all_courses[s_course].classes[s_class].class_id,
                        name = all_courses[s_course].name,
                        points = all_courses[s_course].points,
                        sum_schedule = concat_schedule
                    })
                end
            end
        end
    elseif filter:match("^%d+$") then
        local s_course = tonumber(filter)
        for s_class in ipairs(all_courses[s_course].classes) do
            print("\27[94mSubscribing " .. all_courses[s_course].name .. " from teacher " .. all_courses[s_course].classes[s_class].teacher .. ".\27[0m")
            local concat_schedule = ""
            for _, d in ipairs(all_courses[s_course].classes[s_class].details) do
                concat_schedule = concat_schedule .. d.schedule
            end
            table.insert(subscribed_classes, {
                course_id = all_courses[s_course].course_id,
                class_id = all_courses[s_course].classes[s_class].class_id,
                name = all_courses[s_course].name,
                points = all_courses[s_course].points,
                sum_schedule = concat_schedule
            })
        end
    end
end
local count = 0
while true do
    if #subscribed_classes == 0 then
        break
    end
    for i, s in ipairs(subscribed_classes) do
        -- Query
        local list = hust_get(API_CLASS_LIST(s.course_id))
        local total, occupied = list:match([[id="]] .. s.class_id .. [["[%s%S]-selectKT%(this%.id,'(%d+)','(%d+)']])
	if total == nil or occupied == nil then
		print("Parsing numbers error with raw HTML: ")
		print(list)
	else
		if count % 50 == 0 then
		    print("\27[37m[INFO] Course " .. s.name .. " status is " .. occupied .. "/" .. total .. ".\27[0m")
		end
		if tonumber(occupied) < tonumber(total) then
		    -- io.write("\27[1;93m Course " .. s.name .. " is now available with " .. occupied .. "/" .. total .. "! Sign now? [Y/n]\27[0m ")
		    -- local answer = io.read("*l")
		    -- if answer == "n" or answer == "N" then
		    -- else
		    io.write("\27[1;93mCourse " .. s.name .. " is now available with " .. occupied .. "/" .. total .. ".\27[0m")
		    local final = hust_post(API_CHOOSE(), API_CHOOSE_DATA(s.course_id, s.points, s.class_id, total, occupied, s.name))
		    print(final:match("<li>%s*([%s%S]-)%s*</li>"))
		    table.remove(subscribed_classes, i)
		    -- end
		end
	end
        -- !!! USELESS DELAY !!!
        socket.sleep(0.05)
    end
    count = (count + 1) % 50
end
