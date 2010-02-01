MOUNT=/opt/artemis/mnt
MOUNT64:=${MOUNT}64
MOUNT32:=${MOUNT}32
PKG_DIR=/data/bancroft/artemis/live/repository/packages/artemisutils/
PKG_DIR_DEV=/data/bancroft/artemis/devel/repository/packages/artemisutils/
SOURCE_DIR=/home/artemis/perl510/lib/site_perl/5.10.0/Artemis/
DEST_DIR=opt/artemis/lib/perl5/site_perl/5.10.0/Artemis/

live:
	./scripts/dist_upload_wotan.sh
	ssh artemis@bancroft "cd ${MOUNT64}; sudo chroot ${MOUNT64} /opt/artemis/bin/cpan Artemis::PRC; tar -czf ${PKG_DIR}/opt-artemis64.tar.gz opt/ etc/resolv.conf"
	ssh artemis@bancroft "cd ${MOUNT32}; sudo chroot ${MOUNT32} /opt/artemis/bin/cpan Artemis::PRC; tar -czf ${PKG_DIR}/opt-artemis32.tar.gz opt/ etc/resolv.conf"
devel:
	./scripts/dist_upload_wotan.sh

	ssh artemis@bancroft "sudo mv ${MOUNT64}/opt ${MOUNT64}/opt.live; sudo mv ${MOUNT64}/opt.devel ${MOUNT64}/opt;"
	ssh artemis@bancroft "cd ${MOUNT64}; sudo rsync -ruv ${SOURCE_DIR} ${DEST_DIR}; sudo tar -czf ${PKG_DIR}/opt-artemis64_devel.tar.gz opt/"
	ssh artemis@bancroft "sudo mv ${MOUNT64}/opt ${MOUNT64}/opt.devel; sudo mv ${MOUNT64}/opt.live ${MOUNT64}/opt;"

	ssh artemis@bancroft "sudo mv ${MOUNT32}/opt ${MOUNT32}/opt.live; sudo mv ${MOUNT32}/opt.devel ${MOUNT32}/opt;"
	ssh artemis@bancroft "cd ${MOUNT32}; sudo rsync -ruv ${SOURCE_DIR} ${DEST_DIR}; sudo tar -czf ${PKG_DIR}/opt-artemis32_devel.tar.gz opt/"
	ssh artemis@bancroft "sudo mv ${MOUNT32}/opt ${MOUNT32}/opt.devel; sudo mv ${MOUNT32}/opt.live ${MOUNT32}/opt;"



