import time
import os
import os.path
import shutil
import json

from tornado.httpclient import HTTPClient, HTTPRequest

from seesaw.project import *
from seesaw.item import *
from seesaw.config import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.tracker import *

DATA_DIR = "data"
USER_AGENT = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:23.0) Gecko/20100101 Firefox/23.0"
VERSION = "20130819.01"
TRACKER = "http://quilt.at.ninjawedding.org/patchy"
RESOLVER = "http://quilt.at.ninjawedding.org:81"
CREDS = "ArchiveTeam:3boiqJvshItPBa66".split(':')

class PrepareDirectories(SimpleTask):
  def __init__(self, warc_prefix):
    SimpleTask.__init__(self, "PrepareDirectories")
    self.warc_prefix = warc_prefix

  def process(self, item):
    item_name = item["item_name"]
    dirname = "/".join(( item["data_dir"], item_name ))

    if os.path.isdir(dirname):
      shutil.rmtree(dirname)
    os.makedirs(dirname)

    item["item_dir"] = dirname
    item["warc_file_base"] = "%s-%s-%s" % (self.warc_prefix, item_name, time.strftime("%Y%m%d-%H%M%S"))

    open("%(item_dir)s/%(warc_file_base)s.warc.gz" % item, "w").close()

class MoveFiles(SimpleTask):
  def __init__(self):
    SimpleTask.__init__(self, "MoveFiles")

  def process(self, item):
    os.rename("%(item_dir)s/%(warc_file_base)s.warc.gz" % item,
              "%(data_dir)s/%(warc_file_base)s.warc.gz" % item)

    shutil.rmtree("%(item_dir)s" % item)

class CannotRetrieveItemError(Exception):
    def __init__(self, code):
        self.code = code

    def __str__(self):
        return "status code %s" % repr(self.code)

class ExpandItem(SimpleTask):
    def __init__(self):
        SimpleTask.__init__(self, "ExpandItem")

        self.http_client = HTTPClient()

    def process(self, item):
        req = HTTPRequest(url='%s/%s' % (RESOLVER, item["item_name"]),
                auth_username=CREDS[0],
                auth_password=CREDS[1])

        resp = self.http_client.fetch(req)

        if resp.code != 200:
            raise CannotRetrieveItemError(resp.status_code)

        doc = json.loads(resp.body)
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
    PrepareDirectories(warc_prefix="patch.com"),
    ExpandItem(),
    WgetDownload([ "./wget-lua",
        "-U", USER_AGENT,
        "-o", ItemInterpolation("%(item_dir)s/wget.log"),
        "--lua-script", "patch.lua",
        "--output-document", ItemInterpolation("%(item_dir)s/wget.tmp"),
        "--truncate-output",
        "--warc-file", ItemInterpolation("%(item_dir)s/%(warc_file_base)s"),
        "--warc-header", "operator: Archive Team",
        "--warc-header", "patch-script-version: " + VERSION,
        "--warc-header", ItemInterpolation("patch-item-name: %(item_name)s"),
        "--page-requisites",
        "--span-hosts",
        "-e", "robots=off",
        "--waitretry", "5",
        "--timeout", "60",
        "-i", ItemInterpolation("%(manifest_fn)s")
    ],
    max_tries = 3,
    accept_on_exit_code = [ 0, 4, 6, 8 ]),
    PrepareStatsForTracker(
        defaults = { "downloader": downloader, "version": VERSION },
        file_groups = {
            "data": [ ItemInterpolation("%(item_dir)s/%(warc_file_base)s.warc.gz") ]
        }
    ),
    MoveFiles(),
    LimitConcurrent(NumberConfigValue(min=1, max=4, default="1", name="shared:rsync_threads", title="Rsync threads", description="The maximum number of concurrent uploads."),
      UploadWithTracker(
        TRACKER,
        downloader = downloader,
        version = VERSION,
        files = [
          ItemInterpolation("%(data_dir)s/%(warc_file_base)s.warc.gz")
        ],
        rsync_target_source_path = ItemInterpolation("%(data_dir)s/"),
        rsync_extra_args = [
          "--recursive",
          "--partial",
          "--partial-dir", ".rsync-tmp"
        ]
      ),
    ),
    SendDoneToTracker(
        tracker_url = TRACKER,
        stats = ItemValue("stats")
    )
)

# vim:ts=4:sw=4:et:tw=78
