PKG_DIR=/data/bancroft/artemis/live/repository/packages/artemisutils/
PKG_DIR_DEV=/data/bancroft/artemis/devel/repository/packages/artemisutils/
SOURCE_DIR=/home/artemis/perl510/lib/site_perl/5.10.0/Artemis/
DEST_DIR=opt/artemis/lib/perl5/site_perl/5.10.0/Artemis/

live:
	./scripts/dist_upload_wotan.sh
	ssh artemis@bancroft "cd /opt/artemis/mnt64/opt/; sudo rsync -ruv  ${SOURCE_DIR} ${DEST_DIR}; sudo tar -xzf ${PKG_DIR}/opt-artemis64.tar.gz"
	ssh artemis@bancroft "cd /opt/artemis/mnt32/opt/; sudo rsync -ruv  ${SOURCE_DIR} ${DEST_DIR}; sudo tar -xzf ${PKG_DIR}/opt-artemis32.tar.gz"
devel:
	./scripts/dist_upload_wotan.sh
	ssh artemis@bancroft "cd /opt/artemis/opt-artemis64-devel/; sudo rsync -ruv ${SOURCE_DIR} ${DEST_DIR}; sudo tar -xzf ${PKG_DIR}/opt-artemis64_devel.tar.gz"
	ssh artemis@bancroft "cd /opt/artemis/opt-artemis32-devel/; sudo rsync -ruv ${SOURCE_DIR} ${DEST_DIR}; sudo tar -xzf ${PKG_DIR}/opt-artemis32_devel.tar.gz"
