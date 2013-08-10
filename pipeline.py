import time
import os
import os.path
import shutil
import json

from seesaw.project import *
from seesaw.item import *
from seesaw.config import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.tracker import *

DATA_DIR = "data"
USER_AGENT = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:23.0) Gecko/20100101 Firefox/23.0"
VERSION = "20130810.01"
TRACKER = "http://quilt.at.ninjawedding.org/patchy"

class PrepareDirectories(SimpleTask):
	def __init__(self):
		SimpleTask.__init__(self, "PrepareDirectories")

	def process(self, item):
		item_dir = "%s/%s" % (DATA_DIR, item["item_name"])
		os.makedirs(item_dir + "/files")

		item["item_dir"] = item_dir

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
	LimitConcurrent(1,
		WgetDownload([ "./wget-lua",
			"-U", USER_AGENT,
			"-o", ItemInterpolation("%(item_dir)s/wget.log"),
			"--output-document", ItemInterpolation("%(item_dir)s/wget.tmp"),
			"--truncate-output",
			"--warc-file", ItemInterpolation("%(item_dir)s/%(item_name)s"),
			"--warc-header", "operator: Archive Team",
			"--warc-header", "patchy-script-version: " + VERSION,
			"--warc-header", ItemInterpolation("patchy-item-name: %(item_name)s"),
			"--mirror",
			"--page-requisites",
			"-e", "robots=off",
			"--waitretry", "5",
			"--timeout", "60",
			"--random-wait",
			"--wait", "1",
			ItemInterpolation("http://%(item_name)s")
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
