from bs4 import BeautifulSoup
import sys
import re
import json

if len(sys.argv) < 2:
	print "Usage: %s FILE" % sys.argv[0]
	sys.exit(1)

path = sys.argv[1]
f = open(path, 'r')

is_patchy = re.compile(r'\Ahttps?://[^\.]+\.patch\.com/')
anchor_pt = re.compile('#.+')

soup = BeautifulSoup(f.read())
links = set()

for link in soup.find_all('a'):
	href = link.get('href')

	if href and re.match(is_patchy, href):
		# Patch.com includes links with anchors, i.e. #s.
		#
		# Javascript fuckery can make foo.html#bar _not_ be included on
		# foo.html, so ordinarily we should not strip the anchor.
		#
		# However, wget will not handle anchors.  URL parsers generally
		# don't handle them either, so including anchors complicates
		# validation.  To get around this whole mess, we just strip the
		# anchor.
		stripped = re.sub(anchor_pt, '', href)
		links.add(stripped)

print json.dumps({'urls': list(links)})
