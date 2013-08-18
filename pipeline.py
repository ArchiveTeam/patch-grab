import time
import os
import os.path
import shutil
import json
import requests

from seesaw.project import *
from seesaw.item import *
from seesaw.config import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.tracker import *

DATA_DIR = "data"
USER_AGENT = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:23.0) Gecko/20100101 Firefox/23.0"
VERSION = "20130818.01"
TRACKER = "http://quilt.at.ninjawedding.org/patchy"
RESOLVER = "http://quilt.at.ninjawedding.org:81"
CREDS = "ArchiveTeam:3boiqJvshItPBa66".split(':')

class PrepareDirectories(SimpleTask):
	def __init__(self):
		SimpleTask.__init__(self, "PrepareDirectories")

	def process(self, item):
		item_dir = "%s/%s" % (DATA_DIR, item["item_name"])
		os.makedirs(item_dir + "/files")

		item["item_dir"] = item_dir

class CannotRetrieveItemError(Exception):
	def __init__(self, code):
		self.code = code

	def __str__(self):
		return "status code %s" % repr(self.code)

class ExpandItem(SimpleTask):
	def __init__(self):
		SimpleTask.__init__(self, "ExpandItem")

	def process(self, item):
		resp = requests.get('%s/%s' % (RESOLVER, item["item_name"]), auth=(CREDS[0], CREDS[1]))

		if resp.status_code != 200:
			raise CannotRetrieveItemError(resp.status_code)

		doc = resp.json()
		manifest_fn = "%s/manifest" % item["item_dir"]

		f = open(manifest_fn, 'w')
		for url in doc['urls']:
			f.write("%s\n" % url)
		f.close

		item["manifest_fn"] = manifest_fn

def calculate_item_id(item):
	return item["item_name"]

project = Project(
  title = "Patchy",
  project_html = """
      <p>Saving patch.com sites.</p>
  """,
  utc_deadline = datetime.datetime(2013, 8, 31, 12, 0, 0)
)

pipeline = Pipeline(
	GetItemFromTracker(TRACKER, downloader),
	PrepareDirectories(),
	ExpandItem(),
	LimitConcurrent(1,
		WgetDownload([ "./wget-lua",
			"-U", USER_AGENT,
			"-o", ItemInterpolation("%(item_dir)s/wget.log"),
			"--lua-script", "patch.lua",
			"--output-document", ItemInterpolation("%(item_dir)s/wget.tmp"),
			"--truncate-output",
			"--warc-file", ItemInterpolation("%(item_dir)s/%(item_name)s"),
			"--warc-header", "operator: Archive Team",
			"--warc-header", "patchy-script-version: " + VERSION,
			"--warc-header", ItemInterpolation("patchy-item-name: %(item_name)s"),
			"--page-requisites",
			"--span-hosts",
			"-e", "robots=off",
			"--waitretry", "5",
			"--timeout", "60",
			"-i", ItemInterpolation("%(manifest_fn)s")
		],
		max_tries = 3)
	),
	PrepareStatsForTracker(
		defaults = { "downloader": downloader, "version": VERSION },
		file_groups = {
			"data": [ ItemInterpolation("%(item_dir)/%(item_name)s.warc.gz") ]
		},
		id_function = calculate_item_id
	),
	SendDoneToTracker(
		tracker_url = TRACKER,
		stats = ItemValue("stats")
  	)
)

# vim:ts=4:sw=4:noet:tw=78
