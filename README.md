patch-grab
==========

**NOTE**: Still under development; not yet intended for general use.

This (will become) a Seesaw script for grabbing patch.com sites.

The dashboard for this grab is http://patch.at.ninjawedding.org/patchy.

If you are not familiar with Archive Team grabs: this program 
repeatedly grabs a user from the tracker, downloads them via 
HTTP, then uploads the compressed archive to a collection server.

Running without a warrior
-------------------------

To run this outside the warrior:

(Ubuntu / Debian 7)

    sudo apt-get update
    sudo apt-get install -y build-essential lua5.1 liblua5.1-0-dev python python-setuptools python-dev git-core openssl libssl-dev python-pip rsync gcc make git screen
    pip install --user seesaw
    git clone https://github.com/ArchiveTeam/xanga-grab
    cd xanga-grab
    ./get-wget-lua.sh
    
    # Start downloading with:
    screen ~/.local/bin/run-pipeline --disable-web-server --concurrent 3 pipeline.py YOURNICKNAME

(Debian 6)

    sudo apt-get update
    sudo apt-get install -y build-essential lua5.1 liblua5.1-0-dev python python-setuptools python-dev git-core openssl libssl-dev python-pip rsync gcc make git screen
    wget --no-check-certificate https://pypi.python.org/packages/source/p/pip/pip-1.3.1.tar.gz tar -xzvf pip-1.3.1.tar.gz
    cd pip-1.3.1
    python setup.py install --user
    cd ..
    ~/.local/bin/pip install --user seesaw
    git clone https://github.com/ArchiveTeam/xanga-grab
    cd xanga-grab
    ./get-wget-lua.sh

    # Start downloading with:
    screen ~/.local/bin/run-pipeline --disable-web-server --concurrent 3 pipeline.py YOURNICKNAME

(CentOS / RHEL / Amazon Linux)

    sudo yum install lua lua-devel python-devel python-distribute git openssl-devel rsync gcc make screen
    wget --no-check-certificate https://pypi.python.org/packages/source/p/pip/pip-1.3.1.tar.gz
    tar -xzvf pip-1.3.1.tar.gz
    cd pip-1.3.1
    python setup.py install --user
    cd ..
    ~/.local/bin/pip install --user seesaw
    git clone https://github.com/ArchiveTeam/xanga-grab
    cd xanga-grab
    ./get-wget-lua.sh

    # Start downloading with:
    screen ~/.local/bin/run-pipeline --disable-web-server --concurrent 3 pipeline.py YOURNICKNAME

For more options, run:

    ~/.local/bin/run-pipeline --help

