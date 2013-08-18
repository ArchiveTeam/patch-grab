function os.capture(cmd)
  local f = assert(io.popen(cmd, 'r'), "unable to start "..cmd)
  local s = f:read('*a')
  f:close()
  return s
end

local url_host = "http://quilt.at.ninjawedding.org:81"
local creds = "ArchiveTeam:3boiqJvshItPBa66"

wget.callbacks.httploop_result = function(url, err, http_status) do
	code = http_status.statcode

	-- HTTP 420 means that we're rate-limited.  We have to abort.
	if (code == 420) then
		io.stdout:write("Server returned status "..code.."; you've exceeded rate limits.\n")
		io.stdout:write("You may want to move to another IP.  Exiting...\n")
		io.stdout.flush()

		return wget.actions.ABORT
	end

	-- On code 2xx, extract URLs and send them to the URL storage
	-- mechanism.  We only do this for things that look like HTML files.
	if (code >= 200 and code <= 299) then
		loc = http_status.local_file

		out = os.capture("file "..loc)

		if (string.find(out, "HTML") == nil) then
			-- OK, this probably isn't an HTML document; don't analyze it
			return wget.actions.NOTHING
		end

		-- OK, this is probably an HTML document.  Get all of its links.
		io.stdout:write("Scraping "..url.url.." for links\n")
		io.stdout:flush()

		ret = os.execute("python scrape.py "..loc.. " | curl -f -X POST -m 10 --basic -u '"..creds.."' --data-binary @- "..url_host)

		io.stdout:write("Sent links for "..url.url.." to "..url_host.."\n")
		io.stdout:flush()

		-- If we can't contact the endpoint, log the error and continue
		-- working.  Chances are some other agent will eventually see
		-- the URLs that we didn't get.
		if (ret ~= 0) then
			io.stdout:write("Warning: URL scraper failed with code "..ret.."\n")
			io.stdout:write("Continuing grab, but please report this failure to someone in #cabbagepatch on EFnet\n")
			io.stdout:flush()
		end

		return wget.actions.NOTHING
	end
end
end
